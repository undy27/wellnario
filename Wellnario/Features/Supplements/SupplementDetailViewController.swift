import UIKit

@MainActor
final class SupplementDetailViewController: FeatureViewController {
    private let supplementID: UUID
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private var supplement: Supplement?
    private var presentations: [PresentationType] = []
    private var actives: [Active] = []
    private var instances: [SupplementInstance] = []
    private var recentConsumptions: [Consumption] = []

    init(repository: WellnarioRepositoryProtocol, supplementID: UUID) {
        self.supplementID = supplementID
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

    override func reloadContent() {
        do {
            guard let supplement = try repository.supplement(id: supplementID) else {
                navigationController?.popViewController(animated: true)
                return
            }
            self.supplement = supplement
            presentations = try repository.fetchPresentationTypes()
            actives = try repository.fetchActives(includeArchived: true)
            instances = try repository.fetchInstances(supplementID: supplementID, includeArchived: true)
            let instanceIDs = Set(instances.map(\.id))
            recentConsumptions = try repository.fetchConsumptions(from: nil, through: nil, limit: nil)
                .filter { instanceIDs.contains($0.instanceID) }
            title = supplement.name
            rebuild()
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

    private func rebuild() {
        guard let supplement else { return }
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stackView.addArrangedSubview(makeHero(supplement))

        let logButton = PrimaryButton(title: L10n.Today.logIntake)
        logButton.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        logButton.tintColor = WellnarioPalette.textPrimary
        logButton.addTarget(self, action: #selector(logIntake), for: .touchUpInside)
        let batchButton = PrimaryButton(title: L10n.Inventory.add, style: .secondary)
        batchButton.addTarget(self, action: #selector(addInstance), for: .touchUpInside)
        let actionStack = UIStackView(arrangedSubviews: [logButton, batchButton], axis: .vertical, spacing: 10)
        stackView.addArrangedSubview(actionStack)

        stackView.addArrangedSubview(makeCompositionCard(supplement))
        stackView.addArrangedSubview(makeInventoryCard())
        stackView.addArrangedSubview(makeHistoryCard())

        let archive = PrimaryButton(title: L10n.text("supplements.archive"), style: .destructive)
        archive.addTarget(self, action: #selector(archiveTapped), for: .touchUpInside)
        stackView.addArrangedSubview(archive)
    }

    private func makeHero(_ supplement: Supplement) -> PremiumCardView {
        let card = PremiumCardView()
        let kind = presentation.map { PresentationKind(name: $0.localizedName(language: catalogLanguage)) } ?? .other
        let artwork = PresentationArtworkView(kind: kind)
        artwork.primaryColor = WellnarioPalette.cyan
        artwork.secondaryColor = WellnarioPalette.magenta
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 176),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor)
        ])

        let name = UILabel()
        name.applyWellnarioStyle(.pageTitle, color: WellnarioPalette.textPrimary)
        name.text = supplement.name
        name.textAlignment = .center
        name.numberOfLines = 0
        let brand = UILabel()
        brand.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        brand.text = [supplement.brand, presentation?.localizedName(language: catalogLanguage)].compactMap { $0 }.joined(separator: " · ")
        brand.textAlignment = .center
        brand.numberOfLines = 0
        let details = UILabel()
        details.applyWellnarioStyle(.secondary, color: WellnarioPalette.textTertiary)
        details.text = supplement.details
        details.textAlignment = .center
        details.numberOfLines = 0
        details.isHidden = supplement.details?.isEmpty != false

        let stack = UIStackView(arrangedSubviews: [artwork, name, brand, details], axis: .vertical, spacing: 8, alignment: .center)
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }

    private var presentation: PresentationType? {
        guard let supplement else { return nil }
        return presentations.first { $0.id == supplement.presentationTypeID }
    }

    private func makeCompositionCard(_ supplement: Supplement) -> PremiumCardView {
        let card = PremiumCardView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.addArrangedSubview(sectionHeader(L10n.Supplements.composition, symbol: "atom"))

        let basisLabel = UILabel()
        basisLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        basisLabel.text = L10n.text(
            "supplements.composition.basis",
            FeatureFormatting.decimal(supplement.basisQuantity),
            supplement.basisUnit.symbol(languageCode: catalogLanguage.rawValue)
        )
        basisLabel.numberOfLines = 0
        stack.addArrangedSubview(basisLabel)

        for component in supplement.components {
            let active = actives.first { $0.id == component.activeID }
            let row = valueRow(
                title: active?.localizedName(language: catalogLanguage) ?? L10n.Form.active,
                value: "\(FeatureFormatting.decimal(component.amount)) \(component.unit.symbol(languageCode: catalogLanguage.rawValue))",
                symbol: "sparkle"
            )
            stack.addArrangedSubview(row)
        }
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }

    private func makeInventoryCard() -> PremiumCardView {
        let card = PremiumCardView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.addArrangedSubview(sectionHeader(L10n.Inventory.title, symbol: "shippingbox.fill"))
        if instances.isEmpty {
            let label = bodyLabel(L10n.Inventory.noItemsMessage)
            stack.addArrangedSubview(label)
        } else {
            for instance in instances {
                let button = UIButton(type: .system)
                var config = UIButton.Configuration.plain()
                config.title = instance.label
                config.subtitle = FeatureFormatting.expirationText(instance.expirationDay)
                config.image = UIImage(systemName: "shippingbox")
                config.imagePadding = 12
                config.baseForegroundColor = WellnarioPalette.textPrimary
                config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
                button.configuration = config
                button.contentHorizontalAlignment = .leading
                button.accessibilityHint = L10n.Common.edit
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.presentSheet(InstanceEditorViewController(repository: self.repository, instance: instance), largeOnly: true)
                }, for: .touchUpInside)
                stack.addArrangedSubview(button)
            }
        }
        let add = PrimaryButton(title: L10n.Inventory.add, style: .secondary)
        add.addTarget(self, action: #selector(addInstance), for: .touchUpInside)
        stack.addArrangedSubview(add)
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }

    private func makeHistoryCard() -> PremiumCardView {
        let card = PremiumCardView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.addArrangedSubview(sectionHeader(L10n.Supplements.recentIntakes, symbol: "clock.arrow.circlepath"))
        if recentConsumptions.isEmpty {
            stack.addArrangedSubview(bodyLabel(L10n.Diary.noEntriesMessage))
        } else {
            for consumption in recentConsumptions.prefix(5) {
                let row = valueRow(
                    title: WellnarioFormatters.dateAndTime(
                        consumption.consumedAt,
                        timeZoneID: consumption.timeZoneID
                    ),
                    value: "\(FeatureFormatting.decimal(consumption.quantity)) \(consumption.unit.symbol(languageCode: catalogLanguage.rawValue))",
                    symbol: "checkmark.circle.fill"
                )
                stack.addArrangedSubview(row)
            }
        }
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }

    private func sectionHeader(_ title: String, symbol: String) -> UIView {
        let label = UILabel()
        label.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        label.text = title
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = WellnarioPalette.textTertiary
        return UIStackView(arrangedSubviews: [label, UIView(), icon], axis: .horizontal, spacing: 8, alignment: .center)
    }

    private func valueRow(title: String, value: String, symbol: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = WellnarioPalette.cyan
        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        titleLabel.text = title
        titleLabel.numberOfLines = 2
        let valueLabel = UILabel()
        valueLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        valueLabel.text = value
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        return UIStackView(arrangedSubviews: [icon, titleLabel, valueLabel], axis: .horizontal, spacing: 10, alignment: .center)
    }

    private func bodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    @objc private func editTapped() {
        guard let supplement else { return }
        presentSheet(SupplementEditorViewController(repository: repository, supplement: supplement), largeOnly: true)
    }

    @objc private func addInstance() {
        presentSheet(InstanceEditorViewController(repository: repository, supplementID: supplementID), largeOnly: true)
    }

    @objc private func logIntake() {
        guard !instances.isEmpty else {
            let alert = UIAlertController(title: L10n.Inventory.noItemsTitle, message: L10n.text("intake.requires_batch"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: L10n.Inventory.add, style: .default) { [weak self] _ in self?.addInstance() })
            present(alert, animated: true)
            return
        }
        if instances.count == 1 {
            presentSheet(IntakeEditorViewController(repository: repository, preferredInstanceID: instances[0].id), largeOnly: true)
            return
        }
        let sheet = UIAlertController(title: L10n.Inventory.batch, message: L10n.text("intake.choose_batch"), preferredStyle: .actionSheet)
        instances.forEach { instance in
            sheet.addAction(UIAlertAction(title: instance.label, style: .default) { [weak self] _ in
                guard let self else { return }
                self.presentSheet(IntakeEditorViewController(repository: self.repository, preferredInstanceID: instance.id), largeOnly: true)
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func archiveTapped() {
        showConfirmation(title: L10n.text("supplements.archive"), message: L10n.text("supplements.archive.confirmation"), destructiveTitle: L10n.text("supplements.archive")) { [weak self] in
            guard let self else { return }
            do {
                _ = try self.repository.deleteSupplement(id: self.supplementID)
                self.navigationController?.popViewController(animated: true)
            } catch { self.showError(error) }
        }
    }
}
