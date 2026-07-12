import UIKit

@MainActor
final class TrendsViewController: FeatureViewController {
    private enum Period: Int, CaseIterable { case sevenDays, thirtyDays, year, custom }

    private let initialActiveID: UUID?
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let activeField = SelectionFieldView(title: L10n.Form.active)
    private let periodStack = UIStackView()
    private let chartCard = PremiumCardView()
    private let chartScrollView = UIScrollView()
    private let chartView = ConsumptionChartView()
    private let selectedPointLabel = UILabel()
    private let summaryStack = UIStackView()
    private let emptyState = EmptyStateView()

    private var actives: [Active] = []
    private var selectedActiveID: UUID?
    private var selectedPeriod: Period = .sevenDays
    private var customFrom = LocalDay(containing: Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date(), in: .current)
    private var customThrough = LocalDay(containing: Date(), in: .current)
    private var series: ConsumptionSeries?

    init(repository: WellnarioRepositoryProtocol, activeID: UUID? = nil) {
        self.initialActiveID = activeID
        self.selectedActiveID = activeID
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
        rebuildPeriodButtons()
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
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

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
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: WellnarioSpacing.medium),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.bottomNavigationInset),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(WellnarioSpacing.screenHorizontal * 2))
        ])

        contentStack.addArrangedSubview(activeField)
        periodStack.axis = .horizontal
        periodStack.spacing = 8
        periodStack.distribution = .fillEqually
        contentStack.addArrangedSubview(periodStack)

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
        rebuildPeriodButtons()
    }

    private func setUpChartCard() {
        let title = UILabel()
        title.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        title.text = L10n.Trends.dailyConsumption
        let icon = UIImageView(image: UIImage(systemName: "chart.xyaxis.line"))
        icon.tintColor = WellnarioPalette.textTertiary
        let header = UIStackView(arrangedSubviews: [title, UIView(), icon], axis: .horizontal, spacing: 8, alignment: .center)

        chartScrollView.showsHorizontalScrollIndicator = false
        chartScrollView.alwaysBounceHorizontal = true
        chartScrollView.layer.cornerRadius = WellnarioRadius.control
        chartScrollView.backgroundColor = WellnarioPalette.background.withAlphaComponent(0.32)
        chartScrollView.addForAutoLayout(chartView)
        chartView.pinEdges(to: chartScrollView.contentLayoutGuide)
        NSLayoutConstraint.activate([
            chartScrollView.heightAnchor.constraint(equalToConstant: 270),
            chartView.heightAnchor.constraint(equalTo: chartScrollView.frameLayoutGuide.heightAnchor),
            chartView.widthAnchor.constraint(greaterThanOrEqualTo: chartScrollView.frameLayoutGuide.widthAnchor)
        ])
        chartView.onSelection = { [weak self] point in self?.show(point: point) }

        selectedPointLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        selectedPointLabel.numberOfLines = 0
        selectedPointLabel.textAlignment = .center
        selectedPointLabel.isAccessibilityElement = true

        let targetLegend = legend(color: WellnarioPalette.violet.withAlphaComponent(0.55), title: L10n.Trends.targetBand)
        let averageLegend = legend(color: WellnarioPalette.magenta, title: L10n.Trends.average)
        let legendRow = UIStackView(arrangedSubviews: [targetLegend, averageLegend, UIView()], axis: .horizontal, spacing: 14, alignment: .center)

        let stack = UIStackView(arrangedSubviews: [header, chartScrollView, selectedPointLabel, legendRow], axis: .vertical, spacing: 14)
        chartCard.contentView.addForAutoLayout(stack)
        stack.pinEdges(to: chartCard.contentView, insets: .all(WellnarioSpacing.cardPadding))
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
        activeField.menu = UIMenu(children: actives.map { active in
            UIAction(
                title: active.localizedName(language: catalogLanguage),
                state: active.id == selectedActiveID ? .on : .off
            ) { [weak self] _ in
                self?.selectedActiveID = active.id
                self?.rebuildActiveMenu()
                self?.reloadContent()
            }
        })
    }

    private func rebuildPeriodButtons() {
        periodStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let titles = [L10n.Trends.sevenDays, L10n.Trends.thirtyDays, L10n.Trends.oneYear, L10n.Trends.customRange]
        for (index, title) in titles.enumerated() {
            let button = ChipButton(title: title)
            button.tag = index
            button.isSelected = selectedPeriod.rawValue == index
            button.addTarget(self, action: #selector(periodTapped(_:)), for: .touchUpInside)
            periodStack.addArrangedSubview(button)
        }
    }

    @objc private func periodTapped(_ sender: ChipButton) {
        guard let period = Period(rawValue: sender.tag) else { return }
        if period == .custom {
            presentCustomRangePicker()
        } else {
            selectedPeriod = period
            rebuildPeriodButtons()
            reloadContent()
        }
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
        let minimumBarWidth: CGFloat = series.points.count > 60 ? 9 : 28
        let chartWidth = max(view.bounds.width - 80, CGFloat(series.points.count) * minimumBarWidth)
        chartView.widthConstraint?.isActive = false
        chartView.widthConstraint = chartView.widthAnchor.constraint(equalToConstant: chartWidth)
        chartView.widthConstraint?.priority = .required
        chartView.widthConstraint?.isActive = true
        chartView.configure(series: series, language: catalogLanguage)
        chartScrollView.layoutIfNeeded()
        let trailing = max(0, chartScrollView.contentSize.width - chartScrollView.bounds.width)
        chartScrollView.setContentOffset(CGPoint(x: trailing, y: 0), animated: false)

        if let last = series.points.last { show(point: last) }
        rebuildSummary(series)
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
            unit: "/\(series.points.count)",
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

    private func show(point: DailyConsumptionPoint) {
        guard let date = FeatureFormatting.localDayDate(point.day), let series else { return }
        let status: String
        switch point.status {
        case .noTarget: status = L10n.text("target.no_target")
        case .below: status = L10n.text("target.below")
        case .within: status = L10n.text("target.within")
        case .above: status = L10n.text("target.above")
        }
        selectedPointLabel.text = "\(WellnarioFormatters.shortDate(date)) · \(FeatureFormatting.decimal(point.amount)) \(series.unit.symbol(languageCode: catalogLanguage.rawValue)) · \(status)"
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
            self.rebuildPeriodButtons()
            self.reloadContent()
        }
        presentSheet(controller, largeOnly: true)
    }

}

@MainActor
private final class ConsumptionChartView: UIView {
    var widthConstraint: NSLayoutConstraint?
    var onSelection: ((DailyConsumptionPoint) -> Void)?

    private var series: ConsumptionSeries?
    private var language: CatalogLanguage = .spanish
    private var selectedIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = [.image, .adjustable]
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(series: ConsumptionSeries, language: CatalogLanguage) {
        self.series = series
        self.language = language
        selectedIndex = series.points.indices.last
        accessibilityLabel = L10n.text("trends.chart.accessibility", series.points.count, FeatureFormatting.decimal(series.average), series.unit.symbol(languageCode: language.rawValue))
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let series, !series.points.isEmpty, let context = UIGraphicsGetCurrentContext() else { return }
        let plot = rect.inset(by: UIEdgeInsets(top: 20, left: 14, bottom: 30, right: 14))
        let amounts = series.points.map { FeatureFormatting.double($0.amount) }
        let targetMax = series.points.compactMap { $0.targetUpper }.map(FeatureFormatting.double).max() ?? 0
        let maximum = max(amounts.max() ?? 0, targetMax, FeatureFormatting.double(series.average), 1) * 1.15
        let step = plot.width / CGFloat(series.points.count)
        let barWidth = max(2, min(step * 0.62, 18))

        context.saveGState()
        let grid = UIBezierPath()
        for line in 0...3 {
            let y = plot.minY + plot.height * CGFloat(line) / 3
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
        }
        grid.setLineDash([2, 5], count: 2, phase: 0)
        WellnarioPalette.hairline.setStroke()
        grid.lineWidth = 1
        grid.stroke()

        context.setFillColor(WellnarioPalette.violet.withAlphaComponent(0.16).cgColor)
        for (index, point) in series.points.enumerated() {
            guard let lower = point.targetLower, let upper = point.targetUpper else { continue }
            let lowerY = plot.maxY - plot.height * CGFloat(FeatureFormatting.double(lower) / maximum)
            let upperY = plot.maxY - plot.height * CGFloat(FeatureFormatting.double(upper) / maximum)
            let bandRect = CGRect(
                x: plot.minX + (CGFloat(index) * step),
                y: upperY,
                width: step + 0.5,
                height: max(2, lowerY - upperY)
            )
            context.fill(bandRect)
        }

        for (index, value) in amounts.enumerated() {
            let height = plot.height * CGFloat(value / maximum)
            let x = plot.minX + step * (CGFloat(index) + 0.5) - barWidth / 2
            let bar = UIBezierPath(roundedRect: CGRect(x: x, y: plot.maxY - height, width: barWidth, height: max(1, height)), cornerRadius: barWidth / 2)
            let color: UIColor
            switch series.points[index].status {
            case .within: color = WellnarioPalette.success
            case .above: color = WellnarioPalette.warning
            case .below: color = WellnarioPalette.cyan
            case .noTarget: color = WellnarioPalette.violet
            }
            color.withAlphaComponent(index == selectedIndex ? 1 : 0.78).setFill()
            bar.fill()
        }

        let average = FeatureFormatting.double(series.average)
        let averageY = plot.maxY - plot.height * CGFloat(average / maximum)
        let averagePath = UIBezierPath()
        averagePath.move(to: CGPoint(x: plot.minX, y: averageY))
        averagePath.addLine(to: CGPoint(x: plot.maxX, y: averageY))
        averagePath.setLineDash([7, 5], count: 2, phase: 0)
        WellnarioPalette.magenta.setStroke()
        averagePath.lineWidth = 2
        averagePath.stroke()

        if let selectedIndex {
            let x = plot.minX + step * (CGFloat(selectedIndex) + 0.5)
            context.setStrokeColor(WellnarioPalette.textPrimary.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: x, y: plot.minY))
            context.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.strokePath()
        }
        context.restoreGState()

        let labelStride = max(1, series.points.count / 6)
        for index in stride(from: 0, to: series.points.count, by: labelStride) {
            guard let date = FeatureFormatting.localDayDate(series.points[index].day) else { continue }
            let formatter = DateFormatter()
            formatter.locale = LocalizationManager.shared.locale
            formatter.dateFormat = series.points.count > 60 ? "MMM" : "d/M"
            let text = formatter.string(from: date) as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: WellnarioTypography.font(for: .caption),
                .foregroundColor: WellnarioPalette.textTertiary
            ]
            let size = text.size(withAttributes: attributes)
            let x = plot.minX + step * (CGFloat(index) + 0.5) - size.width / 2
            text.draw(at: CGPoint(x: x, y: plot.maxY + 8), withAttributes: attributes)
        }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let series, !series.points.isEmpty else { return }
        let plot = bounds.inset(by: UIEdgeInsets(top: 20, left: 14, bottom: 30, right: 14))
        let location = gesture.location(in: self)
        let progress = min(0.999, max(0, (location.x - plot.minX) / max(plot.width, 1)))
        selectedIndex = min(series.points.count - 1, Int(progress * CGFloat(series.points.count)))
        setNeedsDisplay()
        if let selectedIndex { onSelection?(series.points[selectedIndex]) }
    }

    override func accessibilityIncrement() { moveSelection(by: 1) }
    override func accessibilityDecrement() { moveSelection(by: -1) }

    private func moveSelection(by amount: Int) {
        guard let series, !series.points.isEmpty else { return }
        selectedIndex = min(series.points.count - 1, max(0, (selectedIndex ?? 0) + amount))
        setNeedsDisplay()
        guard let selectedIndex else { return }
        let point = series.points[selectedIndex]
        onSelection?(point)
        accessibilityValue = "\(point.day.iso8601), \(FeatureFormatting.decimal(point.amount)) \(series.unit.symbol(languageCode: language.rawValue))"
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
