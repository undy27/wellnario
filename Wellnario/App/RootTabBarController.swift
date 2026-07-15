import UIKit

@MainActor
final class RootTabBarController: UITabBarController {
    private let floatingTabBar = FloatingTabBarView()

    private var floatingBarTravelDistance: CGFloat {
        floatingTabBar.intrinsicContentSize.height + WellnarioSpacing.small
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WellnarioPalette.background
        tabBar.isHidden = true
        setUpFloatingTabBar()
        observeKeyboard()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func install(viewControllers: [UIViewController], selectedIndex: Int) {
        setViewControllers(viewControllers, animated: false)
        let safeIndex = min(max(0, selectedIndex), max(0, viewControllers.count - 1))
        self.selectedIndex = safeIndex
        floatingTabBar.setSelectedIndex(safeIndex, animated: false)
    }

    func select(index: Int, animated: Bool = true) {
        guard let viewControllers, viewControllers.indices.contains(index) else { return }
        guard let rootView = view else { return }
        guard selectedIndex != index else {
            (selectedViewController as? UINavigationController)?.popToRootViewController(animated: animated)
            return
        }

        floatingTabBar.setSelectedIndex(index, animated: animated)
        let contentContainer = selectedViewController?.view.superview ?? rootView
        let changes = { self.selectedIndex = index }

        if animated && WellnarioMotion.animationsEnabled {
            UIView.transition(
                with: contentContainer,
                duration: WellnarioMotion.standard,
                options: [.transitionCrossDissolve, .allowAnimatedContent, .allowUserInteraction],
                animations: changes
            )
        } else {
            changes()
        }
    }

    private func setUpFloatingTabBar() {
        floatingTabBar.onSelection = { [weak self] index in
            self?.select(index: index)
        }
        view.addForAutoLayout(floatingTabBar)
        NSLayoutConstraint.activate([
            floatingTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: WellnarioSpacing.xSmall),
            floatingTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -WellnarioSpacing.xSmall),
            floatingTabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.xxSmall)
        ])
        view.bringSubviewToFront(floatingTabBar)
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        updateFloatingBar(hidden: true, notification: notification)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        updateFloatingBar(hidden: false, notification: notification)
    }

    private func updateFloatingBar(hidden: Bool, notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
            ?? WellnarioMotion.standard
        let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
            ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: curveValue << 16)
            .union([.beginFromCurrentState, .allowUserInteraction])
        let changes = {
            self.floatingTabBar.alpha = hidden ? 0 : 1
            self.floatingTabBar.transform = hidden
                ? CGAffineTransform(translationX: 0, y: self.floatingBarTravelDistance)
                : .identity
        }

        guard WellnarioMotion.animationsEnabled else {
            UIView.performWithoutAnimation(changes)
            return
        }
        UIView.animate(withDuration: duration, delay: 0, options: options, animations: changes)
    }
}
