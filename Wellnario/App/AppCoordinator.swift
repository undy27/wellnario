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
    private let recoveryDataStore: RecoveryDataStore
    private let strengthDataStore: StrengthDataStore

    init(
        repository: WellnarioRepositoryProtocol,
        appleHealthService: AppleHealthSyncing,
        medicalReviewStore: MedicalReviewStore,
        healthDataStore: HealthDataStore,
        recoveryDataStore: RecoveryDataStore,
        strengthDataStore: StrengthDataStore
    ) {
        self.repository = repository
        self.appleHealthService = appleHealthService
        self.medicalReviewStore = medicalReviewStore
        self.healthDataStore = healthDataStore
        self.recoveryDataStore = recoveryDataStore
        self.strengthDataStore = strengthDataStore
    }

    func makeToday() -> TodayViewController {
        TodayViewController(
            repository: repository,
            appleHealthService: appleHealthService,
            medicalReviewStore: medicalReviewStore,
            recoveryDataStore: recoveryDataStore
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
        FitnessViewController(
            appleHealthService: appleHealthService,
            strengthDataStore: strengthDataStore
        )
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
                healthDataStore: environment.healthDataStore,
                recoveryDataStore: environment.recoveryDataStore,
                strengthDataStore: environment.strengthDataStore
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

            let confirmation = WidgetIntakeConfirmationViewController(
                intakes: intakes,
                onConfirm: { [weak self] requests in
                    guard let self else { throw CancellationError() }
                    return try self.recordWidgetIntakes(requests)
                }
            )
            let confirmationNavigation = WellnarioNavigationController(rootViewController: confirmation)
            confirmationNavigation.modalPresentationStyle = .pageSheet
            if let sheet = confirmationNavigation.sheetPresentationController {
                sheet.detents = intakes.count > 3 ? [.large()] : [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = WellnarioRadius.card
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            }
            navigationController.present(confirmationNavigation, animated: true)
        } catch {
            presentWidgetIntakeError(error)
        }
    }

    private func recordWidgetIntakes(_ requests: [WidgetIntakeRequest]) throws -> Int {
        let drafts = requests.flatMap { request in
            Array(
                repeating: ConsumptionDraft(
                    instanceID: request.intake.package.id,
                    quantity: request.amount,
                    unit: request.unit
                ),
                count: request.repetitions
            )
        }
        guard !drafts.isEmpty else { return 0 }

        _ = try environment.repository.createConsumptions(drafts)
        SupplementWidgetDataStore().clearSelectedPackageIDs()
        SupplementWidgetSnapshotUpdater.refresh(repository: environment.repository)
        return drafts.count
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

private struct WidgetIntakeRequest {
    let intake: WidgetPendingIntake
    let amount: Decimal
    let unit: DoseUnit
    let repetitions: Int
}

@MainActor
private final class WidgetIntakeConfirmationViewController: UIViewController {
    private let intakes: [WidgetPendingIntake]
    private let onConfirm: ([WidgetIntakeRequest]) throws -> Int
    private var quantities: [UUID: Int]

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let confirmButton = PrimaryButton(
        title: L10n.text("widget.intake.confirm"),
        style: .primary
    )
    private var quantityLabels: [UUID: UILabel] = [:]
    private var amountFields: [UUID: FormFieldView] = [:]

    init(
        intakes: [WidgetPendingIntake],
        onConfirm: @escaping ([WidgetIntakeRequest]) throws -> Int
    ) {
        self.intakes = intakes
        self.onConfirm = onConfirm
        quantities = Dictionary(
            uniqueKeysWithValues: intakes.map { ($0.package.id, 1) }
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "widget.intake.confirmation"
        navigationItem.title = L10n.text(
            intakes.count == 1
                ? "widget.intake.confirmation.title"
                : "widget.intake.batch.confirmation.title"
        )
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = WellnarioNavigationButton.item(
            title: L10n.Common.cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        configureLayout()
        configureContent()
    }

    private func configureLayout() {
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive

        contentStack.axis = .vertical
        contentStack.spacing = WellnarioSpacing.cardGap
        contentStack.alignment = .fill

        view.addForAutoLayout(scrollView)
        view.addForAutoLayout(confirmButton)
        scrollView.addForAutoLayout(contentStack)

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: confirmButton.topAnchor, constant: -WellnarioSpacing.small),

            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: WellnarioSpacing.small
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -WellnarioSpacing.small
            ),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -(WellnarioSpacing.screenHorizontal * 2)
            ),

            confirmButton.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            confirmButton.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            confirmButton.bottomAnchor.constraint(
                equalTo: safeArea.bottomAnchor,
                constant: -WellnarioSpacing.xxSmall
            )
        ])
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        confirmButton.accessibilityIdentifier = "widget.intake.confirm"
    }

    private func configureContent() {
        let messageLabel = UILabel()
        messageLabel.numberOfLines = 0
        messageLabel.text = L10n.text("widget.intake.adjust.message")
        messageLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        contentStack.addArrangedSubview(messageLabel)

        for (index, intake) in intakes.enumerated() {
            contentStack.addArrangedSubview(makeIntakeCard(intake, index: index))
        }
    }

    private func makeIntakeCard(_ intake: WidgetPendingIntake, index: Int) -> UIView {
        let card = PremiumCardView()
        card.accessibilityIdentifier = "widget.intake.package.\(intake.package.id.uuidString)"

        let titleLabel = UILabel()
        titleLabel.numberOfLines = 2
        titleLabel.text = intake.supplement.name
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)

        let languageCode = LocalizationManager.shared.language.rawValue
        let dose = "\(FeatureFormatting.decimal(intake.supplement.basisQuantity)) \(intake.supplement.basisUnit.symbol(languageCode: languageCode))"
        let detailLabel = UILabel()
        detailLabel.numberOfLines = 2
        detailLabel.text = "\(intake.package.label) · \(dose)"
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)

        let supplementInfo = UIStackView(
            arrangedSubviews: [titleLabel, detailLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )

        let content: UIStackView
        var constraints: [NSLayoutConstraint] = []
        if requiresAmountEntry(for: intake) {
            let amountField = FormFieldView()
            amountField.configure(
                title: L10n.text("widget.intake.amount.title"),
                placeholder: FeatureFormatting.decimal(intake.supplement.basisQuantity),
                keyboardType: .decimalPad
            )
            amountField.unitTitle = intake.supplement.basisUnit.symbol(languageCode: languageCode)
            amountField.unitIsSelectable = false
            amountField.textField.autocorrectionType = .no
            amountField.textField.accessibilityIdentifier = "widget.intake.amount.\(intake.package.id.uuidString)"
            amountFields[intake.package.id] = amountField

            content = UIStackView(
                arrangedSubviews: [supplementInfo, amountField],
                axis: .vertical,
                spacing: WellnarioSpacing.small
            )
        } else {
            let quantityTitle = UILabel()
            quantityTitle.text = L10n.text("widget.intake.quantity.title")
            quantityTitle.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)

            let quantityLabel = UILabel()
            quantityLabel.text = "1"
            quantityLabel.textAlignment = .center
            quantityLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
            quantityLabels[intake.package.id] = quantityLabel

            let stepper = UIStepper()
            stepper.minimumValue = 1
            stepper.maximumValue = 99
            stepper.stepValue = 1
            stepper.value = 1
            stepper.autorepeat = true
            stepper.wraps = false
            stepper.tintColor = WellnarioPalette.cyan
            stepper.tag = index
            stepper.accessibilityLabel = "\(L10n.text("widget.intake.quantity.title")) · \(intake.supplement.name)"
            stepper.accessibilityIdentifier = "widget.intake.quantity.\(intake.package.id.uuidString)"
            stepper.addTarget(self, action: #selector(quantityChanged(_:)), for: .valueChanged)

            let quantityValueStack = UIStackView(
                arrangedSubviews: [quantityLabel, stepper],
                axis: .horizontal,
                spacing: WellnarioSpacing.xxSmall,
                alignment: .center
            )
            let quantityStack = UIStackView(
                arrangedSubviews: [quantityTitle, quantityValueStack],
                axis: .vertical,
                spacing: WellnarioSpacing.xxxSmall,
                alignment: .trailing
            )
            content = UIStackView(
                arrangedSubviews: [supplementInfo, quantityStack],
                axis: .horizontal,
                spacing: WellnarioSpacing.xSmall,
                alignment: .center
            )
            constraints += [
                quantityLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
                stepper.heightAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.minimumTouchTarget)
            ]
        }

        card.contentView.addForAutoLayout(content)
        constraints += [
            content.leadingAnchor.constraint(
                equalTo: card.contentView.leadingAnchor,
                constant: WellnarioSpacing.cardPadding
            ),
            content.trailingAnchor.constraint(
                equalTo: card.contentView.trailingAnchor,
                constant: -WellnarioSpacing.cardPadding
            ),
            content.topAnchor.constraint(
                equalTo: card.contentView.topAnchor,
                constant: WellnarioSpacing.small
            ),
            content.bottomAnchor.constraint(
                equalTo: card.contentView.bottomAnchor,
                constant: -WellnarioSpacing.small
            )
        ]
        NSLayoutConstraint.activate(constraints)
        return card
    }

    private func requiresAmountEntry(for intake: WidgetPendingIntake) -> Bool {
        switch intake.supplement.basisUnit.family {
        case .mass, .volume:
            true
        case .discrete, .internationalUnit:
            false
        }
    }

    @objc private func quantityChanged(_ sender: UIStepper) {
        let intake = intakes[sender.tag]
        let quantity = Int(sender.value)
        quantities[intake.package.id] = quantity
        quantityLabels[intake.package.id]?.text = "\(quantity)"
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func confirmTapped() {
        view.endEditing(true)
        guard let requests = makeIntakeRequests() else { return }
        confirmButton.isLoading = true
        navigationItem.leftBarButtonItem?.isEnabled = false

        do {
            let recordedCount = try onConfirm(requests)
            let announcement = recordedCount == 1
                ? L10n.text("widget.intake.recorded")
                : L10n.text("widget.intake.batch.recorded", recordedCount)
            UIImpactFeedbackGenerator.wellnarioSuccess()
            UIAccessibility.post(notification: .announcement, argument: announcement)
            dismiss(animated: true)
        } catch {
            confirmButton.isLoading = false
            navigationItem.leftBarButtonItem?.isEnabled = true
            presentError(error)
        }
    }

    private func makeIntakeRequests() -> [WidgetIntakeRequest]? {
        var requests: [WidgetIntakeRequest] = []
        for intake in intakes {
            if requiresAmountEntry(for: intake) {
                let amountField = amountFields[intake.package.id]
                amountField?.setError(nil)
                guard let amount = FeatureFormatting.parseDecimal(amountField?.textField.text), amount > 0 else {
                    amountField?.setError(L10n.Error.positiveAmount)
                    amountField?.textField.becomeFirstResponder()
                    return nil
                }
                requests.append(
                    WidgetIntakeRequest(
                        intake: intake,
                        amount: amount,
                        unit: intake.supplement.basisUnit,
                        repetitions: 1
                    )
                )
            } else {
                requests.append(
                    WidgetIntakeRequest(
                        intake: intake,
                        amount: intake.supplement.basisQuantity,
                        unit: intake.supplement.basisUnit,
                        repetitions: quantities[intake.package.id] ?? 1
                    )
                )
            }
        }
        return requests
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(
            title: L10n.Common.error,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
        present(alert, animated: true)
    }
}
