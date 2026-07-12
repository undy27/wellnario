import UIKit

@MainActor
final class MoreViewController: UIViewController {
    var onSelectFeature: ((MoreFeature) -> Void)?
    var onOpenSettings: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let featureStack = UIStackView()
    private let subtitleLabel = UILabel()
    private var featureCards: [(feature: MoreFeature, card: PremiumCardView)] = []
    private var usesSingleColumn: Bool?

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        applyLocalizedCopy()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let newValue = shouldUseSingleColumn
        guard usesSingleColumn != newValue else { return }
        usesSingleColumn = newValue
        rebuildFeatureGrid(singleColumn: newValue)
    }

    private func setUpView() {
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "more.root"
        navigationItem.largeTitleDisplayMode = .always

        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .automatic
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)

        contentStack.axis = .vertical
        contentStack.spacing = WellnarioSpacing.large
        scrollView.addForAutoLayout(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: WellnarioSpacing.xSmall),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.bottomNavigationInset),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(WellnarioSpacing.screenHorizontal * 2))
        ])

        subtitleLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        subtitleLabel.numberOfLines = 0
        contentStack.addArrangedSubview(subtitleLabel)

        featureStack.axis = .vertical
        featureStack.spacing = WellnarioSpacing.cardGap
        contentStack.addArrangedSubview(featureStack)

        featureCards = MoreFeature.allCases.map { feature in
            let card = makeFeatureCard(for: feature)
            return (feature, card)
        }
        usesSingleColumn = shouldUseSingleColumn
        rebuildFeatureGrid(singleColumn: usesSingleColumn ?? false)

        let settingsCard = makeSettingsCard()
        contentStack.addArrangedSubview(settingsCard)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LocalizationManager.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private var shouldUseSingleColumn: Bool {
        traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            || (view.bounds.width > 0 && view.bounds.width < 350)
    }

    private func rebuildFeatureGrid(singleColumn: Bool) {
        featureStack.arrangedSubviews.forEach {
            featureStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if singleColumn {
            featureCards.forEach { featureStack.addArrangedSubview($0.card) }
            return
        }

        var index = 0
        while index < featureCards.count {
            let cards = Array(featureCards[index..<min(index + 2, featureCards.count)]).map(\.card)
            let row = UIStackView(
                arrangedSubviews: cards,
                axis: .horizontal,
                spacing: WellnarioSpacing.cardGap,
                alignment: .fill,
                distribution: .fillEqually
            )
            featureStack.addArrangedSubview(row)
            index += 2
        }
    }

    private func makeFeatureCard(for feature: MoreFeature) -> PremiumCardView {
        let card = PremiumCardView()
        card.isPressable = true
        card.contentView.isUserInteractionEnabled = false
        card.isAccessibilityElement = true
        card.tag = MoreFeature.allCases.firstIndex(of: feature) ?? 0
        card.accessibilityIdentifier = feature.accessibilityIdentifier
        card.accessibilityLabel = feature.title
        card.accessibilityHint = L10n.More.comingSoon
        card.addTarget(self, action: #selector(featureTapped(_:)), for: .touchUpInside)
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 176).isActive = true

        let iconContainer = GradientIconView(
            symbolName: feature.symbolName,
            colors: feature.accentColors
        )
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 48),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor)
        ])

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = feature.title
        titleLabel.numberOfLines = 2
        titleLabel.accessibilityIdentifier = "\(feature.accessibilityIdentifier).title"

        let descriptionLabel = UILabel()
        descriptionLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        descriptionLabel.text = feature.featureDescription
        descriptionLabel.numberOfLines = 3

        let arrow = UIImageView(image: UIImage(systemName: "arrow.up.right"))
        arrow.tintColor = feature.accentColors.first
        arrow.setContentHuggingPriority(.required, for: .horizontal)

        let titleRow = UIStackView(
            arrangedSubviews: [titleLabel, arrow],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .firstBaseline
        )
        let stack = UIStackView(
            arrangedSubviews: [iconContainer, titleRow, descriptionLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall,
            alignment: .fill
        )
        card.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.small))
        return card
    }

    private func makeSettingsCard() -> PremiumCardView {
        let card = PremiumCardView()
        card.isPressable = true
        card.contentView.isUserInteractionEnabled = false
        card.isAccessibilityElement = true
        card.showsAccent = true
        card.accessibilityIdentifier = "more.settings"
        card.accessibilityLabel = L10n.More.settings
        card.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true

        let icon = GradientIconView(
            symbolName: "gearshape.fill",
            colors: [WellnarioPalette.cyan, WellnarioPalette.violet]
        )
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        title.text = L10n.More.settings
        title.accessibilityIdentifier = "more.settings.title"

        let detail = UILabel()
        detail.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detail.text = L10n.Settings.languageFooter
        detail.numberOfLines = 2

        let labels = UIStackView(
            arrangedSubviews: [title, detail],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = WellnarioPalette.textTertiary

        let row = UIStackView(
            arrangedSubviews: [icon, labels, chevron],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        card.contentView.addForAutoLayout(row)
        row.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.small))
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalTo: icon.widthAnchor)
        ])
        return card
    }

    private func applyLocalizedCopy() {
        title = L10n.More.title
        subtitleLabel.text = L10n.More.subtitle
    }

    @objc private func featureTapped(_ sender: PremiumCardView) {
        guard MoreFeature.allCases.indices.contains(sender.tag) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSelectFeature?(MoreFeature.allCases[sender.tag])
    }

    @objc private func settingsTapped() {
        UISelectionFeedbackGenerator().selectionChanged()
        onOpenSettings?()
    }

    @objc private func languageDidChange() {
        applyLocalizedCopy()
    }
}

@MainActor
private final class GradientIconView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let imageView = UIImageView()

    init(symbolName: String, colors: [UIColor]) {
        super.init(frame: .zero)
        gradientLayer.colors = colors.map(\.cgColor)
        imageView.image = UIImage(systemName: symbolName)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = min(bounds.width, bounds.height) * 0.34
    }

    private func setUp() {
        layer.insertSublayer(gradientLayer, at: 0)
        applyContinuousCorners(16)
        clipsToBounds = true

        imageView.tintColor = WellnarioPalette.textPrimary
        imageView.contentMode = .scaleAspectFit
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        addForAutoLayout(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.48),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor)
        ])
    }
}
