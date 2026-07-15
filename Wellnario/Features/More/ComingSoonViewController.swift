import UIKit

@MainActor
final class ComingSoonViewController: UIViewController {
    let feature: MoreFeature

    init(feature: MoreFeature) {
        self.feature = feature
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
    }

    private func setUpView() {
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "placeholder.\(feature.rawValue)"
        title = feature.title
        navigationItem.largeTitleDisplayMode = .never

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)

        let artwork = OrbitalFeatureArtworkView(feature: feature)
        artwork.translatesAutoresizingMaskIntoConstraints = false

        let eyebrow = UILabel()
        eyebrow.applyWellnarioStyle(.caption, color: feature.accentColors.first)
        eyebrow.text = L10n.More.comingSoon.uppercased(with: LocalizationManager.shared.locale)
        eyebrow.textAlignment = .center

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.pageTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = feature.title
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let descriptionLabel = UILabel()
        descriptionLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        descriptionLabel.text = feature.featureDescription
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0

        let statusLabel = InsetLabel()
        statusLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.cyan)
        statusLabel.text = L10n.More.availableLater
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = WellnarioPalette.cyan.withAlphaComponent(0.12)
        statusLabel.layer.borderWidth = 1
        statusLabel.layer.borderColor = WellnarioPalette.cyan.withAlphaComponent(0.30).cgColor
        statusLabel.applyContinuousCorners(14)
        statusLabel.accessibilityIdentifier = "placeholder.status"

        let card = PremiumCardView()
        card.contentView.isUserInteractionEnabled = false
        let textStack = UIStackView(
            arrangedSubviews: [eyebrow, titleLabel, descriptionLabel, statusLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall,
            alignment: .fill
        )
        textStack.setCustomSpacing(WellnarioSpacing.small, after: titleLabel)
        textStack.setCustomSpacing(WellnarioSpacing.medium, after: descriptionLabel)
        card.contentView.addForAutoLayout(textStack)
        textStack.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))

        let contentStack = UIStackView(
            arrangedSubviews: [artwork, card],
            axis: .vertical,
            spacing: WellnarioSpacing.large,
            alignment: .fill
        )
        scrollView.addForAutoLayout(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: WellnarioSpacing.large),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.bottomNavigationInset),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(WellnarioSpacing.screenHorizontal * 2)),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor, multiplier: 0.72)
        ])
    }
}

@MainActor
private final class OrbitalFeatureArtworkView: UIView {
    private let feature: MoreFeature
    private let backgroundGradient = CAGradientLayer()
    private let orbitLayer = CALayer()
    private let outerRing = CAShapeLayer()
    private let innerRing = CAShapeLayer()
    private let symbolView = UIImageView()

    init(feature: MoreFeature) {
        self.feature = feature
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundGradient.frame = bounds
        backgroundGradient.cornerRadius = WellnarioRadius.card
        orbitLayer.frame = bounds

        let square = min(bounds.width, bounds.height)
        let outerRect = CGRect(
            x: bounds.midX - square * 0.35,
            y: bounds.midY - square * 0.35,
            width: square * 0.70,
            height: square * 0.70
        )
        outerRing.frame = bounds
        outerRing.path = UIBezierPath(ovalIn: outerRect).cgPath

        let innerRect = outerRect.insetBy(dx: square * 0.095, dy: square * 0.095)
        innerRing.frame = bounds
        innerRing.path = UIBezierPath(ovalIn: innerRect).cgPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? stopAnimating() : startAnimating()
    }

    private func setUp() {
        isAccessibilityElement = true
        accessibilityTraits = [.image]
        accessibilityLabel = feature.title
        clipsToBounds = true
        applyContinuousCorners(WellnarioRadius.card)

        backgroundGradient.startPoint = CGPoint(x: 0.05, y: 0)
        backgroundGradient.endPoint = CGPoint(x: 0.95, y: 1)
        layer.addSublayer(backgroundGradient)

        outerRing.fillColor = UIColor.clear.cgColor
        outerRing.lineWidth = 2
        outerRing.lineDashPattern = [2, 10]
        outerRing.lineCap = .round

        innerRing.fillColor = UIColor.clear.cgColor
        innerRing.lineWidth = 1

        layer.addSublayer(orbitLayer)
        orbitLayer.addSublayer(outerRing)
        orbitLayer.addSublayer(innerRing)

        symbolView.image = UIImage(systemName: feature.symbolName)
        symbolView.tintColor = WellnarioPalette.textPrimary
        symbolView.contentMode = .scaleAspectFit
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 48, weight: .medium)
        symbolView.layer.borderWidth = 1
        symbolView.applyContinuousCorners(38)
        addForAutoLayout(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 92),
            symbolView.heightAnchor.constraint(equalTo: symbolView.widthAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (self: OrbitalFeatureArtworkView, _: UITraitCollection) in
            self.updateColors()
        }
    }

    private func updateColors() {
        let first = (feature.accentColors.first ?? WellnarioPalette.cyan)
            .resolvedColor(with: traitCollection)
        let last = (feature.accentColors.last ?? WellnarioPalette.violet)
            .resolvedColor(with: traitCollection)
        backgroundGradient.colors = [
            first.withAlphaComponent(0.24).cgColor,
            last.withAlphaComponent(0.10).cgColor,
            WellnarioPalette.surface.resolvedColor(with: traitCollection).cgColor
        ]
        outerRing.strokeColor = first.withAlphaComponent(0.55).cgColor
        innerRing.strokeColor = last.withAlphaComponent(0.34).cgColor
        symbolView.backgroundColor = WellnarioPalette.textPrimary.withAlphaComponent(0.06)
        symbolView.layer.borderColor = WellnarioPalette.hairline
            .resolvedColor(with: traitCollection)
            .cgColor
    }

    private func startAnimating() {
        guard WellnarioMotion.animationsEnabled, orbitLayer.animation(forKey: "orbit") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = CGFloat.pi * 2
        animation.duration = 18
        animation.repeatCount = .infinity
        orbitLayer.add(animation, forKey: "orbit")
    }

    private func stopAnimating() {
        orbitLayer.removeAnimation(forKey: "orbit")
    }

    @objc private func reduceMotionChanged() {
        WellnarioMotion.animationsEnabled ? startAnimating() : stopAnimating()
    }
}

@MainActor
private final class InsetLabel: UILabel {
    var contentInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }
}
