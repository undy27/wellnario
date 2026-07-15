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
    private let appleHealthService: AppleHealthSyncing

    init(
        repository: WellnarioRepositoryProtocol,
        appleHealthService: AppleHealthSyncing
    ) {
        self.repository = repository
        self.appleHealthService = appleHealthService
    }

    func makeToday() -> TodayViewController {
        TodayViewController(
            repository: repository,
            appleHealthService: appleHealthService
        )
    }

    func makeSupplements() -> SupplementsViewController {
        SupplementsViewController(repository: repository)
    }

    func makeSleep() -> SleepViewController {
        SleepViewController(appleHealthService: appleHealthService)
    }

    func makeHealth() -> HealthViewController {
        HealthViewController(appleHealthService: appleHealthService)
    }

    func makeFitness() -> FitnessViewController {
        FitnessViewController(appleHealthService: appleHealthService)
    }
}

@MainActor
final class AppCoordinator: NSObject {
    private let window: UIWindow
    private let environment: AppEnvironment
    private let featureFactory: RootFeatureBuilding
    private let appearanceManager: WellnarioAppearanceManager

    private var rootTabBarController: RootTabBarController?
    private var isRebuildingRoot = false
    private var appliedContentSizeCategory: UIContentSizeCategory?
    private var appliedSystemInterfaceStyle: UIUserInterfaceStyle?

    init(
        window: UIWindow,
        environment: AppEnvironment,
        featureFactory: RootFeatureBuilding? = nil,
        appearanceManager: WellnarioAppearanceManager = .shared
    ) {
        self.window = window
        self.environment = environment
        self.appearanceManager = appearanceManager
        self.featureFactory = featureFactory
            ?? LiveRootFeatureFactory(
                repository: environment.repository,
                appleHealthService: environment.appleHealthService
            )
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LocalizationManager.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: WellnarioAppearanceManager.didChangeNotification,
            object: appearanceManager
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        appearanceManager.apply(to: window)
        window.backgroundColor = WellnarioPalette.background
        let index = environment.launchConfiguration.initialTab.rawValue
        installRoot(selectedIndex: index, restoringSettings: false, animated: false)
        window.makeKeyAndVisible()
        appliedSystemInterfaceStyle = window.traitCollection.userInterfaceStyle
        refreshDynamicTypeIfNeeded(force: true)
        Task { await environment.appleHealthService.syncIfConfigured() }
    }

    func refreshSystemAppearanceIfNeeded() {
        guard appearanceManager.mode == .system else { return }
        let currentStyle = window.traitCollection.userInterfaceStyle
        guard currentStyle != .unspecified,
              currentStyle != appliedSystemInterfaceStyle,
              !isRebuildingRoot else { return }
        appliedSystemInterfaceStyle = currentStyle
        rebuildRootPreservingState(animated: false)
    }

    func refreshDynamicTypeIfNeeded(force: Bool = false) {
        guard let rootView = window.rootViewController?.viewIfLoaded else { return }
        let category = rootView.traitCollection.preferredContentSizeCategory
        guard force || appliedContentSizeCategory != category else { return }
        appliedContentSizeCategory = category

        rootView.refreshWellnarioDynamicType(compatibleWith: rootView.traitCollection)
        UIView.performWithoutAnimation {
            rootView.layoutIfNeeded()
        }
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
            todayNavigation.pushViewController(
                SettingsViewController(appleHealthService: environment.appleHealthService),
                animated: false
            )
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
        todayNavigation.pushViewController(
            SettingsViewController(appleHealthService: environment.appleHealthService),
            animated: true
        )
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

    @objc private func contentSizeCategoryDidChange() {
        refreshDynamicTypeIfNeeded(force: true)
    }

    @objc private func appearanceDidChange() {
        appearanceManager.apply(to: window)
        appliedSystemInterfaceStyle = window.traitCollection.userInterfaceStyle
        rebuildRootPreservingState(animated: true)
    }

    private func rebuildRootPreservingState(animated: Bool) {
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
            animated: animated
        )
        isRebuildingRoot = false
    }
}
