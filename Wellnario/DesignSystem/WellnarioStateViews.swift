import UIKit

/// Empty/error state with offline vector artwork and one clear recovery action.
final class EmptyStateView: UIView {
    let artworkView = PresentationArtworkView(kind: .capsule)
    let titleLabel = UILabel()
    let messageLabel = UILabel()
    let actionButton = PrimaryButton(style: .secondary)

    var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(
        kind: PresentationKind = .capsule,
        title: String,
        message: String,
        actionTitle: String? = nil
    ) {
        artworkView.kind = kind
        titleLabel.text = title
        messageLabel.text = message
        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.isHidden = actionTitle == nil
        accessibilityLabel = [title, message].joined(separator: ". ")
    }

    private func setUp() {
        isAccessibilityElement = false

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            artworkView.widthAnchor.constraint(equalToConstant: 112),
            artworkView.heightAnchor.constraint(equalTo: artworkView.widthAnchor)
        ])

        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        messageLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        let stack = UIStackView(
            arrangedSubviews: [artworkView, titleLabel, messageLabel, actionButton],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        stack.setCustomSpacing(WellnarioSpacing.medium, after: artworkView)
        stack.setCustomSpacing(WellnarioSpacing.medium, after: messageLabel)
        addForAutoLayout(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: WellnarioSpacing.medium),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -WellnarioSpacing.medium),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: WellnarioSpacing.large),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -WellnarioSpacing.large),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }

    @objc private func actionTapped() {
        onAction?()
    }
}

/// Shimmer placeholder that stops animating when Reduce Motion is enabled or
/// when the view leaves the window.
final class SkeletonView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = layer.cornerRadius
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        window == nil ? stopAnimating() : startAnimating()
    }

    func startAnimating() {
        guard WellnarioMotion.animationsEnabled else {
            gradientLayer.removeAllAnimations()
            return
        }
        guard gradientLayer.animation(forKey: "wellnario.shimmer") == nil else { return }

        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-1, -0.5, 0]
        animation.toValue = [1, 1.5, 2]
        animation.duration = 1.35
        animation.repeatCount = .infinity
        gradientLayer.add(animation, forKey: "wellnario.shimmer")
    }

    func stopAnimating() {
        gradientLayer.removeAnimation(forKey: "wellnario.shimmer")
    }

    private func setUp() {
        isAccessibilityElement = false
        backgroundColor = WellnarioPalette.surfaceElevated
        applyContinuousCorners(WellnarioRadius.small)
        clipsToBounds = true

        let base = WellnarioPalette.surfaceElevated
        gradientLayer.colors = [
            base.cgColor,
            UIColor.white.withAlphaComponent(0.08).cgColor,
            base.cgColor
        ]
        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradientLayer)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }

    @objc private func reduceMotionChanged() {
        WellnarioMotion.animationsEnabled ? startAnimating() : stopAnimating()
    }
}

/// A compact progress indicator for inline and table states.
final class InlineLoadingView: UIView {
    let activityIndicator = UIActivityIndicatorView(style: .medium)
    let label = UILabel()

    init(text: String? = nil) {
        super.init(frame: .zero)
        setUp(text: text ?? L10n.Common.loading)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp(text: L10n.Common.loading)
    }

    func startAnimating() { activityIndicator.startAnimating() }
    func stopAnimating() { activityIndicator.stopAnimating() }

    private func setUp(text: String) {
        activityIndicator.color = WellnarioPalette.cyan
        activityIndicator.startAnimating()
        label.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        label.text = text
        label.numberOfLines = 0

        let stack = UIStackView(
            arrangedSubviews: [activityIndicator, label],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        addForAutoLayout(stack)
        stack.pinEdges(to: self)
        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = [.updatesFrequently]
    }
}

/// An inline status banner that never communicates state by color alone.
final class FeedbackBannerView: UIView {
    let iconView = UIImageView()
    let messageLabel = UILabel()
    let actionButton = UIButton(type: .system)

    var onAction: (() -> Void)?

    private(set) var tone: WellnarioTone = .information

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(
        message: String,
        tone: WellnarioTone,
        actionTitle: String? = nil
    ) {
        self.tone = tone
        let color = WellnarioPalette.color(for: tone)
        backgroundColor = color.withAlphaComponent(UIAccessibility.isReduceTransparencyEnabled ? 0.22 : 0.15)
        layer.borderColor = color.withAlphaComponent(0.40).cgColor
        iconView.image = UIImage(systemName: Self.symbolName(for: tone))
        iconView.tintColor = color
        messageLabel.text = message
        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.isHidden = actionTitle == nil
        actionButton.setTitleColor(color, for: .normal)
        accessibilityLabel = [Self.accessibilityPrefix(for: tone), message].joined(separator: ". ")
        let hasAction = actionTitle != nil
        isAccessibilityElement = !hasAction
        messageLabel.isAccessibilityElement = hasAction
        messageLabel.accessibilityLabel = hasAction ? accessibilityLabel : nil
    }

    private func setUp() {
        applyContinuousCorners(WellnarioRadius.control)
        layer.borderWidth = 1

        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        messageLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        messageLabel.numberOfLines = 0

        actionButton.titleLabel?.font = WellnarioTypography.font(for: .caption)
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.minimumTouchTarget).isActive = true
        actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.minimumTouchTarget).isActive = true

        let stack = UIStackView(
            arrangedSubviews: [iconView, messageLabel, actionButton],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        addForAutoLayout(stack)
        stack.pinEdges(to: self, insets: .all(WellnarioSpacing.small))

        isAccessibilityElement = true
        accessibilityTraits = [.staticText]
    }

    @objc private func actionTapped() {
        onAction?()
    }

    private static func symbolName(for tone: WellnarioTone) -> String {
        switch tone {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .information, .accent: "info.circle.fill"
        case .neutral: "circle.fill"
        }
    }

    private static func accessibilityPrefix(for tone: WellnarioTone) -> String {
        switch tone {
        case .success: L10n.Common.success
        case .warning: L10n.Common.warning
        case .danger: L10n.Common.error
        case .information, .accent: L10n.Common.information
        case .neutral: L10n.Common.status
        }
    }
}

/// Presents and dismisses a feedback banner without owning its lifetime. This
/// lets feature controllers decide whether a destructive undo should remain
/// visible longer than routine confirmation feedback.
@MainActor
enum FeedbackPresenter {
    @discardableResult
    static func show(
        message: String,
        tone: WellnarioTone,
        actionTitle: String? = nil,
        in container: UIView,
        bottomInset: CGFloat = WellnarioSpacing.bottomNavigationInset,
        onAction: (() -> Void)? = nil
    ) -> FeedbackBannerView {
        let banner = FeedbackBannerView()
        banner.configure(message: message, tone: tone, actionTitle: actionTitle)
        banner.onAction = onAction
        container.addForAutoLayout(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            banner.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            banner.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -bottomInset)
        ])
        container.layoutIfNeeded()
        banner.alpha = 0
        banner.transform = CGAffineTransform(translationX: 0, y: 18)
        WellnarioMotion.spring {
            banner.alpha = 1
            banner.transform = .identity
        }
        UIAccessibility.post(notification: .announcement, argument: banner.accessibilityLabel)
        return banner
    }

    static func dismiss(_ banner: FeedbackBannerView) {
        WellnarioMotion.animate(duration: 0.20, animations: {
            banner.alpha = 0
            banner.transform = CGAffineTransform(translationX: 0, y: 12)
        }, completion: { _ in
            banner.removeFromSuperview()
        })
    }
}
