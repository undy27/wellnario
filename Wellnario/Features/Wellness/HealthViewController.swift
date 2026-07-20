import UIKit

enum HealthCardKind: String, CaseIterable, WellnessCardKind, Sendable {
    case biologicalAge
    case biomarkers
    case medicalReviews

    static let storageNamespace = "health"

    @MainActor
    var title: String {
        switch self {
        case .biologicalAge: L10n.text("health.biological_age.title")
        case .biomarkers: L10n.text("health.biomarkers.title")
        case .medicalReviews: L10n.text("health.medical_reviews.title")
        }
    }

    var symbolName: String {
        switch self {
        case .biologicalAge: "figure.stand"
        case .biomarkers: "waveform.path.ecg"
        case .medicalReviews: "calendar.badge.clock"
        }
    }
}

typealias HealthCardLayoutPreferences = WellnessCardLayoutPreferences<HealthCardKind>

@MainActor
final class HealthViewController: UIViewController {
    private enum Mode: Int, CaseIterable {
        case reviews
        case biomarkers
        case analytics
    }

    private struct SourceBannerEvent: Equatable {
        let state: AppleHealthSyncState
        let lastSyncedAt: Date?
    }

    private static let sourceBannerHeight: CGFloat = 76
    private static let sourceBannerDisplayDuration: UInt64 = 10_000_000_000

    var onOpenSettings: (() -> Void)?

    private let appleHealthService: AppleHealthSyncing
    private let healthDataStore: HealthDataStore
    private let biologicalAgePreferences: BiologicalAgePreferences
    private let segmentedControl = UISegmentedControl(items: ["", "", ""])
    private let sourceBanner = FeedbackBannerView()
    private lazy var syncIndicator = AppleHealthSyncNavigationIndicator(service: appleHealthService)
    private let biologicalAgeSummary = BiologicalAgeSummaryView()
    private let biomarkerTrendsBarButton = BreathingNavigationButton()
    private lazy var biomarkerTrendsBarButtonItem = UIBarButtonItem(
        customView: biomarkerTrendsBarButton
    )
    private let containerView = UIView()
    private let reviewsController: MedicalReviewsViewController
    private let biomarkersController: BiomarkersViewController
    private let analyticsController: LabAnalysesViewController
    private var sourceBannerHeightConstraint: NSLayoutConstraint!
    private var mode: Mode = .reviews
    private var visibleController: UIViewController?
    private var activeModeTransition: UIViewPropertyAnimator?
    private var activeModeTransitionSnapshot: UIView?
    private var activeModeTransitionID: UUID?
    private var terminalSourceBannerEvent: SourceBannerEvent?
    private var sourceBannerDismissalTask: Task<Void, Never>?

    var scrollView: UIScrollView { reviewsController.tableView }

    init(
        appleHealthService: AppleHealthSyncing,
        medicalReviewStore: MedicalReviewStore = MedicalReviewStore(),
        healthDataStore: HealthDataStore = HealthDataStore(),
        defaults: UserDefaults = .standard
    ) {
        self.appleHealthService = appleHealthService
        self.healthDataStore = healthDataStore
        biologicalAgePreferences = BiologicalAgePreferences(defaults: defaults)
        reviewsController = MedicalReviewsViewController(store: medicalReviewStore)
        biomarkersController = BiomarkersViewController(
            store: healthDataStore,
            appleHealthService: appleHealthService
        )
        analyticsController = LabAnalysesViewController(store: healthDataStore)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WellnarioPalette.background
        title = L10n.text("health.title")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal
        view.accessibilityIdentifier = "health.root"

        configureNavigationBar()
        configureBiomarkerTrendsButton()
        configureBanner()
        configureBiologicalAgeSummary()
        configureSegmentedControl()
        configureChildren()
        updateSourceBanner()
        show(mode: .reviews, animated: false)
        syncIndicator.install(
            on: navigationItem,
            baseItems: navigationItem.rightBarButtonItems ?? []
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appleHealthDidChange),
            name: .appleHealthSyncDidChange,
            object: appleHealthService
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(analysesDidChange),
            name: .healthAnalysesDidChange,
            object: healthDataStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LocalizationManager.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshBiologicalAgeForTimeChange),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshBiologicalAgeForTimeChange),
            name: .NSCalendarDayChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshBiologicalAgeForTimeChange),
            name: UIApplication.significantTimeChangeNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        updateSourceBanner()
        refreshBiologicalAgeSummary()
        refreshVisibleController()
        updateTopBarButtons()
        syncIndicator.refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The custom tab transition can complete after viewWillAppear. Read
        // the shared service again once the navigation item is on screen so
        // this is the only animated navigation icon when a sync is active.
        syncIndicator.refresh()
    }

    deinit {
        sourceBannerDismissalTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func configureBanner() {
        sourceBanner.accessibilityIdentifier = "health.source.banner"
        sourceBanner.backgroundOpacityOverride = WellnarioPalette.synchronizationBannerOpacity
        view.addForAutoLayout(sourceBanner)
        sourceBannerHeightConstraint = sourceBanner.heightAnchor.constraint(
            equalToConstant: Self.sourceBannerHeight
        )
        NSLayoutConstraint.activate([
            sourceBanner.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            sourceBanner.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            sourceBanner.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: WellnarioSpacing.xxxSmall
            ),
            sourceBannerHeightConstraint
        ])
    }

    private func configureNavigationBar() {
        // The health screen starts directly with its biological-age summary and
        // tabs; keep the navigation bar available for actions without a title.
        navigationItem.leftBarButtonItem = nil
        navigationItem.titleView = UIView(frame: .zero)
    }

    private func configureBiologicalAgeSummary() {
        biologicalAgeSummary.onTap = { [weak self] in
            self?.openBiologicalAgeEstimation()
        }
        biologicalAgeSummary.onTripleTap = { [weak self] in
            self?.openBiologicalAgeAudit()
        }
        refreshBiologicalAgeSummary()
        view.addForAutoLayout(biologicalAgeSummary)
        NSLayoutConstraint.activate([
            biologicalAgeSummary.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            biologicalAgeSummary.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            biologicalAgeSummary.topAnchor.constraint(
                equalTo: sourceBanner.bottomAnchor,
                constant: WellnarioSpacing.xSmall
            ),
            biologicalAgeSummary.heightAnchor.constraint(equalToConstant: 132)
        ])
    }

    private func configureSegmentedControl() {
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.selectedSegmentTintColor = WellnarioPalette.fuchsia
        segmentedControl.backgroundColor = WellnarioPalette.surface
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: WellnarioPalette.textSecondary,
            .font: WellnarioTypography.font(for: .caption)
        ], for: .normal)
        segmentedControl.setTitleTextAttributes([
            .foregroundColor: UIColor.white,
            .font: WellnarioTypography.font(for: .caption)
        ], for: .selected)
        segmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        segmentedControl.accessibilityIdentifier = "health.tabs"
        applyLocalizedCopy()

        view.addForAutoLayout(segmentedControl)
        view.addForAutoLayout(containerView)
        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            segmentedControl.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            segmentedControl.topAnchor.constraint(
                equalTo: biologicalAgeSummary.bottomAnchor,
                constant: WellnarioSpacing.xSmall
            ),
            segmentedControl.heightAnchor.constraint(equalToConstant: 40),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.topAnchor.constraint(
                equalTo: segmentedControl.bottomAnchor,
                constant: WellnarioSpacing.xSmall
            ),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureChildren() {
        [reviewsController, biomarkersController, analyticsController].forEach { controller in
            addChild(controller)
            containerView.addForAutoLayout(controller.view)
            controller.view.pinEdges(to: containerView)
            controller.didMove(toParent: self)
            controller.view.isHidden = true
        }
    }

    private func applyLocalizedCopy() {
        title = L10n.text("health.title")
        segmentedControl.setTitle(L10n.text("health.tabs.reviews"), forSegmentAt: Mode.reviews.rawValue)
        segmentedControl.setTitle(L10n.text("health.tabs.biomarkers"), forSegmentAt: Mode.biomarkers.rawValue)
        segmentedControl.setTitle(L10n.text("health.tabs.analytics"), forSegmentAt: Mode.analytics.rawValue)
        biomarkerTrendsBarButton.accessibilityLabel = L10n.text("health.biomarker_trends.title")
        biomarkerTrendsBarButtonItem.accessibilityLabel = L10n.text("health.biomarker_trends.title")
        refreshBiologicalAgeSummary()
    }

    private func show(mode newMode: Mode, animated: Bool) {
        let destination = controller(for: newMode)
        guard destination !== visibleController else {
            mode = newMode
            segmentedControl.selectedSegmentIndex = newMode.rawValue
            updateTopBarButtons()
            return
        }

        finishActiveModeTransition()
        let old = visibleController
        mode = newMode
        segmentedControl.selectedSegmentIndex = newMode.rawValue
        destination.view.isHidden = false
        destination.view.alpha = 1
        containerView.bringSubviewToFront(destination.view)
        visibleController = destination
        refreshVisibleController()
        updateTopBarButtons()

        guard animated, let old else {
            old?.view.isHidden = true
            old?.view.alpha = 1
            return
        }

        guard let snapshot = old.view.snapshotView(afterScreenUpdates: true) else {
            old.view.alpha = 1
            destination.view.alpha = 0
            startFallbackTransition(from: old, to: destination)
            return
        }

        let snapshotFrame = old.view.convert(old.view.bounds, to: containerView)
        snapshot.frame = snapshotFrame
        snapshot.isUserInteractionEnabled = false
        snapshot.isAccessibilityElement = false
        snapshot.accessibilityIdentifier = "health.tabTransition.snapshot"
        containerView.addSubview(snapshot)

        destination.view.alpha = 0
        let identifier = UUID()
        activeModeTransitionID = identifier
        activeModeTransitionSnapshot = snapshot
        let animator = UIViewPropertyAnimator(
            duration: WellnarioScreenTransition.effectiveDuration,
            curve: .linear
        ) {
            snapshot.alpha = 0
            destination.view.alpha = 1
        }
        animator.addCompletion { [weak self, weak old, weak destination, weak snapshot] _ in
            guard let self, self.activeModeTransitionID == identifier else { return }
            old?.view.isHidden = true
            old?.view.alpha = 1
            destination?.view.isHidden = false
            destination?.view.alpha = 1
            snapshot?.removeFromSuperview()
            self.activeModeTransition = nil
            self.activeModeTransitionSnapshot = nil
            self.activeModeTransitionID = nil
        }
        activeModeTransition = animator
        animator.startAnimation()
    }

    private func startFallbackTransition(from old: UIViewController, to destination: UIViewController) {
        let identifier = UUID()
        activeModeTransitionID = identifier
        let animator = UIViewPropertyAnimator(
            duration: WellnarioScreenTransition.effectiveDuration,
            curve: .linear
        ) {
            old.view.alpha = 0
            destination.view.alpha = 1
        }
        animator.addCompletion { [weak self, weak old, weak destination] _ in
            guard let self, self.activeModeTransitionID == identifier else { return }
            old?.view.isHidden = true
            old?.view.alpha = 1
            destination?.view.isHidden = false
            destination?.view.alpha = 1
            self.activeModeTransition = nil
            self.activeModeTransitionID = nil
        }
        activeModeTransition = animator
        animator.startAnimation()
    }

    private func finishActiveModeTransition() {
        activeModeTransition?.stopAnimation(true)
        activeModeTransition = nil
        activeModeTransitionSnapshot?.removeFromSuperview()
        activeModeTransitionSnapshot = nil
        activeModeTransitionID = nil
        [reviewsController, biomarkersController, analyticsController].forEach { controller in
            controller.view.alpha = 1
            controller.view.isHidden = controller !== visibleController
        }
    }

    private func controller(for mode: Mode) -> UIViewController {
        switch mode {
        case .reviews: reviewsController
        case .biomarkers: biomarkersController
        case .analytics: analyticsController
        }
    }

    private func refreshVisibleController() {
        switch mode {
        case .reviews: reviewsController.reloadReviews()
        case .biomarkers: biomarkersController.reloadContent()
        case .analytics: analyticsController.reloadContent()
        }
    }

    private func updateTopBarButtons() {
        let settings = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        settings.accessibilityLabel = L10n.Settings.title
        settings.accessibilityIdentifier = "health.settings"

        switch mode {
        case .reviews:
            let add = UIBarButtonItem(
                image: UIImage(systemName: "plus"),
                style: .plain,
                target: self,
                action: #selector(addReview)
            )
            add.tintColor = WellnarioPalette.fuchsia
            add.accessibilityLabel = L10n.text("health.medical_reviews.add")
            add.accessibilityIdentifier = "health.medical_reviews.add"
            let history = UIBarButtonItem(
                image: UIImage(systemName: "clock.arrow.circlepath"),
                style: .plain,
                target: self,
                action: #selector(openReviewHistory)
            )
            history.tintColor = WellnarioPalette.fuchsia
            history.accessibilityLabel = L10n.text("health.medical_reviews.all.open")
            history.accessibilityIdentifier = "health.medical_reviews.all.open"
            setRightBarButtonItems([settings, add, history])
        case .biomarkers:
            let add = UIBarButtonItem(
                image: UIImage(systemName: "plus"),
                style: .plain,
                target: self,
                action: #selector(addBiomarker)
            )
            add.tintColor = WellnarioPalette.fuchsia
            add.accessibilityLabel = L10n.text("health.biomarkers.add")
            add.accessibilityIdentifier = "health.biomarkers.add"
            setRightBarButtonItems([settings, add, biomarkerTrendsBarButtonItem])
        case .analytics:
            let add = UIBarButtonItem(
                image: UIImage(systemName: "plus"),
                style: .plain,
                target: self,
                action: #selector(addAnalysis)
            )
            add.tintColor = WellnarioPalette.fuchsia
            add.accessibilityLabel = L10n.text("health.analytics.add")
            add.accessibilityIdentifier = "health.analytics.add"
            setRightBarButtonItems([settings, add, biomarkerTrendsBarButtonItem])
        }
    }

    private func setRightBarButtonItems(_ items: [UIBarButtonItem]) {
        syncIndicator.setBaseItems(items)
    }

    private func configureBiomarkerTrendsButton() {
        biomarkerTrendsBarButton.setImage(UIImage(systemName: "chart.xyaxis.line"), for: .normal)
        biomarkerTrendsBarButton.tintColor = WellnarioPalette.fuchsia
        biomarkerTrendsBarButton.accessibilityIdentifier = "health.biomarker_trends.open"
        biomarkerTrendsBarButton.addTarget(
            self,
            action: #selector(openBiomarkerTrends),
            for: .touchUpInside
        )
        biomarkerTrendsBarButtonItem.accessibilityIdentifier = "health.biomarker_trends.open"
    }

    private func updateSourceBanner() {
        guard appleHealthService.isConfigured else {
            clearTerminalSourceBannerEvent()
            hideSourceBannerImmediately()
            return
        }

        let event = SourceBannerEvent(
            state: appleHealthService.state,
            lastSyncedAt: appleHealthService.snapshot.lastSyncedAt
        )
        switch appleHealthService.state {
        case .ready, .failed:
            if appleHealthService.state == .ready {
                clearTerminalSourceBannerEvent()
                hideSourceBannerImmediately()
                return
            }
            guard terminalSourceBannerEvent != event else {
                if !sourceBanner.isHidden { configureSourceBanner() }
                return
            }
            terminalSourceBannerEvent = event
            showSourceBanner()
            configureSourceBanner()
            scheduleSourceBannerDismissal(for: event)
        case .syncing:
            clearTerminalSourceBannerEvent()
            hideSourceBannerImmediately()
        case .unavailable, .notConfigured:
            clearTerminalSourceBannerEvent()
            showSourceBanner()
            configureSourceBanner()
        }
    }

    private func showSourceBanner() {
        sourceBannerDismissalTask?.cancel()
        sourceBanner.isHidden = false
        sourceBanner.alpha = 1
        sourceBanner.transform = .identity
        sourceBannerHeightConstraint.constant = Self.sourceBannerHeight
        view.bringSubviewToFront(sourceBanner)
        view.setNeedsLayout()
    }

    private func hideSourceBannerImmediately() {
        sourceBanner.isHidden = true
        sourceBanner.alpha = 1
        sourceBanner.transform = .identity
        sourceBannerHeightConstraint.constant = 0
        view.setNeedsLayout()
    }

    private func clearTerminalSourceBannerEvent() {
        sourceBannerDismissalTask?.cancel()
        sourceBannerDismissalTask = nil
        terminalSourceBannerEvent = nil
    }

    private func scheduleSourceBannerDismissal(for event: SourceBannerEvent) {
        sourceBannerDismissalTask?.cancel()
        sourceBannerDismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.sourceBannerDisplayDuration)
            guard !Task.isCancelled,
                  let self,
                  self.terminalSourceBannerEvent == event else { return }
            self.dismissSourceBanner(for: event)
        }
    }

    private func dismissSourceBanner(for event: SourceBannerEvent) {
        guard terminalSourceBannerEvent == event, !sourceBanner.isHidden else { return }
        view.layoutIfNeeded()
        WellnarioMotion.animate(duration: 0.36, animations: {
            self.sourceBanner.alpha = 0
            self.sourceBanner.transform = CGAffineTransform(translationX: 0, y: -6)
            self.sourceBannerHeightConstraint.constant = 0
            self.view.layoutIfNeeded()
        }, completion: { [weak self] _ in
            guard let self, self.terminalSourceBannerEvent == event else { return }
            self.sourceBanner.isHidden = true
            self.sourceBanner.alpha = 1
            self.sourceBanner.transform = .identity
        })
    }

    private func configureSourceBanner() {
        sourceBanner.onAction = nil
        switch appleHealthService.state {
        case .unavailable:
            sourceBanner.configure(message: L10n.text("apple_health.unavailable"), tone: .warning)
        case .notConfigured:
            sourceBanner.configure(
                message: L10n.text("health.source.empty"),
                tone: .information,
                actionTitle: L10n.text("integrations.connect")
            )
            sourceBanner.onAction = { [weak self] in self?.onOpenSettings?() }
        case .syncing:
            sourceBanner.configure(message: L10n.text("apple_health.syncing"), tone: .information)
        case .failed:
            sourceBanner.configure(
                message: L10n.text("apple_health.sync_failed"),
                tone: .warning,
                actionTitle: AppleHealthUIFormatting.twoLineSyncNowActionTitle
            )
            sourceBanner.onAction = { [weak self] in self?.syncNow() }
        case .ready:
            let message = appleHealthService.snapshot.lastSyncedAt.map(AppleHealthUIFormatting.syncedAt)
                ?? L10n.text("apple_health.configured")
            sourceBanner.configure(
                message: message,
                tone: .success,
                actionTitle: AppleHealthUIFormatting.twoLineSyncNowActionTitle
            )
            sourceBanner.onAction = { [weak self] in self?.syncNow() }
        }
    }

    @objc private func modeChanged() {
        guard let mode = Mode(rawValue: segmentedControl.selectedSegmentIndex) else { return }
        show(mode: mode, animated: true)
    }

    @objc private func addReview() { reviewsController.addReview() }
    @objc private func openReviewHistory() { reviewsController.showAllReviews() }
    @objc private func addBiomarker() { biomarkersController.addBiomarker() }
    @objc private func openBiomarkerTrends() {
        navigationController?.pushViewController(
            BiomarkerTrendsViewController(store: biomarkersController.healthDataStore),
            animated: true
        )
    }
    private func openBiologicalAgeEstimation() {
        navigationController?.pushViewController(
            BiologicalAgeEstimationViewController(
                store: healthDataStore,
                appleHealthService: appleHealthService,
                preferences: biologicalAgePreferences
            ),
            animated: true
        )
    }
    private func openBiologicalAgeAudit() {
        let profile = BiologicalAgeProfileResolver.resolve(
            store: healthDataStore,
            snapshot: appleHealthService.snapshot,
            preferences: biologicalAgePreferences
        )
        navigationController?.pushViewController(
            BiologicalAgeAuditViewController(profile: profile),
            animated: true
        )
    }
    @objc private func addAnalysis() { analyticsController.addAnalysis() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func appleHealthDidChange() {
        updateSourceBanner()
        refreshBiologicalAgeSummary()
    }
    @objc private func analysesDidChange() {
        refreshBiologicalAgeSummary()
    }
    @objc private func refreshBiologicalAgeForTimeChange() {
        refreshBiologicalAgeSummary()
    }
    @objc private func languageDidChange() {
        applyLocalizedCopy()
        refreshVisibleController()
        updateTopBarButtons()
    }

    private func syncNow() {
        Task { try? await appleHealthService.sync() }
    }

    private func refreshBiologicalAgeSummary() {
        let profile = BiologicalAgeProfileResolver.resolve(
            store: healthDataStore,
            snapshot: appleHealthService.snapshot,
            preferences: biologicalAgePreferences
        )
        biologicalAgeSummary.configure(profile: profile)
    }
}

@MainActor
private final class BiologicalAgeSummaryView: UIView {
    private static let biologicalAgeScale: CGFloat = 1.20

    var onTap: (() -> Void)?
    var onTripleTap: (() -> Void)?

    private let titleLabel = UILabel()
    private let card = PremiumCardView()
    private let placeholderArtwork = UIImageView()
    private let biologicalAgeRing = BiologicalAgeRingView()
    private let valueStack = UIStackView()
    private let valueLabel = UILabel()
    private let unitLabel = UILabel()
    private let detailLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(profile: BiologicalAgeProfile) {
        titleLabel.text = L10n.text("health.biological_age.estimate")
        placeholderArtwork.image = UIImage(named: "biological_age_placeholder")
        let estimate = profile.estimate
        let phenoAge = estimate.phenoAge.map { Int($0.rounded()) }
        let bioAge = estimate.bioAge.map { Int($0.rounded()) }

        if let phenoAge,
           let bioAge,
           let weightedAge = profile.weightedEstimate.age,
           let chronologicalAge = profile.chronologicalAge {
            let roundedAverage = Int(weightedAge.rounded())
            placeholderArtwork.isHidden = true
            biologicalAgeRing.setValueVisible(true)
            valueStack.isHidden = true
            biologicalAgeRing.configure(
                biologicalAge: weightedAge,
                chronologicalAge: Double(chronologicalAge)
            )
            detailLabel.text = L10n.text(
                "health.biological_age.summary.average.detail",
                chronologicalAge
            )
            card.accessibilityValue = L10n.text(
                "health.biological_age.summary.average.accessibility",
                roundedAverage,
                chronologicalAge,
                phenoAge,
                bioAge
            )
        } else if let estimatedAge = phenoAge ?? bioAge {
            placeholderArtwork.isHidden = true
            biologicalAgeRing.setValueVisible(false)
            valueStack.isHidden = false
            valueLabel.text = String(estimatedAge)
            unitLabel.text = L10n.text("health.biological_age.years")
            detailLabel.text = L10n.text("health.biological_age.summary.partial")
            card.accessibilityValue = L10n.text(
                "health.biological_age.estimate.accessibility",
                estimatedAge
            )
        } else {
            placeholderArtwork.isHidden = false
            biologicalAgeRing.setValueVisible(false)
            valueStack.isHidden = true
            detailLabel.text = L10n.text("health.biological_age.empty")
            card.accessibilityValue = detailLabel.text
        }
        card.accessibilityLabel = titleLabel.text
    }

    private func configureView() {
        accessibilityIdentifier = "health.card.section.biologicalAge"
        titleLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        titleLabel.accessibilityIdentifier = "health.biological_age.title"
        titleLabel.numberOfLines = 1

        placeholderArtwork.contentMode = .scaleAspectFill
        placeholderArtwork.clipsToBounds = true
        placeholderArtwork.applyContinuousCorners(16)
        placeholderArtwork.backgroundColor = WellnarioPalette.surfaceElevated
        placeholderArtwork.accessibilityIdentifier = "health.biological_age.placeholder"

        biologicalAgeRing.accessibilityIdentifier = "health.biological_age.ring"
        biologicalAgeRing.isHidden = true

        valueLabel.applyWellnarioStyle(.metric, color: WellnarioPalette.textPrimary)
        unitLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        valueStack.axis = .horizontal
        valueStack.spacing = 3
        valueStack.alignment = .lastBaseline
        valueStack.transform = CGAffineTransform(scaleX: Self.biologicalAgeScale, y: Self.biologicalAgeScale)
        valueStack.addArrangedSubview(valueLabel)
        valueStack.addArrangedSubview(unitLabel)

        let leading = UIView()
        leading.addForAutoLayout(placeholderArtwork)
        leading.addForAutoLayout(biologicalAgeRing)
        leading.addForAutoLayout(valueStack)
        NSLayoutConstraint.activate([
            leading.widthAnchor.constraint(equalToConstant: 80 * Self.biologicalAgeScale),
            placeholderArtwork.widthAnchor.constraint(equalToConstant: 70),
            placeholderArtwork.heightAnchor.constraint(equalTo: placeholderArtwork.widthAnchor),
            placeholderArtwork.centerXAnchor.constraint(equalTo: leading.centerXAnchor),
            placeholderArtwork.centerYAnchor.constraint(equalTo: leading.centerYAnchor),
            biologicalAgeRing.widthAnchor.constraint(equalToConstant: 59 * Self.biologicalAgeScale),
            biologicalAgeRing.heightAnchor.constraint(equalTo: biologicalAgeRing.widthAnchor),
            biologicalAgeRing.centerXAnchor.constraint(equalTo: leading.centerXAnchor),
            biologicalAgeRing.centerYAnchor.constraint(equalTo: leading.centerYAnchor),
            valueStack.centerXAnchor.constraint(equalTo: leading.centerXAnchor),
            valueStack.centerYAnchor.constraint(equalTo: leading.centerYAnchor)
        ])

        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detailLabel.accessibilityIdentifier = "health.biological_age.detail"
        detailLabel.numberOfLines = 5
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        let content = UIStackView(
            arrangedSubviews: [leading, detailLabel],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        card.accessibilityIdentifier = "health.biological_age"
        card.accessibilityHint = L10n.text("health.biological_age.audit.hint")
        card.isPressable = true
        card.addTarget(self, action: #selector(cardTapped), for: .touchUpInside)
        let tripleTap = UITapGestureRecognizer(target: self, action: #selector(cardTripleTapped))
        tripleTap.numberOfTapsRequired = 3
        tripleTap.numberOfTouchesRequired = 1
        tripleTap.cancelsTouchesInView = true
        tripleTap.delaysTouchesEnded = true
        card.addGestureRecognizer(tripleTap)
        card.contentView.addForAutoLayout(content)
        content.pinEdges(
            to: card.contentView,
            insets: NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        )
        card.heightAnchor.constraint(equalToConstant: 94).isActive = true

        let stack = UIStackView(
            arrangedSubviews: [titleLabel, card],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        addForAutoLayout(stack)
        stack.pinEdges(
            to: self,
            insets: NSDirectionalEdgeInsets(
                top: WellnarioSpacing.xxxSmall,
                leading: WellnarioSpacing.screenHorizontal,
                bottom: WellnarioSpacing.xxxSmall,
                trailing: WellnarioSpacing.screenHorizontal
            )
        )
        isAccessibilityElement = false
    }

    @objc private func cardTapped() {
        onTap?()
    }

    @objc private func cardTripleTapped() {
        onTripleTap?()
    }
}

struct BiologicalAgeRingComparison: Equatable, Sendable {
    let coloredArcProportion: Double
    let usesGreen: Bool

    init(biologicalAge: Double, chronologicalAge: Double) {
        let referenceAge = max(max(biologicalAge, chronologicalAge), 0)
        let comparedAge = max(min(biologicalAge, chronologicalAge), 0)
        coloredArcProportion = referenceAge > 0
            ? min(max(comparedAge / referenceAge, 0), 1)
            : 0
        usesGreen = chronologicalAge > biologicalAge
    }
}

/// A compact comparison of chronological and biological age. The larger age
/// defines the full circumference; the smaller age defines the green or red
/// share, while violet fills the remainder. A soft glow and a narrow light
/// reflection give the ring its raised, luminous treatment.
@MainActor
private final class BiologicalAgeRingView: UIView {
    private static let biologicalAgeScale: CGFloat = 1.20
    private static let glowAnimationKey = "wellnario.biologicalAge.glow"
    private static let glowOpacityAnimationKey = "wellnario.biologicalAge.glowOpacity"

    private let ringContainerLayer = CALayer()
    private let breathingGlowLayer = CAShapeLayer()
    private let coloredArcLayer = CAShapeLayer()
    private let remainderArcLayer = CAShapeLayer()
    private let coloredHighlightLayer = CAShapeLayer()
    private let remainderHighlightLayer = CAShapeLayer()
    private let ageLabel = UILabel()
    private let unitLabel = UILabel()
    private var coloredArcProportion: CGFloat = 0
    private var usesGreen = false
    private var hasConfiguredValue = false
    private var isValueVisible = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateGlowAnimation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ringContainerLayer.frame = bounds
        let lineWidth: CGFloat = 8.6 * Self.biologicalAgeScale
        let glowLineWidth: CGFloat = 15.75 * Self.biologicalAgeScale
        let halfDimension = min(bounds.width, bounds.height) / 2
        let arcRadius = max(0, halfDimension - lineWidth / 2 - 2)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let arcPath = UIBezierPath(
            arcCenter: center,
            radius: arcRadius,
            startAngle: -.pi / 2,
            endAngle: 3 * .pi / 2,
            clockwise: true
        )
        breathingGlowLayer.path = arcPath.cgPath
        breathingGlowLayer.lineWidth = glowLineWidth
        [coloredArcLayer, remainderArcLayer].forEach { layer in
            layer.path = arcPath.cgPath
            layer.lineWidth = lineWidth
        }
        let highlightPath = UIBezierPath(
            arcCenter: CGPoint(x: center.x, y: center.y - 0.75),
            radius: max(0, arcRadius - 0.25),
            startAngle: -.pi / 2,
            endAngle: 3 * .pi / 2,
            clockwise: true
        )
        [coloredHighlightLayer, remainderHighlightLayer].forEach { layer in
            layer.path = highlightPath.cgPath
            layer.lineWidth = 2.4 * Self.biologicalAgeScale
        }
        applyArcProportions()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard hasConfiguredValue else { return }
        applyColors()
        updateGlowAnimation()
    }

    func setValueVisible(_ isVisible: Bool) {
        isValueVisible = isVisible
        isHidden = !isVisible
        updateGlowAnimation()
    }

    func configure(biologicalAge: Double, chronologicalAge: Double) {
        let comparison = BiologicalAgeRingComparison(
            biologicalAge: biologicalAge,
            chronologicalAge: chronologicalAge
        )
        coloredArcProportion = CGFloat(comparison.coloredArcProportion)
        usesGreen = comparison.usesGreen
        ageLabel.text = String(Int(biologicalAge.rounded()))
        unitLabel.text = L10n.text("health.biological_age.years")
        hasConfiguredValue = true
        applyColors()
        setNeedsLayout()
        updateGlowAnimation()
    }

    private func configureView() {
        isAccessibilityElement = false
        ringContainerLayer.addSublayer(breathingGlowLayer)
        ringContainerLayer.addSublayer(coloredArcLayer)
        ringContainerLayer.addSublayer(remainderArcLayer)
        ringContainerLayer.addSublayer(coloredHighlightLayer)
        ringContainerLayer.addSublayer(remainderHighlightLayer)
        layer.addSublayer(ringContainerLayer)
        [
            breathingGlowLayer,
            coloredArcLayer,
            remainderArcLayer,
            coloredHighlightLayer,
            remainderHighlightLayer
        ].forEach { layer in
            layer.fillColor = UIColor.clear.cgColor
            layer.lineCap = .round
        }
        breathingGlowLayer.shadowOffset = .zero
        breathingGlowLayer.shadowOpacity = 0.68
        breathingGlowLayer.shadowRadius = 7.5
        [coloredArcLayer, remainderArcLayer].forEach { layer in
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 1.5)
            layer.shadowOpacity = 0.22
            layer.shadowRadius = 3
        }

        ageLabel.applyWellnarioStyle(.biologicalAgeRingMetric, color: WellnarioPalette.textPrimary)
        ageLabel.textAlignment = .center
        ageLabel.adjustsFontSizeToFitWidth = true
        ageLabel.minimumScaleFactor = 0.7
        unitLabel.applyWellnarioStyle(.biologicalAgeRingUnit, color: WellnarioPalette.textSecondary)
        unitLabel.textAlignment = .center

        let labels = UIStackView(
            arrangedSubviews: [ageLabel, unitLabel],
            axis: .vertical,
            spacing: -3,
            alignment: .center
        )
        labels.transform = CGAffineTransform(scaleX: Self.biologicalAgeScale, y: Self.biologicalAgeScale)
        addForAutoLayout(labels)
        NSLayoutConstraint.activate([
            labels.centerXAnchor.constraint(equalTo: centerXAnchor),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }

    private func applyArcProportions() {
        [coloredArcLayer, coloredHighlightLayer].forEach { layer in
            layer.strokeStart = 0
            layer.strokeEnd = coloredArcProportion
        }
        [remainderArcLayer, remainderHighlightLayer].forEach { layer in
            layer.strokeStart = coloredArcProportion
            layer.strokeEnd = 1
        }
        breathingGlowLayer.strokeStart = 0
        breathingGlowLayer.strokeEnd = 1
    }

    private func applyColors() {
        let predominant = (
            usesGreen
                ? WellnarioPalette.biologicalAgeGreen
                : WellnarioPalette.danger
        ).resolvedColor(with: traitCollection)
        let remainder = WellnarioPalette.violet
            .resolvedColor(with: traitCollection)
        coloredArcLayer.strokeColor = predominant.cgColor
        remainderArcLayer.strokeColor = remainder.cgColor
        breathingGlowLayer.strokeColor = predominant.withAlphaComponent(0.34).cgColor
        breathingGlowLayer.shadowColor = predominant.cgColor

        let reflection = UIColor.white.withAlphaComponent(
            traitCollection.userInterfaceStyle == .dark ? 0.48 : 0.34
        ).cgColor
        coloredHighlightLayer.strokeColor = reflection
        remainderHighlightLayer.strokeColor = reflection
    }

    private func updateGlowAnimation() {
        guard window != nil,
              hasConfiguredValue,
              isValueVisible,
              WellnarioMotion.animationsEnabled else {
            breathingGlowLayer.removeAnimation(forKey: Self.glowAnimationKey)
            breathingGlowLayer.removeAnimation(forKey: Self.glowOpacityAnimationKey)
            return
        }
        guard breathingGlowLayer.animation(forKey: Self.glowAnimationKey) == nil else { return }

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.075
        scale.duration = 1.9
        scale.autoreverses = true
        scale.repeatCount = .infinity
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.62
        opacity.toValue = 1.0
        opacity.duration = 1.9
        opacity.autoreverses = true
        opacity.repeatCount = .infinity
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        breathingGlowLayer.add(scale, forKey: Self.glowAnimationKey)
        breathingGlowLayer.add(opacity, forKey: Self.glowOpacityAnimationKey)
    }

    @objc private func reduceMotionChanged() {
        updateGlowAnimation()
    }

}
