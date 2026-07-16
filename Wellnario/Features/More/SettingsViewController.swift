import UIKit

@MainActor
final class SettingsViewController: UIViewController {
    private let spanishButton = LanguageChoiceControl(language: .spanish)
    private let englishButton = LanguageChoiceControl(language: .english)
    private let darkAppearanceButton = AppearanceChoiceControl(mode: .dark)
    private let lightAppearanceButton = AppearanceChoiceControl(mode: .light)
    private let systemAppearanceButton = AppearanceChoiceControl(mode: .system)
    private let appleHealthRow = IntegrationRowControl(provider: .appleHealth)
    private let appleHealthService: AppleHealthSyncing
    private let appearanceManager: WellnarioAppearanceManager
    private let activeTargetMarginPreferences: ActiveTargetMarginPreferences
    private let sleepManualOverrideStore: SleepManualOverrideStore

    init(
        appleHealthService: AppleHealthSyncing,
        appearanceManager: WellnarioAppearanceManager = .shared,
        activeTargetMarginPreferences: ActiveTargetMarginPreferences = ActiveTargetMarginPreferences(),
        sleepManualOverrideStore: SleepManualOverrideStore = SleepManualOverrideStore()
    ) {
        self.appleHealthService = appleHealthService
        self.appearanceManager = appearanceManager
        self.activeTargetMarginPreferences = activeTargetMarginPreferences
        self.sleepManualOverrideStore = sleepManualOverrideStore
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        updateSelection()
        updateAppearanceSelection()
        updateAppleHealthStatus()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appleHealthDidChange),
            name: .appleHealthSyncDidChange,
            object: appleHealthService
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private func setUpView() {
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "settings.root"
        title = L10n.Settings.title
        navigationItem.largeTitleDisplayMode = .never
        let backButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"),
            style: .plain,
            target: self,
            action: #selector(closeSettings)
        )
        backButton.accessibilityIdentifier = "settings.back"
        backButton.accessibilityLabel = L10n.Common.back
        navigationItem.leftBarButtonItem = backButton

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)

        let languageTitle = makeSectionTitle(L10n.Settings.language)
        let languageFooter = UILabel()
        languageFooter.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        languageFooter.text = L10n.Settings.languageFooter
        languageFooter.numberOfLines = 0

        spanishButton.accessibilityIdentifier = "settings.language.es"
        englishButton.accessibilityIdentifier = "settings.language.en"
        spanishButton.addTarget(self, action: #selector(languageTapped(_:)), for: .touchUpInside)
        englishButton.addTarget(self, action: #selector(languageTapped(_:)), for: .touchUpInside)

        let languageChoices = UIStackView(
            arrangedSubviews: [spanishButton, englishButton],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )
        let languageContent = UIStackView(
            arrangedSubviews: [languageTitle, languageChoices, languageFooter],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        let languageCard = makeCard(containing: languageContent, identifier: "settings.language.card")

        let appearanceTitle = makeSectionTitle(L10n.Settings.appearance)
        let appearanceFooter = UILabel()
        appearanceFooter.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        appearanceFooter.text = L10n.Settings.appearanceFooter
        appearanceFooter.numberOfLines = 0

        darkAppearanceButton.accessibilityIdentifier = "settings.appearance.dark"
        lightAppearanceButton.accessibilityIdentifier = "settings.appearance.light"
        systemAppearanceButton.accessibilityIdentifier = "settings.appearance.system"
        for button in [darkAppearanceButton, lightAppearanceButton, systemAppearanceButton] {
            button.addTarget(self, action: #selector(appearanceTapped(_:)), for: .touchUpInside)
        }

        let appearanceChoices = UIStackView(
            arrangedSubviews: [darkAppearanceButton, lightAppearanceButton, systemAppearanceButton],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )
        let appearanceContent = UIStackView(
            arrangedSubviews: [appearanceTitle, appearanceChoices, appearanceFooter],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        let appearanceCard = makeCard(
            containing: appearanceContent,
            identifier: "settings.appearance.card"
        )

        let integrationsTitle = makeSectionTitle(L10n.text("integrations.title"))
        let integrationsFooter = UILabel()
        integrationsFooter.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        integrationsFooter.text = L10n.text("integrations.footer")
        integrationsFooter.numberOfLines = 0

        let oura = IntegrationRowControl(provider: .oura)
        appleHealthRow.addTarget(self, action: #selector(integrationTapped(_:)), for: .touchUpInside)
        oura.addTarget(self, action: #selector(integrationTapped(_:)), for: .touchUpInside)
        let integrationRows = UIStackView(
            arrangedSubviews: [appleHealthRow, oura],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )
        let integrationContent = UIStackView(
            arrangedSubviews: [integrationsTitle, integrationRows, integrationsFooter],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        let integrationsCard = makeCard(
            containing: integrationContent,
            identifier: "settings.integrations.card"
        )

        let supplementsRow = makeAdvancedOptionsRow(
            symbolName: "pills.fill",
            title: L10n.text("settings.advanced.supplements.title"),
            body: L10n.text("settings.advanced.supplements.body"),
            tone: WellnarioPalette.cyan,
            identifier: "settings.advanced.supplements.card"
        )
        supplementsRow.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(
                SupplementAdvancedOptionsViewController(
                    preferences: self.activeTargetMarginPreferences
                ),
                animated: true
            )
        }, for: .touchUpInside)

        let sleepRow = makeAdvancedOptionsRow(
            symbolName: "moon.stars.fill",
            title: L10n.text("settings.advanced.sleep.title"),
            body: L10n.text("settings.advanced.sleep.body"),
            tone: WellnarioPalette.violet,
            identifier: "settings.advanced.sleep.card"
        )
        sleepRow.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(
                SleepAdvancedOptionsViewController(
                    appleHealthService: self.appleHealthService,
                    store: self.sleepManualOverrideStore
                ),
                animated: true
            )
        }, for: .touchUpInside)

        let healthRow = makeAdvancedOptionsRow(
            symbolName: "heart.text.square.fill",
            title: L10n.text("settings.advanced.health.title"),
            body: L10n.text("settings.advanced.health.body"),
            tone: WellnarioPalette.pink,
            identifier: "settings.advanced.health.card"
        )
        healthRow.addAction(UIAction { [weak self] _ in
            self?.navigationController?.pushViewController(
                AdvancedOptionsPlaceholderViewController(
                    title: L10n.text("settings.advanced.health.title")
                ),
                animated: true
            )
        }, for: .touchUpInside)

        let fitnessRow = makeAdvancedOptionsRow(
            symbolName: "figure.run",
            title: L10n.text("settings.advanced.fitness.title"),
            body: L10n.text("settings.advanced.fitness.body"),
            tone: WellnarioPalette.magenta,
            identifier: "settings.advanced.fitness.card"
        )
        fitnessRow.addAction(UIAction { [weak self] _ in
            self?.navigationController?.pushViewController(
                AdvancedOptionsPlaceholderViewController(
                    title: L10n.text("settings.advanced.fitness.title")
                ),
                animated: true
            )
        }, for: .touchUpInside)

        let advancedRows = groupedStack([
            supplementsRow,
            sleepRow,
            healthRow,
            fitnessRow
        ])
        let advancedContent = UIStackView(
            arrangedSubviews: [
                makeSectionTitle(L10n.text("settings.advanced.title")),
                advancedRows
            ],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        let advancedOptionsCard = makeCard(
            containing: advancedContent,
            identifier: "settings.advanced.card"
        )

        let aboutSection = makeInformationSection(
            symbolName: "sparkles",
            title: L10n.Settings.about,
            body: L10n.Settings.aboutBody,
            tone: WellnarioPalette.violet,
            identifier: "settings.about"
        )
        let privacySection = makeInformationSection(
            symbolName: "lock.shield.fill",
            title: L10n.Settings.privacy,
            body: L10n.text("settings.privacy.body"),
            tone: WellnarioPalette.success,
            identifier: "settings.privacy"
        )
        let disclaimerSection = makeInformationSection(
            symbolName: "cross.case.fill",
            title: L10n.Settings.medicalDisclaimer,
            body: L10n.Settings.medicalDisclaimerBody,
            tone: WellnarioPalette.cyan,
            identifier: "settings.medicalDisclaimer"
        )
        let informationCard = makeCard(
            containing: groupedStack([
                aboutSection,
                privacySection,
                disclaimerSection
            ]),
            identifier: "settings.information.card"
        )

        let contentStack = UIStackView(
            arrangedSubviews: [
                integrationsCard,
                appearanceCard,
                languageCard,
                advancedOptionsCard,
                informationCard
            ],
            axis: .vertical,
            spacing: WellnarioSpacing.cardGap
        )
        scrollView.addForAutoLayout(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: WellnarioSpacing.medium),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.bottomNavigationInset),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(WellnarioSpacing.screenHorizontal * 2))
        ])
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    private func makeCard(containing content: UIView, identifier: String) -> PremiumCardView {
        let card = PremiumCardView()
        card.accessibilityIdentifier = identifier
        card.contentView.addForAutoLayout(content)
        content.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }

    private func makeAdvancedOptionsRow(
        symbolName: String,
        title: String,
        body: String,
        tone: UIColor,
        identifier: String
    ) -> UIButton {
        let symbol = UIImageView(image: UIImage(systemName: symbolName))
        symbol.tintColor = tone
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 19,
            weight: .semibold
        )
        symbol.widthAnchor.constraint(equalToConstant: 28).isActive = true
        symbol.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        titleLabel.text = title
        titleLabel.numberOfLines = 0

        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.tintColor = WellnarioPalette.textTertiary
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 14,
            weight: .semibold
        )
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        bodyLabel.text = body
        bodyLabel.numberOfLines = 0

        let labels = UIStackView(
            arrangedSubviews: [titleLabel, bodyLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        let content = UIStackView(
            arrangedSubviews: [symbol, labels, chevron],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        content.isUserInteractionEnabled = false

        let row = UIButton(type: .system)
        row.accessibilityIdentifier = identifier
        row.accessibilityLabel = title
        row.accessibilityHint = body
        row.addForAutoLayout(content)
        content.pinEdges(
            to: row,
            insets: NSDirectionalEdgeInsets(top: 11, leading: 0, bottom: 11, trailing: 0)
        )
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true
        return row
    }

    private func makeInformationSection(
        symbolName: String,
        title: String,
        body: String,
        tone: UIColor,
        identifier: String
    ) -> UIView {
        let symbol = UIImageView(image: UIImage(systemName: symbolName))
        symbol.tintColor = tone
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 19,
            weight: .semibold
        )
        symbol.widthAnchor.constraint(equalToConstant: 28).isActive = true
        symbol.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        titleLabel.text = title
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        bodyLabel.text = body
        bodyLabel.numberOfLines = 0

        let labels = UIStackView(
            arrangedSubviews: [titleLabel, bodyLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        let content = UIStackView(
            arrangedSubviews: [symbol, labels],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .top
        )
        let section = UIView()
        section.accessibilityIdentifier = identifier
        section.isAccessibilityElement = true
        section.accessibilityLabel = [title, body].joined(separator: ". ")
        section.addForAutoLayout(content)
        content.pinEdges(
            to: section,
            insets: NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0)
        )
        return section
    }

    private func groupedStack(_ sections: [UIView]) -> UIStackView {
        var arrangedSubviews: [UIView] = []
        for (index, section) in sections.enumerated() {
            if index > 0 {
                let separator = UIView()
                separator.backgroundColor = WellnarioPalette.hairline
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                arrangedSubviews.append(separator)
            }
            arrangedSubviews.append(section)
        }
        return UIStackView(
            arrangedSubviews: arrangedSubviews,
            axis: .vertical,
            spacing: 0
        )
    }

    private func updateSelection() {
        let language = LocalizationManager.shared.language
        spanishButton.isSelected = language == .spanish
        englishButton.isSelected = language == .english
    }

    private func updateAppearanceSelection() {
        let mode = appearanceManager.mode
        darkAppearanceButton.isSelected = mode == .dark
        lightAppearanceButton.isSelected = mode == .light
        systemAppearanceButton.isSelected = mode == .system
    }

    private func updateAppleHealthStatus() {
        let status: String
        let tone: UIColor
        switch appleHealthService.state {
        case .unavailable:
            status = L10n.text("apple_health.status.unavailable")
            tone = WellnarioPalette.textTertiary
        case .notConfigured:
            status = L10n.text("integrations.connect")
            tone = WellnarioPalette.cyan
        case .syncing:
            status = L10n.text("apple_health.status.syncing")
            tone = WellnarioPalette.information
        case .failed:
            status = L10n.text("apple_health.status.error")
            tone = WellnarioPalette.warning
        case .ready:
            status = L10n.text("apple_health.status.configured")
            tone = WellnarioPalette.success
        }
        appleHealthRow.configureStatus(status, tone: tone)
    }

    @objc private func languageTapped(_ sender: LanguageChoiceControl) {
        guard sender.language != LocalizationManager.shared.language else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        LocalizationManager.shared.setLanguage(sender.language)
    }

    @objc private func appearanceTapped(_ sender: AppearanceChoiceControl) {
        guard sender.mode != appearanceManager.mode else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        appearanceManager.setMode(sender.mode)
        updateAppearanceSelection()
    }

    @objc private func integrationTapped(_ sender: IntegrationRowControl) {
        navigationController?.pushViewController(
            IntegrationSetupViewController(
                provider: sender.provider,
                appleHealthService: appleHealthService
            ),
            animated: true
        )
    }

    @objc private func closeSettings() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func appleHealthDidChange() { updateAppleHealthStatus() }
}

@MainActor
private final class SleepAdvancedOptionsViewController: UIViewController {
    private let appleHealthService: AppleHealthSyncing
    private let store: SleepManualOverrideStore

    init(appleHealthService: AppleHealthSyncing, store: SleepManualOverrideStore) {
        self.appleHealthService = appleHealthService
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "settings.advanced.sleep.root"
        title = L10n.text("settings.advanced.sleep.title")
        navigationItem.largeTitleDisplayMode = .never

        let qualityCard = optionCard(
            symbolName: "gauge.with.dots.needle.67percent",
            title: L10n.text("settings.advanced.sleep.quality.title"),
            body: L10n.text("settings.advanced.sleep.quality.body"),
            identifier: "settings.advanced.sleep.quality.card"
        )
        qualityCard.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(
                SleepQualityOptionsViewController(
                    appleHealthService: self.appleHealthService,
                    preferences: self.store.qualityPreferences
                ),
                animated: true
            )
        }, for: .touchUpInside)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text("settings.advanced.sleep.manual.title")
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        bodyLabel.text = L10n.text("settings.advanced.sleep.manual.body")
        bodyLabel.numberOfLines = 0

        let icon = UIImageView(image: UIImage(systemName: "calendar"))
        icon.tintColor = WellnarioPalette.fuchsia
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 22,
            weight: .semibold
        )
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.tintColor = WellnarioPalette.textTertiary
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let labels = UIStackView(
            arrangedSubviews: [titleLabel, bodyLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        let row = UIStackView(
            arrangedSubviews: [icon, labels, chevron],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        let card = PremiumCardView()
        card.isPressable = true
        card.accessibilityIdentifier = "settings.advanced.sleep.manual.card"
        card.accessibilityLabel = titleLabel.text
        card.accessibilityHint = bodyLabel.text
        card.contentView.addForAutoLayout(row)
        row.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        card.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(
                ManualSleepDataViewController(
                    appleHealthService: self.appleHealthService,
                    store: self.store
                ),
                animated: true
            )
        }, for: .touchUpInside)

        let notice = UILabel()
        notice.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        notice.text = L10n.text("settings.advanced.sleep.manual.local_only")
        notice.numberOfLines = 0

        let stack = UIStackView(
            arrangedSubviews: [qualityCard, card, notice],
            axis: .vertical,
            spacing: WellnarioSpacing.cardGap
        )
        stack.setCustomSpacing(WellnarioSpacing.xSmall, after: card)
        view.addForAutoLayout(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            stack.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            stack.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: WellnarioSpacing.medium
            )
        ])
    }

    private func optionCard(
        symbolName: String,
        title: String,
        body: String,
        identifier: String
    ) -> PremiumCardView {
        let icon = UIImageView(image: UIImage(systemName: symbolName))
        icon.tintColor = WellnarioPalette.fuchsia
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 22,
            weight: .semibold
        )
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = title
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        bodyLabel.text = body
        bodyLabel.numberOfLines = 0

        let labels = UIStackView(
            arrangedSubviews: [titleLabel, bodyLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.tintColor = WellnarioPalette.textTertiary
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(
            arrangedSubviews: [icon, labels, chevron],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        let card = PremiumCardView()
        card.isPressable = true
        card.accessibilityIdentifier = identifier
        card.accessibilityLabel = title
        card.accessibilityHint = body
        card.contentView.addForAutoLayout(row)
        row.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }
}

@MainActor
private final class SleepQualityOptionsViewController: UIViewController {
    private let appleHealthService: AppleHealthSyncing
    private let preferences: SleepQualityPreferences
    private let profileLabel = UILabel()
    private let targetValueLabel = UILabel()
    private let targetPicker = UIDatePicker()
    private let recommendedButton = PrimaryButton(
        title: L10n.text("settings.advanced.sleep.quality.use_recommended"),
        style: .secondary
    )
    private let durationSlider = UISlider()
    private let regularitySlider = UISlider()
    private let interruptionSlider = UISlider()
    private let durationWeightLabel = UILabel()
    private let regularityWeightLabel = UILabel()
    private let interruptionWeightLabel = UILabel()
    private let formulaLabel = UILabel()
    private var isUpdatingControls = false

    init(
        appleHealthService: AppleHealthSyncing,
        preferences: SleepQualityPreferences
    ) {
        self.appleHealthService = appleHealthService
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        loadPreferences()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appleHealthDidChange),
            name: .appleHealthSyncDidChange,
            object: appleHealthService
        )
    }

    private func setUpView() {
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "settings.advanced.sleep.quality.root"
        title = L10n.text("settings.advanced.sleep.quality.title")
        navigationItem.largeTitleDisplayMode = .never

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)

        let targetCard = makeTargetCard()
        let weightsCard = makeWeightsCard()
        let methodCard = makeMethodCard()
        let recommendationsCard = makeRecommendationsCard()
        let stack = UIStackView(
            arrangedSubviews: [targetCard, weightsCard, methodCard, recommendationsCard],
            axis: .vertical,
            spacing: WellnarioSpacing.cardGap
        )
        scrollView.addForAutoLayout(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            stack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            stack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: WellnarioSpacing.medium
            ),
            stack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -WellnarioSpacing.bottomNavigationInset
            ),
            stack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -(WellnarioSpacing.screenHorizontal * 2)
            )
        ])
    }

    private func makeTargetCard() -> PremiumCardView {
        let titleLabel = makeLabel(
            L10n.text("settings.advanced.sleep.quality.target.title"),
            style: .sectionTitle,
            color: WellnarioPalette.textPrimary
        )
        let bodyLabel = makeLabel(
            L10n.text("settings.advanced.sleep.quality.target.body"),
            style: .secondary,
            color: WellnarioPalette.textSecondary
        )
        profileLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        profileLabel.numberOfLines = 0
        profileLabel.accessibilityIdentifier = "settings.advanced.sleep.quality.profile"

        targetValueLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.fuchsia)
        targetValueLabel.textAlignment = .center
        targetValueLabel.numberOfLines = 0
        targetValueLabel.accessibilityIdentifier = "settings.advanced.sleep.quality.target.value"

        targetPicker.datePickerMode = .countDownTimer
        targetPicker.minuteInterval = 5
        targetPicker.locale = LocalizationManager.shared.locale
        targetPicker.tintColor = WellnarioPalette.fuchsia
        targetPicker.accessibilityIdentifier = "settings.advanced.sleep.quality.target.picker"
        targetPicker.addTarget(self, action: #selector(targetChanged), for: .valueChanged)

        recommendedButton.accessibilityIdentifier = "settings.advanced.sleep.quality.target.recommended"
        recommendedButton.addTarget(self, action: #selector(useRecommendedTarget), for: .touchUpInside)

        let content = UIStackView(
            arrangedSubviews: [
                titleLabel,
                bodyLabel,
                profileLabel,
                targetValueLabel,
                targetPicker,
                recommendedButton
            ],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        content.setCustomSpacing(WellnarioSpacing.xSmall, after: bodyLabel)
        return makeCard(content, identifier: "settings.advanced.sleep.quality.target.card")
    }

    private func makeWeightsCard() -> PremiumCardView {
        let titleLabel = makeLabel(
            L10n.text("settings.advanced.sleep.quality.weights.title"),
            style: .sectionTitle,
            color: WellnarioPalette.textPrimary
        )
        let bodyLabel = makeLabel(
            L10n.text("settings.advanced.sleep.quality.weights.body"),
            style: .secondary,
            color: WellnarioPalette.textSecondary
        )
        configureWeightSlider(durationSlider, index: 0, identifier: "duration")
        configureWeightSlider(regularitySlider, index: 1, identifier: "regularity")
        configureWeightSlider(interruptionSlider, index: 2, identifier: "interruptions")

        formulaLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.fuchsia)
        formulaLabel.numberOfLines = 0
        formulaLabel.textAlignment = .center
        formulaLabel.accessibilityIdentifier = "settings.advanced.sleep.quality.weights.summary"

        let content = UIStackView(
            arrangedSubviews: [
                titleLabel,
                bodyLabel,
                makeWeightRow(
                    title: L10n.text("settings.advanced.sleep.quality.weight.duration"),
                    slider: durationSlider,
                    valueLabel: durationWeightLabel
                ),
                makeWeightRow(
                    title: L10n.text("settings.advanced.sleep.quality.weight.regularity"),
                    slider: regularitySlider,
                    valueLabel: regularityWeightLabel
                ),
                makeWeightRow(
                    title: L10n.text("settings.advanced.sleep.quality.weight.interruptions"),
                    slider: interruptionSlider,
                    valueLabel: interruptionWeightLabel
                ),
                formulaLabel
            ],
            axis: .vertical,
            spacing: WellnarioSpacing.medium
        )
        content.setCustomSpacing(WellnarioSpacing.small, after: bodyLabel)
        return makeCard(content, identifier: "settings.advanced.sleep.quality.weights.card")
    }

    private func makeRecommendationsCard() -> PremiumCardView {
        let titleLabel = makeLabel(
            L10n.text("settings.advanced.sleep.quality.table.title"),
            style: .sectionTitle,
            color: WellnarioPalette.textPrimary
        )
        let bodyLabel = makeLabel(
            L10n.text("settings.advanced.sleep.quality.table.body"),
            style: .caption,
            color: WellnarioPalette.textSecondary
        )
        var rows: [UIView] = [makeRecommendationHeader()]
        for recommendation in SleepDurationRecommendation.all {
            let separator = UIView()
            separator.backgroundColor = WellnarioPalette.hairline
            separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
            rows.append(separator)
            rows.append(makeRecommendationRow(recommendation))
        }
        let table = UIStackView(
            arrangedSubviews: rows,
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )
        let sourceLabel = makeLabel(
            L10n.text("settings.advanced.sleep.quality.table.source"),
            style: .caption,
            color: WellnarioPalette.textTertiary
        )
        let content = UIStackView(
            arrangedSubviews: [titleLabel, bodyLabel, table, sourceLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        return makeCard(content, identifier: "settings.advanced.sleep.quality.table.card")
    }

    private func makeMethodCard() -> PremiumCardView {
        let titleLabel = makeLabel(
            L10n.text("settings.advanced.sleep.quality.method.title"),
            style: .sectionTitle,
            color: WellnarioPalette.textPrimary
        )
        let duration = makeMethodRow(
            symbolName: "timer",
            title: L10n.text("settings.advanced.sleep.quality.weight.duration"),
            body: L10n.text("settings.advanced.sleep.quality.method.duration")
        )
        let regularity = makeMethodRow(
            symbolName: "calendar.badge.clock",
            title: L10n.text("settings.advanced.sleep.quality.weight.regularity"),
            body: L10n.text("settings.advanced.sleep.quality.method.regularity")
        )
        let interruptions = makeMethodRow(
            symbolName: "bed.double.fill",
            title: L10n.text("settings.advanced.sleep.quality.weight.interruptions"),
            body: L10n.text("settings.advanced.sleep.quality.method.interruptions")
        )
        let content = UIStackView(
            arrangedSubviews: [titleLabel, duration, regularity, interruptions],
            axis: .vertical,
            spacing: WellnarioSpacing.medium
        )
        return makeCard(content, identifier: "settings.advanced.sleep.quality.method.card")
    }

    private func makeMethodRow(
        symbolName: String,
        title: String,
        body: String
    ) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbolName))
        icon.tintColor = WellnarioPalette.fuchsia
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 17,
            weight: .semibold
        )
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let titleLabel = makeLabel(title, style: .body, color: WellnarioPalette.textPrimary)
        let bodyLabel = makeLabel(body, style: .caption, color: WellnarioPalette.textSecondary)
        let labels = UIStackView(
            arrangedSubviews: [titleLabel, bodyLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        return UIStackView(
            arrangedSubviews: [icon, labels],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .top
        )
    }

    private func makeWeightRow(
        title: String,
        slider: UISlider,
        valueLabel: UILabel
    ) -> UIView {
        let titleLabel = makeLabel(title, style: .body, color: WellnarioPalette.textPrimary)
        valueLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.fuchsia)
        valueLabel.textAlignment = .right
        valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
        let header = UIStackView(
            arrangedSubviews: [titleLabel, UIView(), valueLabel],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        return UIStackView(
            arrangedSubviews: [header, slider],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )
    }

    private func configureWeightSlider(
        _ slider: UISlider,
        index: Int,
        identifier: String
    ) {
        slider.tag = index
        slider.minimumValue = 0
        slider.maximumValue = 100
        slider.minimumTrackTintColor = WellnarioPalette.fuchsia
        slider.maximumTrackTintColor = WellnarioPalette.hairline
        slider.thumbTintColor = WellnarioPalette.fuchsia
        slider.isContinuous = true
        slider.accessibilityIdentifier = "settings.advanced.sleep.quality.weight.\(identifier)"
        slider.addTarget(self, action: #selector(weightChanged(_:)), for: .valueChanged)
    }

    private func makeRecommendationHeader() -> UIView {
        let row = recommendationColumns(
            age: L10n.text("settings.advanced.sleep.quality.table.age"),
            duration: L10n.text("settings.advanced.sleep.quality.table.duration"),
            style: .caption,
            color: WellnarioPalette.textTertiary
        )
        row.accessibilityIdentifier = "settings.advanced.sleep.quality.table.header"
        return row
    }

    private func makeRecommendationRow(_ recommendation: SleepDurationRecommendation) -> UIView {
        let range = L10n.text(
            "settings.advanced.sleep.quality.table.range",
            Int(recommendation.minimumHours),
            Int(recommendation.maximumHours)
        )
        let row = recommendationColumns(
            age: L10n.text(
                "settings.advanced.sleep.quality.age.\(recommendation.ageGroup.rawValue)"
            ),
            duration: range,
            style: .caption,
            color: WellnarioPalette.textPrimary
        )
        row.accessibilityIdentifier = "settings.advanced.sleep.quality.table.row.\(recommendation.ageGroup.rawValue)"
        return row
    }

    private func recommendationColumns(
        age: String,
        duration: String,
        style: WellnarioTextStyle,
        color: UIColor
    ) -> UIStackView {
        let ageLabel = makeLabel(age, style: style, color: color)
        ageLabel.textAlignment = .left
        let durationLabel = makeLabel(duration, style: style, color: color)
        durationLabel.textAlignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(
            arrangedSubviews: [ageLabel, durationLabel],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        return row
    }

    private func makeLabel(
        _ text: String,
        style: WellnarioTextStyle,
        color: UIColor
    ) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(style, color: color)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    private func makeCard(_ content: UIView, identifier: String) -> PremiumCardView {
        let card = PremiumCardView()
        card.accessibilityIdentifier = identifier
        card.contentView.addForAutoLayout(content)
        content.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }

    private func loadPreferences() {
        isUpdatingControls = true
        let recommendation = preferences.recommendation(
            dateOfBirthComponents: appleHealthService.snapshot.dateOfBirthComponents
        )
        let configuration = preferences.configuration(
            dateOfBirthComponents: appleHealthService.snapshot.dateOfBirthComponents
        )
        targetPicker.countDownDuration = min(
            max(configuration.targetHours * 3_600, 60),
            23 * 3_600 + 55 * 60
        )
        durationSlider.value = Float(configuration.weights.duration)
        regularitySlider.value = Float(configuration.weights.regularity)
        interruptionSlider.value = Float(configuration.weights.interruptions)
        updateProfileLabel(recommendation)
        updateDisplayedValues()
        isUpdatingControls = false
    }

    private func updateProfileLabel(_ recommendation: SleepDurationRecommendation) {
        let ageGroup = L10n.text(
            "settings.advanced.sleep.quality.age.\(recommendation.ageGroup.rawValue)"
        )
        let range = L10n.text(
            "settings.advanced.sleep.quality.table.range",
            Int(recommendation.minimumHours),
            Int(recommendation.maximumHours)
        )
        if appleHealthService.snapshot.dateOfBirthComponents == nil {
            profileLabel.text = L10n.text(
                "settings.advanced.sleep.quality.profile.unavailable",
                range
            )
        } else {
            profileLabel.text = L10n.text(
                "settings.advanced.sleep.quality.profile.available",
                ageGroup,
                range
            )
        }
    }

    private func updateDisplayedValues() {
        let duration = Int(durationSlider.value.rounded())
        let regularity = Int(regularitySlider.value.rounded())
        let interruptions = Int(interruptionSlider.value.rounded())
        durationWeightLabel.text = L10n.text(
            "settings.advanced.sleep.quality.weight.value",
            duration
        )
        regularityWeightLabel.text = L10n.text(
            "settings.advanced.sleep.quality.weight.value",
            regularity
        )
        interruptionWeightLabel.text = L10n.text(
            "settings.advanced.sleep.quality.weight.value",
            interruptions
        )
        formulaLabel.text = L10n.text(
            "settings.advanced.sleep.quality.weights.summary",
            duration,
            regularity,
            interruptions
        )
        let target = targetPicker.countDownDuration
        let targetText = AppleHealthUIFormatting.duration(target)
        let key = preferences.customTargetHours == nil
            ? "settings.advanced.sleep.quality.target.recommended_value"
            : "settings.advanced.sleep.quality.target.custom_value"
        targetValueLabel.text = L10n.text(key, targetText)
        recommendedButton.isHidden = preferences.customTargetHours == nil
    }

    @objc private func targetChanged() {
        guard !isUpdatingControls else { return }
        let hours = targetPicker.countDownDuration / 3_600
        _ = preferences.setCustomTargetHours(hours)
        updateDisplayedValues()
    }

    @objc private func useRecommendedTarget() {
        preferences.useRecommendedTarget()
        UISelectionFeedbackGenerator().selectionChanged()
        loadPreferences()
    }

    @objc private func weightChanged(_ sender: UISlider) {
        guard !isUpdatingControls else { return }
        isUpdatingControls = true
        sender.setValue(sender.value.rounded(), animated: false)
        var values = [
            Int(durationSlider.value.rounded()),
            Int(regularitySlider.value.rounded()),
            Int(interruptionSlider.value.rounded())
        ]
        let changedIndex = sender.tag
        let remainingIndices = values.indices.filter { $0 != changedIndex }
        let available = 100 - values[changedIndex]
        let previousRemainder = remainingIndices.reduce(0) { $0 + values[$1] }
        let firstValue: Int
        if previousRemainder > 0 {
            firstValue = Int(
                (Double(available) * Double(values[remainingIndices[0]])
                    / Double(previousRemainder)).rounded()
            )
        } else {
            firstValue = available / 2
        }
        values[remainingIndices[0]] = firstValue
        values[remainingIndices[1]] = available - firstValue
        durationSlider.value = Float(values[0])
        regularitySlider.value = Float(values[1])
        interruptionSlider.value = Float(values[2])
        _ = preferences.setWeights(SleepQualityWeights(
            duration: values[0],
            regularity: values[1],
            interruptions: values[2]
        ))
        updateDisplayedValues()
        isUpdatingControls = false
    }

    @objc private func appleHealthDidChange() {
        loadPreferences()
    }
}

@MainActor
private final class ManualSleepDataViewController: UIViewController,
    UICalendarSelectionSingleDateDelegate {
    private let appleHealthService: AppleHealthSyncing
    private let store: SleepManualOverrideStore
    private let calendarView = UICalendarView()
    private let selectedDateLabel = UILabel()
    private let sourceLabel = UILabel()
    private let qualitySwitch = UISwitch()
    private let qualitySlider = UISlider()
    private let qualityValueLabel = UILabel()
    private let durationSwitch = UISwitch()
    private let durationPicker = UIDatePicker()
    private let saveButton = PrimaryButton(title: L10n.Common.save)
    private let removeButton = PrimaryButton(
        title: L10n.text("settings.advanced.sleep.manual.remove"),
        style: .destructive
    )
    private var selectedDayHasQuality = false
    private var selectedDay = LocalDay(containing: Date(), in: .current)
    private lazy var calendarSelection = UICalendarSelectionSingleDate(delegate: self)

    init(appleHealthService: AppleHealthSyncing, store: SleepManualOverrideStore) {
        self.appleHealthService = appleHealthService
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        selectInitialDay()
        loadSelectedDay()
    }

    private func setUpView() {
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "settings.advanced.sleep.manual.root"
        title = L10n.text("settings.advanced.sleep.manual.title")
        navigationItem.largeTitleDisplayMode = .never

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)

        calendarView.calendar = .autoupdatingCurrent
        calendarView.locale = LocalizationManager.shared.locale
        calendarView.tintColor = WellnarioPalette.fuchsia
        calendarView.selectionBehavior = calendarSelection
        calendarView.accessibilityIdentifier = "settings.advanced.sleep.manual.calendar"
        if let earliest = Calendar.autoupdatingCurrent.date(
            from: DateComponents(year: 1900, month: 1, day: 1)
        ) {
            calendarView.availableDateRange = DateInterval(start: earliest, end: Date())
        }
        calendarView.heightAnchor.constraint(equalToConstant: 340).isActive = true

        let calendarCard = PremiumCardView()
        calendarCard.contentView.addForAutoLayout(calendarView)
        calendarView.pinEdges(
            to: calendarCard.contentView,
            insets: NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        )

        selectedDateLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        selectedDateLabel.numberOfLines = 0
        selectedDateLabel.accessibilityIdentifier = "settings.advanced.sleep.manual.selected_date"

        sourceLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        sourceLabel.numberOfLines = 0
        sourceLabel.accessibilityIdentifier = "settings.advanced.sleep.manual.source"

        qualitySwitch.onTintColor = WellnarioPalette.fuchsia
        qualitySwitch.accessibilityIdentifier = "settings.advanced.sleep.manual.quality.toggle"
        qualitySwitch.addTarget(self, action: #selector(overrideToggleChanged), for: .valueChanged)

        qualityValueLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.fuchsia)
        qualityValueLabel.textAlignment = .right
        qualityValueLabel.accessibilityIdentifier = "settings.advanced.sleep.manual.quality.value"

        qualitySlider.minimumValue = Float(SleepManualOverrideStore.qualityRange.lowerBound)
        qualitySlider.maximumValue = Float(SleepManualOverrideStore.qualityRange.upperBound)
        qualitySlider.minimumTrackTintColor = WellnarioPalette.fuchsia
        qualitySlider.maximumTrackTintColor = WellnarioPalette.hairline
        qualitySlider.thumbTintColor = WellnarioPalette.fuchsia
        qualitySlider.accessibilityIdentifier = "settings.advanced.sleep.manual.quality.slider"
        qualitySlider.accessibilityLabel = L10n.text("settings.advanced.sleep.manual.quality")
        qualitySlider.addTarget(self, action: #selector(qualityChanged), for: .valueChanged)

        durationSwitch.onTintColor = WellnarioPalette.fuchsia
        durationSwitch.accessibilityIdentifier = "settings.advanced.sleep.manual.duration.toggle"
        durationSwitch.addTarget(self, action: #selector(overrideToggleChanged), for: .valueChanged)

        durationPicker.datePickerMode = .countDownTimer
        durationPicker.minuteInterval = 1
        durationPicker.locale = LocalizationManager.shared.locale
        durationPicker.tintColor = WellnarioPalette.fuchsia
        durationPicker.accessibilityIdentifier = "settings.advanced.sleep.manual.duration.picker"

        let qualityTitle = makeToggleHeader(
            title: L10n.text("settings.advanced.sleep.manual.quality"),
            valueView: qualityValueLabel,
            toggle: qualitySwitch
        )
        let qualityHelp = UILabel()
        qualityHelp.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        qualityHelp.text = L10n.text("settings.advanced.sleep.manual.quality.help")
        qualityHelp.numberOfLines = 0
        let qualityStack = UIStackView(
            arrangedSubviews: [qualityTitle, qualitySlider, qualityHelp],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )

        let separator = UIView()
        separator.backgroundColor = WellnarioPalette.hairline
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let durationTitle = makeToggleHeader(
            title: L10n.text("settings.advanced.sleep.manual.duration"),
            valueView: nil,
            toggle: durationSwitch
        )
        let durationStack = UIStackView(
            arrangedSubviews: [durationTitle, durationPicker],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )

        let localOnlyLabel = UILabel()
        localOnlyLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        localOnlyLabel.text = L10n.text("settings.advanced.sleep.manual.local_only")
        localOnlyLabel.numberOfLines = 0

        let dataContent = UIStackView(
            arrangedSubviews: [
                selectedDateLabel,
                sourceLabel,
                qualityStack,
                separator,
                durationStack,
                localOnlyLabel
            ],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        dataContent.setCustomSpacing(WellnarioSpacing.xSmall, after: selectedDateLabel)
        let dataCard = PremiumCardView()
        dataCard.accessibilityIdentifier = "settings.advanced.sleep.manual.data.card"
        dataCard.contentView.addForAutoLayout(dataContent)
        dataContent.pinEdges(to: dataCard.contentView, insets: .all(WellnarioSpacing.cardPadding))

        saveButton.accessibilityIdentifier = "settings.advanced.sleep.manual.save"
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        removeButton.accessibilityIdentifier = "settings.advanced.sleep.manual.remove"
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)

        let stack = UIStackView(
            arrangedSubviews: [calendarCard, dataCard, saveButton, removeButton],
            axis: .vertical,
            spacing: WellnarioSpacing.cardGap
        )
        scrollView.addForAutoLayout(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            stack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            stack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: WellnarioSpacing.medium
            ),
            stack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -WellnarioSpacing.bottomNavigationInset
            ),
            stack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -(WellnarioSpacing.screenHorizontal * 2)
            )
        ])
    }

    private func makeToggleHeader(
        title: String,
        valueView: UIView?,
        toggle: UISwitch
    ) -> UIStackView {
        let label = UILabel()
        label.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        label.text = title
        label.numberOfLines = 0
        var views: [UIView] = [label, UIView()]
        if let valueView { views.append(valueView) }
        views.append(toggle)
        return UIStackView(
            arrangedSubviews: views,
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
    }

    private func selectInitialDay() {
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day],
            from: Date()
        )
        calendarSelection.setSelected(components, animated: false)
    }

    private func loadSelectedDay() {
        let manualOverride = store.override(for: selectedDay)
        let healthEntry = effectiveHealthEntry(for: selectedDay)
        let availableQuality = manualOverride?.qualityScore ?? healthEntry?.qualityScore
        selectedDayHasQuality = availableQuality != nil
        let quality = availableQuality ?? 80
        let duration = manualOverride?.durationHours ?? healthEntry?.hours ?? 8

        qualitySwitch.setOn(manualOverride?.qualityScore != nil, animated: false)
        durationSwitch.setOn(manualOverride?.durationHours != nil, animated: false)
        qualitySlider.setValue(Float(quality), animated: false)
        durationPicker.countDownDuration = min(
            max(duration * 3_600, 60),
            23 * 3_600 + 59 * 60
        )
        selectedDateLabel.text = formattedSelectedDay()

        if manualOverride != nil {
            sourceLabel.text = L10n.text("settings.advanced.sleep.manual.source.manual")
            sourceLabel.textColor = WellnarioPalette.fuchsia
        } else if healthEntry?.hours != nil || healthEntry?.qualityScore != nil {
            sourceLabel.text = L10n.text("settings.advanced.sleep.manual.source.apple_health")
            sourceLabel.textColor = WellnarioPalette.success
        } else {
            sourceLabel.text = L10n.text("settings.advanced.sleep.manual.source.empty")
            sourceLabel.textColor = WellnarioPalette.textTertiary
        }
        removeButton.isHidden = manualOverride == nil
        updateControls()
    }

    private func effectiveHealthEntry(for day: LocalDay) -> AppleHealthSleepDay? {
        store.applying(to: appleHealthService.snapshot).sleepTrend.last {
            LocalDay(containing: $0.date, in: .current) == day
        }
    }

    private func formattedSelectedDay() -> String {
        guard let date = try? selectedDay.startDate(in: .current) else {
            return selectedDay.iso8601
        }
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func updateControls() {
        let qualityEnabled = qualitySwitch.isOn
        qualitySlider.isEnabled = qualityEnabled
        qualitySlider.alpha = qualityEnabled ? 1 : 0.42
        qualityValueLabel.alpha = qualityEnabled ? 1 : 0.55

        let durationEnabled = durationSwitch.isOn
        durationPicker.isEnabled = durationEnabled
        durationPicker.alpha = durationEnabled ? 1 : 0.42

        if qualityEnabled || selectedDayHasQuality {
            let roundedQuality = Int(qualitySlider.value.rounded())
            qualityValueLabel.text = L10n.text(
                "settings.advanced.sleep.manual.quality.value",
                roundedQuality
            )
            qualitySlider.accessibilityValue = qualityValueLabel.text
        } else {
            qualityValueLabel.text = "—"
            qualitySlider.accessibilityValue = L10n.text("wellness.no_data")
        }
        saveButton.isEnabled = qualityEnabled || durationEnabled
        saveButton.alpha = saveButton.isEnabled ? 1 : 0.5
    }

    private func showValidationMessage(_ message: String) {
        let alert = UIAlertController(
            title: L10n.text("settings.advanced.sleep.manual.validation.title"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
        present(alert, animated: true)
    }

    @objc private func overrideToggleChanged() {
        UISelectionFeedbackGenerator().selectionChanged()
        updateControls()
    }

    @objc private func qualityChanged(_ sender: UISlider) {
        sender.setValue(sender.value.rounded(), animated: false)
        updateControls()
    }

    @objc private func saveTapped() {
        let quality = qualitySwitch.isOn ? Double(qualitySlider.value.rounded()) : nil
        let duration = durationSwitch.isOn ? durationPicker.countDownDuration / 3_600 : nil
        guard quality != nil || duration != nil else {
            showValidationMessage(
                L10n.text("settings.advanced.sleep.manual.validation.empty")
            )
            return
        }
        guard store.save(
            day: selectedDay,
            qualityScore: quality,
            durationHours: duration
        ) else {
            showValidationMessage(
                L10n.text("settings.advanced.sleep.manual.validation.invalid")
            )
            return
        }
        UIImpactFeedbackGenerator.wellnarioSuccess()
        _ = FeedbackPresenter.show(
            message: L10n.text("settings.advanced.sleep.manual.saved"),
            tone: .success,
            in: view
        )
        loadSelectedDay()
    }

    @objc private func removeTapped() {
        let alert = UIAlertController(
            title: L10n.text("settings.advanced.sleep.manual.remove.confirmation.title"),
            message: L10n.text("settings.advanced.sleep.manual.remove.confirmation.body"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(
            title: L10n.text("settings.advanced.sleep.manual.remove"),
            style: .destructive
        ) { [weak self] _ in
            guard let self else { return }
            self.store.remove(day: self.selectedDay)
            UIImpactFeedbackGenerator.wellnarioSuccess()
            self.loadSelectedDay()
        })
        present(alert, animated: true)
    }

    func dateSelection(
        _ selection: UICalendarSelectionSingleDate,
        didSelectDate dateComponents: DateComponents?
    ) {
        guard let dateComponents,
              let date = Calendar.autoupdatingCurrent.date(from: dateComponents) else { return }
        selectedDay = LocalDay(containing: date, in: .current)
        UISelectionFeedbackGenerator().selectionChanged()
        loadSelectedDay()
    }

    func dateSelection(
        _ selection: UICalendarSelectionSingleDate,
        canSelectDate dateComponents: DateComponents?
    ) -> Bool {
        guard let dateComponents,
              let date = Calendar.autoupdatingCurrent.date(from: dateComponents) else { return false }
        return date <= Date()
    }
}

@MainActor
private final class AdvancedOptionsPlaceholderViewController: UIViewController {
    private let navigationTitle: String

    init(title: String) {
        navigationTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WellnarioPalette.background
        title = navigationTitle
        navigationItem.largeTitleDisplayMode = .never

        let emptyState = EmptyStateView()
        emptyState.configure(
            kind: .other,
            title: L10n.text("settings.advanced.empty.title"),
            message: L10n.text("settings.advanced.empty.body"),
            actionTitle: nil
        )
        view.addForAutoLayout(emptyState)
        emptyState.pinEdges(to: view.safeAreaLayoutGuide, insets: .all(WellnarioSpacing.large))
    }
}

@MainActor
private final class SupplementAdvancedOptionsViewController: UIViewController {
    private let preferences: ActiveTargetMarginPreferences
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private let exampleLabel = UILabel()
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private var displayedPercentage: Int

    init(preferences: ActiveTargetMarginPreferences) {
        self.preferences = preferences
        displayedPercentage = preferences.percentage
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        updateDisplayedValue()
    }

    private func setUpView() {
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "settings.advanced.supplements.root"
        title = L10n.text("settings.advanced.supplements.title")
        navigationItem.largeTitleDisplayMode = .never

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text("settings.advanced.target_margin.title")
        titleLabel.numberOfLines = 0

        let descriptionLabel = UILabel()
        descriptionLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        descriptionLabel.text = L10n.text("settings.advanced.target_margin.body")
        descriptionLabel.numberOfLines = 0

        valueLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.fuchsia)
        valueLabel.textAlignment = .center
        valueLabel.accessibilityIdentifier = "settings.advanced.target_margin.value"

        let valueContainer = UIView()
        valueContainer.backgroundColor = WellnarioPalette.fuchsia.withAlphaComponent(0.12)
        valueContainer.applyContinuousCorners(WellnarioRadius.control)
        valueContainer.addForAutoLayout(valueLabel)
        valueLabel.pinEdges(
            to: valueContainer,
            insets: NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        )

        slider.minimumValue = Float(ActiveTargetMarginPreferences.allowedPercentages.lowerBound)
        slider.maximumValue = Float(ActiveTargetMarginPreferences.allowedPercentages.upperBound)
        slider.value = Float(displayedPercentage)
        slider.minimumTrackTintColor = WellnarioPalette.fuchsia
        slider.maximumTrackTintColor = WellnarioPalette.hairline
        slider.thumbTintColor = WellnarioPalette.fuchsia
        slider.isContinuous = true
        slider.accessibilityIdentifier = "settings.advanced.target_margin.slider"
        slider.accessibilityLabel = L10n.text("settings.advanced.target_margin.title")
        slider.accessibilityHint = L10n.text("settings.advanced.target_margin.accessibility_hint")
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)

        let minimumLabel = endpointLabel(
            percentage: ActiveTargetMarginPreferences.allowedPercentages.lowerBound
        )
        let maximumLabel = endpointLabel(
            percentage: ActiveTargetMarginPreferences.allowedPercentages.upperBound
        )
        let endpoints = UIStackView(
            arrangedSubviews: [minimumLabel, UIView(), maximumLabel],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )

        exampleLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        exampleLabel.numberOfLines = 0

        let exampleIcon = UIImageView(image: UIImage(systemName: "scope"))
        exampleIcon.tintColor = WellnarioPalette.fuchsia
        exampleIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 19,
            weight: .semibold
        )
        exampleIcon.setContentHuggingPriority(.required, for: .horizontal)

        let exampleRow = UIStackView(
            arrangedSubviews: [exampleIcon, exampleLabel],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .top
        )
        let exampleContainer = UIView()
        exampleContainer.backgroundColor = WellnarioPalette.fuchsia.withAlphaComponent(0.08)
        exampleContainer.applyContinuousCorners(WellnarioRadius.control)
        exampleContainer.addForAutoLayout(exampleRow)
        exampleRow.pinEdges(
            to: exampleContainer,
            insets: NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        )

        let controlsStack = UIStackView(
            arrangedSubviews: [valueContainer, slider, endpoints],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .fill
        )
        valueContainer.setContentHuggingPriority(.required, for: .vertical)

        let content = UIStackView(
            arrangedSubviews: [titleLabel, descriptionLabel, controlsStack, exampleContainer],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        let card = PremiumCardView()
        card.accessibilityIdentifier = "settings.advanced.target_margin.card"
        card.contentView.addForAutoLayout(content)
        content.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))

        scrollView.addForAutoLayout(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            card.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            card.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: WellnarioSpacing.medium
            ),
            card.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -WellnarioSpacing.bottomNavigationInset
            ),
            card.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -(WellnarioSpacing.screenHorizontal * 2)
            )
        ])
    }

    private func endpointLabel(percentage: Int) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        label.text = L10n.text("settings.advanced.target_margin.percentage", percentage)
        return label
    }

    private func updateDisplayedValue() {
        let percentageText = L10n.text(
            "settings.advanced.target_margin.percentage",
            displayedPercentage
        )
        valueLabel.text = percentageText
        slider.accessibilityValue = percentageText

        let target: Decimal = 26
        let ratio = Decimal(displayedPercentage) / 100
        let lower = target * (1 - ratio)
        let upper = target * (1 + ratio)
        exampleLabel.text = L10n.text(
            "settings.advanced.target_margin.example",
            displayedPercentage,
            FeatureFormatting.decimal(lower),
            FeatureFormatting.decimal(upper)
        )
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        let percentage = Int(sender.value.rounded())
        sender.setValue(Float(percentage), animated: false)
        guard percentage != displayedPercentage else { return }
        displayedPercentage = percentage
        preferences.setPercentage(percentage)
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
        updateDisplayedValue()
    }
}

@MainActor
private final class LanguageChoiceControl: UIControl {
    let language: AppLanguage

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet {
            WellnarioMotion.spring(duration: 0.16) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.985, y: 0.985)
                    : .identity
            }
        }
    }

    private let titleLabel = UILabel()
    private let checkView = UIImageView()

    init(language: AppLanguage) {
        self.language = language
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        backgroundColor = WellnarioPalette.surfaceElevated
        applyContinuousCorners(WellnarioRadius.control)
        layer.borderWidth = 1
        heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true

        titleLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        titleLabel.text = language.nativeDisplayName

        checkView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        checkView.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(
            arrangedSubviews: [titleLabel, checkView],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        // Keep hit testing on the UIControl itself. UIStackView otherwise
        // receives the synthesized/physical touch and the value-change action
        // never fires.
        row.isUserInteractionEnabled = false
        addForAutoLayout(row)
        row.pinEdges(to: self, insets: NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = language.nativeDisplayName
        updateAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (self: LanguageChoiceControl, _: UITraitCollection) in
            self.updateAppearance()
        }
    }

    private func updateAppearance() {
        checkView.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        checkView.tintColor = isSelected ? WellnarioPalette.fuchsia : WellnarioPalette.textTertiary
        layer.borderColor = (isSelected ? WellnarioPalette.fuchsia.withAlphaComponent(0.55) : WellnarioPalette.hairline).cgColor
        backgroundColor = isSelected
            ? WellnarioPalette.fuchsia.withAlphaComponent(0.10)
            : WellnarioPalette.surfaceElevated
        if isSelected {
            accessibilityTraits.insert(.selected)
            accessibilityValue = L10n.Common.status
        } else {
            accessibilityTraits.remove(.selected)
            accessibilityValue = nil
        }
    }
}

@MainActor
private final class AppearanceChoiceControl: UIControl {
    let mode: WellnarioAppearanceMode

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet {
            WellnarioMotion.spring(duration: 0.16) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.985, y: 0.985)
                    : .identity
            }
        }
    }

    private let titleLabel = UILabel()
    private let checkView = UIImageView()

    init(mode: WellnarioAppearanceMode) {
        self.mode = mode
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        backgroundColor = WellnarioPalette.surfaceElevated
        applyContinuousCorners(WellnarioRadius.control)
        layer.borderWidth = 1
        heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true

        titleLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        titleLabel.text = title

        checkView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        checkView.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(
            arrangedSubviews: [titleLabel, checkView],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        row.isUserInteractionEnabled = false
        addForAutoLayout(row)
        row.pinEdges(
            to: self,
            insets: NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        )

        isAccessibilityElement = true
        accessibilityTraits = [.button]
        accessibilityLabel = title
        updateAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (self: AppearanceChoiceControl, _: UITraitCollection) in
            self.updateAppearance()
        }
    }

    private var title: String {
        switch mode {
        case .dark: L10n.Settings.appearanceDark
        case .light: L10n.Settings.appearanceLight
        case .system: L10n.Settings.appearanceSystem
        }
    }

    private func updateAppearance() {
        checkView.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        checkView.tintColor = isSelected ? WellnarioPalette.fuchsia : WellnarioPalette.textTertiary
        layer.borderColor = (
            isSelected
                ? WellnarioPalette.fuchsia.withAlphaComponent(0.55)
                : WellnarioPalette.hairline
        ).cgColor
        backgroundColor = isSelected
            ? WellnarioPalette.fuchsia.withAlphaComponent(0.10)
            : WellnarioPalette.surfaceElevated
        if isSelected {
            accessibilityTraits.insert(.selected)
            accessibilityValue = L10n.Common.status
        } else {
            accessibilityTraits.remove(.selected)
            accessibilityValue = nil
        }
    }
}
