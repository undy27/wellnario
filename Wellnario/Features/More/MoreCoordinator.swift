import UIKit

@MainActor
final class MoreCoordinator: NSObject, UINavigationControllerDelegate {
    let navigationController: WellnarioNavigationController
    private let appleHealthService: AppleHealthSyncing

    private(set) var currentRoute: MoreRoute = .root

    init(
        navigationController: WellnarioNavigationController,
        appleHealthService: AppleHealthSyncing
    ) {
        self.navigationController = navigationController
        self.appleHealthService = appleHealthService
        super.init()
        navigationController.delegate = self
    }

    func start(restoring route: MoreRoute = .root, animated: Bool = false) {
        let rootController = makeRootViewController()
        navigationController.setViewControllers([rootController], animated: false)
        currentRoute = .root
        guard route != .root else { return }
        show(route, animated: animated)
    }

    func show(_ route: MoreRoute, animated: Bool = true) {
        switch route {
        case .root:
            navigationController.popToRootViewController(animated: animated)
        case .settings:
            guard !(navigationController.topViewController is SettingsViewController) else { return }
            navigationController.pushViewController(
                SettingsViewController(appleHealthService: appleHealthService),
                animated: animated
            )
        case let .placeholder(feature):
            if let current = navigationController.topViewController as? ComingSoonViewController,
               current.feature == feature {
                return
            }
            navigationController.pushViewController(
                ComingSoonViewController(feature: feature),
                animated: animated
            )
        }
        currentRoute = route
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        switch viewController {
        case is MoreViewController:
            currentRoute = .root
        case is SettingsViewController:
            currentRoute = .settings
        case let controller as ComingSoonViewController:
            currentRoute = .placeholder(controller.feature)
        default:
            break
        }
    }

    private func makeRootViewController() -> MoreViewController {
        let controller = MoreViewController()
        controller.onSelectFeature = { [weak self] feature in
            self?.show(.placeholder(feature))
        }
        controller.onOpenSettings = { [weak self] in
            self?.show(.settings)
        }
        return controller
    }
}
