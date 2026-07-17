import UIKit

@MainActor
final class ActiveEditorViewController: EditorViewController {
    private let active: Active?
    private let nameField = FormFieldView()
    private let descriptionField = TextAreaFieldView()
    private let unitField = SelectionFieldView(title: L10n.Form.unit)
    private let categoriesField = SelectionFieldView()
    private let lowerField = FormFieldView()
    private let upperField = FormFieldView()
    private var selectedUnit: DoseUnit
    private var selectedTargetUnit: DoseUnit
    private var selectedCategories: Set<ActiveCategory>

    init(repository: WellnarioRepositoryProtocol, active: Active? = nil) {
        self.active = active
        self.selectedUnit = active?.baseUnit ?? .milligram
        self.selectedTargetUnit = active?.currentTarget?.unit ?? active?.baseUnit ?? .milligram
        self.selectedCategories = Set(active?.categories ?? [])
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
                            imageKey: active.imageKey,
                            categories: Array(selectedCategories)
                        )
                    )
                }
            } else {
                saved = try repository.createActive(
                    ActiveDraft(
                        name: name,
                        description: normalized(descriptionField.text),
                        baseUnit: selectedUnit,
                        imageKey: "active.custom",
                        categories: Array(selectedCategories)
                    )
                )
            }

            let today = LocalDay(containing: Date(), in: .current)
            if let lower, let upper {
                _ = try repository.setTarget(
                    activeID: saved.id,
                    lowerBound: lower,
                    upperBound: upper,
                    unit: selectedTargetUnit,
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
        lowerField.unitTitle = selectedTargetUnit.symbol(languageCode: catalogLanguage.rawValue)
        upperField.unitTitle = selectedTargetUnit.symbol(languageCode: catalogLanguage.rawValue)
        lowerField.helperText = L10n.text("actives.target.helper")

        unitField.button.isEnabled = !isSeeded
        rebuildUnitMenu()

        categoriesField.title = L10n.text("actives.categories")
        categoriesField.button.isEnabled = !isSeeded
        rebuildCategoryMenu()
    }

    private func buildForm() {
        let artwork = makeActiveArtwork(
            imageKey: active?.imageKey,
            size: 112,
            accessibilityIdentifier: "active.editor.artwork"
        )
        let artworkContainer = UIView()
        artworkContainer.addForAutoLayout(artwork)
        NSLayoutConstraint.activate([
            artwork.centerXAnchor.constraint(equalTo: artworkContainer.centerXAnchor),
            artwork.topAnchor.constraint(equalTo: artworkContainer.topAnchor),
            artwork.bottomAnchor.constraint(equalTo: artworkContainer.bottomAnchor)
        ])

        addSection(title: L10n.Form.basics, views: [artworkContainer, nameField, descriptionField, unitField, categoriesField])
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
                convertedValues.append(try selectedTargetUnit.convert(value, to: unit))
            } catch {
                showError(RepositoryError.validation(L10n.text("error.target_unit_conversion")))
                return
            }
        }

        selectedUnit = unit
        selectedTargetUnit = unit
        lowerField.textField.text = convertedValues[0].map { FeatureFormatting.decimal($0) }
        upperField.textField.text = convertedValues[1].map { FeatureFormatting.decimal($0) }
        lowerField.setError(nil)
        upperField.setError(nil)
        lowerField.unitTitle = unit.symbol(languageCode: catalogLanguage.rawValue)
        upperField.unitTitle = unit.symbol(languageCode: catalogLanguage.rawValue)
        rebuildUnitMenu()
    }

    private func rebuildCategoryMenu() {
        let orderedSelection = ActiveCategory.allCases.filter(selectedCategories.contains)
        categoriesField.value = orderedSelection.isEmpty
            ? L10n.text("actives.categories.none")
            : orderedSelection.map { $0.localizedName(language: catalogLanguage) }.joined(separator: ", ")
        categoriesField.menu = UIMenu(
            options: .displayInline,
            children: ActiveCategory.allCases.map { category in
                UIAction(
                    title: category.localizedName(language: catalogLanguage),
                    state: selectedCategories.contains(category) ? .on : .off
                ) { [weak self] _ in
                    guard let self else { return }
                    if self.selectedCategories.contains(category) {
                        self.selectedCategories.remove(category)
                    } else {
                        self.selectedCategories.insert(category)
                    }
                    self.rebuildCategoryMenu()
                }
            }
        )
    }

    private func normalized(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

@MainActor
final class ActiveDetailViewController: FeatureViewController, UIGestureRecognizerDelegate {
    private let activeID: UUID
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let favoriteButton = UIButton(type: .system)
    private let targetField = FormFieldView()
    private let targetSaveButton = PrimaryButton(style: .secondary)
    private var currentActive: Active?
    private var selectedTargetUnit: DoseUnit = .milligram

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
        configureControls()
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
            currentActive = active
            title = active.localizedName(language: catalogLanguage)
            rebuild(active)
        } catch { showError(error) }
    }

    private func setUpView() {
        view.addForAutoLayout(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView = touch.view
        while let candidate = touchedView {
            if candidate is UIControl { return false }
            touchedView = candidate.superview
        }
        return true
    }

    private func configureControls() {
        favoriteButton.accessibilityIdentifier = "active.detail.favorite"
        favoriteButton.addTarget(self, action: #selector(toggleFavorite), for: .touchUpInside)

        targetField.textField.accessibilityIdentifier = "active.detail.target.amount"
        targetField.unitButton.accessibilityIdentifier = "active.detail.target.unit"
        targetField.unitButton.showsMenuAsPrimaryAction = true
        targetField.helperText = L10n.text("actives.target.exact.helper")

        targetSaveButton.setTitle(L10n.text("actives.target.save"), for: .normal)
        targetSaveButton.accessibilityIdentifier = "active.detail.target.save"
        targetSaveButton.addTarget(self, action: #selector(saveTarget), for: .touchUpInside)
    }

    private func rebuild(_ active: Active) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let hero = PremiumCardView()
        let artwork = makeActiveArtwork(
            imageKey: active.imageKey,
            size: 112,
            accessibilityIdentifier: "active.detail.artwork"
        )
        let name = UILabel()
        name.applyWellnarioStyle(.pageTitle, color: WellnarioPalette.textPrimary)
        name.text = active.localizedName(language: catalogLanguage)
        name.numberOfLines = 0
        let description = UILabel()
        description.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        description.text = active.localizedDescription(language: catalogLanguage)
        description.numberOfLines = 0
        configureFavoriteButton(isFavorite: active.isFavorite)
        let heroStack = UIStackView(
            arrangedSubviews: [artwork, name, description, favoriteButton],
            axis: .vertical,
            spacing: 12,
            alignment: .center
        )
        hero.contentView.addForAutoLayout(heroStack)
        heroStack.pinEdges(to: hero.contentView, insets: .all(WellnarioSpacing.cardPadding))
        stackView.addArrangedSubview(hero)

        let targetCard = PremiumCardView()
        let targetTitle = UILabel()
        targetTitle.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        targetTitle.text = L10n.text("actives.target.consumption")

        let currentTargetLabel = UILabel()
        currentTargetLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        currentTargetLabel.numberOfLines = 0
        currentTargetLabel.accessibilityIdentifier = "active.detail.target.current"
        if let target = active.currentTarget {
            currentTargetLabel.text = L10n.text("actives.target.current", targetDescription(target))
        } else {
            currentTargetLabel.text = L10n.text("actives.target.not_set")
        }

        selectedTargetUnit = active.currentTarget?.unit ?? active.baseUnit
        let exactAmount = active.currentTarget.flatMap { target in
            target.lowerBound == target.upperBound ? target.lowerBound : nil
        }
        targetField.configure(
            title: L10n.text("actives.target.daily_amount"),
            placeholder: "0",
            text: exactAmount.map { FeatureFormatting.decimal($0) },
            keyboardType: .decimalPad
        )
        rebuildTargetUnitMenu(active: active)

        let targetStack = UIStackView(
            arrangedSubviews: [targetTitle, currentTargetLabel, targetField, targetSaveButton],
            axis: .vertical,
            spacing: 16
        )
        targetCard.contentView.addForAutoLayout(targetStack)
        targetStack.pinEdges(to: targetCard.contentView, insets: .all(WellnarioSpacing.cardPadding))
        stackView.addArrangedSubview(targetCard)

        let trendsButton = PrimaryButton(title: L10n.Tab.trends)
        trendsButton.accessibilityIdentifier = "active.detail.trends"
        trendsButton.addTarget(self, action: #selector(showTrends), for: .touchUpInside)
        stackView.addArrangedSubview(trendsButton)
    }

    private func configureFavoriteButton(isFavorite: Bool) {
        favoriteButton.isEnabled = true
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: isFavorite ? "star.fill" : "star")
        configuration.title = isFavorite
            ? L10n.text("actives.favorite.selected")
            : L10n.text("actives.favorite.add")
        configuration.imagePadding = 8
        configuration.baseForegroundColor = WellnarioPalette.fuchsia
        configuration.baseBackgroundColor = WellnarioPalette.fuchsia.withAlphaComponent(0.16)
        configuration.cornerStyle = .capsule
        favoriteButton.configuration = configuration
        favoriteButton.accessibilityValue = isFavorite
            ? L10n.text("actives.favorite.accessibility.on")
            : L10n.text("actives.favorite.accessibility.off")
    }

    private func rebuildTargetUnitMenu(active: Active) {
        let units = DoseUnit.allCases.filter { $0.isCompatible(with: active.baseUnit) }
        if !units.contains(selectedTargetUnit) { selectedTargetUnit = active.baseUnit }
        targetField.unitTitle = selectedTargetUnit.symbol(languageCode: catalogLanguage.rawValue)
        targetField.unitButton.menu = UIMenu(children: units.map { unit in
            UIAction(
                title: unit.symbol(languageCode: catalogLanguage.rawValue),
                state: unit == selectedTargetUnit ? .on : .off
            ) { [weak self] _ in
                self?.selectTargetUnit(unit)
            }
        })
        targetField.unitButton.accessibilityValue = selectedTargetUnit.symbol(languageCode: catalogLanguage.rawValue)
    }

    private func selectTargetUnit(_ unit: DoseUnit) {
        guard let active = currentActive, unit != selectedTargetUnit else { return }
        let text = targetField.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            guard let amount = FeatureFormatting.parseDecimal(text) else {
                targetField.setError(L10n.Error.invalidNumber)
                return
            }
            do {
                let converted = try selectedTargetUnit.convert(amount, to: unit)
                targetField.textField.text = FeatureFormatting.decimal(converted)
            } catch {
                showError(error)
                return
            }
        }
        selectedTargetUnit = unit
        targetField.setError(nil)
        rebuildTargetUnitMenu(active: active)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func targetDescription(_ target: ActiveTarget) -> String {
        let amount = target.lowerBound == target.upperBound
            ? FeatureFormatting.decimal(target.lowerBound)
            : "\(FeatureFormatting.decimal(target.lowerBound))–\(FeatureFormatting.decimal(target.upperBound))"
        return "\(amount) \(target.unit.symbol(languageCode: catalogLanguage.rawValue))"
    }

    @objc private func toggleFavorite() {
        guard let active = currentActive else { return }
        favoriteButton.isEnabled = false
        do {
            _ = try repository.setActiveFavorite(id: activeID, isFavorite: !active.isFavorite)
            UISelectionFeedbackGenerator().selectionChanged()
            reloadContent()
        } catch {
            favoriteButton.isEnabled = true
            showError(error)
        }
    }

    @objc private func saveTarget() {
        dismissKeyboard()
        targetField.setError(nil)
        guard let amount = FeatureFormatting.parseDecimal(targetField.textField.text), amount > 0 else {
            targetField.setError(L10n.Error.positiveAmount)
            return
        }
        targetSaveButton.isLoading = true
        do {
            _ = try repository.setTarget(
                activeID: activeID,
                lowerBound: amount,
                upperBound: amount,
                unit: selectedTargetUnit,
                effectiveFrom: LocalDay(containing: Date(), in: .current)
            )
            targetSaveButton.isLoading = false
            UIImpactFeedbackGenerator.wellnarioSuccess()
            returnAfterSavingTarget()
        } catch {
            targetSaveButton.isLoading = false
            showError(error)
        }
    }

    private func returnAfterSavingTarget() {
        if let navigationController,
           navigationController.topViewController === self,
           navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
            return
        }
        if let navigationController, navigationController.presentingViewController != nil {
            navigationController.dismiss(animated: true)
            return
        }
        if presentingViewController != nil {
            dismiss(animated: true)
        }
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

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

@MainActor
private func makeActiveArtwork(
    imageKey: String?,
    size: CGFloat,
    accessibilityIdentifier: String
) -> UIView {
    if let imageKey, let image = UIImage(named: imageKey) {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIdentifier = accessibilityIdentifier
        imageView.isAccessibilityElement = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: size),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor)
        ])
        return imageView
    }

    let artwork = PresentationArtworkView(kind: .other)
    artwork.primaryColor = WellnarioPalette.violet
    artwork.secondaryColor = WellnarioPalette.cyan
    artwork.accessibilityIdentifier = accessibilityIdentifier
    artwork.isAccessibilityElement = false
    NSLayoutConstraint.activate([
        artwork.widthAnchor.constraint(equalToConstant: size),
        artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor)
    ])
    return artwork
}
