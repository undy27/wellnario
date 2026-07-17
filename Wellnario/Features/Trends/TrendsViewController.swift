import UIKit

@MainActor
final class TrendsViewController: FeatureViewController {
    private static let referenceLinePreferenceKey = "wellnario.consumption.trends.referenceLine"

    private enum Period: Int, CaseIterable { case sevenDays, thirtyDays, year, custom }

    private struct FavoritePeriodSummary {
        let total: Decimal
        let status: TargetProgressStatus
    }

    private struct FavoriteConsumptionSummary {
        let active: Active
        let lastSevenDays: FavoritePeriodSummary
        let lastThirtyDays: FavoritePeriodSummary
    }

    private let initialActiveID: UUID?
    private let returnsToActiveDetail: Bool
    private let defaults: UserDefaults
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let activeField = SelectionFieldView(title: L10n.Form.active)
    private let favoritesSummaryCard = PremiumCardView()
    private let chartCard = PremiumCardView()
    private let chartView = WellnessTrendChartView()
    private let summaryStack = UIStackView()
    private let emptyState = EmptyStateView()
    private lazy var periodControl = makePeriodControl()
    private lazy var referenceLineControl = makeReferenceLineControl()

    private var actives: [Active] = []
    private var selectedActiveID: UUID?
    private var selectedPeriod: Period = .sevenDays
    private var selectedReferenceLine: WellnessTrendReferenceLine
    private var customFrom = LocalDay(containing: Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date(), in: .current)
    private var customThrough = LocalDay(containing: Date(), in: .current)
    private var series: ConsumptionSeries?
    private var favoriteSummaries: [FavoriteConsumptionSummary] = []

    init(
        repository: WellnarioRepositoryProtocol,
        activeID: UUID? = nil,
        returnsToActiveDetail: Bool = false,
        defaults: UserDefaults = .standard
    ) {
        self.initialActiveID = activeID
        self.selectedActiveID = activeID
        self.returnsToActiveDetail = returnsToActiveDetail
        self.defaults = defaults
        let storedReferenceLine = defaults.object(forKey: Self.referenceLinePreferenceKey) as? Int
        selectedReferenceLine = storedReferenceLine
            .flatMap(WellnessTrendReferenceLine.init(rawValue:))
            ?? .linearTrend
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: TrendsViewController, _) in
            if let series = self.series { self.rebuildSummary(series) }
        }
        applyLocalizedCopy()
        reloadContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        reloadContent()
    }

    override func applyLocalizedCopy() {
        title = L10n.Trends.title
        rebuildActiveMenu()
        updateSelectorTitles()
        rebuildFavoritesSummaryCard()
        if let series { render(series) }
    }

    override func reloadContent() {
        do {
            actives = try repository.fetchActives(includeArchived: false)
            if selectedActiveID == nil || !actives.contains(where: { $0.id == selectedActiveID }) {
                selectedActiveID = initialActiveID.flatMap { id in actives.first(where: { $0.id == id })?.id }
                    ?? actives.first?.id
            }
            rebuildActiveMenu()
            try rebuildFavoriteSummaries()
            guard let selectedActiveID else {
                showEmptyActives()
                return
            }
            let range = try dateRange()
            let series = try repository.dailyConsumption(activeID: selectedActiveID, from: range.from, through: range.through)
            self.series = series
            emptyState.isHidden = true
            contentStack.isHidden = false
            render(series)
        } catch { showError(error) }
    }

    private func setUpView() {
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.hidesBackButton = true
        let back = UIBarButtonItem(
            image: UIImage(systemName: "chevron.backward"),
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
        back.accessibilityLabel = L10n.Common.back
        back.accessibilityIdentifier = returnsToActiveDetail
            ? "trends.back_to_active"
            : "trends.back"
        navigationItem.leftBarButtonItem = back

        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

        contentStack.axis = .vertical
        contentStack.spacing = WellnarioSpacing.cardGap
        scrollView.addForAutoLayout(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: WellnarioSpacing.xSmall),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.bottomNavigationInset),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(WellnarioSpacing.screenHorizontal * 2))
        ])

        favoritesSummaryCard.isHidden = true
        contentStack.addArrangedSubview(favoritesSummaryCard)
        contentStack.addArrangedSubview(activeField)
        activeField.button.accessibilityIdentifier = "trends.active.selector"

        setUpChartCard()
        contentStack.addArrangedSubview(chartCard)
        summaryStack.axis = .vertical
        summaryStack.spacing = WellnarioSpacing.cardGap
        contentStack.addArrangedSubview(summaryStack)

        emptyState.configure(kind: .other, title: L10n.Actives.noItemsTitle, message: L10n.Actives.noItemsMessage, actionTitle: L10n.Actives.add)
        emptyState.onAction = { [weak self] in
            guard let self else { return }
            self.presentSheet(ActiveEditorViewController(repository: self.repository), largeOnly: true)
        }
        view.addForAutoLayout(emptyState)
        NSLayoutConstraint.activate([
            emptyState.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            emptyState.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            emptyState.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.bottomNavigationInset)
        ])
        emptyState.isHidden = true
    }

    @objc private func backTapped() {
        guard let navigationController else { return }

        guard WellnarioMotion.animationsEnabled else {
            navigationController.popViewController(animated: false)
            return
        }

        UIView.transition(
            with: navigationController.view,
            duration: WellnarioMotion.standard,
            options: [.transitionCrossDissolve, .allowAnimatedContent, .beginFromCurrentState]
        ) {
            navigationController.popViewController(animated: false)
        }
    }

    private func setUpChartCard() {
        let title = UILabel()
        title.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        title.text = L10n.Trends.dailyConsumption
        let icon = UIImageView(image: UIImage(systemName: "chart.xyaxis.line"))
        icon.tintColor = WellnarioPalette.textTertiary
        let header = UIStackView(arrangedSubviews: [title, UIView(), icon], axis: .horizontal, spacing: 8, alignment: .center)

        chartView.accessibilityIdentifier = "trends.chart"
        chartView.heightAnchor.constraint(equalToConstant: 190).isActive = true

        let targetLegend = legend(
            color: WellnarioPalette.fuchsia.withAlphaComponent(0.52),
            title: L10n.Trends.targetBand
        )
        let withinLegend = legend(
            color: WellnarioPalette.success,
            title: L10n.text("target.within")
        )
        let belowLegend = legend(
            color: WellnarioPalette.yellow,
            title: L10n.text("target.below")
        )
        let aboveLegend = legend(
            color: WellnarioPalette.danger,
            title: L10n.text("target.above")
        )
        let firstLegendRow = UIStackView(
            arrangedSubviews: [targetLegend, UIView(), withinLegend],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        let secondLegendRow = UIStackView(
            arrangedSubviews: [belowLegend, UIView(), aboveLegend],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        let legends = UIStackView(
            arrangedSubviews: [firstLegendRow, secondLegendRow],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )

        let stack = UIStackView(
            arrangedSubviews: [
                header,
                makeReferenceLineControlContainer(),
                chartView,
                periodControl,
                legends
            ],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        chartCard.contentView.addForAutoLayout(stack)
        stack.pinEdges(
            to: chartCard.contentView,
            insets: NSDirectionalEdgeInsets(top: 16, leading: 8, bottom: 16, trailing: 8)
        )
    }

    private func legend(color: UIColor, title: String) -> UIView {
        let swatch = UIView()
        swatch.backgroundColor = color
        swatch.applyContinuousCorners(3)
        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 16),
            swatch.heightAnchor.constraint(equalToConstant: 6)
        ])
        let label = UILabel()
        label.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        label.text = title
        return UIStackView(arrangedSubviews: [swatch, label], axis: .horizontal, spacing: 6, alignment: .center)
    }

    private func rebuildActiveMenu() {
        let selected = actives.first { $0.id == selectedActiveID }
        activeField.value = selected?.localizedName(language: catalogLanguage) ?? L10n.Common.required
        activeField.leadingImage = activeIcon(for: selected)
        activeField.menu = UIMenu(children: actives.map { active in
            UIAction(
                title: active.localizedName(language: catalogLanguage),
                image: activeIcon(for: active),
                state: active.id == selectedActiveID ? .on : .off
            ) { [weak self] _ in
                self?.selectedActiveID = active.id
                self?.rebuildActiveMenu()
                self?.reloadContent()
                UISelectionFeedbackGenerator().selectionChanged()
            }
        })
    }

    private func activeIcon(for active: Active?) -> UIImage? {
        if let imageKey = active?.imageKey, let image = UIImage(named: imageKey) {
            return image
        }
        return UIImage(systemName: "leaf.fill")
    }

    private func rebuildFavoriteSummaries() throws {
        let favorites = actives
            .filter(\.isFavorite)
            .sorted {
                $0.localizedName(language: catalogLanguage)
                    .localizedCaseInsensitiveCompare($1.localizedName(language: catalogLanguage)) == .orderedAscending
            }
        guard !favorites.isEmpty else {
            favoriteSummaries = []
            rebuildFavoritesSummaryCard()
            return
        }

        let through = LocalDay(containing: Date(), in: .current)
        let monthFrom = try through.adding(days: -29)
        favoriteSummaries = try favorites.map { active in
            let monthSeries = try repository.dailyConsumption(
                activeID: active.id,
                from: monthFrom,
                through: through
            )
            let lastSevenDays = Array(monthSeries.points.suffix(7))
            return FavoriteConsumptionSummary(
                active: active,
                lastSevenDays: try favoritePeriodSummary(for: lastSevenDays),
                lastThirtyDays: try favoritePeriodSummary(for: monthSeries.points)
            )
        }
        rebuildFavoritesSummaryCard()
    }

    private func favoritePeriodSummary(
        for points: [DailyConsumptionPoint]
    ) throws -> FavoritePeriodSummary {
        var total: Decimal = 0
        var lowerTotal: Decimal = 0
        var upperTotal: Decimal = 0
        var hasTargetForEveryDay = !points.isEmpty

        for point in points {
            total = try DecimalMath.add(total, point.amount)
            guard let lower = point.targetLower, let upper = point.targetUpper else {
                hasTargetForEveryDay = false
                continue
            }
            lowerTotal = try DecimalMath.add(lowerTotal, lower)
            upperTotal = try DecimalMath.add(upperTotal, upper)
        }

        return FavoritePeriodSummary(
            total: total,
            status: hasTargetForEveryDay
                ? status(for: total, lower: lowerTotal, upper: upperTotal)
                : .noTarget
        )
    }

    private func status(
        for total: Decimal,
        lower: Decimal,
        upper: Decimal
    ) -> TargetProgressStatus {
        if total < lower { return .below }
        if total > upper { return .above }
        return .within
    }

    private func rebuildFavoritesSummaryCard() {
        favoritesSummaryCard.contentView.subviews.forEach { $0.removeFromSuperview() }
        favoritesSummaryCard.isHidden = favoriteSummaries.isEmpty
        guard !favoriteSummaries.isEmpty else { return }

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text("trends.favorites.title")

        let icon = UIImageView(image: UIImage(systemName: "heart.fill"))
        icon.tintColor = WellnarioPalette.fuchsia
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let titleRow = UIStackView(
            arrangedSubviews: [icon, titleLabel, UIView()],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )

        let subtitle = UILabel()
        subtitle.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        subtitle.text = L10n.text("trends.favorites.body")
        subtitle.numberOfLines = 0

        let sevenDaysHeader = periodHeader(L10n.Trends.sevenDays)
        let thirtyDaysHeader = periodHeader(L10n.Trends.thirtyDays)
        let headers = UIStackView(
            arrangedSubviews: [UIView(), sevenDaysHeader, thirtyDaysHeader],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        [sevenDaysHeader, thirtyDaysHeader].forEach {
            $0.widthAnchor.constraint(equalToConstant: 72).isActive = true
        }

        let rows = UIStackView(
            arrangedSubviews: favoriteSummaries.map(favoriteSummaryRow),
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )
        let content = UIStackView(
            arrangedSubviews: [titleRow, subtitle, headers, rows],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        content.setCustomSpacing(WellnarioSpacing.xSmall, after: subtitle)
        favoritesSummaryCard.accessibilityIdentifier = "trends.favorites.card"
        favoritesSummaryCard.contentView.addForAutoLayout(content)
        content.pinEdges(
            to: favoritesSummaryCard.contentView,
            insets: NSDirectionalEdgeInsets(
                top: WellnarioSpacing.small,
                leading: WellnarioSpacing.cardPadding,
                bottom: WellnarioSpacing.small,
                trailing: WellnarioSpacing.cardPadding
            )
        )
    }

    private func periodHeader(_ title: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        label.text = title
        label.textAlignment = .right
        return label
    }

    private func favoriteSummaryRow(_ summary: FavoriteConsumptionSummary) -> UIView {
        let icon = UIImageView(image: activeIcon(for: summary.active))
        icon.contentMode = .scaleAspectFit
        icon.tintColor = WellnarioPalette.fuchsia
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalTo: icon.widthAnchor)
        ])

        let name = UILabel()
        name.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        name.text = summary.active.localizedName(language: catalogLanguage)
        name.numberOfLines = 2

        let details = UIStackView(
            arrangedSubviews: [icon, name],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        let lastSevenDays = favoriteValue(
            summary.lastSevenDays,
            active: summary.active,
            identifier: "trends.favorites.\(summary.active.id.uuidString).7d"
        )
        let lastThirtyDays = favoriteValue(
            summary.lastThirtyDays,
            active: summary.active,
            identifier: "trends.favorites.\(summary.active.id.uuidString).30d"
        )
        let row = UIStackView(
            arrangedSubviews: [details, lastSevenDays, lastThirtyDays],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        [lastSevenDays, lastThirtyDays].forEach {
            $0.widthAnchor.constraint(equalToConstant: 72).isActive = true
        }
        row.isAccessibilityElement = true
        row.accessibilityIdentifier = "trends.favorites.\(summary.active.id.uuidString)"
        row.accessibilityLabel = [
            summary.active.localizedName(language: catalogLanguage),
            L10n.Trends.sevenDays,
            favoriteValueText(summary.lastSevenDays, active: summary.active),
            L10n.Trends.thirtyDays,
            favoriteValueText(summary.lastThirtyDays, active: summary.active)
        ].joined(separator: ". ")
        return row
    }

    private func favoriteValue(
        _ summary: FavoritePeriodSummary,
        active: Active,
        identifier: String
    ) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.secondary, color: favoriteColor(for: summary.status))
        label.text = favoriteValueText(summary, active: active)
        label.textAlignment = .right
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.72
        label.accessibilityIdentifier = identifier
        return label
    }

    private func favoriteValueText(
        _ summary: FavoritePeriodSummary,
        active: Active
    ) -> String {
        "\(FeatureFormatting.decimal(summary.total)) \(active.baseUnit.symbol(languageCode: catalogLanguage.rawValue))"
    }

    private func favoriteColor(for status: TargetProgressStatus) -> UIColor {
        switch status {
        case .below: WellnarioPalette.yellow
        case .within: WellnarioPalette.success
        case .above: WellnarioPalette.danger
        case .noTarget: WellnarioPalette.textSecondary
        }
    }

    private func makePeriodControl() -> UISegmentedControl {
        let control = UISegmentedControl(items: Period.allCases.map(periodTitle))
        control.selectedSegmentIndex = selectedPeriod.rawValue
        control.apportionsSegmentWidthsByContent = true
        styleSelector(control, fontSize: 13)
        control.accessibilityIdentifier = "trends.period.selector"
        control.accessibilityLabel = L10n.text("trends.period.selector.accessibility")
        control.addTarget(self, action: #selector(periodDidChange), for: .valueChanged)
        return control
    }

    private func makeReferenceLineControl() -> UISegmentedControl {
        let control = UISegmentedControl(
            items: WellnessTrendReferenceLine.allCases.map(referenceLineTitle)
        )
        control.selectedSegmentIndex = selectedReferenceLine.rawValue
        styleSelector(control, fontSize: 11)
        control.accessibilityIdentifier = "trends.reference.selector"
        control.accessibilityLabel = L10n.text("trends.reference.selector.accessibility")
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

    private func makeReferenceLineControlContainer() -> UIView {
        let container = UIView()
        container.addForAutoLayout(referenceLineControl)
        NSLayoutConstraint.activate([
            referenceLineControl.topAnchor.constraint(equalTo: container.topAnchor),
            referenceLineControl.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            referenceLineControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            referenceLineControl.widthAnchor.constraint(equalToConstant: 180),
            referenceLineControl.heightAnchor.constraint(equalToConstant: 28)
        ])
        return container
    }

    private func updateSelectorTitles() {
        for period in Period.allCases {
            periodControl.setTitle(periodTitle(period), forSegmentAt: period.rawValue)
        }
        for referenceLine in WellnessTrendReferenceLine.allCases {
            referenceLineControl.setTitle(
                referenceLineTitle(referenceLine),
                forSegmentAt: referenceLine.rawValue
            )
        }
    }

    private func periodTitle(_ period: Period) -> String {
        switch period {
        case .sevenDays: L10n.Trends.sevenDays
        case .thirtyDays: L10n.Trends.thirtyDays
        case .year: L10n.Trends.oneYear
        case .custom: L10n.Trends.customRange
        }
    }

    private func referenceLineTitle(_ referenceLine: WellnessTrendReferenceLine) -> String {
        switch referenceLine {
        case .average: L10n.text("trends.reference.average")
        case .linearTrend: L10n.text("trends.reference.linear")
        }
    }

    @objc private func periodDidChange() {
        guard let period = Period(rawValue: periodControl.selectedSegmentIndex) else { return }
        if period == .custom {
            periodControl.selectedSegmentIndex = selectedPeriod.rawValue
            presentCustomRangePicker()
        } else {
            guard period != selectedPeriod else { return }
            selectedPeriod = period
            reloadContent()
        }
    }

    @objc private func referenceLineDidChange() {
        guard let referenceLine = WellnessTrendReferenceLine(
            rawValue: referenceLineControl.selectedSegmentIndex
        ) else { return }
        selectedReferenceLine = referenceLine
        defaults.set(referenceLine.rawValue, forKey: Self.referenceLinePreferenceKey)
        chartView.referenceLine = referenceLine
    }

    private func dateRange() throws -> (from: LocalDay, through: LocalDay) {
        let through = LocalDay(containing: Date(), in: .current)
        switch selectedPeriod {
        case .sevenDays: return (try through.adding(days: -6), through)
        case .thirtyDays: return (try through.adding(days: -29), through)
        case .year: return (try through.adding(days: -364), through)
        case .custom: return (customFrom, customThrough)
        }
    }

    private func render(_ series: ConsumptionSeries) {
        let values = series.amountsFromFirstRecordedDay.map { amount -> Double? in
            amount.map(FeatureFormatting.double)
        }
        chartView.values = values
        chartView.labels = axisLabels(for: series)
        chartView.selectionLabels = selectionLabels(for: series)
        chartView.lineColor = WellnarioPalette.textSecondary
        chartView.lineColors = series.points.map { lineColor(for: $0.status) }
        chartView.targetRanges = series.points.map { point in
            guard let lower = point.targetLower, let upper = point.targetUpper else { return nil }
            return FeatureFormatting.double(lower)...FeatureFormatting.double(upper)
        }
        chartView.targetBandColor = WellnarioPalette.fuchsia
        chartView.linearTrend = WellnessLinearRegression.fit(values: values)
        chartView.referenceLine = selectedReferenceLine
        chartView.averageTitle = L10n.Trends.average
        chartView.averageColor = WellnarioPalette.cyan
        chartView.smoothingWindow = 1
        chartView.emptyText = L10n.Trends.noDataMessage
        let unit = series.unit.symbol(languageCode: catalogLanguage.rawValue)
        chartView.valueFormatter = { value in
            "\(WellnarioFormatters.number(value, maximumFractionDigits: 2)) \(unit)"
        }
        chartView.accessibilityHint = L10n.text("trends.chart.interaction.hint")
        chartView.accessibilityLabel = L10n.text(
            "trends.chart.accessibility",
            series.active.localizedName(language: catalogLanguage),
            periodTitle(selectedPeriod)
        )
        chartView.accessibilityValue = L10n.text(
            "trends.chart.accessibility.values",
            chartView.valueFormatter(FeatureFormatting.double(series.average)),
            series.daysWithinTarget,
            series.recordedDayCount
        )
        rebuildSummary(series)
    }

    private func lineColor(for status: TargetProgressStatus) -> UIColor {
        switch status {
        case .within: WellnarioPalette.success
        case .below: WellnarioPalette.yellow
        case .above: WellnarioPalette.danger
        case .noTarget: WellnarioPalette.fuchsia
        }
    }

    private func axisLabels(for series: ConsumptionSeries) -> [String] {
        guard !series.points.isEmpty else { return [] }
        if selectedPeriod == .sevenDays {
            let formatter = DateFormatter()
            formatter.locale = LocalizationManager.shared.locale
            formatter.setLocalizedDateFormatFromTemplate("EEEEE")
            return series.points.map { point in
                guard let date = FeatureFormatting.localDayDate(point.day) else { return "" }
                return formatter.string(from: date).uppercased(with: formatter.locale)
            }
        }

        let labelCount = min(selectedPeriod == .thirtyDays ? 4 : 3, series.points.count)
        let indexes = Set((0..<labelCount).map { labelIndex in
            guard labelCount > 1 else { return 0 }
            return Int(
                (Double(labelIndex) * Double(series.points.count - 1) / Double(labelCount - 1))
                    .rounded()
            )
        })
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        let startDate = FeatureFormatting.localDayDate(series.from)
        let endDate = FeatureFormatting.localDayDate(series.through)
        let span = endDate?.timeIntervalSince(startDate ?? endDate ?? Date()) ?? 0
        let spanInDays = Int(span / 86_400)
        formatter.setLocalizedDateFormatFromTemplate(
            spanInDays > 370 ? "MMMyy" : (spanInDays > 45 ? "MMM" : "dMMM")
        )
        return series.points.enumerated().map { index, point in
            guard indexes.contains(index),
                  let date = FeatureFormatting.localDayDate(point.day) else { return "" }
            return formatter.string(from: date)
        }
    }

    private func selectionLabels(for series: ConsumptionSeries) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.setLocalizedDateFormatFromTemplate("dMMMy")
        return series.points.map { point in
            guard let date = FeatureFormatting.localDayDate(point.day) else { return point.day.iso8601 }
            return formatter.string(from: date)
        }
    }

    private func rebuildSummary(_ series: ConsumptionSeries) {
        summaryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let unit = series.unit.symbol(languageCode: catalogLanguage.rawValue)
        let average = summaryCard(
            title: L10n.Trends.average,
            value: FeatureFormatting.decimal(series.average),
            unit: unit,
            symbol: "waveform.path.ecg",
            tone: .accent
        )
        let total = summaryCard(
            title: L10n.Trends.total,
            value: FeatureFormatting.decimal(series.total),
            unit: unit,
            symbol: "sum",
            tone: .information
        )
        let inTarget = summaryCard(
            title: L10n.Trends.daysInTarget,
            value: "\(series.daysWithinTarget)",
            unit: "/\(series.recordedDayCount)",
            symbol: "scope",
            tone: series.daysWithinTarget > 0 ? .success : .neutral
        )
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            [average, total, inTarget].forEach(summaryStack.addArrangedSubview)
        } else {
            let top = UIStackView(arrangedSubviews: [average, total], axis: .horizontal, spacing: WellnarioSpacing.cardGap, distribution: .fillEqually)
            average.widthAnchor.constraint(equalTo: total.widthAnchor).isActive = true
            summaryStack.addArrangedSubview(top)
            summaryStack.addArrangedSubview(inTarget)
        }

        if series.active.currentTarget == nil {
            let button = PrimaryButton(title: L10n.text("trends.define_target"), style: .secondary)
            button.addTarget(self, action: #selector(defineTarget), for: .touchUpInside)
            summaryStack.addArrangedSubview(button)
        }
    }

    private func summaryCard(title: String, value: String, unit: String, symbol: String, tone: WellnarioTone) -> MetricCardView {
        let card = MetricCardView()
        card.configure(title: title, symbolName: symbol, value: value, unit: unit, status: "", tone: tone)
        let progress = SegmentedProgressView()
        progress.totalSegments = 6
        progress.completedSegments = tone == .neutral ? 0 : 4
        card.setVisualization(progress)
        return card
    }

    private func showEmptyActives() {
        contentStack.isHidden = true
        emptyState.isHidden = false
    }

    @objc private func defineTarget() {
        guard let active = actives.first(where: { $0.id == selectedActiveID }) else { return }
        presentSheet(ActiveEditorViewController(repository: repository, active: active), largeOnly: true)
    }

    private func presentCustomRangePicker() {
        let controller = CustomRangeViewController(from: customFrom, through: customThrough)
        controller.onApply = { [weak self] from, through in
            guard let self else { return }
            self.customFrom = from
            self.customThrough = through
            self.selectedPeriod = .custom
            self.periodControl.selectedSegmentIndex = Period.custom.rawValue
            self.reloadContent()
        }
        presentSheet(controller, largeOnly: true)
    }

}

@MainActor
private final class CustomRangeViewController: UIViewController {
    var onApply: ((LocalDay, LocalDay) -> Void)?
    private let fromPicker = UIDatePicker()
    private let throughPicker = UIDatePicker()

    init(from: LocalDay, through: LocalDay) {
        super.init(nibName: nil, bundle: nil)
        fromPicker.date = FeatureFormatting.localDayDate(from) ?? Date()
        throughPicker.date = FeatureFormatting.localDayDate(through) ?? Date()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.Trends.customRange
        view.backgroundColor = WellnarioPalette.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: L10n.Common.cancel, style: .plain, target: self, action: #selector(cancelTapped))

        [fromPicker, throughPicker].forEach {
            $0.datePickerMode = .date
            $0.preferredDatePickerStyle = .compact
            $0.maximumDate = Date()
            $0.tintColor = WellnarioPalette.cyan
        }

        let fromTitle = label(L10n.text("trends.range.from"))
        let throughTitle = label(L10n.text("trends.range.through"))
        let apply = PrimaryButton(title: L10n.Common.done)
        apply.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [fromTitle, fromPicker, throughTitle, throughPicker, apply], axis: .vertical, spacing: 12)
        view.addForAutoLayout(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    private func label(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        label.text = text
        return label
    }

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func applyTapped() {
        let from = LocalDay(containing: fromPicker.date, in: .current)
        let through = LocalDay(containing: throughPicker.date, in: .current)
        guard from <= through else {
            let alert = UIAlertController(title: L10n.Common.error, message: L10n.text("trends.range.invalid"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
            present(alert, animated: true)
            return
        }
        onApply?(from, through)
        dismiss(animated: true)
    }
}
