import UIKit

@MainActor
final class SleepViewController: WellnessScrollViewController {
    var onOpenSettings: (() -> Void)?

    private let appleHealthService: AppleHealthSyncing
    private let trendChart = WellnessTrendChartView()
    private var selectedTrendPeriod = AppleHealthSleepTrendPeriod.sevenDays
    private lazy var trendPeriodControl: UISegmentedControl = makeTrendPeriodControl()

    init(appleHealthService: AppleHealthSyncing) {
        self.appleHealthService = appleHealthService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("sleep.title")
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
        buildContent()
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let snapshot = appleHealthService.snapshot

        contentStack.addArrangedSubview(makeSourceBanner(snapshot: snapshot))
        contentStack.addArrangedSubview(makeSectionTitle(
            L10n.text("sleep.latest.title"),
            detail: L10n.text("sleep.latest.detail")
        ))
        contentStack.addArrangedSubview(makeLatestSessionCard(snapshot.latestSleepSession))

        let session = snapshot.latestSleepSession
        let metrics = [
            makeMiniMetric(
                title: L10n.text("sleep.deep"),
                value: stageValue(session?.deepSeconds),
                detail: stageDetail(session?.deepSeconds),
                symbol: "circle.bottomhalf.filled",
                tone: WellnarioPalette.violet
            ),
            makeMiniMetric(
                title: L10n.text("sleep.rem"),
                value: stageValue(session?.remSeconds),
                detail: stageDetail(session?.remSeconds),
                symbol: "brain.head.profile",
                tone: WellnarioPalette.magenta
            )
        ]
        let metricRow = UIStackView(
            arrangedSubviews: metrics,
            axis: .horizontal,
            spacing: WellnarioSpacing.cardGap,
            alignment: .fill,
            distribution: .fillEqually
        )
        metrics[0].widthAnchor.constraint(equalTo: metrics[1].widthAnchor).isActive = true
        contentStack.addArrangedSubview(metricRow)

        contentStack.setCustomSpacing(WellnarioSpacing.large, after: metricRow)
        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("sleep.trend.title")))

        configureTrendChart(with: snapshot)
        let trendContent = UIStackView(
            arrangedSubviews: [trendChart, trendPeriodControl],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        let chartCard = makeCard(containing: trendContent, identifier: "sleep.trend.card")
        contentStack.addArrangedSubview(chartCard)

        contentStack.setCustomSpacing(WellnarioSpacing.large, after: chartCard)
        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("sleep.factors.title")))
        contentStack.addArrangedSubview(makeFactorCard())
    }

    private func configureTrendChart(with snapshot: AppleHealthSnapshot) {
        let trend = AppleHealthSleepAggregator.trend(
            from: snapshot.sleepTrend,
            period: selectedTrendPeriod
        )
        trendChart.values = trend.map(\.hours)
        trendChart.labels = trendLabels(for: trend, period: selectedTrendPeriod)
        trendChart.lineColor = WellnarioPalette.violet
        trendChart.emptyText = L10n.text("sleep.trend.empty")
        trendChart.accessibilityIdentifier = "sleep.trend.chart"
        trendChart.accessibilityLabel = L10n.text(
            "sleep.trend.accessibility.format",
            trendPeriodTitle(selectedTrendPeriod)
        )
        trendChart.accessibilityValue = trend.compactMap(\.hours).isEmpty
            ? L10n.text("sleep.trend.empty")
            : trendChart.accessibilityLabel
    }

    private func makeTrendPeriodControl() -> UISegmentedControl {
        let control = UISegmentedControl(items: AppleHealthSleepTrendPeriod.allCases.map(trendPeriodTitle))
        control.selectedSegmentIndex = selectedTrendPeriod.rawValue
        control.apportionsSegmentWidthsByContent = true
        control.selectedSegmentTintColor = WellnarioPalette.violet
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

    private func trendPeriodTitle(_ period: AppleHealthSleepTrendPeriod) -> String {
        switch period {
        case .sevenDays: L10n.text("sleep.trend.period.7d")
        case .thirtyDays: L10n.text("sleep.trend.period.30d")
        case .sixMonths: L10n.text("sleep.trend.period.6m")
        case .allTime: L10n.text("sleep.trend.period.all")
        }
    }

    private func trendLabels(
        for trend: [AppleHealthSleepDay],
        period: AppleHealthSleepTrendPeriod
    ) -> [String] {
        guard !trend.isEmpty else { return [] }
        if period == .sevenDays {
            return trend.map { AppleHealthUIFormatting.weekdayInitial(for: $0.date) }
        }

        let labelCount = min(5, trend.count)
        let indexes = Set((0..<labelCount).map { labelIndex in
            guard labelCount > 1 else { return 0 }
            return Int((Double(labelIndex) * Double(trend.count - 1) / Double(labelCount - 1)).rounded())
        })
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        let spansMoreThanAYear = (trend.last?.date.timeIntervalSince(trend.first?.date ?? Date()) ?? 0)
            >= 365 * 24 * 60 * 60
        formatter.setLocalizedDateFormatFromTemplate(spansMoreThanAYear ? "MMMyy" : "dMMM")
        return trend.enumerated().map { index, entry in
            indexes.contains(index) ? formatter.string(from: entry.date) : ""
        }
    }

    private func makeSourceBanner(snapshot: AppleHealthSnapshot) -> FeedbackBannerView {
        let banner = FeedbackBannerView()
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
        return banner
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
        let content = UIStackView(
            arrangedSubviews: [iconContainer, text],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        let card = makeCard(containing: content, identifier: "sleep.latest.card")
        card.showsAccent = true
        card.isAccessibilityElement = true
        card.accessibilityLabel = [titleLabel.text, bodyLabel.text].compactMap { $0 }.joined(separator: ". ")
        return card
    }

    private func makeMiniMetric(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tone: UIColor
    ) -> PremiumCardView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = tone
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        titleLabel.text = title
        titleLabel.numberOfLines = 2
        let valueLabel = UILabel()
        valueLabel.applyWellnarioStyle(.metric, color: WellnarioPalette.textPrimary)
        valueLabel.text = value
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.72
        let detailLabel = UILabel()
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        detailLabel.text = detail
        detailLabel.numberOfLines = 2

        let heading = UIStackView(
            arrangedSubviews: [titleLabel, UIView(), icon],
            axis: .horizontal,
            spacing: 6,
            alignment: .top
        )
        let stack = UIStackView(arrangedSubviews: [heading, valueLabel, detailLabel], axis: .vertical, spacing: 6)
        let card = makeCard(containing: stack)
        card.isAccessibilityElement = true
        card.accessibilityLabel = title
        card.accessibilityValue = [value, detail].joined(separator: ", ")
        return card
    }

    private func stageValue(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        return AppleHealthUIFormatting.duration(seconds)
    }

    private func stageDetail(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds > 0 else { return L10n.text("sleep.no_data") }
        return L10n.text("sleep.from_apple_health")
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
}
