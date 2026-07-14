import UIKit

@MainActor
final class SettingsViewController: UIViewController {
    private let spanishButton = LanguageChoiceControl(language: .spanish)
    private let englishButton = LanguageChoiceControl(language: .english)

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        updateSelection()
    }

    private func setUpView() {
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "settings.root"
        title = L10n.Settings.title
        navigationItem.largeTitleDisplayMode = .never

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

        let integrationsTitle = makeSectionTitle(L10n.text("integrations.title"))
        let integrationsFooter = UILabel()
        integrationsFooter.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        integrationsFooter.text = L10n.text("integrations.footer")
        integrationsFooter.numberOfLines = 0

        let appleHealth = IntegrationRowControl(provider: .appleHealth)
        let oura = IntegrationRowControl(provider: .oura)
        appleHealth.addTarget(self, action: #selector(integrationTapped(_:)), for: .touchUpInside)
        oura.addTarget(self, action: #selector(integrationTapped(_:)), for: .touchUpInside)
        let integrationRows = UIStackView(
            arrangedSubviews: [appleHealth, oura],
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

        let aboutCard = makeInformationCard(
            symbolName: "sparkles",
            title: L10n.Settings.about,
            body: L10n.Settings.aboutBody,
            tone: WellnarioPalette.violet,
            identifier: "settings.about"
        )
        let privacyCard = makeInformationCard(
            symbolName: "lock.shield.fill",
            title: L10n.Settings.privacy,
            body: L10n.text("settings.privacy.body"),
            tone: WellnarioPalette.success,
            identifier: "settings.privacy"
        )
        let disclaimerCard = makeInformationCard(
            symbolName: "cross.case.fill",
            title: L10n.Settings.medicalDisclaimer,
            body: L10n.Settings.medicalDisclaimerBody,
            tone: WellnarioPalette.cyan,
            identifier: "settings.medicalDisclaimer"
        )

        let contentStack = UIStackView(
            arrangedSubviews: [integrationsCard, languageCard, aboutCard, privacyCard, disclaimerCard],
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

    private func makeInformationCard(
        symbolName: String,
        title: String,
        body: String,
        tone: UIColor,
        identifier: String
    ) -> PremiumCardView {
        let symbol = UIImageView(image: UIImage(systemName: symbolName))
        symbol.tintColor = tone
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        symbol.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = title
        titleLabel.numberOfLines = 0

        let heading = UIStackView(
            arrangedSubviews: [symbol, titleLabel],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        bodyLabel.text = body
        bodyLabel.numberOfLines = 0

        let stack = UIStackView(
            arrangedSubviews: [heading, bodyLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        let card = makeCard(containing: stack, identifier: identifier)
        card.isAccessibilityElement = true
        card.accessibilityLabel = [title, body].joined(separator: ". ")
        return card
    }

    private func updateSelection() {
        let language = LocalizationManager.shared.language
        spanishButton.isSelected = language == .spanish
        englishButton.isSelected = language == .english
    }

    @objc private func languageTapped(_ sender: LanguageChoiceControl) {
        guard sender.language != LocalizationManager.shared.language else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        LocalizationManager.shared.setLanguage(sender.language)
    }

    @objc private func integrationTapped(_ sender: IntegrationRowControl) {
        navigationController?.pushViewController(
            IntegrationSetupViewController(provider: sender.provider),
            animated: true
        )
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
    }

    private func updateAppearance() {
        checkView.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        checkView.tintColor = isSelected ? WellnarioPalette.cyan : WellnarioPalette.textTertiary
        layer.borderColor = (isSelected ? WellnarioPalette.cyan.withAlphaComponent(0.55) : WellnarioPalette.hairline).cgColor
        backgroundColor = isSelected
            ? WellnarioPalette.cyan.withAlphaComponent(0.10)
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
