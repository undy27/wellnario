import UIKit

@MainActor
protocol WellnarioPreservesScrollPositionWhenRevealed {}

@MainActor
final class WellnarioNavigationController: UINavigationController, UINavigationControllerDelegate {
    private let navigationTitlePresenter = WellnarioNavigationTitlePresenter()

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        navigationBar.prefersLargeTitles = true
        navigationBar.tintColor = WellnarioPalette.cyan

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = WellnarioPalette.background
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: WellnarioPalette.textPrimary,
            .font: WellnarioTypography.font(for: .cardTitle)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: WellnarioPalette.textPrimary,
            .font: WellnarioTypography.font(for: .pageTitle)
        ]

        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        view.backgroundColor = WellnarioPalette.background

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshVisibleNavigationTitle),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refreshNavigationTitle(for: topViewController)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        guard operation == .push || operation == .pop else { return nil }
        return WellnarioNavigationTransitionAnimator(
            operation: operation,
            reducesMotion: !WellnarioMotion.animationsEnabled
        )
    }

    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        WellnarioScrollPosition.reset(in: viewController)
        refreshNavigationTitle(for: viewController)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        refreshNavigationTitle(for: viewController)
    }

    @objc private func refreshVisibleNavigationTitle() {
        refreshNavigationTitle(for: topViewController)
    }

    private func refreshNavigationTitle(for controller: UIViewController?) {
        guard let controller else { return }
        navigationTitlePresenter.present(
            controller.navigationItem,
            title: controller.title,
            maximumWidth: availableTitleWidth(for: controller)
        )
    }

    private func availableTitleWidth(for controller: UIViewController) -> CGFloat {
        let navigationBarWidth = navigationBar.bounds.width
        guard navigationBarWidth > 0 else { return 180 }

        let leftItems = controller.navigationItem.leftBarButtonItems
        let hasExplicitLeftItem = !(leftItems ?? []).isEmpty
        let leftWidth = navigationSideWidth(
            leftItems,
            includesBackButton: viewControllers.first !== controller
                && !controller.navigationItem.hidesBackButton
                && (!hasExplicitLeftItem || controller.navigationItem.leftItemsSupplementBackButton)
        )
        let rightWidth = navigationSideWidth(
            controller.navigationItem.rightBarButtonItems,
            includesBackButton: false
        )
        let sideWidth = max(leftWidth, rightWidth)
        return min(250, max(96, navigationBarWidth - (sideWidth * 2) - 12))
    }

    private func navigationSideWidth(
        _ items: [UIBarButtonItem]?,
        includesBackButton: Bool
    ) -> CGFloat {
        let items = items ?? []
        var width: CGFloat = includesBackButton ? 44 : 0

        for item in items {
            let itemWidth: CGFloat
            if let customView = item.customView {
                let fittedWidth = customView.systemLayoutSizeFitting(
                    CGSize(width: UIView.layoutFittingCompressedSize.width, height: 44)
                ).width
                itemWidth = max(44, customView.bounds.width, fittedWidth)
            } else if let title = item.title, !title.isEmpty {
                let titleWidth = (title as NSString).size(
                    withAttributes: [.font: WellnarioTypography.font(for: .secondary)]
                ).width
                itemWidth = max(44, ceil(titleWidth) + 18)
            } else {
                itemWidth = 44
            }
            width += itemWidth
        }

        if items.count > 1 {
            width += CGFloat(items.count - 1) * 4
        }
        return width
    }
}

/// Keeps navigation titles legible in narrow bars without allowing them to
/// overlap the navigation controls. Long titles scroll at a relaxed pace;
/// when Reduce Motion is enabled, multi-word titles fall back to two lines.
@MainActor
private final class WellnarioNavigationTitlePresenter {
    func present(_ item: UINavigationItem, title: String?, maximumWidth: CGFloat) {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return
        }

        if let titleView = item.titleView as? WellnarioNavigationTitleView {
            titleView.configure(title: title, maximumWidth: maximumWidth)
            return
        }

        // Preserve any title view explicitly supplied by a screen.
        guard item.titleView == nil else { return }

        let titleView = WellnarioNavigationTitleView()
        titleView.configure(title: title, maximumWidth: maximumWidth)
        item.titleView = titleView
    }
}

@MainActor
private final class WellnarioNavigationTitleView: UIView {
    private let primaryLabel = UILabel()
    private let repeatedLabel = UILabel()
    private let animationKey = "wellnario.navigationTitle.marquee"
    private var titleText = ""
    private var maximumWidth: CGFloat = 180
    private var animatedDistance: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var intrinsicContentSize: CGSize {
        let width: CGFloat
        if usesTwoLineFallback {
            width = maximumWidth
        } else {
            width = min(maximumWidth, max(44, ceil(singleLineTextWidth)))
        }
        return CGSize(width: width, height: usesTwoLineFallback ? 38 : 36)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopAnimation() }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTitle()
    }

    func configure(title: String, maximumWidth: CGFloat) {
        let usedTwoLineFallback = usesTwoLineFallback
        let didChange = titleText != title
        let widthDidChange = abs(self.maximumWidth - maximumWidth) > 0.5
        guard didChange || widthDidChange else { return }
        titleText = title
        self.maximumWidth = maximumWidth
        if usedTwoLineFallback != usesTwoLineFallback {
            applyTypography()
        }
        primaryLabel.text = title
        repeatedLabel.text = title
        accessibilityLabel = title
        if didChange { stopAnimation() }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private var usesTwoLineFallback: Bool {
        !WellnarioMotion.animationsEnabled && titleText.split(whereSeparator: \.isWhitespace).count >= 2
    }

    private var singleLineTextWidth: CGFloat {
        ceil((titleText as NSString).size(withAttributes: [.font: primaryLabel.font as Any]).width)
    }

    private func setUp() {
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .header
        applyTypography()

        [primaryLabel, repeatedLabel].forEach { label in
            label.textColor = WellnarioPalette.textPrimary
            label.textAlignment = .center
            label.isAccessibilityElement = false
            addSubview(label)
        }
        repeatedLabel.isHidden = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (self: WellnarioNavigationTitleView, _: UITraitCollection) in
            self.applyTypography()
            self.stopAnimation()
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
        }
    }

    private func applyTypography() {
        let style: UIFont.TextStyle = usesTwoLineFallback ? .subheadline : .headline
        let size: CGFloat = usesTwoLineFallback ? 13 : 16
        let font = UIFontMetrics(forTextStyle: style).scaledFont(
            for: .systemFont(ofSize: size, weight: .semibold),
            compatibleWith: traitCollection
        )
        primaryLabel.font = font
        repeatedLabel.font = font
        primaryLabel.adjustsFontForContentSizeCategory = true
        repeatedLabel.adjustsFontForContentSizeCategory = true
    }

    private func layoutTitle() {
        let isTwoLine = usesTwoLineFallback
        primaryLabel.numberOfLines = isTwoLine ? 2 : 1
        primaryLabel.lineBreakMode = isTwoLine ? .byWordWrapping : .byClipping

        guard !isTwoLine,
              WellnarioMotion.animationsEnabled,
              window != nil,
              singleLineTextWidth > bounds.width + 1 else {
            stopAnimation()
            repeatedLabel.isHidden = true
            primaryLabel.frame = bounds
            return
        }

        let gap: CGFloat = 28
        let distance = singleLineTextWidth + gap
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryLabel.frame = CGRect(x: 0, y: 0, width: singleLineTextWidth, height: bounds.height)
        repeatedLabel.frame = CGRect(x: distance, y: 0, width: singleLineTextWidth, height: bounds.height)
        repeatedLabel.isHidden = false
        CATransaction.commit()

        guard animatedDistance != distance
                || primaryLabel.layer.animation(forKey: animationKey) == nil else {
            return
        }
        stopAnimation()
        let duration = max(6, TimeInterval(distance / 26))
        [primaryLabel, repeatedLabel].forEach { label in
            let animation = CABasicAnimation(keyPath: "transform.translation.x")
            animation.fromValue = 0
            animation.toValue = -distance
            animation.duration = duration
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = false
            label.layer.add(animation, forKey: animationKey)
        }
        animatedDistance = distance
    }

    private func stopAnimation() {
        primaryLabel.layer.removeAnimation(forKey: animationKey)
        repeatedLabel.layer.removeAnimation(forKey: animationKey)
        animatedDistance = nil
    }

    @objc private func reduceMotionChanged() {
        applyTypography()
        stopAnimation()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}

@MainActor
enum WellnarioScrollPosition {
    static func reset(in controller: UIViewController?) {
        guard let controller else { return }
        let contentController: UIViewController
        if let navigationController = controller as? UINavigationController {
            contentController = navigationController.visibleViewController
                ?? navigationController.viewControllers.first
                ?? navigationController
        } else {
            contentController = controller
        }
        guard !(contentController is WellnarioPreservesScrollPositionWhenRevealed) else {
            return
        }

        contentController.loadViewIfNeeded()
        contentController.view.layoutIfNeeded()
        let scrollView = (contentController.view as? UIScrollView)
            ?? contentController.view.subviews.compactMap { $0 as? UIScrollView }.first
        guard let scrollView else { return }
        scrollView.setContentOffset(
            CGPoint(
                x: scrollView.contentOffset.x,
                y: -scrollView.adjustedContentInset.top
            ),
            animated: false
        )
    }
}

@MainActor
private final class WellnarioNavigationTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let operation: UINavigationController.Operation
    private let reducesMotion: Bool

    init(operation: UINavigationController.Operation, reducesMotion: Bool) {
        self.operation = operation
        self.reducesMotion = reducesMotion
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        reducesMotion ? 0.20 : WellnarioScreenTransition.duration
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let toController = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }

        let container = transitionContext.containerView
        let finalFrame = transitionContext.finalFrame(for: toController)
        toView.frame = finalFrame
        if operation == .push {
            container.addSubview(toView)
        } else {
            container.insertSubview(toView, belowSubview: fromView)
        }

        fromView.alpha = 1
        fromView.transform = .identity
        toView.alpha = 0
        toView.transform = .identity

        UIView.animate(
            withDuration: transitionDuration(using: transitionContext),
            delay: 0,
            options: [
                .curveLinear,
                .allowAnimatedContent,
                .allowUserInteraction,
                .beginFromCurrentState
            ],
            animations: {
                fromView.alpha = 0
                toView.alpha = 1
            },
            completion: { _ in
                let completed = !transitionContext.transitionWasCancelled
                fromView.alpha = 1
                toView.alpha = 1
                transitionContext.completeTransition(completed)
            }
        )
    }
}

@MainActor
enum WellnarioScreenTransition {
    static let duration: TimeInterval = 0.60
    static var effectiveDuration: TimeInterval {
        WellnarioMotion.animationsEnabled ? duration : 0.20
    }

    static func changeTab(
        in container: UIView,
        outgoingView: UIView,
        changes: () -> Void,
        incomingView: () -> UIView?,
        completion: @escaping () -> Void
    ) -> UIViewPropertyAnimator? {
        let snapshotFrame = outgoingView.convert(outgoingView.bounds, to: container)
        guard !snapshotFrame.isEmpty,
              let snapshot = outgoingView.snapshotView(afterScreenUpdates: true) else {
            changes()
            completion()
            return nil
        }

        changes()
        container.layoutIfNeeded()
        guard let incoming = incomingView() else {
            completion()
            return nil
        }

        snapshot.frame = snapshotFrame
        snapshot.isUserInteractionEnabled = false
        snapshot.isAccessibilityElement = false
        snapshot.accessibilityIdentifier = "wellnario.tabTransition.snapshot"
        container.addSubview(snapshot)

        snapshot.alpha = 1
        snapshot.transform = .identity
        incoming.alpha = 0
        incoming.transform = .identity

        let animator = UIViewPropertyAnimator(duration: effectiveDuration, curve: .linear) {
            snapshot.alpha = 0
            incoming.alpha = 1
        }
        animator.addCompletion { _ in
            incoming.alpha = 1
            snapshot.removeFromSuperview()
            completion()
        }
        animator.startAnimation()
        return animator
    }
}
