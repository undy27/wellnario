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
    private let medicalReviewStore: MedicalReviewStore

    init(
        repository: WellnarioRepositoryProtocol,
        appleHealthService: AppleHealthSyncing,
        medicalReviewStore: MedicalReviewStore
    ) {
        self.repository = repository
        self.appleHealthService = appleHealthService
        self.medicalReviewStore = medicalReviewStore
    }

    func makeToday() -> TodayViewController {
        TodayViewController(
            repository: repository,
            appleHealthService: appleHealthService,
            medicalReviewStore: medicalReviewStore
        )
    }

    func makeSupplements() -> SupplementsViewController {
        SupplementsViewController(repository: repository)
    }

    func makeSleep() -> SleepViewController {
        SleepViewController(appleHealthService: appleHealthService)
    }

    func makeHealth() -> HealthViewController {
        HealthViewController(
            appleHealthService: appleHealthService,
            medicalReviewStore: medicalReviewStore
        )
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
                appleHealthService: environment.appleHealthService,
                medicalReviewStore: environment.medicalReviewStore
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositoryDidChange(_:)),
            name: .wellnarioRepositoryDidChange,
            object: environment.repository
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
        SupplementReminderNotificationScheduler(repository: environment.repository).reschedule()
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
        let navigationControllers = [
            todayNavigation,
            supplementsNavigation,
            sleepNavigation,
            healthNavigation,
            fitnessNavigation
        ]
        let safeSelectedIndex = min(
            max(0, selectedIndex),
            max(0, navigationControllers.count - 1)
        )

        if restoringSettings {
            navigationControllers[safeSelectedIndex].pushViewController(
                SettingsViewController(
                    appleHealthService: environment.appleHealthService,
                    repository: environment.repository
                ),
                animated: false
            )
        }

        let rootController = RootTabBarController()
        rootController.install(
            viewControllers: navigationControllers,
            selectedIndex: safeSelectedIndex
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
        supplementsController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        fitnessController.onOpenSettings = { [weak self] in
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
              let selectedNavigation = rootTabBarController.selectedViewController
                as? UINavigationController else {
            return
        }
        guard !(selectedNavigation.topViewController is SettingsViewController) else { return }
        selectedNavigation.pushViewController(
            SettingsViewController(
                appleHealthService: environment.appleHealthService,
                repository: environment.repository
            ),
            animated: true
        )
    }

    @objc private func languageDidChange() {
        guard !isRebuildingRoot else { return }
        isRebuildingRoot = true

        let selectedIndex = rootTabBarController?.selectedIndex
            ?? environment.launchConfiguration.initialTab.rawValue
        installRoot(
            selectedIndex: selectedIndex,
            restoringSettings: settingsIsVisibleInSelectedTab,
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

    @objc private func repositoryDidChange(_ notification: Notification) {
        guard let change = notification.userInfo?[WellnarioRepositoryNotificationKey.change]
                as? RepositoryChange else { return }
        switch change.entity {
        case .target, .supplement:
            SupplementReminderNotificationScheduler(repository: environment.repository).reschedule()
        case .active, .instance, .consumption:
            break
        }
    }

    private func rebuildRootPreservingState(animated: Bool) {
        guard !isRebuildingRoot else { return }
        isRebuildingRoot = true
        let selectedIndex = rootTabBarController?.selectedIndex
            ?? environment.launchConfiguration.initialTab.rawValue
        installRoot(
            selectedIndex: selectedIndex,
            restoringSettings: settingsIsVisibleInSelectedTab,
            animated: animated
        )
        isRebuildingRoot = false
    }

    private var settingsIsVisibleInSelectedTab: Bool {
        guard let selectedNavigation = rootTabBarController?.selectedViewController
                as? UINavigationController else {
            return false
        }
        return selectedNavigation.viewControllers.contains { $0 is SettingsViewController }
    }
}
