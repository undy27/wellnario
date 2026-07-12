import UIKit

@MainActor
final class ActiveEditorViewController: EditorViewController {
    private let active: Active?
    private let nameField = FormFieldView()
    private let descriptionField = TextAreaFieldView()
    private let unitField = SelectionFieldView(title: L10n.Form.unit)
    private let lowerField = FormFieldView()
    private let upperField = FormFieldView()
    private var selectedUnit: DoseUnit

    init(repository: WellnarioRepositoryProtocol, active: Active? = nil) {
        self.active = active
        self.selectedUnit = active?.baseUnit ?? .milligram
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = active == nil ? L10n.Actives.add : L10n.text("actives.edit")
        configureFields()
        buildForm()
    }

    override func performSave() {
        nameField.setError(nil)
        lowerField.setError(nil)
        upperField.setError(nil)

        let name = nameField.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowerText = lowerField.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let upperText = upperField.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard active?.isSeeded == true || !name.isEmpty else {
            nameField.setError(L10n.Error.required)
            saveButton.isLoading = false
            return
        }

        let lower = FeatureFormatting.parseDecimal(lowerText)
        let upper = FeatureFormatting.parseDecimal(upperText)
        if !lowerText.isEmpty, lower == nil {
            lowerField.setError(L10n.Error.invalidNumber)
            saveButton.isLoading = false
            return
        }
        if !upperText.isEmpty, upper == nil {
            upperField.setError(L10n.Error.invalidNumber)
            saveButton.isLoading = false
            return
        }
        if lowerText.isEmpty != upperText.isEmpty {
            let message = L10n.Error.targetRange
            lowerField.setError(message)
            upperField.setError(message)
            saveButton.isLoading = false
            return
        }
        if let lower, let upper, (lower < 0 || upper < lower) {
            let message = L10n.Error.targetRange
            lowerField.setError(message)
            upperField.setError(message)
            saveButton.isLoading = false
            return
        }

        do {
            let saved: Active
            if let active {
                if active.isSeeded {
                    saved = active
                } else {
                    saved = try repository.updateActive(
                        id: active.id,
                        with: ActiveDraft(
                            name: name,
                            description: normalized(descriptionField.text),
                            baseUnit: selectedUnit,
                            proposedDailyMale: active.proposedDailyMale,
                            proposedDailyFemale: active.proposedDailyFemale,
                            imageKey: active.imageKey
                        )
                    )
                }
            } else {
                saved = try repository.createActive(
                    ActiveDraft(
                        name: name,
                        description: normalized(descriptionField.text),
                        baseUnit: selectedUnit,
                        imageKey: "active.custom"
                    )
                )
            }

            let today = LocalDay(containing: Date(), in: .current)
            if let lower, let upper {
                _ = try repository.setTarget(
                    activeID: saved.id,
                    lowerBound: lower,
                    upperBound: upper,
                    effectiveFrom: today
                )
            } else if active?.currentTarget != nil {
                try repository.clearTarget(activeID: saved.id, effectiveFrom: today)
            }
            finishSaving()
        } catch {
            saveButton.isLoading = false
            showError(error)
        }
    }

    private func configureFields() {
        let isSeeded = active?.isSeeded == true
        nameField.configure(
            title: L10n.Form.name,
            placeholder: L10n.text("actives.name.placeholder"),
            text: active?.localizedName(language: catalogLanguage),
            contentType: .name
        )
        nameField.textField.isEnabled = !isSeeded

        descriptionField.title = L10n.Form.description
        descriptionField.placeholder = L10n.text("actives.description.placeholder")
        descriptionField.text = active?.localizedDescription(language: catalogLanguage) ?? ""
        descriptionField.textView.isEditable = !isSeeded

        lowerField.configure(
            title: L10n.Actives.targetMinimum,
            placeholder: "0",
            text: active?.currentTarget.map { FeatureFormatting.decimal($0.lowerBound) },
            keyboardType: .decimalPad
        )
        upperField.configure(
            title: L10n.Actives.targetMaximum,
            placeholder: "0",
            text: active?.currentTarget.map { FeatureFormatting.decimal($0.upperBound) },
            keyboardType: .decimalPad
        )
        lowerField.unitTitle = selectedUnit.symbol(languageCode: catalogLanguage.rawValue)
        upperField.unitTitle = selectedUnit.symbol(languageCode: catalogLanguage.rawValue)
        lowerField.helperText = L10n.text("actives.target.helper")

        unitField.button.isEnabled = !isSeeded
        rebuildUnitMenu()
    }

    private func buildForm() {
        let artwork = PresentationArtworkView(kind: .other)
        artwork.primaryColor = WellnarioPalette.violet
        artwork.secondaryColor = WellnarioPalette.magenta
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 112),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor)
        ])
        let artworkContainer = UIView()
        artworkContainer.addForAutoLayout(artwork)
        NSLayoutConstraint.activate([
            artwork.centerXAnchor.constraint(equalTo: artworkContainer.centerXAnchor),
            artwork.topAnchor.constraint(equalTo: artworkContainer.topAnchor),
            artwork.bottomAnchor.constraint(equalTo: artworkContainer.bottomAnchor)
        ])

        addSection(title: L10n.Form.basics, views: [artworkContainer, nameField, descriptionField, unitField])
        addSection(title: L10n.Actives.target, views: [lowerField, upperField])
        addSaveButton()
    }

    private func rebuildUnitMenu() {
        unitField.value = selectedUnit.symbol(languageCode: catalogLanguage.rawValue)
        unitField.menu = UIMenu(children: DoseUnit.allCases.map { unit in
            UIAction(
                title: unit.symbol(languageCode: catalogLanguage.rawValue),
                state: unit == selectedUnit ? .on : .off
            ) { [weak self] _ in
                self?.selectUnit(unit)
            }
        })
    }

    private func selectUnit(_ unit: DoseUnit) {
        guard unit != selectedUnit else { return }

        let fields = [lowerField, upperField]
        var convertedValues: [Decimal?] = []
        for field in fields {
            let text = field.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                convertedValues.append(nil)
                continue
            }
            guard let value = FeatureFormatting.parseDecimal(text) else {
                field.setError(L10n.Error.invalidNumber)
                return
            }
            do {
                convertedValues.append(try selectedUnit.convert(value, to: unit))
            } catch {
                showError(RepositoryError.validation(L10n.text("error.target_unit_conversion")))
                return
            }
        }

        selectedUnit = unit
        lowerField.textField.text = convertedValues[0].map { FeatureFormatting.decimal($0) }
        upperField.textField.text = convertedValues[1].map { FeatureFormatting.decimal($0) }
        lowerField.setError(nil)
        upperField.setError(nil)
        lowerField.unitTitle = unit.symbol(languageCode: catalogLanguage.rawValue)
        upperField.unitTitle = unit.symbol(languageCode: catalogLanguage.rawValue)
        rebuildUnitMenu()
    }

    private func normalized(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

@MainActor
final class ActiveDetailViewController: FeatureViewController {
    private let activeID: UUID
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    init(repository: WellnarioRepositoryProtocol, activeID: UUID) {
        self.activeID = activeID
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.Common.edit,
            style: .plain,
            target: self,
            action: #selector(editTapped)
        )
        setUpView()
        reloadContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Resolve the scroll view and card hierarchy before the navigation
        // transition starts. Otherwise the hero card can receive its final
        // size in a later animation frame and look only partially rendered.
        UIView.performWithoutAnimation {
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    override func reloadContent() {
        do {
            guard let active = try repository.active(id: activeID) else { return }
            title = active.localizedName(language: catalogLanguage)
            rebuild(active)
        } catch { showError(error) }
    }

    private func setUpView() {
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        stackView.axis = .vertical
        stackView.spacing = WellnarioSpacing.cardGap
        scrollView.addForAutoLayout(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: WellnarioSpacing.medium),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.bottomNavigationInset),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(WellnarioSpacing.screenHorizontal * 2))
        ])
    }

    private func rebuild(_ active: Active) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let hero = PremiumCardView()
        hero.showsAccent = true
        let artwork = PresentationArtworkView(kind: .other)
        artwork.primaryColor = WellnarioPalette.violet
        artwork.secondaryColor = WellnarioPalette.cyan
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 112),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor)
        ])
        let name = UILabel()
        name.applyWellnarioStyle(.pageTitle, color: WellnarioPalette.textPrimary)
        name.text = active.localizedName(language: catalogLanguage)
        name.numberOfLines = 0
        let description = UILabel()
        description.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        description.text = active.localizedDescription(language: catalogLanguage)
        description.numberOfLines = 0
        let heroStack = UIStackView(arrangedSubviews: [artwork, name, description], axis: .vertical, spacing: 12, alignment: .center)
        hero.contentView.addForAutoLayout(heroStack)
        heroStack.pinEdges(to: hero.contentView, insets: .all(WellnarioSpacing.cardPadding))
        stackView.addArrangedSubview(hero)

        let targetCard = PremiumCardView()
        let targetTitle = UILabel()
        targetTitle.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        targetTitle.text = L10n.Actives.target
        let targetValue = UILabel()
        targetValue.applyWellnarioStyle(.metric, color: active.currentTarget == nil ? WellnarioPalette.textTertiary : WellnarioPalette.cyan)
        targetValue.numberOfLines = 0
        if let target = active.currentTarget {
            targetValue.text = "\(FeatureFormatting.decimal(target.lowerBound))–\(FeatureFormatting.decimal(target.upperBound)) \(target.unit.symbol(languageCode: catalogLanguage.rawValue))"
        } else {
            targetValue.text = "—"
        }
        let targetStack = UIStackView(arrangedSubviews: [targetTitle, targetValue], axis: .vertical, spacing: 16)
        targetCard.contentView.addForAutoLayout(targetStack)
        targetStack.pinEdges(to: targetCard.contentView, insets: .all(WellnarioSpacing.cardPadding))
        stackView.addArrangedSubview(targetCard)

        let trendsButton = PrimaryButton(title: L10n.Tab.trends)
        trendsButton.accessibilityIdentifier = "active.detail.trends"
        trendsButton.addTarget(self, action: #selector(showTrends), for: .touchUpInside)
        stackView.addArrangedSubview(trendsButton)
    }

    @objc private func editTapped() {
        do {
            guard let active = try repository.active(id: activeID) else { return }
            presentSheet(ActiveEditorViewController(repository: repository, active: active), largeOnly: true)
        } catch { showError(error) }
    }

    @objc private func showTrends() {
        guard let navigationController else { return }
        let trends = TrendsViewController(
            repository: repository,
            activeID: activeID,
            returnsToActiveDetail: true
        )

        guard WellnarioMotion.animationsEnabled else {
            navigationController.pushViewController(trends, animated: false)
            return
        }

        UIView.transition(
            with: navigationController.view,
            duration: WellnarioMotion.standard,
            options: [.transitionCrossDissolve, .allowAnimatedContent, .beginFromCurrentState]
        ) {
            navigationController.pushViewController(trends, animated: false)
        }
    }
}
