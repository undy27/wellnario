import UIKit
import UniformTypeIdentifiers

@MainActor
final class TodayViewController: FeatureViewController {
    var onOpenSettings: (() -> Void)?
    var onShowSupplements: (() -> Void)?
    var onShowSleep: (() -> Void)?
    var onShowHealth: (() -> Void)?
    var onShowFitness: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let dateButton = UIButton(type: .system)
    private let syncIndicatorContainer = UIView()
    private let syncIndicatorView = UIImageView()
    private let lastSyncLabel = UILabel()
    private lazy var settingsBarButton: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        item.tintColor = WellnarioPalette.cyan
        item.accessibilityIdentifier = "today.settings"
        return item
    }()
    private lazy var syncIndicatorButton = UIBarButtonItem(customView: syncIndicatorContainer)

    private let sleepCard = TodaySleepSummaryCard()
    private let recoveryCard = TodayRecoverySummaryCard()
    private let stressCard = TodayStressSummaryCard()
    private let supplementsCard = WellnessSummaryCard()
    private let fitnessCard = WellnessSummaryCard()
    private let reviewsCard = TodayMedicalReviewsSummaryCard()

    private let intakeAction = QuickActionControl()
    private let workoutAction = QuickActionControl()
    private let labAction = QuickActionControl()
    private let factorAction = QuickActionControl()

    private var summary: DashboardSummary?
    private var selectedDate = Date()
    private var historicalStressTimeline: AppleHealthStressTimeline?
    private var historicalStressSleepSessions: [AppleHealthSleepSession] = []
    private var historicalStressWorkouts: [AppleHealthWorkout] = []
    private var requestedHistoricalStressDay: LocalDay?
    private var historicalStressTimelineTask: Task<Void, Never>?
    private let appleHealthService: AppleHealthSyncing
    private let medicalReviewStore: MedicalReviewStore
    private let sleepManualOverrideStore: SleepManualOverrideStore
    private let recoveryDataStore: RecoveryDataStore

    init(
        repository: WellnarioRepositoryProtocol,
        appleHealthService: AppleHealthSyncing,
        medicalReviewStore: MedicalReviewStore = MedicalReviewStore(),
        recoveryDataStore: RecoveryDataStore,
        sleepManualOverrideStore: SleepManualOverrideStore = SleepManualOverrideStore()
    ) {
        self.appleHealthService = appleHealthService
        self.medicalReviewStore = medicalReviewStore
        self.recoveryDataStore = recoveryDataStore
        self.sleepManualOverrideStore = sleepManualOverrideStore
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appleHealthDidChange),
            name: .appleHealthSyncDidChange,
            object: appleHealthService
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sleepManualOverridesDidChange),
            name: .sleepManualOverridesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sleepQualityPreferencesDidChange),
            name: .sleepQualityPreferencesDidChange,
            object: nil
        )
        applyLocalizedCopy()
        reloadContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        reloadContent()
    }

    override func applyLocalizedCopy() {
        navigationItem.accessibilityLabel = L10n.Tab.today
        dateButton.setTitle(WellnarioFormatters.dateHeader(selectedDate), for: .normal)
        settingsBarButton.accessibilityLabel = L10n.Settings.title
        syncIndicatorContainer.accessibilityLabel = L10n.text("apple_health.sync_now")
        updateLastSyncLabel()
        refreshHistoricalStressTimelineIfNeeded()
        configureStaticCards()
        configureQuickActions()
        if let summary { render(summary) }
    }

    override func reloadContent() {
        updateSyncIndicator()
        updateLastSyncLabel()
        refreshHistoricalStressTimelineIfNeeded()
        configureStaticCards()
        do {
            let summary = try repository.dashboard(
                on: LocalDay(containing: selectedDate, in: .current),
                expiringWithinDays: 30
            )
            self.summary = summary
            render(summary)
        } catch {
            showError(error)
        }
    }

    private func setUpView() {
        navigationController?.setNavigationBarHidden(false, animated: false)
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "today.root"
        setUpNavigationBar()

        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .always
        scrollView.showsVerticalScrollIndicator = false
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)

        contentStack.axis = .vertical
        contentStack.spacing = WellnarioSpacing.cardGap
        scrollView.addForAutoLayout(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: WellnarioSpacing.xxxSmall
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -WellnarioSpacing.bottomNavigationInset
            ),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -(WellnarioSpacing.screenHorizontal * 2)
            )
        ])

        contentStack.addArrangedSubview(makeWellnessSummaryHeader())
        setUpSummaryCards()
        contentStack.addArrangedSubview(makeSummaryGrid())

        let summaryGrid = contentStack.arrangedSubviews.last!
        contentStack.setCustomSpacing(WellnarioSpacing.large, after: summaryGrid)
        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("today.quick_actions")))
        setUpQuickActions()
        contentStack.addArrangedSubview(makeQuickActionsGrid())
    }

    private func setUpNavigationBar() {
        dateButton.titleLabel?.font = WellnarioTypography.font(for: .sectionTitle)
        dateButton.titleLabel?.adjustsFontForContentSizeCategory = true
        dateButton.titleLabel?.adjustsFontSizeToFitWidth = true
        dateButton.titleLabel?.minimumScaleFactor = 0.80
        dateButton.setTitleColor(WellnarioPalette.textPrimary, for: .normal)
        dateButton.contentHorizontalAlignment = .center
        dateButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        dateButton.tintColor = WellnarioPalette.textSecondary
        dateButton.semanticContentAttribute = .forceRightToLeft
        dateButton.addTarget(self, action: #selector(selectDate), for: .touchUpInside)
        navigationItem.titleView = dateButton

        syncIndicatorContainer.backgroundColor = .clear
        syncIndicatorContainer.accessibilityIdentifier = "today.apple_health.syncing"
        syncIndicatorContainer.accessibilityLabel = L10n.text("apple_health.sync_now")
        syncIndicatorContainer.isAccessibilityElement = true
        syncIndicatorContainer.accessibilityTraits = [.button]
        syncIndicatorContainer.isUserInteractionEnabled = true
        syncIndicatorContainer.addGestureRecognizer(UITapGestureRecognizer(
            target: self,
            action: #selector(syncAppleHealth)
        ))
        NSLayoutConstraint.activate([
            syncIndicatorContainer.widthAnchor.constraint(equalToConstant: 36),
            syncIndicatorContainer.heightAnchor.constraint(equalToConstant: 44)
        ])

        syncIndicatorView.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        syncIndicatorView.tintColor = WellnarioPalette.orange
        syncIndicatorView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 20,
            weight: .semibold
        )
        syncIndicatorView.contentMode = .scaleAspectFit
        syncIndicatorContainer.addForAutoLayout(syncIndicatorView)
        NSLayoutConstraint.activate([
            syncIndicatorView.centerXAnchor.constraint(equalTo: syncIndicatorContainer.centerXAnchor),
            syncIndicatorView.centerYAnchor.constraint(equalTo: syncIndicatorContainer.centerYAnchor)
        ])

        navigationItem.rightBarButtonItems = [settingsBarButton]
    }

    private func updateSyncIndicator() {
        let isSyncing = appleHealthService.state == .syncing
        let animationKey = "wellnario.today.appleHealthSync"
        syncIndicatorContainer.isHidden = false
        syncIndicatorContainer.alpha = 1
        syncIndicatorContainer.accessibilityLabel = L10n.text(
            isSyncing ? "apple_health.status.syncing" : "apple_health.sync_now"
        )
        syncIndicatorView.tintColor = WellnarioPalette.orange
        navigationItem.rightBarButtonItems = [settingsBarButton, syncIndicatorButton]
        guard isSyncing else {
            syncIndicatorView.layer.removeAnimation(forKey: animationKey)
            return
        }
        guard WellnarioMotion.animationsEnabled,
              syncIndicatorView.layer.animation(forKey: animationKey) == nil else {
            return
        }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = Double.pi * 2
        rotation.duration = 0.9
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        syncIndicatorView.layer.add(rotation, forKey: animationKey)
    }

    @objc private func syncAppleHealth() {
        guard appleHealthService.state != .syncing else { return }
        Task { [weak self] in
            guard let self else { return }
            try? await appleHealthService.sync()
        }
    }

    private func refreshHistoricalStressTimelineIfNeeded() {
        let calendar = Calendar.autoupdatingCurrent
        guard !calendar.isDateInToday(selectedDate) else {
            historicalStressTimelineTask?.cancel()
            historicalStressTimelineTask = nil
            requestedHistoricalStressDay = nil
            historicalStressTimeline = nil
            historicalStressSleepSessions = []
            historicalStressWorkouts = []
            return
        }

        let day = LocalDay(containing: selectedDate, in: calendar.timeZone)
        guard requestedHistoricalStressDay != day else { return }
        historicalStressTimelineTask?.cancel()
        requestedHistoricalStressDay = day
        historicalStressTimeline = nil
        historicalStressSleepSessions = []
        historicalStressWorkouts = []

        historicalStressTimelineTask = Task { [weak self, appleHealthService] in
            // Refresh HealthKit first: historical measurements may have been
            // written by a wearable since the last automatic sync, and the
            // source filters used by the day query are refreshed by sync.
            try? await appleHealthService.sync()
            guard !Task.isCancelled else { return }
            let result = await appleHealthService.stressTimeline(for: day)
            guard !Task.isCancelled,
                  let self,
                  self.requestedHistoricalStressDay == day else {
                return
            }
            self.historicalStressTimeline = result?.timeline
            self.historicalStressSleepSessions = result?.sleepSessions ?? []
            self.historicalStressWorkouts = result?.workouts ?? []
            self.historicalStressTimelineTask = nil
            self.configureStaticCards()
        }
    }

    private func invalidateHistoricalStressTimeline() {
        historicalStressTimelineTask?.cancel()
        historicalStressTimelineTask = nil
        requestedHistoricalStressDay = nil
        historicalStressTimeline = nil
        historicalStressSleepSessions = []
        historicalStressWorkouts = []
    }

    private func makeSectionTitle(_ title: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        label.text = title
        label.numberOfLines = 0
        return label
    }

    private func makeWellnessSummaryHeader() -> UIView {
        let titleLabel = makeSectionTitle(L10n.text("today.wellness_summary"))
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        lastSyncLabel.applyWellnarioStyle(.summaryDetail, color: WellnarioPalette.orange)
        lastSyncLabel.numberOfLines = 1
        lastSyncLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        lastSyncLabel.setContentHuggingPriority(.required, for: .horizontal)

        let header = UIStackView(
            arrangedSubviews: [titleLabel, lastSyncLabel],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .firstBaseline
        )
        header.isAccessibilityElement = false
        updateLastSyncLabel()
        return header
    }

    private func updateLastSyncLabel() {
        guard let lastSyncedAt = appleHealthService.snapshot.lastSyncedAt else {
            lastSyncLabel.text = nil
            lastSyncLabel.isHidden = true
            return
        }
        lastSyncLabel.text = L10n.text(
            "today.last_sync",
            WellnarioFormatters.time(lastSyncedAt)
        )
        lastSyncLabel.isHidden = false
    }

    private func setUpSummaryCards() {
        sleepCard.accessibilityIdentifier = "today.summary.sleep"
        recoveryCard.accessibilityIdentifier = "today.summary.recovery"
        stressCard.accessibilityIdentifier = "today.summary.stress"
        supplementsCard.accessibilityIdentifier = "today.summary.supplements"
        fitnessCard.accessibilityIdentifier = "today.summary.fitness"
        reviewsCard.accessibilityIdentifier = "today.summary.reviews"

        sleepCard.addTarget(self, action: #selector(openSleep), for: .touchUpInside)
        recoveryCard.addTarget(self, action: #selector(openRecovery), for: .touchUpInside)
        stressCard.addTarget(self, action: #selector(openStressDetails), for: .touchUpInside)
        supplementsCard.addTarget(self, action: #selector(openTodayIntakes), for: .touchUpInside)
        fitnessCard.addTarget(self, action: #selector(openFitness), for: .touchUpInside)
        reviewsCard.addTarget(self, action: #selector(openHealth), for: .touchUpInside)
    }

    private func configureStaticCards() {
        let noData = L10n.text("wellness.no_data")
        let snapshot = sleepManualOverrideStore.applying(to: appleHealthService.snapshot)
        let isToday = Calendar.autoupdatingCurrent.isDateInToday(selectedDate)
        let selectedDay = LocalDay(containing: selectedDate, in: .current)
        let manualOverride = sleepManualOverrideStore.override(for: selectedDay)
        let selectedSleepDay = snapshot.sleepTrend.last {
            LocalDay(containing: $0.date, in: .current) == selectedDay
        }

        let sleepDetail: String
        if selectedSleepDay?.hours != nil {
            if manualOverride != nil {
                sleepDetail = L10n.text("sleep.manual.source")
            } else if isToday, let session = snapshot.latestSleepSession {
                sleepDetail = AppleHealthUIFormatting.sleepRange(session)
            } else {
                sleepDetail = noData
            }
        } else if isToday, let session = snapshot.latestSleepSession {
            if manualOverride != nil {
                sleepDetail = L10n.text("sleep.manual.source")
            } else {
                sleepDetail = AppleHealthUIFormatting.sleepRange(session)
            }
        } else {
            sleepDetail = WellnessLocalStore.lastSleepFactor ?? noData
        }
        let qualityConfiguration = sleepManualOverrideStore.qualityPreferences.configuration(
            dateOfBirthComponents: snapshot.dateOfBirthComponents,
            calendar: .autoupdatingCurrent
        )
        let qualityBreakdown = selectedSleepDay.flatMap {
            SleepQualityCalculator.breakdown(
                for: $0,
                in: snapshot.sleepTrend,
                configuration: qualityConfiguration,
                calendar: .autoupdatingCurrent
            )
        }
        let isRefreshingHistoricalDay = !isToday
            && historicalStressTimelineTask != nil
        let displayedQualityScore = TodaySleepQualityPresentation.score(
            manualOverride: manualOverride,
            breakdown: qualityBreakdown,
            isRefreshingHistoricalDay: isRefreshingHistoricalDay
        )
        sleepCard.configure(
            entry: selectedSleepDay,
            breakdown: isRefreshingHistoricalDay ? nil : qualityBreakdown,
            qualityScore: displayedQualityScore,
            detail: sleepDetail
        )

        let hasSleep = selectedSleepDay?.hours != nil
        let recoveryScore = hasSleep ? try? recoveryDataStore.fetchScore(forDate: selectedDay.description) : nil
        recoveryCard.configure(
            title: L10n.text("wellness.recovery"),
            symbolName: "figure.cooldown",
            currentScore: recoveryScore?.score,
            tone: WellnarioPalette.success
        )

        let stressTimeline = isToday
            ? snapshot.latestPreSleepStressTimeline
            : historicalStressTimeline
        let stressScore = isToday
            ? stressTimeline?.latestScoredPoint?.score ?? snapshot.currentStressDetails?.score
            : stressTimeline?.latestScoredPoint?.score
        stressCard.configure(
            title: L10n.text("wellness.stress"),
            symbolName: "waveform.path.ecg",
            currentScore: stressScore,
            showsCurrentScore: isToday,
            isSyncing: appleHealthService.state == .syncing
                || (!isToday && historicalStressTimelineTask != nil),
            tone: WellnarioPalette.warning,
            timeline: stressTimeline,
            sleepSessions: isToday
                ? [snapshot.latestSleepSession].compactMap { $0 }
                : historicalStressSleepSessions,
            workouts: isToday ? snapshot.workoutsThisWeek : historicalStressWorkouts
        )

        let workouts = isToday ? snapshot.workoutsThisWeek.count : 0
        let steps = isToday ? snapshot.stepsToday : nil
        fitnessCard.configure(
            title: L10n.text("wellness.fitness"),
            symbolName: "figure.run",
            value: "\(workouts)",
            detail: steps.map {
                L10n.text("apple_health.steps_today", AppleHealthUIFormatting.number($0))
            } ?? L10n.text("fitness.workouts_this_week"),
            tone: WellnarioPalette.magenta
        )
        reviewsCard.configure(
            reviews: medicalReviewStore.reviews,
            referenceDate: Date()
        )
    }

    private func makeSummaryGrid() -> UIView {
        let secondRow = equalRow(recoveryCard, supplementsCard)
        let fourthRow = equalRow(fitnessCard, reviewsCard)
        return UIStackView(
            arrangedSubviews: [sleepCard, stressCard, secondRow, fourthRow],
            axis: .vertical,
            spacing: 10
        )
    }

    private func setUpQuickActions() {
        intakeAction.accessibilityIdentifier = "today.quick.intake"
        workoutAction.accessibilityIdentifier = "today.quick.workout"
        labAction.accessibilityIdentifier = "today.quick.lab"
        factorAction.accessibilityIdentifier = "today.quick.sleep_factor"

        intakeAction.addTarget(self, action: #selector(logIntake), for: .touchUpInside)
        workoutAction.addTarget(self, action: #selector(startWorkout), for: .touchUpInside)
        labAction.addTarget(self, action: #selector(importLab), for: .touchUpInside)
        factorAction.addTarget(self, action: #selector(addSleepFactor), for: .touchUpInside)
    }

    private func configureQuickActions() {
        intakeAction.configure(
            title: L10n.text("quick.intake.title"),
            detail: L10n.text("quick.intake.detail"),
            symbolName: "pills.fill",
            tone: WellnarioPalette.cyan
        )
        workoutAction.configure(
            title: L10n.text("quick.workout.title"),
            detail: L10n.text("quick.workout.detail"),
            symbolName: "play.fill",
            tone: WellnarioPalette.magenta
        )
        labAction.configure(
            title: L10n.text("quick.lab.title"),
            detail: L10n.text("quick.lab.detail"),
            symbolName: "doc.badge.plus",
            tone: WellnarioPalette.information
        )
        factorAction.configure(
            title: L10n.text("quick.factor.title"),
            detail: L10n.text("quick.factor.detail"),
            symbolName: "moon.badge.plus.fill",
            tone: WellnarioPalette.violet
        )
    }

    private func makeQuickActionsGrid() -> UIView {
        UIStackView(
            arrangedSubviews: [intakeAction, workoutAction, labAction, factorAction],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )
    }

    private func equalRow(_ first: UIView, _ second: UIView) -> UIStackView {
        let row = UIStackView(
            arrangedSubviews: [first, second],
            axis: .horizontal,
            spacing: 10,
            alignment: .fill,
            distribution: .fillEqually
        )
        first.widthAnchor.constraint(equalTo: second.widthAnchor).isActive = true
        return row
    }

    private func render(_ summary: DashboardSummary) {
        supplementsCard.configure(
            title: L10n.text("wellness.supplements"),
            symbolName: "pills.fill",
            value: "\(summary.consumptionCount)",
            detail: summary.consumptionCount == 1
                ? L10n.text("today.intake.singular")
                : L10n.text("today.intake.plural"),
            tone: summary.consumptionCount == 0 ? WellnarioPalette.textSecondary : WellnarioPalette.cyan
        )
    }

    @objc private func selectDate() {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.maximumDate = Date()
        picker.date = selectedDate

        let controller = UIViewController()
        controller.view.backgroundColor = WellnarioPalette.background
        controller.view.addForAutoLayout(picker)
        picker.pinEdges(to: controller.view.safeAreaLayoutGuide, insets: .all(WellnarioSpacing.small))
        controller.preferredContentSize = CGSize(width: 360, height: 420)
        picker.addAction(UIAction { [weak self, weak controller] action in
            guard let picker = action.sender as? UIDatePicker else { return }
            self?.selectedDate = picker.date
            self?.invalidateHistoricalStressTimeline()
            self?.applyLocalizedCopy()
            self?.reloadContent()
            controller?.dismiss(animated: true)
        }, for: .valueChanged)
        presentSheet(controller)
    }

    @objc private func logIntake() {
        do {
            let instances = try repository.fetchInstances(supplementID: nil, includeArchived: false)
            guard !instances.isEmpty else {
                let alert = UIAlertController(
                    title: L10n.Inventory.noItemsTitle,
                    message: L10n.text("intake.requires_batch"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
                alert.addAction(UIAlertAction(title: L10n.Today.addFirstSupplement, style: .default) { [weak self] _ in
                    self?.onShowSupplements?()
                })
                present(alert, animated: true)
                return
            }
            navigationController?.pushViewController(
                IntakeEditorViewController(repository: repository),
                animated: true
            )
        } catch {
            showError(error)
        }
    }

    @objc private func startWorkout() {
        let controller = WorkoutStarterViewController()
        controller.onStarted = { [weak self] type in
            guard let self else { return }
            _ = FeedbackPresenter.show(
                message: L10n.text("workout.started", type),
                tone: .success,
                in: self.view
            )
        }
        presentSheet(controller)
    }

    @objc private func addSleepFactor() {
        let controller = SleepFactorDailyLogViewController(
            appleHealthService: appleHealthService,
            date: selectedDate,
            repository: repository
        )
        controller.onLogged = { [weak self] factor in
            guard let self else { return }
            self.configureStaticCards()
            _ = FeedbackPresenter.show(
                message: L10n.text("sleep.factor.logged", factor),
                tone: .success,
                in: self.view
            )
        }
        presentSheet(controller)
    }

    @objc private func importLab() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openTodayIntakes() {
        navigationController?.pushViewController(
            DiaryViewController(
                repository: repository,
                dayFilter: LocalDay(containing: Date(), in: .current)
            ),
            animated: true
        )
    }
    @objc private func openSleep() { onShowSleep?() }
    @objc private func openHealth() { onShowHealth?() }
    
    @objc private func openRecovery() {
        let selectedDay = LocalDay(containing: selectedDate, in: .current)
        let snapshot = sleepManualOverrideStore.applying(to: appleHealthService.snapshot)
        let isToday = Calendar.autoupdatingCurrent.isDateInToday(selectedDate)
        let selectedSleepDay = snapshot.sleepTrend.last {
            LocalDay(containing: $0.date, in: .current) == selectedDay
        }
        let hasSleep = selectedSleepDay?.hours != nil
        let recoveryScore = hasSleep ? try? recoveryDataStore.fetchScore(forDate: selectedDay.description) : nil
        
        let detailVC = RecoveryDetailViewController(score: recoveryScore?.score)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    @objc private func openFitness() { onShowFitness?() }
    @objc private func openStressDetails() {
        let snapshot = sleepManualOverrideStore.applying(to: appleHealthService.snapshot)
        let isToday = Calendar.autoupdatingCurrent.isDateInToday(selectedDate)
        if isToday {
            navigationController?.pushViewController(
                StressDetailsViewController(
                    details: snapshot.currentStressDetails,
                    fallbackScore: nil,
                    fallbackDate: nil,
                    timing: .current,
                    timeline: snapshot.latestPreSleepStressTimeline,
                    sleepSessions: [snapshot.latestSleepSession].compactMap { $0 },
                    workouts: snapshot.workoutsThisWeek
                ),
                animated: true
            )
        } else {
            let latestPreSleep = snapshot.automaticSleepFactors?.last
            navigationController?.pushViewController(
                StressDetailsViewController(
                    details: latestPreSleep?.preSleepStressDetails,
                    fallbackScore: latestPreSleep?.preSleepStressScore,
                    fallbackDate: latestPreSleep?.date,
                    timing: .beforeSleep,
                    timeline: historicalStressTimeline,
                    sleepSessions: historicalStressSleepSessions,
                    workouts: historicalStressWorkouts
                ),
                animated: true
            )
        }
    }
    @objc private func appleHealthDidChange() {
        // A historical selection performs its own sync before requesting the
        // day. Do not cancel that in-flight request when its sync emits the
        // normal Apple Health state notifications.
        if historicalStressTimelineTask == nil {
            invalidateHistoricalStressTimeline()
        }
        reloadContent()
    }
    @objc private func sleepManualOverridesDidChange() { reloadContent() }
    @objc private func sleepQualityPreferencesDidChange() { reloadContent() }
}

enum TodaySleepQualityPresentation {
    static func score(
        manualOverride: SleepManualOverride?,
        breakdown: SleepQualityBreakdown?,
        isRefreshingHistoricalDay: Bool
    ) -> Double? {
        if let manualQuality = manualOverride?.qualityScore {
            return manualQuality
        }
        guard !isRefreshingHistoricalDay else { return nil }
        return breakdown?.totalScore
    }
}

@MainActor
final class TodaySleepSummaryCard: PremiumCardView {
    static let metricRingDiameter: CGFloat = 68
    static let metricsHeight: CGFloat = 126

    private let symbolContainer = UIView()
    private let symbolView = UIImageView(image: UIImage(systemName: "moon.stars.fill"))
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let qualityMetric = TodaySleepMetricView()
    private let durationMetric = TodaySleepFactorMetricView()
    private let regularityMetric = TodaySleepFactorMetricView()
    private let interruptionsMetric = TodaySleepFactorMetricView()
    private let heartRateDropMetric = TodaySleepFactorMetricView()
    private let sleepStressMetric = TodaySleepFactorMetricView()
    private let remDeepSleepMetric = TodaySleepFactorMetricView()
    private let sleepLatencyMetric = TodaySleepFactorMetricView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(
        entry: AppleHealthSleepDay?,
        breakdown: SleepQualityBreakdown?,
        qualityScore: Double?,
        detail: String
    ) {
        titleLabel.text = L10n.text("wellness.sleep")
        detailLabel.text = detail

        qualityMetric.configure(
            title: L10n.text("today.sleep.metric.quality"),
            value: qualityScore,
            valueText: qualityScore.map { AppleHealthUIFormatting.number($0) } ?? "—",
            gradient: (WellnarioPalette.violet, WellnarioPalette.fuchsia)
        )

        let durationText = entry?.hours.map {
            AppleHealthUIFormatting.compactDuration($0 * 3_600)
        } ?? "—"
        durationMetric.configure(
            title: L10n.text("sleep.duration"),
            valueText: durationText,
            score: breakdown?.durationScore,
            symbolName: "bed.double.fill"
        )

        let regularityText: String
        if let breakdown {
            regularityText = "\(breakdown.compliantDays)/\(SleepQualityCalculator.regularityWindowDays)"
        } else {
            regularityText = "—"
        }
        regularityMetric.configure(
            title: L10n.text("settings.advanced.sleep.quality.weight.regularity"),
            valueText: regularityText,
            score: breakdown?.regularityScore,
            symbolName: "calendar"
        )

        let interruptionsText: String
        if let breakdown, entry?.awakeHours != nil {
            interruptionsText = percentageText(breakdown.awakePercentage)
        } else {
            interruptionsText = "—"
        }
        interruptionsMetric.configure(
            title: L10n.text("settings.advanced.sleep.quality.weight.interruptions"),
            valueText: interruptionsText,
            score: entry?.awakeHours == nil ? nil : breakdown?.interruptionScore,
            symbolName: "moon.zzz.fill"
        )

        let heartRateDropText = breakdown?.heartRateDropPercentage.map {
            percentageText($0)
        } ?? "—"
        heartRateDropMetric.configure(
            title: L10n.text("today.sleep.metric.heart_rate_drop"),
            valueText: heartRateDropText,
            score: breakdown?.heartRateDropScore,
            symbolName: "heart.fill"
        )

        let sleepStressText = breakdown?.averageSleepStressScore.map {
            percentageText($0)
        } ?? "—"
        sleepStressMetric.configure(
            title: L10n.text("today.sleep.metric.sleep_stress"),
            valueText: sleepStressText,
            score: breakdown?.sleepStressScore,
            symbolName: "waveform.path.ecg"
        )

        let remDeepSleepText = breakdown?.remDeepSleepPercentage.map {
            percentageText($0)
        } ?? "—"
        remDeepSleepMetric.configure(
            title: L10n.text("today.sleep.metric.rem_deep_sleep"),
            valueText: remDeepSleepText,
            score: breakdown?.remDeepSleepScore,
            symbolName: "brain.head.profile"
        )

        let sleepLatencyText = breakdown?.sleepLatencyMinutes.map {
            AppleHealthUIFormatting.compactDuration($0 * 60)
        } ?? "—"
        sleepLatencyMetric.configure(
            title: L10n.text("today.sleep.metric.sleep_latency"),
            valueText: sleepLatencyText,
            score: breakdown?.sleepLatencyScore,
            symbolName: "hourglass"
        )

        accessibilityLabel = titleLabel.text
        accessibilityValue = [
            metricAccessibilityValue(
                title: qualityMetric.metricTitle,
                value: qualityMetric.metricValue
            ),
            metricAccessibilityValue(
                title: durationMetric.metricTitle,
                value: durationMetric.metricValue
            ),
            metricAccessibilityValue(
                title: regularityMetric.metricTitle,
                value: regularityMetric.metricValue
            ),
            metricAccessibilityValue(
                title: interruptionsMetric.metricTitle,
                value: interruptionsMetric.metricValue
            ),
            metricAccessibilityValue(
                title: heartRateDropMetric.metricTitle,
                value: heartRateDropMetric.metricValue
            ),
            metricAccessibilityValue(
                title: sleepStressMetric.metricTitle,
                value: sleepStressMetric.metricValue
            ),
            metricAccessibilityValue(
                title: remDeepSleepMetric.metricTitle,
                value: remDeepSleepMetric.metricValue
            ),
            metricAccessibilityValue(
                title: sleepLatencyMetric.metricTitle,
                value: sleepLatencyMetric.metricValue
            ),
            detail
        ].joined(separator: ". ")
    }

    private func metricAccessibilityValue(title: String, value: String) -> String {
        [title, value].joined(separator: ": ")
    }

    private func percentageText(_ percentage: Double) -> String {
        "\(AppleHealthUIFormatting.number(percentage.rounded()))%"
    }

    private func setUp() {
        symbolContainer.applyContinuousCorners(11)
        symbolContainer.backgroundColor = WellnarioPalette.violet.withAlphaComponent(0.14)
        NSLayoutConstraint.activate([
            symbolContainer.widthAnchor.constraint(equalToConstant: 34),
            symbolContainer.heightAnchor.constraint(equalTo: symbolContainer.widthAnchor)
        ])

        symbolView.tintColor = WellnarioPalette.violet
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 15,
            weight: .semibold
        )
        symbolContainer.addForAutoLayout(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor)
        ])

        titleLabel.applyWellnarioStyle(.summaryTitle, color: WellnarioPalette.textPrimary)
        detailLabel.applyWellnarioStyle(.summaryDetail, color: WellnarioPalette.textSecondary)
        detailLabel.textAlignment = .right
        detailLabel.numberOfLines = 1
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        qualityMetric.accessibilityIdentifier = "today.sleep.metric.quality"
        durationMetric.accessibilityIdentifier = "today.sleep.metric.duration"
        regularityMetric.accessibilityIdentifier = "today.sleep.metric.regularity"
        interruptionsMetric.accessibilityIdentifier = "today.sleep.metric.interruptions"
        heartRateDropMetric.accessibilityIdentifier = "today.sleep.metric.heart_rate_drop"
        sleepStressMetric.accessibilityIdentifier = "today.sleep.metric.sleep_stress"
        remDeepSleepMetric.accessibilityIdentifier = "today.sleep.metric.rem_deep_sleep"
        sleepLatencyMetric.accessibilityIdentifier = "today.sleep.metric.sleep_latency"

        let header = UIStackView(
            arrangedSubviews: [symbolContainer, titleLabel, UIView(), detailLabel],
            axis: .horizontal,
            spacing: 7,
            alignment: .center
        )
        let factorMetrics = UIStackView(
            arrangedSubviews: [
                durationMetric,
                regularityMetric,
                interruptionsMetric,
                heartRateDropMetric,
                sleepStressMetric,
                remDeepSleepMetric,
                sleepLatencyMetric
            ],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall,
            distribution: .fillEqually
        )
        let metrics = UIStackView(
            arrangedSubviews: [qualityMetric, factorMetrics],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        let content = UIStackView(
            arrangedSubviews: [header, metrics],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        contentView.addForAutoLayout(content)
        content.pinEdges(to: contentView, insets: .all(WellnarioSpacing.xSmall))
        metrics.heightAnchor.constraint(equalToConstant: Self.metricsHeight).isActive = true
        qualityMetric.widthAnchor.constraint(equalToConstant: Self.metricRingDiameter).isActive = true
        factorMetrics.heightAnchor.constraint(equalTo: metrics.heightAnchor).isActive = true
        isPressable = true
    }
}

@MainActor
private final class TodaySleepMetricView: UIView {
    fileprivate private(set) var metricTitle = ""
    fileprivate private(set) var metricValue = "—"

    private let ring = TodaySleepMetricRingView()
    private let titleLabel = ContinuousMarqueeLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(
        title: String,
        value: Double?,
        valueText: String,
        gradient: (UIColor, UIColor),
        valueTextScale: CGFloat = 1
    ) {
        metricTitle = title
        metricValue = valueText
        titleLabel.text = title
        ring.configure(
            value: value,
            valueText: valueText,
            gradient: gradient,
            valueTextScale: valueTextScale
        )
        accessibilityElementsHidden = true
    }

    private func setUp() {
        titleLabel.applyTextStyle(.summaryDetail, color: WellnarioPalette.textSecondary)
        titleLabel.textAlignment = .center
        titleLabel.isMarqueeEnabled = true

        let stack = UIStackView(
            arrangedSubviews: [ring, titleLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall,
            alignment: .center
        )
        addForAutoLayout(stack)
        stack.pinEdges(to: self)
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(
                equalToConstant: TodaySleepSummaryCard.metricRingDiameter
            ),
            ring.heightAnchor.constraint(equalTo: ring.widthAnchor),
            titleLabel.widthAnchor.constraint(equalTo: ring.widthAnchor)
        ])
    }
}

@MainActor
private final class TodaySleepFactorMetricView: UIView {
    fileprivate private(set) var metricTitle = ""
    fileprivate private(set) var metricValue = "—"

    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let scoreBar = ScoreSegmentBarView(
        segmentCount: 10,
        spacing: 1.5,
        cornerRadius: 1.5
    )
    private let valueLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(
        title: String,
        valueText: String,
        score: Double?,
        symbolName: String
    ) {
        metricTitle = title
        metricValue = valueText
        titleLabel.text = title
        valueLabel.text = valueText
        symbolView.image = UIImage(systemName: symbolName)
        scoreBar.configure(score: score)
        accessibilityElementsHidden = true
    }

    private func setUp() {
        isAccessibilityElement = false

        symbolView.tintColor = WellnarioPalette.violet
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 11,
            weight: .semibold
        )
        symbolView.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: 15),
            symbolView.heightAnchor.constraint(equalTo: symbolView.widthAnchor)
        ])

        titleLabel.applyWellnarioStyle(.summaryDetail, color: WellnarioPalette.textSecondary)
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(equalToConstant: 82)
        ])

        NSLayoutConstraint.activate([
            scoreBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 42),
            scoreBar.heightAnchor.constraint(equalToConstant: 7)
        ])

        valueLabel.applyWellnarioStyle(.tab, color: WellnarioPalette.textPrimary)
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            valueLabel.widthAnchor.constraint(equalToConstant: 36)
        ])

        let row = UIStackView(
            arrangedSubviews: [symbolView, titleLabel, scoreBar, valueLabel],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxxSmall,
            alignment: .center
        )
        addForAutoLayout(row)
        row.pinEdges(to: self)
    }
}

@MainActor
private final class TodaySleepMetricRingView: UIView {
    private let trackLayer = CAShapeLayer()
    private let gradientLayer = CAGradientLayer()
    private let progressMask = CAShapeLayer()
    private let valueLabel = UILabel()
    private var progress: CGFloat = 0
    private var gradient: (UIColor, UIColor) = (WellnarioPalette.violet, WellnarioPalette.fuchsia)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let lineWidth: CGFloat = 5.5
        let radius = max(min(bounds.width, bounds.height) / 2 - lineWidth / 2 - 2, 0)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: .pi * 1.5,
            clockwise: true
        )

        trackLayer.frame = bounds
        trackLayer.path = path.cgPath
        progressMask.frame = bounds
        progressMask.path = path.cgPath
        progressMask.strokeEnd = progress
        gradientLayer.frame = bounds
    }

    func configure(
        value: Double?,
        valueText: String,
        gradient: (UIColor, UIColor),
        valueTextScale: CGFloat
    ) {
        progress = CGFloat(min(max(value ?? 0, 0), 100) / 100)
        self.gradient = gradient
        valueLabel.text = valueText
        valueLabel.transform = CGAffineTransform(
            scaleX: min(max(valueTextScale, 0.5), 1),
            y: min(max(valueTextScale, 0.5), 1)
        )
        updateColors()
        setNeedsLayout()
    }

    private func setUp() {
        isAccessibilityElement = false
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.lineCap = .round
        trackLayer.lineWidth = 5.5
        layer.addSublayer(trackLayer)

        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.mask = progressMask
        layer.addSublayer(gradientLayer)

        progressMask.fillColor = UIColor.clear.cgColor
        progressMask.strokeColor = UIColor.black.cgColor
        progressMask.lineCap = .round
        progressMask.lineWidth = 5.5

        valueLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textPrimary)
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.60
        valueLabel.numberOfLines = 1
        addForAutoLayout(valueLabel)
        NSLayoutConstraint.activate([
            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5)
        ])
        updateColors()

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (self: TodaySleepMetricRingView, _: UITraitCollection) in
            self.updateColors()
        }
    }

    private func updateColors() {
        trackLayer.strokeColor = WellnarioPalette.hairline
            .resolvedColor(with: traitCollection)
            .withAlphaComponent(0.7)
            .cgColor
        gradientLayer.colors = [gradient.0, gradient.1].map {
            $0.resolvedColor(with: traitCollection).cgColor
        }
    }
}

@MainActor
final class TodayMedicalReviewsSummaryCard: PremiumCardView {
    let symbolContainer = UIView()
    private let symbolView = UIImageView(image: UIImage(systemName: "calendar.badge.clock"))
    let titleLabel = UILabel()
    private let reviewsStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(
        reviews: [MedicalReview],
        referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        titleLabel.text = L10n.text("today.reviews.title")
        reviewsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let entries = MedicalReviewTimeline.entries(
            from: reviews,
            referenceDate: referenceDate,
            calendar: calendar
        )

        if entries.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.applyWellnarioStyle(.summaryDetail, color: WellnarioPalette.textTertiary)
            emptyLabel.text = L10n.text("today.reviews.empty")
            emptyLabel.numberOfLines = 2
            reviewsStack.addArrangedSubview(emptyLabel)
            accessibilityValue = emptyLabel.text
        } else {
            for (index, entry) in entries.enumerated() {
                reviewsStack.addArrangedSubview(
                    TodayMedicalReviewRow(
                        entry: entry,
                        index: index,
                        referenceDate: referenceDate,
                        calendar: calendar
                    )
                )
            }
            accessibilityValue = entries.map {
                [
                    $0.review.title,
                    MedicalReviewFormatting.dueStatus(
                        $0.review,
                        referenceDate: referenceDate,
                        calendar: calendar
                    )
                ].joined(separator: ", ")
            }.joined(separator: ". ")
        }

        accessibilityLabel = L10n.text("today.reviews.title")
    }

    private func setUp() {
        symbolContainer.applyContinuousCorners(11)
        symbolContainer.backgroundColor = WellnarioPalette.fuchsia.withAlphaComponent(0.14)
        NSLayoutConstraint.activate([
            symbolContainer.widthAnchor.constraint(equalToConstant: 34),
            symbolContainer.heightAnchor.constraint(equalTo: symbolContainer.widthAnchor)
        ])

        symbolView.tintColor = WellnarioPalette.fuchsia
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 15,
            weight: .semibold
        )
        symbolContainer.addForAutoLayout(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor)
        ])

        titleLabel.applyWellnarioStyle(.summaryTitle, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = UIStackView(
            arrangedSubviews: [symbolContainer, titleLabel, UIView()],
            axis: .horizontal,
            spacing: 7,
            alignment: .center
        )
        header.setContentHuggingPriority(.required, for: .vertical)
        header.setContentCompressionResistancePriority(.required, for: .vertical)
        reviewsStack.axis = .vertical
        reviewsStack.spacing = 1
        contentView.addForAutoLayout(header)
        contentView.addForAutoLayout(reviewsStack)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: WellnarioSpacing.xSmall
            ),
            header.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: WellnarioSpacing.xSmall
            ),
            header.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -WellnarioSpacing.xSmall
            ),
            reviewsStack.topAnchor.constraint(
                equalTo: header.bottomAnchor,
                constant: WellnarioSpacing.xxxSmall
            ),
            reviewsStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            reviewsStack.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            reviewsStack.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor,
                constant: -WellnarioSpacing.xSmall
            )
        ])
        heightAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true
        isPressable = true
    }
}

@MainActor
private final class StressScoreSegmentBarView: UIView {
    private static let segmentCount = 12
    private let segments = (0..<StressScoreSegmentBarView.segmentCount).map { _ in UIView() }
    private let stack = UIStackView()
    private var activeSegmentCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(score: Double?) {
        guard let score else {
            activeSegmentCount = 0
            updateColors()
            return
        }
        let normalized = min(max(score / 100, 0), 1)
        activeSegmentCount = Int(
            (normalized * Double(Self.segmentCount)).rounded(.up)
        )
        updateColors()
    }

    private func setUp() {
        isAccessibilityElement = false
        stack.axis = .horizontal
        stack.spacing = 2
        stack.distribution = .fillEqually
        segments.forEach { segment in
            segment.applyContinuousCorners(2)
            stack.addArrangedSubview(segment)
        }
        addForAutoLayout(stack)
        stack.pinEdges(to: self)
        updateColors()

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (self: StressScoreSegmentBarView, _: UITraitCollection) in
            self.updateColors()
        }
    }

    private func updateColors() {
        for (index, segment) in segments.enumerated() {
            if index < activeSegmentCount {
                segment.backgroundColor = color(for: index)
            } else {
                segment.backgroundColor = WellnarioPalette.hairline
                    .resolvedColor(with: traitCollection)
                    .withAlphaComponent(0.55)
            }
        }
    }

    private func color(for index: Int) -> UIColor {
        let progress = CGFloat(index) / CGFloat(max(Self.segmentCount - 1, 1))
        if progress <= 0.5 {
            return interpolate(
                WellnarioPalette.cyan,
                WellnarioPalette.warning,
                progress: progress * 2
            )
        }
        return interpolate(
            WellnarioPalette.warning,
            WellnarioPalette.danger,
            progress: (progress - 0.5) * 2
        )
    }

    private func interpolate(_ start: UIColor, _ end: UIColor, progress: CGFloat) -> UIColor {
        let resolvedStart = start.resolvedColor(with: traitCollection)
        let resolvedEnd = end.resolvedColor(with: traitCollection)
        var startRed: CGFloat = 0
        var startGreen: CGFloat = 0
        var startBlue: CGFloat = 0
        var startAlpha: CGFloat = 0
        var endRed: CGFloat = 0
        var endGreen: CGFloat = 0
        var endBlue: CGFloat = 0
        var endAlpha: CGFloat = 0
        guard resolvedStart.getRed(
            &startRed,
            green: &startGreen,
            blue: &startBlue,
            alpha: &startAlpha
        ), resolvedEnd.getRed(
            &endRed,
            green: &endGreen,
            blue: &endBlue,
            alpha: &endAlpha
        ) else {
            return progress < 0.5 ? start : end
        }
        let t = min(max(progress, 0), 1)
        return UIColor(
            red: startRed + (endRed - startRed) * t,
            green: startGreen + (endGreen - startGreen) * t,
            blue: startBlue + (endBlue - startBlue) * t,
            alpha: startAlpha + (endAlpha - startAlpha) * t
        )
    }
}

@MainActor
final class TodayStressSummaryCard: PremiumCardView {
    private let symbolContainer = UIView()
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let currentScoreBar = StressScoreSegmentBarView()
    private let currentScoreValueLabel = UILabel()
    private let currentScoreRow = UIStackView()
    private let currentLevelLabel = UILabel()
    private let currentScoreStack = UIStackView()
    private let chart = WellnessTrendChartView()
    private var isSyncing = false
    private var timeline: AppleHealthStressTimeline?
    private var sleepSessions: [AppleHealthSleepSession] = []
    private var workouts: [AppleHealthWorkout] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(
        title: String,
        symbolName: String,
        currentScore: Double?,
        showsCurrentScore: Bool,
        isSyncing: Bool,
        tone: UIColor,
        timeline: AppleHealthStressTimeline?,
        sleepSessions: [AppleHealthSleepSession],
        workouts: [AppleHealthWorkout]
    ) {
        titleLabel.text = title
        symbolView.image = UIImage(systemName: symbolName)
        symbolView.tintColor = tone
        symbolContainer.backgroundColor = tone.withAlphaComponent(0.14)
        currentScoreStack.isHidden = !showsCurrentScore
        self.isSyncing = isSyncing
        currentScoreBar.configure(score: currentScore)
        currentScoreValueLabel.text = currentScore.map {
            AppleHealthUIFormatting.number($0)
        } ?? "—"
        let levelText = currentScore.map {
            L10n.text(AppleHealthStressScoreCalculator.levelLocalizationKey(for: $0))
        }
        currentLevelLabel.text = levelText
        currentLevelLabel.isHidden = levelText == nil
        self.timeline = timeline
        self.sleepSessions = sleepSessions
        self.workouts = workouts
        updateTimelineGraph()
        accessibilityLabel = title
        let scoreText = currentScore.map {
            AppleHealthUIFormatting.number($0)
        }
        accessibilityValue = [showsCurrentScore ? scoreText : nil, showsCurrentScore ? levelText : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func setUp() {
        symbolContainer.applyContinuousCorners(11)
        NSLayoutConstraint.activate([
            symbolContainer.widthAnchor.constraint(equalToConstant: 34),
            symbolContainer.heightAnchor.constraint(equalTo: symbolContainer.widthAnchor)
        ])

        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 15,
            weight: .semibold
        )
        symbolView.contentMode = .scaleAspectFit
        symbolContainer.addForAutoLayout(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor)
        ])

        titleLabel.applyWellnarioStyle(.summaryTitle, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 2
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            currentScoreBar.widthAnchor.constraint(equalToConstant: 82),
            currentScoreBar.heightAnchor.constraint(equalToConstant: 17)
        ])

        currentScoreValueLabel.applyWellnarioStyle(.bodyBold, color: WellnarioPalette.textPrimary)
        currentScoreValueLabel.textAlignment = .right
        currentScoreValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        currentScoreValueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        currentLevelLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        currentLevelLabel.textAlignment = .center
        currentLevelLabel.numberOfLines = 1
        currentLevelLabel.adjustsFontSizeToFitWidth = true
        currentLevelLabel.minimumScaleFactor = 0.75

        currentScoreStack.axis = .vertical
        currentScoreStack.spacing = WellnarioSpacing.xxxSmall
        currentScoreStack.alignment = .center
        currentScoreRow.axis = .horizontal
        currentScoreRow.spacing = WellnarioSpacing.xxxSmall
        currentScoreRow.alignment = .center
        currentScoreRow.addArrangedSubview(currentScoreBar)
        currentScoreRow.addArrangedSubview(currentScoreValueLabel)
        currentScoreStack.addArrangedSubview(currentScoreRow)
        currentScoreStack.addArrangedSubview(currentLevelLabel)

        chart.fixedBounds = WellnessTrendBounds(lower: 0, upper: 100)
        chart.lineColor = WellnarioPalette.warning
        chart.referenceLine = .average
        chart.averageTitle = ""
        chart.averageColor = WellnarioPalette.cyan
        chart.showsAverageValueOnYAxis = true
        chart.smoothingWindow = 1
        chart.emptyText = isSyncing
            ? L10n.text("apple_health.syncing")
            : L10n.text("apple_health.stress.timeline.empty")
        chart.valueFormatter = {
            AppleHealthUIFormatting.number($0)
        }
        chart.accessibilityIdentifier = "today.summary.stress.timeline"
        chart.accessibilityLabel = L10n.text("apple_health.stress.timeline.title")
        chart.isUserInteractionEnabled = false

        let titleLeading = UIStackView(
            arrangedSubviews: [symbolContainer, titleLabel],
            axis: .horizontal,
            spacing: 7,
            alignment: .center
        )
        let heading = UIStackView(
            arrangedSubviews: [titleLeading, UIView(), currentScoreStack],
            axis: .horizontal,
            spacing: 7,
            alignment: .center
        )
        let stack = UIStackView(
            arrangedSubviews: [heading, chart],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        contentView.addForAutoLayout(stack)
        stack.pinEdges(to: contentView, insets: .all(WellnarioSpacing.xSmall))
        chart.heightAnchor.constraint(equalToConstant: 126).isActive = true
        isPressable = true

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (self: TodayStressSummaryCard, _: UITraitCollection) in
            self.updateTimelineGraph()
        }
    }

    private func updateTimelineGraph() {
        let points = timeline?.points ?? []
        chart.values = points.map(\.score)
        chart.lineColors = points.map { point in
            point.score.map(stressColor(for:))
        }
        chart.xPositions = normalizedPositions(for: points)
        chart.intervalHighlights = timelineHighlights(for: timeline)
        chart.selectionLabels = points.map { WellnarioFormatters.time($0.date) }
        chart.labels = []
        chart.xAxisLabels = timelineAxisLabels(for: timeline)
        chart.emptyText = isSyncing
            ? L10n.text("apple_health.syncing")
            : L10n.text("apple_health.stress.timeline.empty")
        chart.accessibilityValue = points.compactMap(\.score).last.map {
            L10n.text("apple_health.stress.score.value", Int($0.rounded()))
        } ?? chart.emptyText
    }

    private func timelineAxisLabels(
        for timeline: AppleHealthStressTimeline?
    ) -> [WellnessTrendXAxisLabel] {
        stressTimelineAxisLabels(for: timeline)
    }

    private func normalizedPositions(for points: [AppleHealthStressTimelinePoint]) -> [CGFloat] {
        stressNormalizedPositions(for: points)
    }

    private func timelineHighlights(
        for timeline: AppleHealthStressTimeline?
    ) -> [WellnessTrendIntervalHighlight] {
        stressTimelineHighlights(for: timeline, sleepSessions: sleepSessions, workouts: workouts)
    }

    private func stressColor(for score: Double) -> UIColor {
        calculateStressColor(for: score, traitCollection: traitCollection)
    }
}

@MainActor
fileprivate func stressTimelineAxisLabels(
    for timeline: AppleHealthStressTimeline?
) -> [WellnessTrendXAxisLabel] {
    guard let start = timeline?.points.first?.date,
          let end = timeline?.points.last?.date,
          end > start else {
        return []
    }
    let middle = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
    return [
        WellnessTrendXAxisLabel(position: 0, text: WellnarioFormatters.time(start)),
        WellnessTrendXAxisLabel(position: 0.5, text: WellnarioFormatters.time(middle)),
        WellnessTrendXAxisLabel(position: 1, text: WellnarioFormatters.time(end))
    ]
}

@MainActor
fileprivate func stressNormalizedPositions(for points: [AppleHealthStressTimelinePoint]) -> [CGFloat] {
    guard let start = points.first?.date,
          let end = points.last?.date,
          end > start else {
        return points.indices.map { _ in 0 }
    }
    let duration = end.timeIntervalSince(start)
    return points.map {
        CGFloat(min(max($0.date.timeIntervalSince(start) / duration, 0), 1))
    }
}

@MainActor
func stressTimelineHighlights(
    for timeline: AppleHealthStressTimeline?,
    sleepSessions: [AppleHealthSleepSession],
    workouts: [AppleHealthWorkout]
) -> [WellnessTrendIntervalHighlight] {
    guard let timeline,
          let start = timeline.points.first?.date,
          let end = timeline.points.last?.date,
          end > start else {
        return []
    }

    func position(_ date: Date) -> CGFloat {
        CGFloat(min(max(date.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1))
    }
    func highlight(
        start intervalStart: Date,
        end intervalEnd: Date,
        color: UIColor,
        symbolName: String
    ) -> WellnessTrendIntervalHighlight? {
        guard intervalEnd >= start, intervalStart <= end else { return nil }
        return WellnessTrendIntervalHighlight(
            startPosition: position(max(intervalStart, start)),
            endPosition: position(min(intervalEnd, end)),
            color: color,
            symbolName: symbolName
        )
    }

    var highlights: [WellnessTrendIntervalHighlight] = []
    highlights.append(contentsOf: sleepSessions.compactMap {
        highlight(
            start: $0.startDate,
            end: $0.endDate,
            color: WellnarioPalette.violet,
            symbolName: "bed.double.fill"
        )
    })
    highlights.append(contentsOf: workouts.compactMap {
        highlight(
            start: $0.startDate,
            end: $0.endDate,
            color: WellnarioPalette.fuchsia,
            symbolName: $0.kind == .strength
                ? "figure.strengthtraining.traditional"
                : "figure.run"
        )
    })
    return highlights
}

@MainActor
fileprivate func calculateStressColor(for score: Double, traitCollection: UITraitCollection? = nil) -> UIColor {
    let progress = min(max(score / 100, 0), 1)
    let tc = traitCollection ?? UITraitCollection.current
    let cyan = WellnarioPalette.cyan.resolvedColor(with: tc)
    let red = WellnarioPalette.danger.resolvedColor(with: tc)
    var cyanRed: CGFloat = 0
    var cyanGreen: CGFloat = 0
    var cyanBlue: CGFloat = 0
    var cyanAlpha: CGFloat = 0
    var redRed: CGFloat = 0
    var redGreen: CGFloat = 0
    var redBlue: CGFloat = 0
    var redAlpha: CGFloat = 0
    guard cyan.getRed(&cyanRed, green: &cyanGreen, blue: &cyanBlue, alpha: &cyanAlpha),
          red.getRed(&redRed, green: &redGreen, blue: &redBlue, alpha: &redAlpha) else {
        return score < 50 ? WellnarioPalette.cyan : WellnarioPalette.danger
    }
    return UIColor(
        red: cyanRed + (redRed - cyanRed) * progress,
        green: cyanGreen + (redGreen - cyanGreen) * progress,
        blue: cyanBlue + (redBlue - cyanBlue) * progress,
        alpha: cyanAlpha + (redAlpha - cyanAlpha) * progress
    )
}

@MainActor
final class StressDetailsViewController: WellnessScrollViewController {
    enum Timing {
        case current
        case beforeSleep
    }

    private let details: AppleHealthStressCalculationDetails?
    private let fallbackScore: Double?
    private let fallbackDate: Date?
    private let timing: Timing
    private let timeline: AppleHealthStressTimeline?
    private let sleepSessions: [AppleHealthSleepSession]
    private let workouts: [AppleHealthWorkout]

    init(
        details: AppleHealthStressCalculationDetails?,
        fallbackScore: Double? = nil,
        fallbackDate: Date? = nil,
        timing: Timing = .current,
        timeline: AppleHealthStressTimeline? = nil,
        sleepSessions: [AppleHealthSleepSession] = [],
        workouts: [AppleHealthWorkout] = []
    ) {
        self.details = details
        self.fallbackScore = fallbackScore
        self.fallbackDate = fallbackDate
        self.timing = timing
        self.timeline = timeline
        self.sleepSessions = sleepSessions
        self.workouts = workouts
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("apple_health.stress.details.title")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal
        view.accessibilityIdentifier = "today.stress.details"
        buildContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
    }

    private func buildContent() {
        contentStack.addArrangedSubview(makeSummaryCard())
        if let chartCard = makeChartCard() {
            contentStack.addArrangedSubview(chartCard)
        }
        guard let details else { return }
        contentStack.addArrangedSubview(makeMetricCard(details))
        contentStack.addArrangedSubview(makeMethodCard(details))
    }

    private func makeChartCard() -> PremiumCardView? {
        guard let timeline, !timeline.points.isEmpty else { return nil }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = WellnarioSpacing.small

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text("apple_health.stress.timeline.title")

        let chart = WellnessTrendChartView()
        chart.fixedBounds = WellnessTrendBounds(lower: 0, upper: 100)
        chart.lineColor = WellnarioPalette.warning
        chart.referenceLine = .average
        chart.averageTitle = ""
        chart.averageColor = WellnarioPalette.cyan
        chart.showsAverageValueOnYAxis = true
        chart.smoothingWindow = 1
        chart.isUserInteractionEnabled = true
        chart.emptyText = L10n.text("apple_health.stress.timeline.empty")
        chart.valueFormatter = { AppleHealthUIFormatting.number($0) }

        let points = timeline.points
        chart.values = points.map(\.score)
        chart.lineColors = points.map { point in
            point.score.map { calculateStressColor(for: $0, traitCollection: traitCollection) }
        }
        chart.xPositions = stressNormalizedPositions(for: points)
        chart.intervalHighlights = stressTimelineHighlights(
            for: timeline,
            sleepSessions: sleepSessions,
            workouts: workouts
        )
        chart.selectionLabels = points.map { WellnarioFormatters.time($0.date) }
        chart.labels = []
        chart.xAxisLabels = stressTimelineAxisLabels(for: timeline)

        chart.heightAnchor.constraint(equalToConstant: 180).isActive = true

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(chart)

        return makeCard(containing: stack, identifier: "today.stress.details.chart")
    }

    private func makeSummaryCard() -> PremiumCardView {
        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text(
            timing == .current
                ? "apple_health.stress.details.current.title"
                : "apple_health.stress.details.before_sleep.title"
        )

        let scoreLabel = UILabel()
        scoreLabel.applyWellnarioStyle(.metric, color: WellnarioPalette.warning)
        scoreLabel.textAlignment = .center
        let latestVisiblePoint = timing == .current
            ? timeline?.latestScoredPoint
            : nil
        let score = latestVisiblePoint?.score ?? details?.score ?? fallbackScore
        scoreLabel.text = score.map {
            L10n.text("apple_health.stress.score.value", Int($0.rounded()))
        } ?? "—"
        scoreLabel.accessibilityIdentifier = "today.stress.details.score"

        let levelLabel = UILabel()
        levelLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        levelLabel.textAlignment = .center
        levelLabel.numberOfLines = 0
        if let score {
            if details == nil {
                levelLabel.text = L10n.text("apple_health.stress.details.resync_required")
            } else {
                levelLabel.text = L10n.text(
                    "apple_health.stress.details.level",
                    L10n.text(AppleHealthStressScoreCalculator.levelLocalizationKey(for: score)),
                    WellnarioFormatters.numericDateAndTime(
                        latestVisiblePoint?.date ?? details?.date ?? fallbackDate ?? Date()
                    )
                )
            }
        } else {
            levelLabel.text = L10n.text("apple_health.stress.details.no_score")
        }

        let stack = UIStackView(
            arrangedSubviews: [titleLabel, scoreLabel, levelLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        return makeCard(containing: stack, identifier: "today.stress.details.summary")
    }

    private func makeMetricCard(
        _ details: AppleHealthStressCalculationDetails
    ) -> PremiumCardView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = WellnarioSpacing.small
        stack.addArrangedSubview(cardTitle(L10n.text("apple_health.stress.details.inputs.title")))
        stack.addArrangedSubview(metricRow(
            title: L10n.text("apple_health.stress.details.metric.hrv"),
            metric: details.heartRateVariability,
            unit: "ms",
            activityAdjusted: details.hadActivityInPreviousTwoHours
        ))
        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(metricRow(
            title: L10n.text(
                details.usesInstantaneousHeartRate == true
                    ? "apple_health.stress.details.metric.heart_rate"
                    : "apple_health.stress.details.metric.resting_hr"
            ),
            metric: details.restingHeartRate,
            unit: L10n.text("apple_health.unit.bpm")
        ))
        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(metricRow(
            title: L10n.text("apple_health.stress.details.metric.respiratory_rate"),
            metric: details.respiratoryRate,
            unit: L10n.text("apple_health.unit.breaths_per_minute")
        ))
        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(metricRow(
            title: L10n.text("apple_health.stress.details.metric.sleep_quality"),
            metric: details.sleepQuality,
            unit: ""
        ))
        return makeCard(containing: stack, identifier: "today.stress.details.inputs")
    }

    private func metricRow(
        title: String,
        metric: AppleHealthStressMetricDetails,
        unit: String,
        activityAdjusted: Bool = false
    ) -> UIView {
        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.bodyBold, color: WellnarioPalette.textPrimary)
        titleLabel.text = title

        let valueText = metric.value.map { formatted($0, unit: unit) }
            ?? L10n.text("apple_health.stress.details.unavailable")
        let valueLabel = UILabel()
        valueLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        valueLabel.text = L10n.text("apple_health.stress.details.metric.value", valueText)
        valueLabel.numberOfLines = 0

        var rows: [UIView] = [titleLabel, valueLabel]
        if activityAdjusted,
           let adjusted = metric.adjustedValue,
           metric.value != nil,
           abs(adjusted - (metric.value ?? adjusted)) > 0.000_001 {
            rows.append(detailLabel(L10n.text(
                "apple_health.stress.details.metric.adjusted",
                formatted(adjusted, unit: unit)
            )))
        }
        let baselineText: String
        if let median = metric.baselineMedian, let mad = metric.baselineMAD {
            baselineText = L10n.text(
                "apple_health.stress.details.metric.baseline",
                formatted(median, unit: unit),
                formatted(mad, unit: unit),
                metric.baselineSampleCount
            )
        } else {
            baselineText = L10n.text(
                "apple_health.stress.details.metric.baseline_missing",
                metric.baselineSampleCount
            )
        }
        rows.append(detailLabel(baselineText))
        rows.append(detailLabel(
            metric.zScore.map {
                L10n.text(
                    "apple_health.stress.details.metric.z_contribution",
                    String(format: "%.2f", $0),
                    String(format: "%+.2f", metric.contribution ?? 0),
                    String(format: "%+.2f", metric.weight)
                )
            } ?? L10n.text("apple_health.stress.details.metric.not_in_score")
        ))
        let stack = UIStackView(arrangedSubviews: rows, axis: .vertical, spacing: WellnarioSpacing.xxxSmall)
        return stack
    }

    private func makeMethodCard(
        _ details: AppleHealthStressCalculationDetails
    ) -> PremiumCardView {
        let composite = details.compositeIndex.map { String(format: "%.2f", $0) }
            ?? L10n.text("apple_health.stress.details.unavailable")
        let compositeBaseline: String
        if let median = details.compositeBaselineMedian,
           let mad = details.compositeBaselineMAD {
            compositeBaseline = L10n.text(
                "apple_health.stress.details.composite.baseline",
                String(format: "%.2f", median),
                String(format: "%.2f", mad)
            )
        } else {
            compositeBaseline = L10n.text("apple_health.stress.details.composite.baseline_missing")
        }
        let z = details.compositeZScore.map { String(format: "%.2f", $0) }
            ?? L10n.text("apple_health.stress.details.unavailable")
        let activity = details.hadActivityInPreviousTwoHours
            ? L10n.text("apple_health.stress.details.activity_adjusted")
            : L10n.text("apple_health.stress.details.activity_not_adjusted")
        let body = L10n.text(
            "apple_health.stress.details.method.body",
            AppleHealthStressScoreCalculator.baselineDays,
            AppleHealthStressScoreCalculator.minimumHistoricalSamples
        )
        var rows: [UIView] = [
            cardTitle(L10n.text("apple_health.stress.details.method.title")),
            explanatoryLabel(body),
            detailLabel(L10n.text(
                details.usesSleepCalibration == true
                    ? "apple_health.stress.details.formula.sleep"
                    : "apple_health.stress.details.formula"
            )),
            detailLabel(L10n.text("apple_health.stress.details.composite", composite))
        ]
        if details.usesSleepCalibration != true {
            rows.append(detailLabel(compositeBaseline))
            rows.append(detailLabel(L10n.text("apple_health.stress.details.composite.z", z)))
        }
        rows.append(detailLabel(activity))
        let stack = UIStackView(
            arrangedSubviews: rows,
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        return makeCard(containing: stack, identifier: "today.stress.details.method")
    }

    private func cardTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    private func explanatoryLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    private func detailLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    private func divider() -> UIView {
        let view = UIView()
        view.backgroundColor = WellnarioPalette.hairline
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    private func formatted(_ value: Double, unit: String) -> String {
        let number = AppleHealthUIFormatting.number(value, maximumFractionDigits: 2)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

@MainActor
final class TodayMedicalReviewRow: UIStackView {
    private(set) var urgency: MedicalReviewDueUrgency
    let reviewTitleLabel = UILabel()

    init(
        entry: MedicalReviewTimelineEntry,
        index: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        urgency = entry.urgency
        super.init(frame: .zero)
        accessibilityIdentifier = "today.summary.reviews.row.\(index)"
        axis = .horizontal
        spacing = 5
        alignment = .center

        let color = Self.color(for: entry.urgency)
        let marker = UIView()
        marker.backgroundColor = color
        marker.applyContinuousCorners(4)
        NSLayoutConstraint.activate([
            marker.widthAnchor.constraint(equalToConstant: 7),
            marker.heightAnchor.constraint(equalTo: marker.widthAnchor)
        ])

        reviewTitleLabel.applyWellnarioStyle(.summaryDetail, color: color)
        reviewTitleLabel.text = [
            entry.review.title,
            MedicalReviewFormatting.relativeDayStatus(
                dueDate: entry.dueDate,
                referenceDate: referenceDate,
                calendar: calendar
            )
        ].joined(separator: " · ")
        reviewTitleLabel.numberOfLines = 2
        reviewTitleLabel.lineBreakMode = .byWordWrapping
        addArrangedSubview(marker)
        addArrangedSubview(reviewTitleLabel)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func color(for urgency: MedicalReviewDueUrgency) -> UIColor {
        switch urgency {
        case .upcoming: WellnarioPalette.success
        case .overdueUnderQuarter: WellnarioPalette.yellow
        case .overdueFromQuarterThroughThreeQuarters: WellnarioPalette.orange
        case .overdueOverThreeQuarters: WellnarioPalette.danger
        }
    }
}

extension TodayViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let alert = UIAlertController(
            title: L10n.text("lab.imported.title"),
            message: L10n.text("lab.imported.message", url.lastPathComponent),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
        present(alert, animated: true)
    }
}


// MARK: - Recovery Components

private final class ScoreSegmentBarView: UIView {
    private let segmentCount: Int
    private let segmentSpacing: CGFloat
    private let segmentCornerRadius: CGFloat
    private var segments = [UIView]()
    private let stack = UIStackView()
    private var activeSegmentCount = 0

    init(
        segmentCount: Int = 12,
        spacing: CGFloat = 2,
        cornerRadius: CGFloat = 2,
        frame: CGRect = .zero
    ) {
        self.segmentCount = max(segmentCount, 1)
        segmentSpacing = spacing
        segmentCornerRadius = cornerRadius
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        segmentCount = 12
        segmentSpacing = 2
        segmentCornerRadius = 2
        super.init(coder: coder)
        setUp()
    }

    func configure(score: Double?) {
        guard let score else {
            activeSegmentCount = 0
            updateColors()
            return
        }
        let normalized = min(max(score / 100, 0), 1)
        activeSegmentCount = Int(
            (normalized * Double(segmentCount)).rounded(.up)
        )
        updateColors()
    }

    private func setUp() {
        isAccessibilityElement = false
        stack.axis = .horizontal
        stack.spacing = segmentSpacing
        stack.distribution = .fillEqually
        segments = (0..<segmentCount).map { _ in UIView() }
        segments.forEach { segment in
            segment.applyContinuousCorners(segmentCornerRadius)
            stack.addArrangedSubview(segment)
        }
        addForAutoLayout(stack)
        stack.pinEdges(to: self)
        updateColors()

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (self: ScoreSegmentBarView, _: UITraitCollection) in
            self.updateColors()
        }
    }

    private func updateColors() {
        for (index, segment) in segments.enumerated() {
            if index < activeSegmentCount {
                segment.backgroundColor = color(for: index)
            } else {
                segment.backgroundColor = WellnarioPalette.hairline
                    .resolvedColor(with: traitCollection)
                    .withAlphaComponent(0.55)
            }
        }
    }

    private func color(for index: Int) -> UIColor {
        let progress = CGFloat(index) / CGFloat(max(segmentCount - 1, 1))
        if progress <= 0.5 {
            return interpolate(
                WellnarioPalette.danger,
                WellnarioPalette.warning,
                progress: progress * 2
            )
        }
        return interpolate(
            WellnarioPalette.warning,
            WellnarioPalette.success,
            progress: (progress - 0.5) * 2
        )
    }

    private func interpolate(_ start: UIColor, _ end: UIColor, progress: CGFloat) -> UIColor {
        let resolvedStart = start.resolvedColor(with: traitCollection)
        let resolvedEnd = end.resolvedColor(with: traitCollection)
        var startRed: CGFloat = 0
        var startGreen: CGFloat = 0
        var startBlue: CGFloat = 0
        var startAlpha: CGFloat = 0
        var endRed: CGFloat = 0
        var endGreen: CGFloat = 0
        var endBlue: CGFloat = 0
        var endAlpha: CGFloat = 0
        guard resolvedStart.getRed(&startRed, green: &startGreen, blue: &startBlue, alpha: &startAlpha),
              resolvedEnd.getRed(&endRed, green: &endGreen, blue: &endBlue, alpha: &endAlpha) else {
            return progress < 0.5 ? start : end
        }
        let t = min(max(progress, 0), 1)
        return UIColor(
            red: startRed + (endRed - startRed) * t,
            green: startGreen + (endGreen - startGreen) * t,
            blue: startBlue + (endBlue - startBlue) * t,
            alpha: startAlpha + (endAlpha - startAlpha) * t
        )
    }
}

@MainActor
final class TodayRecoverySummaryCard: PremiumCardView {
    let symbolContainer = UIView()
    private let symbolView = UIImageView()
    let titleLabel = UILabel()
    private let currentScoreBar = ScoreSegmentBarView()
    private let currentScoreValueLabel = UILabel()
    private let currentScoreRow = UIStackView()
    private let currentLevelLabel = UILabel()
    private let currentScoreStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(
        title: String,
        symbolName: String,
        currentScore: Double?,
        tone: UIColor
    ) {
        titleLabel.text = title
        symbolView.image = UIImage(systemName: symbolName)
        symbolView.tintColor = tone
        symbolContainer.backgroundColor = tone.withAlphaComponent(0.14)
        currentScoreBar.configure(score: currentScore)
        currentScoreValueLabel.text = currentScore.map {
            AppleHealthUIFormatting.number($0)
        } ?? "—"
        
        let levelText: String
        if let score = currentScore {
            if score < 40 {
                levelText = L10n.text("apple_health.recovery.level.low")
            } else if score < 70 {
                levelText = L10n.text("apple_health.recovery.level.moderate")
            } else {
                levelText = L10n.text("apple_health.recovery.level.high")
            }
        } else {
            levelText = L10n.text("wellness.no_data")
        }
        currentLevelLabel.text = levelText
        currentLevelLabel.isHidden = false
        
        accessibilityLabel = title
        let scoreText = currentScore.map { AppleHealthUIFormatting.number($0) }
        accessibilityValue = [scoreText, levelText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        accessibilityTraits = [.button]
        isPressable = true
    }

    private func setUp() {
        symbolContainer.applyContinuousCorners(11)
        NSLayoutConstraint.activate([
            symbolContainer.widthAnchor.constraint(equalToConstant: 34),
            symbolContainer.heightAnchor.constraint(equalTo: symbolContainer.widthAnchor)
        ])

        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 15,
            weight: .semibold
        )
        symbolView.contentMode = .scaleAspectFit
        symbolContainer.addForAutoLayout(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor)
        ])

        titleLabel.applyWellnarioStyle(.summaryTitle, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            currentScoreBar.widthAnchor.constraint(equalToConstant: 82),
            currentScoreBar.heightAnchor.constraint(equalToConstant: 17)
        ])

        currentScoreValueLabel.applyWellnarioStyle(.bodyBold, color: WellnarioPalette.textPrimary)
        currentScoreValueLabel.textAlignment = .right
        currentScoreValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        currentScoreValueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        currentLevelLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        currentLevelLabel.textAlignment = .left
        currentLevelLabel.numberOfLines = 1
        currentLevelLabel.adjustsFontSizeToFitWidth = true
        currentLevelLabel.minimumScaleFactor = 0.75

        currentScoreStack.axis = .vertical
        currentScoreStack.spacing = WellnarioSpacing.xxxSmall
        currentScoreStack.alignment = .leading
        
        currentScoreRow.axis = .horizontal
        currentScoreRow.spacing = WellnarioSpacing.xxxSmall
        currentScoreRow.alignment = .center
        currentScoreRow.addArrangedSubview(currentScoreBar)
        currentScoreRow.addArrangedSubview(currentScoreValueLabel)
        
        currentScoreStack.addArrangedSubview(currentScoreRow)
        currentScoreStack.addArrangedSubview(currentLevelLabel)

        let titleRow = UIStackView(
            arrangedSubviews: [symbolContainer, titleLabel, UIView()],
            axis: .horizontal,
            spacing: 7,
            alignment: .center
        )
        
        let stack = UIStackView(
            arrangedSubviews: [titleRow, currentScoreStack],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        
        contentView.addForAutoLayout(stack)
        stack.pinEdges(to: contentView, insets: .all(WellnarioSpacing.xSmall))
    }
}

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class RecoveryDetailViewController: WellnessScrollViewController {
    private let score: Double?
    private let descriptionLabel = UILabel()
    private let aiAdviceTitleLabel = UILabel()
    private let aiAdviceBodyLabel = UILabel()
    private let aiContainer = UIView()
    private let aiActivityIndicator = UIActivityIndicatorView(style: .medium)

    init(score: Double?) {
        self.score = score
        super.init(nibName: nil, bundle: nil)
        title = L10n.text("wellness.recovery")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WellnarioPalette.background.resolvedColor(with: traitCollection)
        setUp()
        generateAIAdvice()
    }

    private func setUp() {
        descriptionLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.text = L10n.text("apple_health.recovery.explanation.body")

        aiAdviceTitleLabel.applyWellnarioStyle(.bodyBold, color: WellnarioPalette.textPrimary)
        aiAdviceTitleLabel.text = L10n.text("health.analytics.import.method.foundation_models") + " Advice"
        aiAdviceTitleLabel.numberOfLines = 1

        aiAdviceBodyLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        aiAdviceBodyLabel.numberOfLines = 0
        aiAdviceBodyLabel.text = "Loading advice..."

        aiContainer.backgroundColor = WellnarioPalette.surfaceElevated.resolvedColor(with: traitCollection)
        aiContainer.applyContinuousCorners(12)
        
        let aiStack = UIStackView(arrangedSubviews: [aiAdviceTitleLabel, aiAdviceBodyLabel])
        aiStack.axis = .vertical
        aiStack.spacing = WellnarioSpacing.small
        
        aiContainer.addForAutoLayout(aiStack)
        aiStack.pinEdges(to: aiContainer, insets: .all(WellnarioSpacing.medium))
        
        aiContainer.addForAutoLayout(aiActivityIndicator)
        NSLayoutConstraint.activate([
            aiActivityIndicator.centerYAnchor.constraint(equalTo: aiAdviceTitleLabel.centerYAnchor),
            aiActivityIndicator.trailingAnchor.constraint(equalTo: aiContainer.trailingAnchor, constant: -WellnarioSpacing.medium)
        ])

        let mainStack = UIStackView(arrangedSubviews: [descriptionLabel, aiContainer])
        mainStack.axis = .vertical
        mainStack.spacing = WellnarioSpacing.large
        
        contentStack.addArrangedSubview(mainStack)
        
        // Hide AI container if FoundationModels is not available
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            aiContainer.isHidden = false
        } else {
            aiContainer.isHidden = true
        }
        #else
        aiContainer.isHidden = true
        #endif
    }

    private func generateAIAdvice() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard let score = score else {
                aiAdviceBodyLabel.text = L10n.text("apple_health.recovery.no_data")
                return
            }
            aiActivityIndicator.startAnimating()
            
            Task {
                do {
                    let model = SystemLanguageModel.default
                    let langCode = Locale.current.language.languageCode?.identifier ?? "en"
                    let session = LanguageModelSession(
                        model: model,
                        instructions: """
                        You are a world-class wellness coach giving direct, actionable advice to a user.
                        Their current physiological recovery score is \(Int(score))/100.
                        Provide exactly 1 or 2 sentences of direct advice addressing the user (e.g., "You should...").
                        - Score < 40: Emphasize rest, active recovery, and very light activity.
                        - Score 40-70: Suggest moderate training but advise them to pay attention to fatigue.
                        - Score > 70: Encourage intense workouts as their body is fully primed for performance.

                        Respond ONLY with the final advice to the user in the language corresponding to the locale code '\(langCode)'. Do not include quotes, greetings, explanations of the score, or descriptions of what you are doing. Make it sound natural, direct, and encouraging.
                        """
                    )
                    
                    let prompt = "My recovery score is \(Int(score)). What should I do today?"
                    let responseText = try await session.respond(to: prompt)
                    self.aiAdviceBodyLabel.text = responseText.content
                } catch {
                    self.aiAdviceBodyLabel.text = "Could not generate advice at this time."
                }
                self.aiActivityIndicator.stopAnimating()
            }
        }
        #endif
    }
}
