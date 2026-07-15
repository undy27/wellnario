import UIKit

@MainActor
final class SleepViewController: WellnessScrollViewController {
    private static let trendReferenceLinePreferenceKey = "wellnario.sleep.trend.referenceLine"
    private static let sourceBannerHeight: CGFloat = 76

    private enum TrendMetric: Int, CaseIterable {
        case quality
        case duration
        case rem
        case deep
        case light
    }

    var onOpenSettings: (() -> Void)?

    private let appleHealthService: AppleHealthSyncing
    private let defaults: UserDefaults
    private let sourceBanner = FeedbackBannerView()
    private let trendChart = WellnessTrendChartView()
    private var isSourceBannerVisible = false
    private var appliedSourceBannerInset: CGFloat = 0
    private var selectedTrendPeriod = AppleHealthSleepTrendPeriod.sevenDays
    private var selectedTrendMetric = TrendMetric.duration
    private var selectedTrendReferenceLine: WellnessTrendReferenceLine
    private lazy var trendPeriodControl: UISegmentedControl = makeTrendPeriodControl()
    private lazy var trendMetricControl: UISegmentedControl = makeTrendMetricControl()
    private lazy var trendReferenceLineControl: UISegmentedControl = makeTrendReferenceLineControl()

    init(appleHealthService: AppleHealthSyncing, defaults: UserDefaults = .standard) {
        self.appleHealthService = appleHealthService
        self.defaults = defaults
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = L10n.Settings.title
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appleHealthDidChange),
            name: .appleHealthSyncDidChange,
            object: appleHealthService
        )
        setUpSourceBanner()
        buildContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateScrollInsetsForSourceBanner()
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let snapshot = appleHealthService.snapshot

        updateSourceBanner(snapshot: snapshot)
        contentStack.addArrangedSubview(makeSectionTitle(
            L10n.text("sleep.latest.title"),
            detail: L10n.text("sleep.latest.detail")
        ))
        let latestSessionCard = makeLatestSessionCard(snapshot.latestSleepSession)
        contentStack.addArrangedSubview(latestSessionCard)
        contentStack.setCustomSpacing(WellnarioSpacing.large, after: latestSessionCard)
        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("sleep.trend.title")))

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
        let chartCard = PremiumCardView()
        chartCard.accessibilityIdentifier = "sleep.trend.card"
        chartCard.contentView.addForAutoLayout(trendContent)
        trendContent.pinEdges(
            to: chartCard.contentView,
            insets: NSDirectionalEdgeInsets(top: 16, leading: 8, bottom: 16, trailing: 8)
        )
        contentStack.addArrangedSubview(chartCard)

        contentStack.setCustomSpacing(WellnarioSpacing.large, after: chartCard)
        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("sleep.factors.title")))
        contentStack.addArrangedSubview(makeFactorCard())
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
            isSourceBannerVisible = false
            sourceBanner.isHidden = true
            view.setNeedsLayout()
            return
        }

        isSourceBannerVisible = true
        sourceBanner.isHidden = false
        configureSourceBanner(sourceBanner, snapshot: snapshot)
        view.bringSubviewToFront(sourceBanner)
        view.setNeedsLayout()
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
                actionTitle: L10n.text("apple_health.sync_now")
            )
            banner.onAction = { [weak self] in self?.syncNow() }
        case .ready:
            let message = snapshot.lastSyncedAt.map(AppleHealthUIFormatting.syncedAt)
                ?? L10n.text("apple_health.configured")
            banner.configure(
                message: message,
                tone: .success,
                actionTitle: L10n.text("apple_health.sync_now")
            )
            banner.onAction = { [weak self] in self?.syncNow() }
        }
    }

    private func makeLatestSessionCard(_ session: AppleHealthSleepSession?) -> PremiumCardView {
        let moon = UIImageView(image: UIImage(systemName: "moon.stars.fill"))
        moon.tintColor = WellnarioPalette.violet
        moon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 29, weight: .semibold)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = session.map { AppleHealthUIFormatting.duration($0.asleepSeconds) }
            ?? L10n.text("sleep.latest.empty.title")
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        if let session {
            let range = AppleHealthUIFormatting.sleepRange(session)
            let sources = session.sourceNames.joined(separator: ", ")
            bodyLabel.text = sources.isEmpty
                ? range
                : L10n.text("apple_health.sleep.range_source", range, sources)
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
        timeline.configure(session: session)
        let timelineSection = UIStackView(
            arrangedSubviews: [timelineTitle, timeline],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )

        let content = UIStackView(
            arrangedSubviews: [summary, separator, timelineSection],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
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

    private func makeFactorCard() -> PremiumCardView {
        let lastFactor = WellnessLocalStore.lastSleepFactor
        let icon = UIImageView(image: UIImage(systemName: "text.badge.plus"))
        icon.tintColor = WellnarioPalette.cyan
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        titleLabel.text = lastFactor ?? L10n.text("sleep.factors.empty.title")
        let detailLabel = UILabel()
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detailLabel.text = lastFactor == nil
            ? L10n.text("sleep.factors.empty.body")
            : L10n.text("sleep.factors.last_logged")
        detailLabel.numberOfLines = 0

        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel], axis: .vertical, spacing: 4)
        let stack = UIStackView(
            arrangedSubviews: [icon, labels],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        let card = makeCard(containing: stack, identifier: "sleep.factor.summary")
        card.isAccessibilityElement = true
        card.accessibilityLabel = [titleLabel.text, detailLabel.text].compactMap { $0 }.joined(separator: ". ")
        return card
    }

    private func syncNow() {
        Task { try? await appleHealthService.sync() }
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func appleHealthDidChange() { buildContent() }
    @objc private func trendPeriodDidChange() {
        guard let period = AppleHealthSleepTrendPeriod(rawValue: trendPeriodControl.selectedSegmentIndex) else {
            return
        }
        selectedTrendPeriod = period
        configureTrendChart(with: appleHealthService.snapshot)
    }
    @objc private func trendMetricDidChange() {
        guard let metric = TrendMetric(rawValue: trendMetricControl.selectedSegmentIndex) else {
            return
        }
        selectedTrendMetric = metric
        configureTrendChart(with: appleHealthService.snapshot)
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
