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
    private let healthDataStore: HealthDataStore

    init(
        repository: WellnarioRepositoryProtocol,
        appleHealthService: AppleHealthSyncing,
        medicalReviewStore: MedicalReviewStore,
        healthDataStore: HealthDataStore
    ) {
        self.repository = repository
        self.appleHealthService = appleHealthService
        self.medicalReviewStore = medicalReviewStore
        self.healthDataStore = healthDataStore
    }

    func makeToday() -> TodayViewController {
        TodayViewController(
            repository: repository,
            appleHealthService: appleHealthService,
            medicalReviewStore: medicalReviewStore
        )
    }

    func makeSupplements() -> SupplementsViewController {
        SupplementsViewController(
            repository: repository,
            appleHealthService: appleHealthService
        )
    }

    func makeSleep() -> SleepViewController {
        SleepViewController(
            appleHealthService: appleHealthService,
            repository: repository
        )
    }

    func makeHealth() -> HealthViewController {
        HealthViewController(
            appleHealthService: appleHealthService,
            medicalReviewStore: medicalReviewStore,
            healthDataStore: healthDataStore
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
                medicalReviewStore: environment.medicalReviewStore,
                healthDataStore: environment.healthDataStore
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sleepWidgetDataDidChange),
            name: .appleHealthSyncDidChange,
            object: environment.appleHealthService
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sleepWidgetDataDidChange),
            name: .sleepManualOverridesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sleepWidgetDataDidChange),
            name: .sleepQualityPreferencesDidChange,
            object: nil
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
        SupplementWidgetSnapshotUpdater.refresh(repository: environment.repository)
        SleepWidgetSnapshotUpdater.refresh(snapshot: environment.appleHealthService.snapshot)
        Task { [weak self] in
            guard let self else { return }
            if await environment.appleHealthService.consumePendingAuthorizationWarning() {
                presentPendingAppleHealthAuthorizationAlert()
            }
            await environment.appleHealthService.syncIfConfigured()
            SleepWidgetSnapshotUpdater.refresh(snapshot: environment.appleHealthService.snapshot)
        }
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

    /// The widget lets the user select cards in place. Its final batch action
    /// opens the app because WidgetKit cannot present the mandatory
    /// confirmation alert itself.
    func handleWidgetURL(_ url: URL) {
        if SupplementWidgetURL.requestsSleepWidgetSync(from: url) {
            rootTabBarController?.select(
                index: AppLaunchConfiguration.InitialTab.sleep.rawValue
            )
            Task { [weak self] in
                guard let self else { return }
                await environment.appleHealthService.syncIfConfigured()
                SleepWidgetSnapshotUpdater.refresh(snapshot: environment.appleHealthService.snapshot)
            }
            return
        }
        if SupplementWidgetURL.requestsSleepWidget(from: url) {
            rootTabBarController?.select(
                index: AppLaunchConfiguration.InitialTab.sleep.rawValue
            )
            return
        }
        if let packageID = SupplementWidgetURL.packageID(from: url) {
            presentWidgetIntakeConfirmation(for: [packageID])
            return
        }
        guard SupplementWidgetURL.requestsSelectedIntakesConfirmation(from: url) else { return }

        let store = SupplementWidgetDataStore()
        let selected = store.selectedPackageIDs()
        let orderedIdentifiers = store.snapshot()?.packages.map(\.id).filter(selected.contains)
            ?? selected.sorted()
        presentWidgetIntakeConfirmation(
            for: orderedIdentifiers.compactMap(UUID.init(uuidString:))
        )
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

    private func presentWidgetIntakeConfirmation(for packageIDs: [UUID]) {
        guard let rootTabBarController,
              rootTabBarController.presentedViewController == nil else {
            return
        }

        do {
            var seenPackageIDs = Set<UUID>()
            let uniquePackageIDs = packageIDs.filter { seenPackageIDs.insert($0).inserted }
            guard !uniquePackageIDs.isEmpty else { return }
            let intakes = try uniquePackageIDs.map { packageID -> WidgetPendingIntake in
                guard let package = try environment.repository.instance(id: packageID),
                      !package.isArchived,
                      let supplement = try environment.repository.supplement(id: package.supplementID),
                      !supplement.isArchived else {
                    throw RepositoryError.notFound(entity: "Package", id: packageID)
                }
                return WidgetPendingIntake(package: package, supplement: supplement)
            }

            guard !intakes.isEmpty else {
                return
            }

            rootTabBarController.select(
                index: AppLaunchConfiguration.InitialTab.today.rawValue,
                animated: false
            )
            guard let navigationController = rootTabBarController.selectedViewController
                as? UINavigationController else {
                return
            }
            navigationController.popToRootViewController(animated: false)

            let languageCode = LocalizationManager.shared.language.rawValue
            let descriptions = intakes.map { intake in
                "\(intake.supplement.name) · \(amountDescription(for: intake, languageCode: languageCode))"
            }
            let singleIntake = intakes.count == 1
            let title = L10n.text(
                singleIntake
                    ? "widget.intake.confirmation.title"
                    : "widget.intake.batch.confirmation.title"
            )
            let message: String
            if let intake = intakes.first, singleIntake {
                message = L10n.text(
                    "widget.intake.confirmation.message",
                    amountDescription(for: intake, languageCode: languageCode),
                    intake.supplement.name,
                    intake.package.label
                )
            } else {
                message = L10n.text(
                    "widget.intake.batch.confirmation.message",
                    descriptions.joined(separator: "\n")
                )
            }
            let alert = UIAlertController(
                title: title,
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: L10n.Common.confirm, style: .default) { [weak self] _ in
                guard let self else { return }
                do {
                    _ = try self.environment.repository.createConsumptions(intakes.map {
                        ConsumptionDraft(
                            instanceID: $0.package.id,
                            quantity: $0.supplement.basisQuantity,
                            unit: $0.supplement.basisUnit
                        )
                    })
                    SupplementWidgetDataStore().clearSelectedPackageIDs()
                    SupplementWidgetSnapshotUpdater.refresh(repository: self.environment.repository)
                    let announcement = intakes.count == 1
                        ? L10n.text("widget.intake.recorded")
                        : L10n.text("widget.intake.batch.recorded", intakes.count)
                    UIAccessibility.post(notification: .announcement, argument: announcement)
                } catch {
                    self.presentWidgetIntakeError(error)
                }
            })
            navigationController.present(alert, animated: true)
        } catch {
            presentWidgetIntakeError(error)
        }
    }

    private func amountDescription(
        for intake: WidgetPendingIntake,
        languageCode: String
    ) -> String {
        "\(FeatureFormatting.decimal(intake.supplement.basisQuantity)) \(intake.supplement.basisUnit.symbol(languageCode: languageCode))"
    }

    private func presentWidgetIntakeError(_ error: Error) {
        guard let rootTabBarController,
              rootTabBarController.presentedViewController == nil else {
            return
        }
        let alert = UIAlertController(
            title: L10n.Common.error,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
        rootTabBarController.present(alert, animated: true)
    }

    private func presentPendingAppleHealthAuthorizationAlert() {
        guard let rootTabBarController,
              rootTabBarController.presentedViewController == nil else {
            return
        }
        let alert = UIAlertController(
            title: L10n.text("apple_health.authorization_pending.title"),
            message: L10n.text("apple_health.authorization_pending.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: L10n.text("apple_health.authorization_pending.later"),
            style: .cancel
        ))
        alert.addAction(UIAlertAction(
            title: L10n.text("apple_health.authorization_pending.review"),
            style: .default
        ) { [weak self] _ in
            self?.showAppleHealthIntegration()
        })
        rootTabBarController.present(alert, animated: true)
    }

    private func showAppleHealthIntegration() {
        guard let rootTabBarController,
              let selectedNavigation = rootTabBarController.selectedViewController
                as? UINavigationController else {
            return
        }
        selectedNavigation.pushViewController(
            IntegrationSetupViewController(
                provider: .appleHealth,
                appleHealthService: environment.appleHealthService
            ),
            animated: true
        )
    }

    @objc private func languageDidChange() {
        guard !isRebuildingRoot else { return }
        SupplementWidgetSnapshotUpdater.refresh(repository: environment.repository)
        SleepWidgetSnapshotUpdater.refresh(snapshot: environment.appleHealthService.snapshot)
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

    @objc private func sleepWidgetDataDidChange() {
        SleepWidgetSnapshotUpdater.refresh(snapshot: environment.appleHealthService.snapshot)
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
        case .target:
            SupplementReminderNotificationScheduler(repository: environment.repository).reschedule()
        case .supplement:
            SupplementReminderNotificationScheduler(repository: environment.repository).reschedule()
            SupplementWidgetSnapshotUpdater.refresh(repository: environment.repository)
        case .instance, .consumption:
            SupplementWidgetSnapshotUpdater.refresh(repository: environment.repository)
        case .active:
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

private struct WidgetPendingIntake {
    let package: SupplementInstance
    let supplement: Supplement
}
