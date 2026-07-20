import UIKit

@MainActor
final class BiomarkerTrendsViewController: WellnessScrollViewController {
    private enum Period: Int, CaseIterable {
        case lastYear
        case allTime
    }

    private static let referenceLinePreferenceKey = "wellnario.biomarkers.trend.referenceLine"

    private let store: HealthDataStore
    private let defaults: UserDefaults
    private let favoritesSummary = FavoriteBiomarkerAnalysesSummaryView()
    private let biomarkerField = SelectionFieldView()
    private let chartCard = PremiumCardView()
    private let chartView = WellnessTrendChartView()
    private let chartTitleLabel = UILabel()
    private var biomarkers: [HealthBiomarker] = []
    private var selectedBiomarkerID: UUID?
    private var selectedPeriod: Period = .allTime
    private var selectedReferenceLine: WellnessTrendReferenceLine
    private lazy var periodControl = makePeriodControl()
    private lazy var referenceLineControl = makeReferenceLineControl()

    init(store: HealthDataStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        let storedReference = defaults.object(forKey: Self.referenceLinePreferenceKey) as? Int
        selectedReferenceLine = storedReference
            .flatMap(WellnessTrendReferenceLine.init(rawValue:))
            ?? .linearTrend
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal
        view.accessibilityIdentifier = "health.biomarker_trends.root"
        configureContent()
        reloadContent()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: LocalizationManager.didChangeNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        reloadContent()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureContent() {
        biomarkerField.title = ""
        biomarkerField.accessibilityIdentifier = "health.biomarker_trends.selector"
        biomarkerField.button.accessibilityIdentifier = "health.biomarker_trends.selector.button"

        contentStack.addArrangedSubview(favoritesSummary)
        contentStack.setCustomSpacing(WellnarioSpacing.medium, after: favoritesSummary)
        contentStack.addArrangedSubview(chartCard)

        chartTitleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        chartTitleLabel.text = L10n.text("health.biomarker_trends.chart.title")
        let chartIcon = UIImageView(image: UIImage(systemName: "chart.xyaxis.line"))
        chartIcon.tintColor = WellnarioPalette.fuchsia
        let header = UIStackView(
            arrangedSubviews: [chartTitleLabel, UIView(), chartIcon],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )

        chartView.heightAnchor.constraint(equalToConstant: 190).isActive = true
        chartView.accessibilityIdentifier = "health.biomarker_trends.chart"
        chartView.lineColor = WellnarioPalette.fuchsia
        chartView.averageColor = WellnarioPalette.cyan
        chartView.smoothingWindow = 1

        let referenceContainer = UIView()
        referenceContainer.addForAutoLayout(referenceLineControl)
        NSLayoutConstraint.activate([
            referenceLineControl.topAnchor.constraint(equalTo: referenceContainer.topAnchor),
            referenceLineControl.bottomAnchor.constraint(equalTo: referenceContainer.bottomAnchor),
            referenceLineControl.centerXAnchor.constraint(equalTo: referenceContainer.centerXAnchor),
            referenceLineControl.widthAnchor.constraint(equalToConstant: 180),
            referenceLineControl.heightAnchor.constraint(equalToConstant: 28)
        ])

        let stack = UIStackView(
            arrangedSubviews: [header, biomarkerField, referenceContainer, chartView, periodControl],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        chartCard.contentView.addForAutoLayout(stack)
        stack.pinEdges(
            to: chartCard.contentView,
            insets: NSDirectionalEdgeInsets(top: 16, leading: 8, bottom: 16, trailing: 8)
        )
    }

    private func reloadContent() {
        title = L10n.text("health.biomarker_trends.title")
        chartTitleLabel.text = L10n.text("health.biomarker_trends.chart.title")
        biomarkers = store.biomarkers().sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        ensureSelectedBiomarker()
        rebuildBiomarkerMenu()
        favoritesSummary.configure(
            favorites: biomarkers.filter(\.isFavorite),
            analyses: store.analyses()
        )
        configureChart()
    }

    private func ensureSelectedBiomarker() {
        guard biomarkers.contains(where: { $0.id == selectedBiomarkerID }) else {
            let withMeasurements = biomarkers.filter { !store.measurements(for: $0.id).isEmpty }
            selectedBiomarkerID = withMeasurements.first(where: \.isFavorite)?.id
                ?? withMeasurements.first?.id
                ?? biomarkers.first?.id
            return
        }
    }

    private func rebuildBiomarkerMenu() {
        guard let selected = biomarkers.first(where: { $0.id == selectedBiomarkerID }) else {
            biomarkerField.value = L10n.text("health.biomarker_trends.selector.placeholder")
            biomarkerField.leadingImage = nil
            biomarkerField.menu = nil
            return
        }

        biomarkerField.value = selected.name
        biomarkerField.leadingImage = selected.imageKey.flatMap(UIImage.init(named:))
            ?? UIImage(systemName: selected.sampleType.symbolName)
        biomarkerField.menu = UIMenu(children: biomarkers.map { biomarker in
            UIAction(
                title: biomarker.name,
                image: biomarker.imageKey.flatMap(UIImage.init(named:))
                    ?? UIImage(systemName: biomarker.sampleType.symbolName),
                state: biomarker.id == selected.id ? .on : .off
            ) { [weak self] _ in
                guard let self, self.selectedBiomarkerID != biomarker.id else { return }
                self.selectedBiomarkerID = biomarker.id
                self.rebuildBiomarkerMenu()
                self.configureChart()
            }
        })
    }

    private func configureChart() {
        guard let biomarker = biomarkers.first(where: { $0.id == selectedBiomarkerID }) else {
            chartView.values = []
            chartView.labels = []
            chartView.selectionLabels = []
            chartView.linearTrend = nil
            chartView.emptyText = L10n.text("health.biomarker_trends.empty")
            return
        }

        let series = trendSeries(for: biomarker)
        chartView.values = series.values
        chartView.labels = series.axisLabels
        chartView.selectionLabels = series.selectionLabels
        chartView.lineColor = WellnarioPalette.fuchsia
        chartView.lineColors = []
        chartView.targetRanges = []
        chartView.linearTrend = WellnessLinearRegression.fit(values: series.values)
        chartView.referenceLine = selectedReferenceLine
        chartView.averageTitle = L10n.text("health.biomarker_trends.reference.average")
        chartView.averageColor = WellnarioPalette.cyan
        chartView.smoothingWindow = 1
        chartView.emptyText = L10n.text("health.biomarker_trends.empty")
        chartView.valueFormatter = valueFormatter(for: biomarker)
        chartView.accessibilityHint = L10n.text("health.biomarker_trends.chart.interaction.hint")
        chartView.accessibilityLabel = L10n.text(
            "health.biomarker_trends.chart.accessibility",
            biomarker.name,
            periodTitle(selectedPeriod)
        )

        let values = series.values.compactMap { $0 }
        if let minimum = values.min(), let maximum = values.max() {
            let average = values.reduce(0, +) / Double(values.count)
            chartView.accessibilityValue = L10n.text(
                "health.biomarker_trends.chart.accessibility.values",
                chartView.valueFormatter(average),
                chartView.valueFormatter(minimum),
                chartView.valueFormatter(maximum)
            )
        } else {
            chartView.accessibilityValue = chartView.emptyText
        }
    }

    private func trendSeries(for biomarker: HealthBiomarker) -> BiomarkerTrendSeries {
        let calendar = Calendar.autoupdatingCurrent
        let allMeasurements = store.measurements(for: biomarker.id)
        let measurementsByDay = allMeasurements.reduce(into: [Date: BiomarkerMeasurement]()) {
            result, measurement in
            let day = calendar.startOfDay(for: measurement.collectedAt)
            if let existing = result[day], existing.collectedAt >= measurement.collectedAt { return }
            result[day] = measurement
        }
        guard let firstMeasurementDay = measurementsByDay.keys.min(),
              let lastMeasurementDay = measurementsByDay.keys.max() else {
            return .empty
        }

        let today = calendar.startOfDay(for: Date())
        let start: Date
        let end: Date
        switch selectedPeriod {
        case .lastYear:
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: today) ?? today
            start = max(firstMeasurementDay, oneYearAgo)
            end = today
        case .allTime:
            start = firstMeasurementDay
            end = lastMeasurementDay
        }
        guard start <= end else { return .empty }

        var dates: [Date] = []
        var cursor = start
        while cursor <= end {
            dates.append(cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }
        let values = dates.map {
            measurementsByDay[$0].map { FeatureFormatting.double($0.result.value) }
        }
        return BiomarkerTrendSeries(
            values: values,
            axisLabels: axisLabels(for: dates),
            selectionLabels: selectionLabels(for: dates)
        )
    }

    private func axisLabels(for dates: [Date]) -> [String] {
        guard !dates.isEmpty else { return [] }
        let labelCount = min(3, dates.count)
        let displayedIndexes = Set((0..<labelCount).map { labelIndex in
            guard labelCount > 1 else { return 0 }
            return Int(
                (Double(labelIndex) * Double(dates.count - 1) / Double(labelCount - 1)).rounded()
            )
        })
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        let span = dates.last?.timeIntervalSince(dates.first ?? Date()) ?? 0
        formatter.setLocalizedDateFormatFromTemplate(span >= 365 * 86_400 ? "MMMyy" : "dMMM")
        return dates.enumerated().map { index, date in
            displayedIndexes.contains(index) ? formatter.string(from: date) : ""
        }
    }

    private func selectionLabels(for dates: [Date]) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.setLocalizedDateFormatFromTemplate("dMMMy")
        return dates.map { formatter.string(from: $0) }
    }

    private func valueFormatter(for biomarker: HealthBiomarker) -> (Double) -> String {
        let unit = biomarker.defaultUnit
        return { value in
            [WellnarioFormatters.number(value, maximumFractionDigits: 2), unit]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    private func makePeriodControl() -> UISegmentedControl {
        let control = UISegmentedControl(items: Period.allCases.map(periodTitle))
        control.selectedSegmentIndex = selectedPeriod.rawValue
        control.apportionsSegmentWidthsByContent = true
        styleSelector(control, fontSize: 13)
        control.accessibilityIdentifier = "health.biomarker_trends.period.selector"
        control.accessibilityLabel = L10n.text("health.biomarker_trends.period.selector.accessibility")
        control.addTarget(self, action: #selector(periodDidChange), for: .valueChanged)
        return control
    }

    private func makeReferenceLineControl() -> UISegmentedControl {
        let control = UISegmentedControl(items: WellnessTrendReferenceLine.allCases.map(referenceTitle))
        control.selectedSegmentIndex = selectedReferenceLine.rawValue
        styleSelector(control, fontSize: 11)
        control.accessibilityIdentifier = "health.biomarker_trends.reference.selector"
        control.accessibilityLabel = L10n.text("health.biomarker_trends.reference.selector.accessibility")
        control.addTarget(self, action: #selector(referenceLineDidChange), for: .valueChanged)
        return control
    }

    private func styleSelector(_ control: UISegmentedControl, fontSize: CGFloat) {
        control.selectedSegmentTintColor = WellnarioPalette.fuchsia
        control.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: WellnarioPalette.textSecondary
        ], for: .normal)
        control.setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white
        ], for: .selected)
    }

    private func periodTitle(_ period: Period) -> String {
        switch period {
        case .lastYear: L10n.text("health.biomarker_trends.period.last_year")
        case .allTime: L10n.text("health.biomarker_trends.period.all_time")
        }
    }

    private func referenceTitle(_ line: WellnessTrendReferenceLine) -> String {
        switch line {
        case .average: L10n.text("health.biomarker_trends.reference.average")
        case .linearTrend: L10n.text("health.biomarker_trends.reference.trend")
        }
    }

    @objc private func periodDidChange() {
        guard let period = Period(rawValue: periodControl.selectedSegmentIndex) else { return }
        selectedPeriod = period
        configureChart()
    }

    @objc private func referenceLineDidChange() {
        guard let reference = WellnessTrendReferenceLine(
            rawValue: referenceLineControl.selectedSegmentIndex
        ) else { return }
        selectedReferenceLine = reference
        defaults.set(reference.rawValue, forKey: Self.referenceLinePreferenceKey)
        chartView.referenceLine = reference
    }

    @objc private func languageDidChange() {
        biomarkerField.title = ""
        for period in Period.allCases {
            periodControl.setTitle(periodTitle(period), forSegmentAt: period.rawValue)
        }
        for line in WellnessTrendReferenceLine.allCases {
            referenceLineControl.setTitle(referenceTitle(line), forSegmentAt: line.rawValue)
        }
        reloadContent()
    }
}

private struct BiomarkerTrendSeries {
    let values: [Double?]
    let axisLabels: [String]
    let selectionLabels: [String]

    static let empty = BiomarkerTrendSeries(values: [], axisLabels: [], selectionLabels: [])
}

@MainActor
private final class FavoriteBiomarkerAnalysesSummaryView: PremiumCardView {
    private let titleLabel = UILabel()
    private let bodyStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(favorites: [HealthBiomarker], analyses: [LabAnalysis]) {
        titleLabel.text = L10n.text("health.biomarker_trends.summary.title")
        bodyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if favorites.isEmpty {
            let empty = UILabel()
            empty.applyWellnarioStyle(.biomarkerSummaryDetail, color: WellnarioPalette.textSecondary)
            empty.numberOfLines = 0
            empty.text = L10n.text("health.biomarker_trends.summary.empty")
            bodyStack.addArrangedSubview(empty)
        } else {
            let sections = BiomarkerSampleType.allCases.compactMap { sampleType -> (BiomarkerSampleType, [HealthBiomarker])? in
                let sectionFavorites = favorites.filter { $0.sampleType == sampleType }
                guard !sectionFavorites.isEmpty else { return nil }
                return (sampleType, sectionFavorites)
            }
            for (index, section) in sections.enumerated() {
                let sectionView = makeSection(
                    sampleType: section.0,
                    biomarkers: section.1,
                    analyses: analyses
                )
                bodyStack.addArrangedSubview(sectionView)
                if index < sections.count - 1 {
                    bodyStack.setCustomSpacing(WellnarioSpacing.small, after: sectionView)
                }
            }
        }
    }

    private func configureView() {
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text("health.biomarker_trends.summary.title")
        titleLabel.accessibilityIdentifier = "health.biomarker_trends.summary.title"
        titleLabel.heightAnchor.constraint(equalToConstant: WellnarioLayout.fieldMinimumHeight).isActive = true

        bodyStack.axis = .vertical
        bodyStack.spacing = 2

        let stack = UIStackView(
            arrangedSubviews: [titleLabel, bodyStack],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        contentView.addForAutoLayout(stack)
        stack.pinEdges(
            to: contentView,
            insets: NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        )
    }

    private func makeValueHeaderRow(analyses: [LabAnalysis]) -> UIView {
        let dates = (0..<analyses.count).map { index in
            let label = makeTableLabel(
                analyses.indices.contains(index)
                    ? headerDate(analyses[index].collectedAt)
                    : "—",
                color: WellnarioPalette.textTertiary,
                alignment: .right,
                numberOfLines: 2
            )
            if analyses.indices.contains(index) {
                label.accessibilityIdentifier = "health.biomarker_trends.summary.date.\(analyses[index].id.uuidString)"
            }
            return label
        }
        return makeValuesRow(dates, height: 34)
    }

    private func makeSectionHeading(for sampleType: BiomarkerSampleType) -> UILabel {
        let heading = UILabel()
        heading.applyWellnarioStyle(.caption, color: WellnarioPalette.fuchsia)
        heading.text = sampleType.title
        heading.accessibilityIdentifier = "health.biomarker_trends.summary.section.\(sampleType.rawValue)"
        return heading
    }

    private func makeSection(
        sampleType: BiomarkerSampleType,
        biomarkers: [HealthBiomarker],
        analyses: [LabAnalysis]
    ) -> UIView {
        let namesStack = UIStackView()
        namesStack.axis = .vertical
        namesStack.spacing = 2
        let nameHeader = makeTableLabel(
            L10n.text("health.biomarker_trends.summary.biomarker"),
            color: WellnarioPalette.textTertiary,
            alignment: .left
        )
        nameHeader.accessibilityIdentifier = "health.biomarker_trends.summary.name.header.\(sampleType.rawValue)"
        nameHeader.heightAnchor.constraint(equalToConstant: 34).isActive = true
        namesStack.addArrangedSubview(nameHeader)

        let valuesStack = UIStackView()
        valuesStack.axis = .vertical
        valuesStack.spacing = 2
        valuesStack.addArrangedSubview(makeValueHeaderRow(analyses: analyses))
        biomarkers.forEach { biomarker in
            let name = ContinuousMarqueeLabel()
            name.applyTextStyle(.biomarkerSummaryDetail, color: WellnarioPalette.textPrimary)
            name.text = biomarker.name
            name.isMarqueeEnabled = true
            name.accessibilityIdentifier = "health.biomarker_trends.summary.name.\(biomarker.id.uuidString)"
            name.heightAnchor.constraint(equalToConstant: 20).isActive = true
            namesStack.addArrangedSubview(name)
            valuesStack.addArrangedSubview(makeValueRow(biomarker: biomarker, analyses: analyses))
        }

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.accessibilityIdentifier = "health.biomarker_trends.summary.table.\(sampleType.rawValue)"
        scrollView.addForAutoLayout(valuesStack)
        // Free one more analysis column on the compact summary while keeping
        // the marker names fixed outside the horizontal scroll view.
        namesStack.widthAnchor.constraint(equalToConstant: 140).isActive = true
        scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let grid = UIStackView(
            arrangedSubviews: [namesStack, scrollView],
            axis: .horizontal,
            spacing: 2,
            alignment: .top
        )
        NSLayoutConstraint.activate([
            valuesStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            valuesStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            valuesStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            valuesStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            // Keep sparse histories compact: otherwise Auto Layout stretches
            // the last cell to fill the scroll view and creates a visual gap.
            valuesStack.widthAnchor.constraint(equalToConstant: CGFloat(analyses.count) * 46),
            scrollView.heightAnchor.constraint(equalTo: valuesStack.heightAnchor),
            namesStack.heightAnchor.constraint(equalTo: valuesStack.heightAnchor)
        ])

        return UIStackView(
            arrangedSubviews: [makeSectionHeading(for: sampleType), grid],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
    }

    private func makeValueRow(biomarker: HealthBiomarker, analyses: [LabAnalysis]) -> UIView {
        let values = (0..<analyses.count).map { index -> UILabel in
            guard analyses.indices.contains(index),
                  let result = analyses[index].results.first(where: { $0.biomarkerID == biomarker.id }) else {
                return makeTableLabel("—", color: WellnarioPalette.textTertiary, alignment: .right)
            }
            let label = makeTableLabel(
                FeatureFormatting.decimal(result.value, maximumFractionDigits: 2),
                color: result.isOutsideReferenceRange ? WellnarioPalette.danger : WellnarioPalette.textPrimary,
                alignment: .right
            )
            label.accessibilityIdentifier = "health.biomarker_trends.summary.result.\(biomarker.id.uuidString).\(analyses[index].id.uuidString)"
            return label
        }
        return makeValuesRow(values, height: 20)
    }

    private func makeValuesRow(_ values: [UILabel], height: CGFloat) -> UIView {
        let valuesStack = UIStackView(
            arrangedSubviews: values,
            axis: .horizontal,
            spacing: 0,
            alignment: .center,
            distribution: .fill
        )
        values.forEach {
            $0.widthAnchor.constraint(equalToConstant: 46).isActive = true
        }
        valuesStack.heightAnchor.constraint(equalToConstant: height).isActive = true
        return valuesStack
    }

    private func makeTableLabel(
        _ text: String,
        color: UIColor,
        alignment: NSTextAlignment,
        numberOfLines: Int = 1
    ) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.biomarkerSummaryDetail, color: color)
        label.text = text
        label.textAlignment = alignment
        label.numberOfLines = numberOfLines
        label.adjustsFontSizeToFitWidth = false
        return label
    }

    private func headerDate(_ date: Date) -> String {
        let yearFormatter = DateFormatter()
        yearFormatter.locale = LocalizationManager.shared.locale
        yearFormatter.setLocalizedDateFormatFromTemplate("y")

        let dayMonthFormatter = DateFormatter()
        dayMonthFormatter.locale = LocalizationManager.shared.locale
        dayMonthFormatter.setLocalizedDateFormatFromTemplate("dMMM")
        return "\(yearFormatter.string(from: date))\n\(dayMonthFormatter.string(from: date))"
    }
}
