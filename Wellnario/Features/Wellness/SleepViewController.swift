import UIKit

@MainActor
final class SleepViewController: WellnessScrollViewController {
    private static let trendReferenceLinePreferenceKey = "wellnario.sleep.trend.referenceLine"
    private static let sourceBannerHeight: CGFloat = 76
    private static let sourceBannerDisplayDuration: UInt64 = 10_000_000_000

    private enum TrendMetric: Int, CaseIterable {
        case quality
        case duration
        case rem
        case deep
        case light
    }

    private struct SourceBannerEvent: Equatable {
        let state: AppleHealthSyncState
        let lastSyncedAt: Date?
    }

    var onOpenSettings: (() -> Void)?

    private let appleHealthService: AppleHealthSyncing
    private let repository: WellnarioRepositoryProtocol?
    private let defaults: UserDefaults
    private let cardLayoutPreferences: SleepCardLayoutPreferences
    private let sleepManualOverrideStore: SleepManualOverrideStore
    private let sourceBanner = FeedbackBannerView()
    private lazy var syncIndicator = AppleHealthSyncNavigationIndicator(service: appleHealthService)
    private let trendChart = WellnessTrendChartView()
    private var isSourceBannerVisible = false
    private var appliedSourceBannerInset: CGFloat = 0
    private var selectedTrendPeriod = AppleHealthSleepTrendPeriod.sevenDays
    private var selectedTrendMetric = TrendMetric.duration
    private var selectedTrendReferenceLine: WellnessTrendReferenceLine
    private var terminalSourceBannerEvent: SourceBannerEvent?
    private var sourceBannerDismissalTask: Task<Void, Never>?
    private lazy var trendPeriodControl: UISegmentedControl = makeTrendPeriodControl()
    private lazy var trendMetricControl: UISegmentedControl = makeTrendMetricControl()
    private lazy var trendReferenceLineControl: UISegmentedControl = makeTrendReferenceLineControl()

    init(
        appleHealthService: AppleHealthSyncing,
        repository: WellnarioRepositoryProtocol? = nil,
        defaults: UserDefaults = .standard,
        sleepManualOverrideStore: SleepManualOverrideStore? = nil
    ) {
        self.appleHealthService = appleHealthService
        self.repository = repository
        self.defaults = defaults
        self.sleepManualOverrideStore = sleepManualOverrideStore
            ?? SleepManualOverrideStore(defaults: defaults)
        cardLayoutPreferences = SleepCardLayoutPreferences(defaults: defaults)
        let storedReferenceLine = defaults.object(forKey: Self.trendReferenceLinePreferenceKey) as? Int
        selectedTrendReferenceLine = storedReferenceLine
            .flatMap(WellnessTrendReferenceLine.init(rawValue:))
            ?? .linearTrend
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("sleep.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "sleep.root"
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        settingsButton.accessibilityLabel = L10n.Settings.title
        settingsButton.accessibilityIdentifier = "sleep.settings"
        let editCardsButton = UIBarButtonItem(
            image: UIImage(systemName: "square.grid.2x2"),
            style: .plain,
            target: self,
            action: #selector(openCardEditor)
        )
        editCardsButton.tintColor = WellnarioPalette.fuchsia
        editCardsButton.accessibilityLabel = L10n.text("sleep.cards.edit")
        editCardsButton.accessibilityIdentifier = "sleep.cards.edit"
        navigationItem.rightBarButtonItems = [settingsButton, editCardsButton]
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
        setUpSourceBanner()
        buildContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        syncIndicator.refresh()
        buildContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateScrollInsetsForSourceBanner()
    }

    deinit {
        sourceBannerDismissalTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let snapshot = effectiveSnapshot()

        updateSourceBanner(snapshot: snapshot)
        let visibleCards = cardLayoutPreferences.orderedCards.filter(cardLayoutPreferences.isVisible)
        guard !visibleCards.isEmpty else {
            contentStack.addArrangedSubview(makeNoVisibleCardsView())
            return
        }

        for card in visibleCards {
            let section = makeCardSection(card, snapshot: snapshot)
            contentStack.addArrangedSubview(section)
            contentStack.setCustomSpacing(WellnarioSpacing.large, after: section)
        }
    }

    private func effectiveSnapshot() -> AppleHealthSnapshot {
        sleepManualOverrideStore.applying(to: appleHealthService.snapshot)
    }

    private func makeCardSection(_ card: SleepCardKind, snapshot: AppleHealthSnapshot) -> UIView {
        let sectionTitle: UIView
        let cardView: UIView
        switch card {
        case .latestSession:
            sectionTitle = makeSectionTitle(
                L10n.text("sleep.latest.title"),
                detail: L10n.text("sleep.latest.detail")
            )
            cardView = makeLatestSessionCard(snapshot)
        case .trend:
            sectionTitle = makeSectionTitle(L10n.text("sleep.trend.title"))
            cardView = makeTrendCard(snapshot: snapshot)
        case .factors:
            sectionTitle = makeSectionTitle(L10n.text("sleep.factors.title"))
            cardView = makeFactorCards()
        }

        let section = UIStackView(
            arrangedSubviews: [sectionTitle, cardView],
            axis: .vertical,
            spacing: WellnarioSpacing.cardGap
        )
        section.accessibilityIdentifier = "sleep.card.section.\(card.rawValue)"
        return section
    }

    private func makeTrendCard(snapshot: AppleHealthSnapshot) -> PremiumCardView {
        configureTrendChart(with: snapshot)
        let trendContent = UIStackView(
            arrangedSubviews: [
                trendMetricControl,
                makeTrendReferenceLineControlContainer(),
                trendChart,
                trendPeriodControl
            ],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        let card = PremiumCardView()
        card.accessibilityIdentifier = "sleep.trend.card"
        card.contentView.addForAutoLayout(trendContent)
        trendContent.pinEdges(
            to: card.contentView,
            insets: NSDirectionalEdgeInsets(top: 16, leading: 8, bottom: 16, trailing: 8)
        )
        return card
    }

    private func makeNoVisibleCardsView() -> EmptyStateView {
        let emptyState = EmptyStateView()
        emptyState.accessibilityIdentifier = "sleep.cards.empty"
        emptyState.configure(
            kind: .other,
            title: L10n.text("sleep.cards.empty.title"),
            message: L10n.text("sleep.cards.empty.body"),
            actionTitle: L10n.text("sleep.cards.edit")
        )
        emptyState.onAction = { [weak self] in self?.openCardEditor() }
        emptyState.heightAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        return emptyState
    }

    private func setUpSourceBanner() {
        sourceBanner.accessibilityIdentifier = "sleep.source.banner"
        sourceBanner.backgroundOpacityOverride = WellnarioPalette.synchronizationBannerOpacity
        sourceBanner.isHidden = true
        view.addForAutoLayout(sourceBanner)
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
            sourceBanner.heightAnchor.constraint(equalToConstant: Self.sourceBannerHeight)
        ])
        view.bringSubviewToFront(sourceBanner)
    }

    private func updateSourceBanner(snapshot: AppleHealthSnapshot) {
        guard appleHealthService.isConfigured else {
            clearTerminalSourceBannerEvent()
            hideSourceBannerImmediately()
            return
        }

        let event = SourceBannerEvent(
            state: appleHealthService.state,
            lastSyncedAt: snapshot.lastSyncedAt
        )
        switch appleHealthService.state {
        case .ready, .failed:
            if appleHealthService.state == .ready {
                clearTerminalSourceBannerEvent()
                hideSourceBannerImmediately()
                return
            }
            guard terminalSourceBannerEvent != event else {
                if !sourceBanner.isHidden { configureSourceBanner(sourceBanner, snapshot: snapshot) }
                return
            }
            terminalSourceBannerEvent = event
            showSourceBanner()
            configureSourceBanner(sourceBanner, snapshot: snapshot)
            scheduleSourceBannerDismissal(for: event)
        case .syncing:
            clearTerminalSourceBannerEvent()
            hideSourceBannerImmediately()
        case .unavailable, .notConfigured:
            clearTerminalSourceBannerEvent()
            showSourceBanner()
            configureSourceBanner(sourceBanner, snapshot: snapshot)
        }
    }

    private func showSourceBanner() {
        sourceBannerDismissalTask?.cancel()
        isSourceBannerVisible = true
        sourceBanner.isHidden = false
        sourceBanner.alpha = 1
        sourceBanner.transform = .identity
        view.bringSubviewToFront(sourceBanner)
        view.setNeedsLayout()
    }

    private func hideSourceBannerImmediately() {
        isSourceBannerVisible = false
        sourceBanner.isHidden = true
        sourceBanner.alpha = 1
        sourceBanner.transform = .identity
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
            self.isSourceBannerVisible = false
            self.updateScrollInsetsForSourceBanner()
            self.view.layoutIfNeeded()
        }, completion: { [weak self] _ in
            guard let self, self.terminalSourceBannerEvent == event else { return }
            self.sourceBanner.isHidden = true
            self.sourceBanner.alpha = 1
            self.sourceBanner.transform = .identity
        })
    }

    private func updateScrollInsetsForSourceBanner() {
        let targetInset = isSourceBannerVisible
            ? sourceBanner.bounds.height + WellnarioSpacing.xxxSmall
            : 0
        guard abs(targetInset - appliedSourceBannerInset) > 0.5 else { return }

        let previousAdjustedTop = scrollView.adjustedContentInset.top
        let wasAtTop = scrollView.contentOffset.y <= -previousAdjustedTop + 1
        appliedSourceBannerInset = targetInset
        scrollView.contentInset.top = targetInset
        scrollView.verticalScrollIndicatorInsets.top = targetInset
        if wasAtTop {
            scrollView.contentOffset.y = -scrollView.adjustedContentInset.top
        }
    }

    private func configureTrendChart(with snapshot: AppleHealthSnapshot) {
        let series = AppleHealthSleepAggregator.trendSeries(
            from: snapshot.sleepTrend,
            period: selectedTrendPeriod
        )
        let trend = series.entries
        let values = trend.map(trendValue)
        let dailyValues = series.dailyEntries.map(trendValue)
        trendChart.values = values
        trendChart.linearTrend = WellnessLinearRegression.fit(values: dailyValues)
        trendChart.referenceLine = selectedTrendReferenceLine
        trendChart.labels = trendLabels(for: series, period: selectedTrendPeriod)
        trendChart.selectionLabels = trendSelectionLabels(for: series)
        trendChart.lineColor = trendMetricColor(selectedTrendMetric)
        let emptyText = selectedTrendMetric == .quality
            ? L10n.text("sleep.trend.quality.empty")
            : L10n.text("sleep.trend.empty")
        trendChart.emptyText = emptyText
        trendChart.smoothingWindow = 1
        trendChart.averageTitle = L10n.text("sleep.trend.average")
        trendChart.valueFormatter = trendValueFormatter(selectedTrendMetric)
        trendChart.accessibilityIdentifier = "sleep.trend.chart"
        trendChart.accessibilityHint = L10n.text("sleep.trend.interaction.hint")
        trendChart.accessibilityLabel = L10n.text(
            "sleep.trend.accessibility.format",
            trendMetricTitle(selectedTrendMetric),
            trendPeriodTitle(selectedTrendPeriod)
        )
        let validValues = values.compactMap { $0 }
        if let minimum = validValues.min(), let maximum = validValues.max() {
            let average = validValues.reduce(0, +) / Double(validValues.count)
            trendChart.accessibilityValue = L10n.text(
                "sleep.trend.accessibility.values",
                trendChart.valueFormatter(average),
                trendChart.valueFormatter(minimum),
                trendChart.valueFormatter(maximum)
            )
        } else {
            trendChart.accessibilityValue = emptyText
        }
    }

    private func trendValue(_ day: AppleHealthSleepDay) -> Double? {
        switch selectedTrendMetric {
        case .quality: day.qualityScore
        case .duration: day.hours
        case .rem: day.remHours
        case .deep: day.deepHours
        case .light: day.lightHours
        }
    }

    private func trendValueFormatter(_ metric: TrendMetric) -> (Double) -> String {
        switch metric {
        case .quality:
            { AppleHealthUIFormatting.number($0, maximumFractionDigits: 0) }
        case .duration, .rem, .deep, .light:
            { value in
                L10n.text(
                    "sleep.trend.hours.short",
                    AppleHealthUIFormatting.number(value, maximumFractionDigits: 1)
                )
            }
        }
    }

    private func trendMetricColor(_ metric: TrendMetric) -> UIColor {
        switch metric {
        case .quality: WellnarioPalette.pink
        case .duration: WellnarioPalette.violet
        case .rem: WellnarioPalette.magenta
        case .deep: WellnarioPalette.information
        case .light: WellnarioPalette.warning
        }
    }

    private func makeTrendPeriodControl() -> UISegmentedControl {
        let control = UISegmentedControl(items: AppleHealthSleepTrendPeriod.allCases.map(trendPeriodTitle))
        control.selectedSegmentIndex = selectedTrendPeriod.rawValue
        control.apportionsSegmentWidthsByContent = true
        control.selectedSegmentTintColor = WellnarioPalette.fuchsia
        control.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: WellnarioPalette.textSecondary
        ], for: .normal)
        control.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.white
        ], for: .selected)
        control.accessibilityIdentifier = "sleep.trend.period.selector"
        control.accessibilityLabel = L10n.text("sleep.trend.period.selector.accessibility")
        control.addTarget(self, action: #selector(trendPeriodDidChange), for: .valueChanged)
        return control
    }

    private func makeTrendMetricControl() -> UISegmentedControl {
        let control = UISegmentedControl(items: TrendMetric.allCases.map(trendMetricTitle))
        control.selectedSegmentIndex = selectedTrendMetric.rawValue
        control.apportionsSegmentWidthsByContent = true
        control.selectedSegmentTintColor = WellnarioPalette.fuchsia
        control.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: WellnarioPalette.textSecondary
        ], for: .normal)
        control.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.white
        ], for: .selected)
        control.accessibilityIdentifier = "sleep.trend.metric.selector"
        control.accessibilityLabel = L10n.text("sleep.trend.metric.selector.accessibility")
        control.addTarget(self, action: #selector(trendMetricDidChange), for: .valueChanged)
        return control
    }

    private func makeTrendReferenceLineControl() -> UISegmentedControl {
        let control = UISegmentedControl(items: WellnessTrendReferenceLine.allCases.map {
            trendReferenceLineTitle($0)
        })
        control.selectedSegmentIndex = selectedTrendReferenceLine.rawValue
        control.selectedSegmentTintColor = WellnarioPalette.fuchsia
        control.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: WellnarioPalette.textSecondary
        ], for: .normal)
        control.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.white
        ], for: .selected)
        control.accessibilityIdentifier = "sleep.trend.reference.selector"
        control.accessibilityLabel = L10n.text("sleep.trend.reference.selector.accessibility")
        control.addTarget(self, action: #selector(trendReferenceLineDidChange), for: .valueChanged)
        return control
    }

    private func makeTrendReferenceLineControlContainer() -> UIView {
        let container = UIView()
        container.addForAutoLayout(trendReferenceLineControl)
        NSLayoutConstraint.activate([
            trendReferenceLineControl.topAnchor.constraint(equalTo: container.topAnchor),
            trendReferenceLineControl.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            trendReferenceLineControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            trendReferenceLineControl.widthAnchor.constraint(equalToConstant: 180),
            trendReferenceLineControl.heightAnchor.constraint(equalToConstant: 28)
        ])
        return container
    }

    private func trendReferenceLineTitle(_ referenceLine: WellnessTrendReferenceLine) -> String {
        switch referenceLine {
        case .average: L10n.text("sleep.trend.reference.average")
        case .linearTrend: L10n.text("sleep.trend.reference.linear")
        }
    }

    private func trendMetricTitle(_ metric: TrendMetric) -> String {
        switch metric {
        case .quality: L10n.text("sleep.trend.metric.quality")
        case .duration: L10n.text("sleep.trend.metric.duration")
        case .rem: L10n.text("sleep.trend.metric.rem")
        case .deep: L10n.text("sleep.trend.metric.deep")
        case .light: L10n.text("sleep.trend.metric.light")
        }
    }

    private func trendPeriodTitle(_ period: AppleHealthSleepTrendPeriod) -> String {
        switch period {
        case .sevenDays: L10n.text("sleep.trend.period.7d")
        case .thirtyDays: L10n.text("sleep.trend.period.30d")
        case .sixMonths: L10n.text("sleep.trend.period.6m")
        case .allTime: L10n.text("sleep.trend.period.all")
        }
    }

    private func trendLabels(
        for series: AppleHealthSleepTrendSeries,
        period: AppleHealthSleepTrendPeriod
    ) -> [String] {
        let trend = series.entries
        guard !trend.isEmpty else { return [] }
        if period == .sevenDays {
            return trend.map { AppleHealthUIFormatting.weekdayInitial(for: $0.date) }
        }

        let labelCount = min(period == .thirtyDays ? 4 : 3, trend.count)
        let indexes = Set((0..<labelCount).map { labelIndex in
            guard labelCount > 1 else { return 0 }
            return Int((Double(labelIndex) * Double(trend.count - 1) / Double(labelCount - 1)).rounded())
        })
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        let spansMoreThanAYear = (trend.last?.date.timeIntervalSince(trend.first?.date ?? Date()) ?? 0)
            >= 365 * 24 * 60 * 60
        let template: String
        switch series.granularity {
        case .year: template = "y"
        case .month: template = "MMMyy"
        case .day, .week: template = spansMoreThanAYear ? "MMMyy" : "dMMM"
        }
        formatter.setLocalizedDateFormatFromTemplate(template)
        return trend.enumerated().map { index, entry in
            indexes.contains(index) ? formatter.string(from: entry.date) : ""
        }
    }

    private func trendSelectionLabels(for series: AppleHealthSleepTrendSeries) -> [String] {
        let locale = LocalizationManager.shared.locale
        switch series.granularity {
        case .day:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("dMMMy")
            return series.entries.map { formatter.string(from: $0.date) }
        case .week:
            let startFormatter = DateFormatter()
            startFormatter.locale = locale
            startFormatter.setLocalizedDateFormatFromTemplate("dMMM")
            let endFormatter = DateFormatter()
            endFormatter.locale = locale
            endFormatter.setLocalizedDateFormatFromTemplate("dMMMy")
            let calendar = Calendar.autoupdatingCurrent
            return series.entries.map { entry in
                guard let interval = calendar.dateInterval(of: .weekOfYear, for: entry.date),
                      let end = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
                    return startFormatter.string(from: entry.date)
                }
                return "\(startFormatter.string(from: interval.start))–\(endFormatter.string(from: end))"
            }
        case .month:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("MMMMy")
            return series.entries.map { formatter.string(from: $0.date) }
        case .year:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("y")
            return series.entries.map { formatter.string(from: $0.date) }
        }
    }

    private func configureSourceBanner(
        _ banner: FeedbackBannerView,
        snapshot: AppleHealthSnapshot
    ) {
        banner.onAction = nil
        switch appleHealthService.state {
        case .unavailable:
            banner.configure(message: L10n.text("apple_health.unavailable"), tone: .warning)
        case .notConfigured:
            banner.configure(
                message: L10n.text("sleep.source.empty"),
                tone: .information,
                actionTitle: L10n.text("integrations.connect")
            )
            banner.onAction = { [weak self] in self?.onOpenSettings?() }
        case .syncing:
            banner.configure(message: L10n.text("apple_health.syncing"), tone: .information)
        case .failed:
            banner.configure(
                message: L10n.text("apple_health.sync_failed"),
                tone: .warning,
                actionTitle: AppleHealthUIFormatting.twoLineSyncNowActionTitle
            )
            banner.onAction = { [weak self] in self?.syncNow() }
        case .ready:
            let message = snapshot.lastSyncedAt.map(AppleHealthUIFormatting.syncedAt)
                ?? L10n.text("apple_health.configured")
            banner.configure(
                message: message,
                tone: .success,
                actionTitle: AppleHealthUIFormatting.twoLineSyncNowActionTitle
            )
            banner.onAction = { [weak self] in self?.syncNow() }
        }
    }

    private func makeLatestSessionCard(_ snapshot: AppleHealthSnapshot) -> PremiumCardView {
        let session = snapshot.latestSleepSession
        let sessionDay = session.map { LocalDay(containing: $0.endDate, in: .current) }
        let latestManual: SleepManualOverride?
        if let candidate = sleepManualOverrideStore.overrides.last,
           sessionDay.map({ candidate.day >= $0 }) ?? true {
            latestManual = candidate
        } else {
            latestManual = nil
        }
        let displayedSession = latestManual?.day == sessionDay || latestManual == nil
            ? session
            : nil
        let displayedDay = latestManual?.day ?? sessionDay
        let displayedSleepEntry = displayedDay.flatMap { day in
            snapshot.sleepTrend.last {
                LocalDay(containing: $0.date, in: .current) == day
            }
        }
        let displayedQuality = displayedSleepEntry?.qualityScore
        let qualityConfiguration = sleepManualOverrideStore.qualityPreferences.configuration(
            dateOfBirthComponents: snapshot.dateOfBirthComponents,
            calendar: .autoupdatingCurrent
        )
        let qualityBreakdown: SleepQualityBreakdown?
        if latestManual?.qualityScore == nil,
           let displayedSleepEntry {
            qualityBreakdown = SleepQualityCalculator.breakdown(
                for: displayedSleepEntry,
                in: snapshot.sleepTrend,
                configuration: qualityConfiguration,
                calendar: .autoupdatingCurrent
            )
        } else {
            qualityBreakdown = nil
        }

        let moon = UIImageView(image: UIImage(systemName: "moon.stars.fill"))
        moon.tintColor = WellnarioPalette.violet
        moon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 29, weight: .semibold)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        if let durationHours = latestManual?.durationHours {
            titleLabel.text = AppleHealthUIFormatting.duration(durationHours * 3_600)
        } else if let displayedSession {
            titleLabel.text = AppleHealthUIFormatting.duration(displayedSession.asleepSeconds)
        } else if latestManual?.qualityScore != nil {
            titleLabel.text = L10n.text("sleep.latest.title")
        } else {
            titleLabel.text = L10n.text("sleep.latest.empty.title")
        }
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        if let displayedSession {
            let range = AppleHealthUIFormatting.sleepRange(displayedSession)
            let sources = displayedSession.sourceNames.joined(separator: ", ")
            let healthDescription = sources.isEmpty
                ? range
                : L10n.text("apple_health.sleep.range_source", range, sources)
            var details = [healthDescription]
            if latestManual != nil {
                details.append(L10n.text("sleep.manual.source"))
            }
            bodyLabel.text = details.joined(separator: " · ")
        } else if let latestManual {
            let formatter = DateFormatter()
            formatter.locale = LocalizationManager.shared.locale
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            let date = try? latestManual.day.startDate(in: TimeZone.current)
            var details = [L10n.text("sleep.manual.source")]
            if let date { details.insert(formatter.string(from: date), at: 0) }
            bodyLabel.text = details.joined(separator: " · ")
        } else {
            bodyLabel.text = L10n.text("sleep.latest.empty.body")
        }
        bodyLabel.numberOfLines = 0

        let iconContainer = UIView()
        iconContainer.backgroundColor = WellnarioPalette.violet.withAlphaComponent(0.14)
        iconContainer.applyContinuousCorners(22)
        iconContainer.addForAutoLayout(moon)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 64),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor),
            moon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            moon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
        ])

        let text = UIStackView(arrangedSubviews: [titleLabel, bodyLabel], axis: .vertical, spacing: 6)
        let summary = UIStackView(
            arrangedSubviews: [iconContainer, text],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )

        let separator = UIView()
        separator.backgroundColor = WellnarioPalette.hairline
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let timelineTitle = UILabel()
        timelineTitle.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        timelineTitle.text = L10n.text("sleep.stage.timeline.title")

        let timeline = SleepStageTimelineView()
        timeline.configure(session: displayedSession)
        let timelineSection = UIStackView(
            arrangedSubviews: [timelineTitle, timeline],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )

        var sections: [UIView] = [summary]
        if let displayedQuality {
            sections.append(separator)
            sections.append(makeSleepQualityBreakdownSection(
                qualityScore: displayedQuality,
                breakdown: qualityBreakdown,
                configuration: qualityConfiguration,
                entry: displayedSleepEntry
            ))
        }
        let timelineSeparator = UIView()
        timelineSeparator.backgroundColor = WellnarioPalette.hairline
        timelineSeparator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        sections.append(timelineSeparator)
        sections.append(timelineSection)

        let content = UIStackView(arrangedSubviews: sections, axis: .vertical, spacing: WellnarioSpacing.small)
        let card = makeCard(containing: content, identifier: "sleep.latest.card")
        card.isAccessibilityElement = true
        card.accessibilityLabel = [
            titleLabel.text,
            bodyLabel.text,
            L10n.text("sleep.stage.timeline.title"),
            timeline.accessibilityValue
        ].compactMap { $0 }.joined(separator: ". ")
        return card
    }

    private func makeSleepQualityBreakdownSection(
        qualityScore: Double,
        breakdown: SleepQualityBreakdown?,
        configuration: SleepQualityConfiguration,
        entry: AppleHealthSleepDay?
    ) -> UIView {
        let title = UILabel()
        title.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        title.text = L10n.text("sleep.latest.quality.breakdown.title")

        let total = UILabel()
        total.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.violet)
        total.textAlignment = .right
        total.text = L10n.text("sleep.latest.quality.total", Int(qualityScore.rounded()))
        total.setContentCompressionResistancePriority(.required, for: .horizontal)

        let header = UIStackView(
            arrangedSubviews: [title, UIView(), total],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )

        guard let breakdown else {
            let content = UIStackView(arrangedSubviews: [header], axis: .vertical, spacing: 6)
            content.accessibilityIdentifier = "sleep.latest.quality.breakdown"
            content.isAccessibilityElement = true
            content.accessibilityLabel = [title.text, total.text].compactMap { $0 }.joined(separator: ". ")
            return content
        }

        let durationDetail: String
        if let hours = entry?.hours {
            durationDetail = L10n.text(
                "sleep.latest.quality.duration.detail",
                AppleHealthUIFormatting.compactDuration(hours * 3_600),
                AppleHealthUIFormatting.compactDuration(configuration.targetHours * 3_600)
            )
        } else {
            durationDetail = L10n.text("wellness.no_data")
        }
        let regularityDetail = L10n.text(
            "sleep.latest.quality.regularity.detail",
            breakdown.compliantDays,
            SleepQualityCalculator.regularityWindowDays
        )
        let interruptionDetail: String
        if entry?.awakeHours != nil {
            interruptionDetail = L10n.text(
                "sleep.latest.quality.interruptions.detail",
                AppleHealthUIFormatting.number(breakdown.awakePercentage, maximumFractionDigits: 1)
            )
        } else {
            interruptionDetail = L10n.text("sleep.latest.quality.interruptions.unavailable")
        }

        let weights = configuration.weights
        let rows = [
            makeSleepQualityBreakdownRow(
                title: L10n.text("settings.advanced.sleep.quality.weight.duration"),
                detail: durationDetail,
                contribution: breakdown.durationScore * Double(weights.duration) / 100,
                maximumContribution: weights.duration,
                color: WellnarioPalette.violet,
                identifier: "sleep.latest.quality.duration"
            ),
            makeSleepQualityBreakdownRow(
                title: L10n.text("settings.advanced.sleep.quality.weight.regularity"),
                detail: regularityDetail,
                contribution: breakdown.regularityScore * Double(weights.regularity) / 100,
                maximumContribution: weights.regularity,
                color: WellnarioPalette.cyan,
                identifier: "sleep.latest.quality.regularity"
            ),
            makeSleepQualityBreakdownRow(
                title: L10n.text("settings.advanced.sleep.quality.weight.interruptions"),
                detail: interruptionDetail,
                contribution: breakdown.interruptionScore * Double(weights.interruptions) / 100,
                maximumContribution: weights.interruptions,
                color: WellnarioPalette.pink,
                identifier: "sleep.latest.quality.interruptions"
            )
        ]
        let content = UIStackView(arrangedSubviews: [header] + rows, axis: .vertical, spacing: 6)
        content.accessibilityIdentifier = "sleep.latest.quality.breakdown"
        content.isAccessibilityElement = true
        content.accessibilityLabel = (
            [title.text, total.text].compactMap { $0 } + rows.compactMap(\.accessibilityLabel)
        ).joined(separator: ". ")
        return content
    }

    private func makeSleepQualityBreakdownRow(
        title: String,
        detail: String,
        contribution: Double,
        maximumContribution: Int,
        color: UIColor,
        identifier: String
    ) -> UIView {
        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textPrimary)
        titleLabel.text = title

        let detailLabel = UILabel()
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        detailLabel.text = detail
        detailLabel.numberOfLines = 1
        detailLabel.adjustsFontSizeToFitWidth = true
        detailLabel.minimumScaleFactor = 0.76

        let labels = UIStackView(
            arrangedSubviews: [titleLabel, detailLabel],
            axis: .vertical,
            spacing: 1
        )
        let score = UILabel()
        score.applyWellnarioStyle(.bodyBold, color: color)
        score.textAlignment = .right
        score.text = L10n.text(
            "sleep.latest.quality.contribution",
            Int(contribution.rounded()),
            maximumContribution
        )
        score.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(
            arrangedSubviews: [labels, UIView(), score],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        row.accessibilityIdentifier = identifier
        row.isAccessibilityElement = true
        row.accessibilityLabel = [title, score.text, detail].compactMap { $0 }.joined(separator: ". ")
        return row
    }

    private func makeFactorCards() -> UIStackView {
        let cards = [
            makeFactorMenuCard(
                symbolName: "slider.horizontal.3",
                title: L10n.text("sleep.factors.manage.configure.title"),
                body: L10n.text("sleep.factors.manage.configure.body"),
                tone: WellnarioPalette.fuchsia,
                identifier: "sleep.factors.configure"
            ) { [weak self] in
                guard let self else { return }
                self.navigationController?.pushViewController(
                    SleepFactorConfigurationViewController(repository: self.repository),
                    animated: true
                )
            },
            makeFactorMenuCard(
                symbolName: "calendar.badge.plus",
                title: L10n.text("sleep.factors.manage.daily.title"),
                body: L10n.text("sleep.factors.manage.daily.body"),
                tone: WellnarioPalette.cyan,
                identifier: "sleep.factors.daily_log"
            ) { [weak self] in
                guard let self else { return }
                self.navigationController?.pushViewController(
                    SleepFactorDailyLogViewController(
                        appleHealthService: self.appleHealthService,
                        repository: self.repository
                    ),
                    animated: true
                )
            },
            makeFactorMenuCard(
                symbolName: "chart.line.uptrend.xyaxis",
                title: L10n.text("sleep.factors.manage.analysis.title"),
                body: L10n.text("sleep.factors.manage.analysis.body"),
                tone: WellnarioPalette.violet,
                identifier: "sleep.factors.analysis"
            ) { [weak self] in
                guard let self else { return }
                self.navigationController?.pushViewController(
                    SleepFactorAnalysisViewController(
                        appleHealthService: self.appleHealthService,
                        sleepManualOverrideStore: self.sleepManualOverrideStore,
                        repository: self.repository
                    ),
                    animated: true
                )
            }
        ]
        return UIStackView(
            arrangedSubviews: cards,
            axis: .vertical,
            spacing: WellnarioSpacing.cardGap
        )
    }

    private func makeFactorMenuCard(
        symbolName: String,
        title: String,
        body: String,
        tone: UIColor,
        identifier: String,
        action: @escaping () -> Void
    ) -> PremiumCardView {
        let symbol = UIImageView(image: UIImage(systemName: symbolName))
        symbol.tintColor = tone
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        symbol.widthAnchor.constraint(equalToConstant: 28).isActive = true
        symbol.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        titleLabel.text = title
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        bodyLabel.text = body
        bodyLabel.numberOfLines = 0

        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.tintColor = WellnarioPalette.textTertiary
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let labels = UIStackView(
            arrangedSubviews: [titleLabel, bodyLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        let row = UIStackView(
            arrangedSubviews: [symbol, labels, chevron],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = title
        button.accessibilityHint = body
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.addForAutoLayout(row)
        row.pinEdges(to: button, insets: .all(WellnarioSpacing.cardPadding))
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        let card = PremiumCardView()
        card.contentView.addForAutoLayout(button)
        button.pinEdges(to: card.contentView)
        return card
    }

    private func syncNow() {
        Task { try? await appleHealthService.sync() }
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openCardEditor() {
        let editor = SleepCardEditorViewController(preferences: cardLayoutPreferences)
        editor.onLayoutChange = { [weak self] in self?.buildContent() }
        navigationController?.pushViewController(editor, animated: true)
    }
    @objc private func appleHealthDidChange() { buildContent() }
    @objc private func sleepManualOverridesDidChange() { buildContent() }
    @objc private func sleepQualityPreferencesDidChange() { buildContent() }
    @objc private func trendPeriodDidChange() {
        guard let period = AppleHealthSleepTrendPeriod(rawValue: trendPeriodControl.selectedSegmentIndex) else {
            return
        }
        selectedTrendPeriod = period
        configureTrendChart(with: effectiveSnapshot())
    }
    @objc private func trendMetricDidChange() {
        guard let metric = TrendMetric(rawValue: trendMetricControl.selectedSegmentIndex) else {
            return
        }
        selectedTrendMetric = metric
        configureTrendChart(with: effectiveSnapshot())
    }
    @objc private func trendReferenceLineDidChange() {
        guard let referenceLine = WellnessTrendReferenceLine(
            rawValue: trendReferenceLineControl.selectedSegmentIndex
        ) else {
            return
        }
        selectedTrendReferenceLine = referenceLine
        defaults.set(referenceLine.rawValue, forKey: Self.trendReferenceLinePreferenceKey)
        trendChart.referenceLine = referenceLine
    }
}
