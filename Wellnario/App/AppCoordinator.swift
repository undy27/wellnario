import UIKit

@MainActor
protocol RootFeatureBuilding {
    func makeToday() -> TodayViewController
    func makeSupplements() -> SupplementsViewController
    func makeSleep() -> SleepViewController
    func makeHealth() -> HealthViewController
    func makeFitness() -> FitnessViewController
}

@MainActor
private final class LiveRootFeatureFactory: RootFeatureBuilding {
    private let repository: WellnarioRepositoryProtocol

    init(repository: WellnarioRepositoryProtocol) {
        self.repository = repository
    }

    func makeToday() -> TodayViewController {
        TodayViewController(repository: repository)
    }

    func makeSupplements() -> SupplementsViewController {
        SupplementsViewController(repository: repository)
    }

    func makeSleep() -> SleepViewController {
        SleepViewController()
    }

    func makeHealth() -> HealthViewController {
        HealthViewController()
    }

    func makeFitness() -> FitnessViewController {
        FitnessViewController()
    }
}

@MainActor
final class AppCoordinator: NSObject {
    private let window: UIWindow
    private let environment: AppEnvironment
    private let featureFactory: RootFeatureBuilding

    private var rootTabBarController: RootTabBarController?
    private var isRebuildingRoot = false

    init(
        window: UIWindow,
        environment: AppEnvironment,
        featureFactory: RootFeatureBuilding? = nil
    ) {
        self.window = window
        self.environment = environment
        self.featureFactory = featureFactory
            ?? LiveRootFeatureFactory(repository: environment.repository)
        super.init()

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

    func start() {
        let index = environment.launchConfiguration.initialTab.rawValue
        installRoot(selectedIndex: index, restoringSettings: false, animated: false)
        window.makeKeyAndVisible()
    }

    private func installRoot(
        selectedIndex: Int,
        restoringSettings: Bool,
        animated: Bool
    ) {
        let oldSnapshot = animated ? window.snapshotView(afterScreenUpdates: false) : nil

        let todayController = featureFactory.makeToday()
        let supplementsController = featureFactory.makeSupplements()
        let sleepController = featureFactory.makeSleep()
        let healthController = featureFactory.makeHealth()
        let fitnessController = featureFactory.makeFitness()

        let todayNavigation = makeNavigationController(root: todayController, identifier: "navigation.today")
        let supplementsNavigation = makeNavigationController(root: supplementsController, identifier: "navigation.supplements")
        let sleepNavigation = makeNavigationController(root: sleepController, identifier: "navigation.sleep")
        let healthNavigation = makeNavigationController(root: healthController, identifier: "navigation.health")
        let fitnessNavigation = makeNavigationController(root: fitnessController, identifier: "navigation.fitness")

        if restoringSettings {
            todayNavigation.pushViewController(SettingsViewController(), animated: false)
        }

        let rootController = RootTabBarController()
        rootController.install(
            viewControllers: [
                todayNavigation,
                supplementsNavigation,
                sleepNavigation,
                healthNavigation,
                fitnessNavigation
            ],
            selectedIndex: selectedIndex
        )

        todayController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        todayController.onShowSupplements = { [weak rootController] in
            rootController?.select(index: AppLaunchConfiguration.InitialTab.supplements.rawValue)
        }
        todayController.onShowSleep = { [weak rootController] in
            rootController?.select(index: AppLaunchConfiguration.InitialTab.sleep.rawValue)
        }
        todayController.onShowHealth = { [weak rootController] in
            rootController?.select(index: AppLaunchConfiguration.InitialTab.health.rawValue)
        }
        todayController.onShowFitness = { [weak rootController] in
            rootController?.select(index: AppLaunchConfiguration.InitialTab.fitness.rawValue)
        }
        sleepController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        healthController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        fitnessController.onStartWorkout = { [weak fitnessController] in
            guard let fitnessController else { return }
            let controller = WorkoutStarterViewController()
            fitnessController.presentSheet(controller)
        }

        rootTabBarController = rootController
        window.rootViewController = rootController
        rootController.view.layoutIfNeeded()

        guard let oldSnapshot, WellnarioMotion.animationsEnabled else { return }
        oldSnapshot.frame = window.bounds
        oldSnapshot.isUserInteractionEnabled = false
        window.addSubview(oldSnapshot)
        UIView.animate(
            withDuration: WellnarioMotion.emphasized,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                oldSnapshot.alpha = 0
                oldSnapshot.transform = CGAffineTransform(scaleX: 1.015, y: 1.015)
            },
            completion: { _ in oldSnapshot.removeFromSuperview() }
        )
    }

    private func makeNavigationController(
        root: UIViewController,
        identifier: String
    ) -> WellnarioNavigationController {
        let navigationController = WellnarioNavigationController(rootViewController: root)
        navigationController.view.accessibilityIdentifier = identifier
        return navigationController
    }

    private func showSettings() {
        guard let rootTabBarController,
              let todayNavigation = rootTabBarController.viewControllers?.first as? UINavigationController else {
            return
        }
        rootTabBarController.select(index: AppLaunchConfiguration.InitialTab.today.rawValue)
        guard !(todayNavigation.topViewController is SettingsViewController) else { return }
        todayNavigation.pushViewController(SettingsViewController(), animated: true)
    }

    @objc private func languageDidChange() {
        guard !isRebuildingRoot else { return }
        isRebuildingRoot = true

        let selectedIndex = rootTabBarController?.selectedIndex
            ?? environment.launchConfiguration.initialTab.rawValue
        let settingsIsVisible = rootTabBarController?.viewControllers?.first
            .flatMap { $0 as? UINavigationController }?
            .viewControllers
            .contains { $0 is SettingsViewController } ?? false
        installRoot(
            selectedIndex: selectedIndex,
            restoringSettings: settingsIsVisible,
            animated: true
        )
        isRebuildingRoot = false
    }
}
