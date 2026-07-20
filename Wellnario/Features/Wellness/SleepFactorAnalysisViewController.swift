import UIKit

enum SleepFactorAnalysisDataBuilder {
    @MainActor
    static func impact(
        for definition: SleepFactorDefinition,
        outcome: SleepFactorOutcome,
        snapshot: AppleHealthSnapshot,
        log: [SleepFactorLogEntry],
        repository: WellnarioRepositoryProtocol? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SleepFactorImpact {
        let outcomeDays: [(date: Date, value: Double, sleepStartDate: Date?)] = snapshot.sleepTrend.compactMap { day in
            let value: Double?
            switch outcome {
            case .quality: value = day.qualityScore
            case .duration: value = day.hours
            }
            return value.map { (day.date, $0, day.sleepStartDate) }
        }

        if definition.source == .automatic {
            if SleepSupplementFactorCatalog.isSupplementFactor(definition.id) {
                guard let repository else { return .insufficient(sampleCount: 0) }
                let datedOutcomeDays = outcomeDays.map { day in
                    (
                        outcome: day,
                        sourceDay: SleepSupplementFactorCatalog.sourceDay(
                            sleepDate: day.date,
                            sleepStartDate: day.sleepStartDate,
                            calendar: calendar
                        )
                    )
                }
                guard let firstOutcomeDay = datedOutcomeDays.map({ $0.sourceDay }).min(),
                      let firstTrackedDay = SleepSupplementFactorCatalog.firstTrackedDay(
                        for: definition,
                        referenceDay: firstOutcomeDay,
                        repository: repository
                      ) else {
                    return .insufficient(sampleCount: 0)
                }
                var present: [Double] = []
                var absent: [Double] = []
                for item in datedOutcomeDays where item.sourceDay >= firstTrackedDay {
                    let day = item.outcome
                    guard let value = SleepSupplementFactorCatalog.value(
                        for: definition,
                        sleepDate: day.date,
                        sleepStartDate: day.sleepStartDate,
                        repository: repository,
                        calendar: calendar
                    ) else {
                        continue
                    }
                    if value > 0 {
                        present.append(day.value)
                    } else {
                        absent.append(day.value)
                    }
                }
                return SleepFactorStatistics.analyzeDiscrete(
                    presentValues: present,
                    absentValues: absent
                )
            }
            let automaticHistory = snapshot.automaticSleepFactors ?? []
            switch definition.valueKind {
            case .numeric:
                let points = outcomeDays.compactMap { day -> SleepFactorDataPoint? in
                    guard let automatic = automaticHistory.first(where: {
                        calendar.isDate($0.date, inSameDayAs: day.date)
                    }), let value = automatic.value(for: definition.id) else {
                        return nil
                    }
                    return SleepFactorDataPoint(x: value, y: day.value)
                }
                return SleepFactorStatistics.analyzeNumeric(
                    points,
                    analysisStep: definition.analysisStep
                )
            case .discrete:
                var present: [Double] = []
                var absent: [Double] = []
                for day in outcomeDays {
                    guard let automatic = automaticHistory.first(where: {
                        calendar.isDate($0.date, inSameDayAs: day.date)
                    }), let value = automatic.value(for: definition.id) else {
                        continue
                    }
                    if value > 0 {
                        present.append(day.value)
                    } else {
                        absent.append(day.value)
                    }
                }
                return SleepFactorStatistics.analyzeDiscrete(
                    presentValues: present,
                    absentValues: absent
                )
            }
        }

        let definitionEntries = log.filter { entry in
            if let factorID = entry.factorID { return factorID == definition.id }
            return entry.factor.localizedCaseInsensitiveCompare(definition.title) == .orderedSame
        }
        switch definition.valueKind {
        case .numeric:
            let points = outcomeDays.compactMap { day -> SleepFactorDataPoint? in
                guard let entry = definitionEntries.first(where: {
                    calendar.isDate($0.date, inSameDayAs: day.date)
                }), let value = entry.numericValue else {
                    return nil
                }
                return SleepFactorDataPoint(x: value, y: day.value)
            }
            return SleepFactorStatistics.analyzeNumeric(
                points,
                analysisStep: definition.analysisStep
            )
        case .discrete:
            guard let firstRecordDate = definitionEntries.map(\.date).min() else {
                return .insufficient(sampleCount: 0)
            }
            var present: [Double] = []
            var absent: [Double] = []
            outcomeDays
                .filter { calendar.startOfDay(for: $0.date) >= calendar.startOfDay(for: firstRecordDate) }
                .forEach { day in
                    let isPresent = definitionEntries.contains {
                        calendar.isDate($0.date, inSameDayAs: day.date)
                    }
                    if isPresent {
                        present.append(day.value)
                    } else {
                        absent.append(day.value)
                    }
                }
            return SleepFactorStatistics.analyzeDiscrete(
                presentValues: present,
                absentValues: absent
            )
        }
    }
}

@MainActor
final class SleepFactorAnalysisViewController: WellnessScrollViewController {
    private let appleHealthService: AppleHealthSyncing?
    private let sleepManualOverrideStore: SleepManualOverrideStore
    private let repository: WellnarioRepositoryProtocol?
    private let outcomeControl = UISegmentedControl(items: ["", ""])
    private let tabs = SleepFactorCategoryTabsView()
    private var selectedOutcome = SleepFactorOutcome.quality
    private var selectedCategory = SleepFactorCategory.automatic
    private var selectedQualityByWeekdayPeriod = AppleHealthSleepTrendPeriod.sevenDays
    private var areInsufficientFactorsExpanded = false
    private lazy var qualityByWeekdayPeriodControl = makeQualityByWeekdayPeriodControl()

    init(
        appleHealthService: AppleHealthSyncing? = nil,
        sleepManualOverrideStore: SleepManualOverrideStore = SleepManualOverrideStore(),
        repository: WellnarioRepositoryProtocol? = nil
    ) {
        self.appleHealthService = appleHealthService
        self.sleepManualOverrideStore = sleepManualOverrideStore
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("sleep.factors.manage.analysis.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "sleep.factors.analysis.root"
        configureControls()
        buildContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        buildContent()
    }

    private var effectiveSnapshot: AppleHealthSnapshot {
        sleepManualOverrideStore.applying(to: appleHealthService?.snapshot ?? .empty)
    }

    private var definitions: [SleepFactorDefinition] {
        WellnessLocalStore.enabledSleepFactorDefinitions(repository: repository).filter {
            $0.category == selectedCategory
        }
    }

    private func configureControls() {
        SleepFactorOutcome.allCases.forEach {
            outcomeControl.setTitle($0.title, forSegmentAt: $0.rawValue)
        }
        outcomeControl.selectedSegmentIndex = selectedOutcome.rawValue
        outcomeControl.selectedSegmentTintColor = WellnarioPalette.fuchsia
        outcomeControl.backgroundColor = WellnarioPalette.surface
        outcomeControl.setTitleTextAttributes([
            .foregroundColor: WellnarioPalette.textSecondary,
            .font: WellnarioTypography.font(for: .caption)
        ], for: .normal)
        outcomeControl.setTitleTextAttributes([
            .foregroundColor: UIColor.white,
            .font: WellnarioTypography.font(for: .caption)
        ], for: .selected)
        outcomeControl.addTarget(self, action: #selector(outcomeChanged), for: .valueChanged)
        outcomeControl.accessibilityIdentifier = "sleep.factors.analysis.outcome"

        tabs.onSelection = { [weak self] category in
            guard let self else { return }
            self.selectedCategory = category
            self.areInsufficientFactorsExpanded = false
            self.buildContent()
        }
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let snapshot = effectiveSnapshot
        contentStack.addArrangedSubview(outcomeControl)
        contentStack.addArrangedSubview(tabs)
        contentStack.addArrangedSubview(makeDisclaimer())

        if selectedCategory == .automatic {
            contentStack.addArrangedSubview(makeSleepMetricByWeekdayCard(snapshot: snapshot))
        }

        guard !definitions.isEmpty else {
            let label = UILabel()
            label.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
            label.text = L10n.text("sleep.factors.category.empty")
            label.numberOfLines = 0
            label.textAlignment = .center
            contentStack.addArrangedSubview(makeCard(
                containing: label,
                identifier: "sleep.factors.analysis.empty"
            ))
            return
        }

        let impacts = definitions.map { definition in
            (
                definition,
                SleepFactorAnalysisDataBuilder.impact(
                    for: definition,
                    outcome: selectedOutcome,
                    snapshot: snapshot,
                    log: WellnessLocalStore.sleepFactorLog,
                    repository: repository
                )
            )
        }
        let insufficient = impacts.filter { _, impact in
            if case .insufficient = impact { return true }
            return false
        }

        impacts.forEach { definition, impact in
            guard case .insufficient = impact else {
                contentStack.addArrangedSubview(makeImpactCard(
                    definition: definition,
                    impact: impact
                ))
                return
            }
        }
        if !insufficient.isEmpty {
            contentStack.addArrangedSubview(makeInsufficientFactorsCard(insufficient))
        }
    }

    private func makeSleepMetricByWeekdayCard(snapshot: AppleHealthSnapshot) -> PremiumCardView {
        let title = UILabel()
        title.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        title.text = L10n.text(
            "sleep.analysis.weekday.title",
            sleepMetricByWeekdayTitle
        )
        title.numberOfLines = 0

        let chart = WellnessTrendChartView()
        let summary = sleepMetricByWeekdaySummary(from: snapshot)
        chart.values = summary.values
        chart.labels = summary.labels
        chart.selectionLabels = summary.labels
        if selectedOutcome == .quality {
            chart.fixedBounds = WellnessTrendBounds(lower: 0, upper: 100)
        }
        chart.lineColor = sleepMetricByWeekdayColor
        chart.valueFormatter = sleepMetricByWeekdayValueFormatter
        chart.axisLabelFont = UIFont.systemFont(ofSize: 10, weight: .regular)
        chart.smoothingWindow = 1
        chart.usesStraightLineSegments = true
        chart.emptyText = L10n.text(
            "sleep.analysis.weekday.empty",
            sleepMetricByWeekdayTitle.lowercased()
        )
        chart.accessibilityIdentifier = "sleep.analysis.weekday.chart"
        chart.accessibilityHint = L10n.text("sleep.analysis.weekday.interaction.hint")
        chart.accessibilityLabel = L10n.text(
            "sleep.analysis.weekday.accessibility",
            sleepMetricByWeekdayTitle,
            sleepTrendPeriodTitle(selectedQualityByWeekdayPeriod)
        )

        qualityByWeekdayPeriodControl.selectedSegmentIndex = selectedQualityByWeekdayPeriod.rawValue
        let stack = UIStackView(
            arrangedSubviews: [title, chart, qualityByWeekdayPeriodControl],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        return makeCard(
            containing: stack,
            identifier: "sleep.analysis.weekday.card"
        )
    }

    private func makeQualityByWeekdayPeriodControl() -> UISegmentedControl {
        let control = UISegmentedControl(
            items: AppleHealthSleepTrendPeriod.allCases.map(sleepTrendPeriodTitle)
        )
        control.selectedSegmentIndex = selectedQualityByWeekdayPeriod.rawValue
        control.apportionsSegmentWidthsByContent = true
        control.selectedSegmentTintColor = WellnarioPalette.fuchsia
        control.backgroundColor = WellnarioPalette.surface
        control.setTitleTextAttributes([
            .foregroundColor: WellnarioPalette.textSecondary,
            .font: WellnarioTypography.font(for: .caption)
        ], for: .normal)
        control.setTitleTextAttributes([
            .foregroundColor: UIColor.white,
            .font: WellnarioTypography.font(for: .caption)
        ], for: .selected)
        control.accessibilityIdentifier = "sleep.analysis.weekday.period"
        control.accessibilityLabel = L10n.text(
            "sleep.analysis.weekday.period.selector.accessibility"
        )
        control.addTarget(self, action: #selector(qualityByWeekdayPeriodChanged), for: .valueChanged)
        return control
    }

    private func sleepMetricByWeekdaySummary(
        from snapshot: AppleHealthSnapshot,
        calendar: Calendar = .autoupdatingCurrent
    ) -> (values: [Double?], labels: [String]) {
        let series = AppleHealthSleepAggregator.trendSeries(
            from: snapshot.sleepTrend,
            period: selectedQualityByWeekdayPeriod,
            calendar: calendar
        )
        var valuesByWeekday: [Int: [Double]] = [:]
        for entry in series.dailyEntries {
            let value: Double?
            switch selectedOutcome {
            case .quality: value = entry.qualityScore
            case .duration: value = entry.hours
            }
            guard let value else { continue }
            let weekday = calendar.component(.weekday, from: entry.date)
            valuesByWeekday[weekday, default: []].append(value)
        }

        let weekdayOrder = orderedWeekdays(calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        let symbols = formatter.shortWeekdaySymbols ?? []
        let labels = weekdayOrder.map { weekday in
            guard symbols.indices.contains(weekday - 1) else { return "" }
            return symbols[weekday - 1].capitalized(with: formatter.locale)
        }
        let values = weekdayOrder.map { weekday -> Double? in
            guard let samples = valuesByWeekday[weekday], !samples.isEmpty else { return nil }
            return samples.reduce(0, +) / Double(samples.count)
        }
        return (values, labels)
    }

    private func orderedWeekdays(calendar: Calendar) -> [Int] {
        let firstWeekday = min(max(calendar.firstWeekday, 1), 7)
        return Array(firstWeekday...7) + Array(1..<firstWeekday)
    }

    private var sleepMetricByWeekdayTitle: String {
        switch selectedOutcome {
        case .quality: L10n.text("sleep.trend.metric.quality")
        case .duration: L10n.text("sleep.trend.metric.duration")
        }
    }

    private var sleepMetricByWeekdayColor: UIColor {
        switch selectedOutcome {
        case .quality: WellnarioPalette.pink
        case .duration: WellnarioPalette.violet
        }
    }

    private var sleepMetricByWeekdayValueFormatter: (Double) -> String {
        switch selectedOutcome {
        case .quality:
            { AppleHealthUIFormatting.number($0, maximumFractionDigits: 0) }
        case .duration:
            { value in
                L10n.text(
                    "sleep.trend.hours.short",
                    AppleHealthUIFormatting.number(value, maximumFractionDigits: 1)
                )
            }
        }
    }

    private func sleepTrendPeriodTitle(_ period: AppleHealthSleepTrendPeriod) -> String {
        switch period {
        case .sevenDays: L10n.text("sleep.trend.period.7d")
        case .thirtyDays: L10n.text("sleep.trend.period.30d")
        case .sixMonths: L10n.text("sleep.trend.period.6m")
        case .allTime: L10n.text("sleep.trend.period.all")
        }
    }

    private func makeInsufficientFactorsCard(
        _ factors: [(SleepFactorDefinition, SleepFactorImpact)]
    ) -> PremiumCardView {
        let title = UILabel()
        title.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        title.text = L10n.text("sleep.factors.analysis.insufficient.group.title")
        title.numberOfLines = 0

        let count = UILabel()
        count.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        count.text = L10n.text("sleep.factors.analysis.insufficient.group.count", factors.count)

        let chevron = UIImageView()
        chevron.tintColor = WellnarioPalette.textTertiary
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 13,
            weight: .semibold
        )
        chevron.image = UIImage(systemName: areInsufficientFactorsExpanded
            ? "chevron.up"
            : "chevron.down")

        let header = UIStackView(
            arrangedSubviews: [title, UIView(), count, chevron],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        header.isUserInteractionEnabled = false

        let toggle = UIButton(type: .system)
        toggle.addForAutoLayout(header)
        header.pinEdges(
            to: toggle,
            insets: NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)
        )
        toggle.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        toggle.accessibilityIdentifier = "sleep.factors.analysis.insufficient_group.toggle"
        toggle.accessibilityLabel = title.text
        toggle.accessibilityValue = L10n.text(
            areInsufficientFactorsExpanded ? "accessibility.collapse" : "accessibility.expand"
        )
        toggle.addTarget(self, action: #selector(toggleInsufficientFactors), for: .touchUpInside)

        let details = UIStackView()
        details.axis = .vertical
        details.spacing = WellnarioSpacing.small
        details.isHidden = !areInsufficientFactorsExpanded
        for (index, factor) in factors.enumerated() {
            if index > 0 {
                let separator = UIView()
                separator.backgroundColor = WellnarioPalette.hairline
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                details.addArrangedSubview(separator)
            }
            let factorTitle = UILabel()
            factorTitle.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
            factorTitle.text = factor.0.title
            factorTitle.numberOfLines = 0

            let explanation = UILabel()
            explanation.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
            explanation.text = explanationText(definition: factor.0, impact: factor.1)
            explanation.numberOfLines = 0
            details.addArrangedSubview(UIStackView(
                arrangedSubviews: [factorTitle, explanation],
                axis: .vertical,
                spacing: 2
            ))
        }

        return makeCard(
            containing: UIStackView(
                arrangedSubviews: [toggle, details],
                axis: .vertical,
                spacing: WellnarioSpacing.xSmall
            ),
            identifier: "sleep.factors.analysis.insufficient_group"
        )
    }

    private func makeDisclaimer() -> FeedbackBannerView {
        let banner = FeedbackBannerView()
        banner.configure(
            message: L10n.text("sleep.factors.analysis.disclaimer"),
            tone: .information
        )
        // Match the blue, translucent advice/status cards used for Apple
        // Health synchronization, while keeping the banner non-interactive.
        banner.backgroundOpacityOverride = WellnarioPalette.synchronizationBannerOpacity
        banner.accessibilityIdentifier = "sleep.factors.analysis.disclaimer"
        return banner
    }

    private func makeImpactCard(
        definition: SleepFactorDefinition,
        impact: SleepFactorImpact
    ) -> PremiumCardView {
        let title = UILabel()
        title.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        title.text = definition.title
        title.numberOfLines = 0

        let method = UILabel()
        method.applyWellnarioStyle(.caption, color: WellnarioPalette.fuchsia)
        method.text = methodText(impact)
        method.numberOfLines = 0
        method.textAlignment = .right

        let header = UIStackView(
            arrangedSubviews: [title, UIView(), method],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .firstBaseline
        )
        let explanation = UILabel()
        explanation.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        explanation.text = explanationText(definition: definition, impact: impact)
        explanation.numberOfLines = 0

        var views: [UIView] = [header]
        if case let .numeric(numericImpact) = impact {
            let chart = SleepFactorRelationshipChartView()
            chart.impact = numericImpact
            chart.xUnit = definition.valueKind.unit
            chart.xLowerBound = definition.chartMinimumValue
            chart.xUpperBound = definition.chartMaximumValue
            chart.yFormatter = { [selectedOutcome] value in
                switch selectedOutcome {
                case .quality: return String(Int(value.rounded()))
                case .duration: return String(format: "%.1f h", value)
                }
            }
            chart.accessibilityIdentifier = "sleep.factors.analysis.chart.\(definition.id)"
            views.append(chart)
        }
        views.append(explanation)
        let stack = UIStackView(
            arrangedSubviews: views,
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        return makeCard(
            containing: stack,
            identifier: "sleep.factors.analysis.factor.\(definition.id)"
        )
    }

    private func methodText(_ impact: SleepFactorImpact) -> String {
        switch impact {
        case let .numeric(result):
            switch result.model {
            case .linear: return L10n.text("sleep.factors.analysis.method.linear")
            case .quadratic: return L10n.text("sleep.factors.analysis.method.quadratic")
            }
        case .discrete:
            return L10n.text("sleep.factors.analysis.method.hypothesis")
        case .insufficient:
            return L10n.text("sleep.factors.analysis.method.pending")
        }
    }

    private func explanationText(
        definition: SleepFactorDefinition,
        impact: SleepFactorImpact
    ) -> String {
        let outcome = selectedOutcome.title.lowercased()
        switch impact {
        case let .numeric(result):
            let confidence = Int((result.confidence * 100).rounded())
            if result.model == .quadratic {
                if let optimum = result.optimumX {
                    return L10n.text(
                        "sleep.factors.analysis.quadratic.with_vertex",
                        definition.title,
                        outcome,
                        formattedNumber(optimum),
                        definition.valueKind.unit ?? "",
                        confidence
                    )
                }
                return L10n.text(
                    "sleep.factors.analysis.quadratic",
                    definition.title,
                    outcome,
                    confidence
                )
            }
            let key = result.effectPercentPerStep >= 0
                ? "sleep.factors.analysis.numeric.positive"
                : "sleep.factors.analysis.numeric.negative"
            let sign = result.effectPercentPerStep >= 0 ? "positive" : "negative"
            if definition.id == SleepFactorCatalog.automaticStepsID {
                return L10n.text(
                    "sleep.factors.analysis.steps.\(sign)",
                    definition.analysisStepLabel,
                    outcome,
                    abs(result.effectPercentPerStep),
                    confidence
                )
            }
            if definition.id == SleepFactorCatalog.automaticDaylightMinutesID
                || definition.id == SleepFactorCatalog.automaticEarlyDaylightMinutesID {
                return L10n.text(
                    "sleep.factors.analysis.sunlight.\(sign)",
                    outcome,
                    abs(result.effectPercentPerStep),
                    confidence
                )
            }
            return L10n.text(
                key,
                definition.analysisStepLabel,
                definition.title,
                outcome,
                abs(result.effectPercentPerStep),
                confidence
            )
        case let .discrete(result):
            let key = result.effectPercent >= 0
                ? "sleep.factors.analysis.discrete.positive"
                : "sleep.factors.analysis.discrete.negative"
            let effectText = L10n.text(
                key,
                definition.title,
                outcome,
                abs(result.effectPercent),
                Int((result.confidence * 100).rounded())
            )
            let groupsKey = SleepSupplementFactorCatalog.isSupplementFactor(definition.id)
                ? "sleep.factors.analysis.discrete.supplement_groups"
                : "sleep.factors.analysis.discrete.factor_groups"
            let groupsText = L10n.text(
                groupsKey,
                result.presentSampleCount,
                result.absentSampleCount
            )
            return effectText + " " + groupsText
        case let .insufficient(sampleCount, presentSampleCount, absentSampleCount):
            if SleepSupplementFactorCatalog.isSupplementFactor(definition.id),
               let presentSampleCount,
               let absentSampleCount {
                return L10n.text(
                    "sleep.factors.analysis.insufficient.supplement_groups",
                    presentSampleCount,
                    absentSampleCount,
                    SleepFactorStatistics.minimumDiscreteGroupSamples
                )
            }
            return L10n.text(
                "sleep.factors.analysis.insufficient",
                sampleCount
            )
        }
    }

    private func formattedNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    @objc private func outcomeChanged() {
        guard let outcome = SleepFactorOutcome(rawValue: outcomeControl.selectedSegmentIndex) else {
            return
        }
        selectedOutcome = outcome
        areInsufficientFactorsExpanded = false
        buildContent()
    }

    @objc private func qualityByWeekdayPeriodChanged() {
        guard let period = AppleHealthSleepTrendPeriod(rawValue: qualityByWeekdayPeriodControl.selectedSegmentIndex) else {
            return
        }
        selectedQualityByWeekdayPeriod = period
        buildContent()
    }

    @objc private func toggleInsufficientFactors() {
        areInsufficientFactorsExpanded.toggle()
        buildContent()
    }
}

@MainActor
final class SleepFactorRelationshipChartView: UIView {
    var impact: SleepFactorNumericImpact? { didSet { setNeedsDisplay() } }
    var xUnit: String? { didSet { setNeedsDisplay() } }
    var xLowerBound: Double? { didSet { setNeedsDisplay() } }
    var xUpperBound: Double? { didSet { setNeedsDisplay() } }
    var yFormatter: (Double) -> String = { String(format: "%.1f", $0) } {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 184)
    }

    override func draw(_ rect: CGRect) {
        guard let impact, !impact.points.isEmpty else { return }
        let plot = rect.inset(by: UIEdgeInsets(top: 14, left: 48, bottom: 30, right: 10))
        let xs = impact.points.map(\.x)
        let predictionXs = (0...60).map { index in
            (xs.min() ?? 0) + ((xs.max() ?? 0) - (xs.min() ?? 0)) * Double(index) / 60
        }
        let predictions = predictionXs.map(impact.predictedValue(at:))
        let ys = impact.points.map(\.y) + predictions
        guard let rawMinX = xs.min(), let rawMaxX = xs.max(),
              let rawMinY = ys.min(), let rawMaxY = ys.max() else {
            return
        }
        let yPadding = max((rawMaxY - rawMinY) * 0.10, 0.5)
        let xDomain = Self.xDomain(
            minimum: rawMinX,
            maximum: rawMaxX,
            lowerBound: xLowerBound,
            upperBound: xUpperBound
        )
        let minX = xDomain.lowerBound
        let maxX = xDomain.upperBound
        let minY = rawMinY - yPadding
        let maxY = rawMaxY + yPadding

        drawGrid(in: plot)
        drawLabels(
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            in: plot
        )
        func point(x: Double, y: Double) -> CGPoint {
            CGPoint(
                x: plot.minX + plot.width * CGFloat((x - minX) / (maxX - minX)),
                y: plot.maxY - plot.height * CGFloat((y - minY) / (maxY - minY))
            )
        }

        // Draw the samples first. The fitted line is the analytical result
        // and must remain visible when it crosses a sample, so it is painted
        // last and therefore overwrites the points underneath it.
        impact.points.forEach { sample in
            let position = point(x: sample.x, y: sample.y)
            WellnarioPalette.cyan.withAlphaComponent(0.25).setFill()
            UIBezierPath(ovalIn: CGRect(
                x: position.x - 6,
                y: position.y - 6,
                width: 12,
                height: 12
            )).fill()
            WellnarioPalette.cyan.setFill()
            UIBezierPath(ovalIn: CGRect(
                x: position.x - 3,
                y: position.y - 3,
                width: 6,
                height: 6
            )).fill()
        }

        let curve = UIBezierPath()
        predictionXs.enumerated().forEach { index, x in
            let position = point(x: x, y: predictions[index])
            index == 0 ? curve.move(to: position) : curve.addLine(to: position)
        }
        WellnarioPalette.fuchsia.setStroke()
        curve.lineWidth = 3
        curve.lineCapStyle = .round
        curve.lineJoinStyle = .round
        curve.stroke()
    }

    private func setUp() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = L10n.text("sleep.factors.analysis.chart.accessibility")
    }

    private func drawGrid(in rect: CGRect) {
        for index in 0...3 {
            let y = rect.minY + rect.height * CGFloat(index) / 3
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            path.setLineDash([2, 5], count: 2, phase: 0)
            WellnarioPalette.hairline.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawLabels(
        minX: Double,
        maxX: Double,
        minY: Double,
        maxY: Double,
        in rect: CGRect
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: WellnarioTypography.font(for: .caption),
            .foregroundColor: WellnarioPalette.textSecondary
        ]
        let yLabels = [(maxY, rect.minY), (minY, rect.maxY)]
        yLabels.forEach { value, y in
            let text = yFormatter(value)
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: rect.minX - size.width - 7, y: y - size.height / 2),
                withAttributes: attributes
            )
        }
        let minText = formattedX(minX)
        let maxText = formattedX(maxX)
        minText.draw(
            at: CGPoint(x: rect.minX, y: rect.maxY + 8),
            withAttributes: attributes
        )
        let maxSize = maxText.size(withAttributes: attributes)
        maxText.draw(
            at: CGPoint(x: rect.maxX - maxSize.width, y: rect.maxY + 8),
            withAttributes: attributes
        )
    }

    private func formattedX(_ value: Double) -> String {
        let number = value.rounded() == value
            ? String(Int(value))
            : String(format: "%.1f", value)
        guard let xUnit, !xUnit.isEmpty else { return number }
        return "\(number) \(xUnit)"
    }

    static func xDomain(
        minimum rawMinimum: Double,
        maximum rawMaximum: Double,
        lowerBound: Double?,
        upperBound: Double?
    ) -> ClosedRange<Double> {
        let span = max(rawMaximum - rawMinimum, 0)
        let padding = max(span * 0.05, 0.5)
        let minimum = lowerBound ?? (rawMinimum - padding)
        let minimumSpan = max(span * 0.1, 0.5)
        // An explicit upper bound is a hard semantic limit (for example,
        // StressScore is 0–100), not merely a hint for extra chart padding.
        // Keeping the padding above that bound produced labels such as
        // 102.1%, which contradicts the factor's scale.
        let maximum = upperBound ?? max(rawMaximum + padding, minimum + minimumSpan)
        return minimum...maximum
    }
}
