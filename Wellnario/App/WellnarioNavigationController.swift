import UIKit

@MainActor
protocol WellnarioPreservesScrollPositionWhenRevealed {}

@MainActor
final class WellnarioNavigationController: UINavigationController, UINavigationControllerDelegate {
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
