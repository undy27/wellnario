import UIKit

@MainActor
class WellnessScrollViewController: UIViewController {
    let scrollView = UIScrollView()
    let contentStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WellnarioPalette.background
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)

        contentStack.axis = .vertical
        contentStack.spacing = WellnarioSpacing.cardGap
        scrollView.addForAutoLayout(contentStack)
        NSLayoutConstraint.activate([
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
                constant: WellnarioSpacing.xSmall
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
    }

    func makeSectionTitle(_ title: String, detail: String? = nil) -> UIView {
        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = title
        titleLabel.numberOfLines = 0

        let detailLabel = UILabel()
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        detailLabel.text = detail
        detailLabel.textAlignment = .right
        detailLabel.numberOfLines = 2
        detailLabel.isHidden = detail == nil

        return UIStackView(
            arrangedSubviews: [titleLabel, UIView(), detailLabel],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .firstBaseline
        )
    }

    func makeCard(containing content: UIView, identifier: String? = nil) -> PremiumCardView {
        let card = PremiumCardView()
        card.accessibilityIdentifier = identifier
        card.contentView.addForAutoLayout(content)
        content.pinEdges(to: card.contentView, insets: .all(WellnarioSpacing.cardPadding))
        return card
    }

    func presentSheet(_ controller: UIViewController, largeOnly: Bool = false) {
        let navigationController = controller as? UINavigationController
            ?? UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .pageSheet
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = largeOnly ? [.large()] : [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = WellnarioRadius.card
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(navigationController, animated: true)
    }
}

@MainActor
final class SleepStageTimelineView: UIView {
    private struct DisplayInterval {
        let startDate: Date
        let endDate: Date
        let stage: AppleHealthSleepStage
    }

    private let horizontalLabelInset: CGFloat = 90
    private let durationLabelWidth: CGFloat = 64
    private let durationLabelGap: CGFloat = 6
    private let topInset: CGFloat = 8
    private let bottomInset: CGFloat = 28
    private var sessionStart: Date?
    private var sessionEnd: Date?
    private var displayIntervals: [DisplayInterval] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 164)
    }

    func configure(session: AppleHealthSleepSession?) {
        sessionStart = session?.startDate
        sessionEnd = session?.endDate
        displayIntervals = (session?.stageIntervals ?? [])
            .filter { $0.endDate > $0.startDate }
            .sorted { $0.startDate < $1.startDate }
            .map {
                DisplayInterval(startDate: $0.startDate, endDate: $0.endDate, stage: $0.stage)
            }
        accessibilityValue = displayIntervals.isEmpty
            ? L10n.text("sleep.stage.timeline.empty")
            : L10n.text("sleep.stage.timeline.accessibility.value", displayIntervals.count)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let plot = CGRect(
            x: horizontalLabelInset,
            y: topInset,
            width: max(
                0,
                bounds.width - horizontalLabelInset - durationLabelGap - durationLabelWidth
            ),
            height: max(0, bounds.height - topInset - bottomInset)
        )
        guard plot.width > 0, plot.height > 0 else { return }

        drawStageGuides(in: plot, context: context)
        guard let sessionStart,
              let sessionEnd,
              sessionEnd > sessionStart,
              !displayIntervals.isEmpty else {
            drawEmptyState(in: plot)
            return
        }

        drawStageDurations(nextTo: plot)
        drawTimeline(
            in: plot,
            from: sessionStart,
            through: sessionEnd,
            context: context
        )
        drawTimeLabels(start: sessionStart, end: sessionEnd, below: plot)
    }

    private func setUp() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = L10n.text("sleep.stage.timeline.title")
        accessibilityTraits = [.image]
        contentMode = .redraw
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (self: SleepStageTimelineView, _: UITraitCollection) in
            self.setNeedsDisplay()
        }
    }

    private var orderedStages: [AppleHealthSleepStage] {
        [.awake, .rem, .core, .deep]
    }

    private func drawStageGuides(in plot: CGRect, context: CGContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: timelineFont(
                size: 15,
                maximumPointSize: 18,
                weight: .regular,
                textStyle: .subheadline
            ),
            .foregroundColor: WellnarioPalette.textTertiary,
            .paragraphStyle: paragraph
        ]

        context.saveGState()
        context.setLineWidth(1)
        context.setStrokeColor(WellnarioPalette.hairline.cgColor)
        context.setLineDash(phase: 0, lengths: [3, 5])
        for stage in orderedStages {
            let y = yPosition(for: stage, in: plot)
            context.move(to: CGPoint(x: plot.minX, y: y))
            context.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.strokePath()

            let labelRect = CGRect(x: 0, y: y - 12, width: horizontalLabelInset - 8, height: 24)
            stageTitle(stage).draw(in: labelRect, withAttributes: attributes)
        }
        context.restoreGState()
    }

    private func drawStageDurations(nextTo plot: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let durationRectX = plot.maxX + durationLabelGap

        for stage in orderedStages {
            let duration = displayIntervals.reduce(0) { total, interval in
                guard displayStage(interval.stage) == stage else { return total }
                return total + interval.endDate.timeIntervalSince(interval.startDate)
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: timelineFont(
                    size: 15,
                    maximumPointSize: 18,
                    weight: .regular,
                    textStyle: .subheadline,
                    usesMonospacedDigits: true
                ),
                .foregroundColor: stageColor(stage).withAlphaComponent(0.9),
                .paragraphStyle: paragraph
            ]
            AppleHealthUIFormatting.compactDuration(duration).draw(
                in: CGRect(
                    x: durationRectX,
                    y: yPosition(for: stage, in: plot) - 11,
                    width: durationLabelWidth,
                    height: 22
                ),
                withAttributes: attributes
            )
        }
    }

    private func drawTimeline(
        in plot: CGRect,
        from start: Date,
        through end: Date,
        context: CGContext
    ) {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return }

        func xPosition(_ date: Date) -> CGFloat {
            let progress = min(1, max(0, date.timeIntervalSince(start) / duration))
            return plot.minX + plot.width * progress
        }

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)

        var previous: DisplayInterval?
        for interval in displayIntervals {
            let displayedStage = displayStage(interval.stage)
            let x1 = xPosition(interval.startDate)
            let x2 = max(x1 + 1, xPosition(interval.endDate))
            let y = yPosition(for: displayedStage, in: plot)

            if let previous,
               abs(interval.startDate.timeIntervalSince(previous.endDate)) <= 90 {
                let previousY = yPosition(for: displayStage(previous.stage), in: plot)
                context.setStrokeColor(WellnarioPalette.textTertiary.withAlphaComponent(0.55).cgColor)
                context.setLineWidth(1.5)
                context.move(to: CGPoint(x: x1, y: previousY))
                context.addLine(to: CGPoint(x: x1, y: y))
                context.strokePath()
            }

            context.setStrokeColor(stageColor(interval.stage).cgColor)
            context.setLineWidth(6)
            context.move(to: CGPoint(x: x1, y: y))
            context.addLine(to: CGPoint(x: x2, y: y))
            context.strokePath()
            previous = interval
        }
        context.restoreGState()
    }

    private func drawTimeLabels(start: Date, end: Date, below plot: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: timelineFont(
                size: 15,
                maximumPointSize: 18,
                weight: .regular,
                textStyle: .subheadline,
                usesMonospacedDigits: true
            ),
            .foregroundColor: WellnarioPalette.textTertiary,
            .paragraphStyle: paragraph
        ]
        let labelY = plot.maxY + 4
        paragraph.alignment = .left
        WellnarioFormatters.time(start).draw(
            in: CGRect(x: plot.minX, y: labelY, width: plot.width / 2, height: 24),
            withAttributes: baseAttributes
        )
        paragraph.alignment = .right
        WellnarioFormatters.time(end).draw(
            in: CGRect(x: plot.midX, y: labelY, width: plot.width / 2, height: 24),
            withAttributes: baseAttributes
        )
    }

    private func drawEmptyState(in plot: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: timelineFont(
                size: 15,
                maximumPointSize: 18,
                weight: .regular,
                textStyle: .subheadline
            ),
            .foregroundColor: WellnarioPalette.textTertiary,
            .paragraphStyle: paragraph
        ]
        let rect = CGRect(x: plot.minX, y: plot.midY - 40, width: plot.width, height: 80)
        L10n.text("sleep.stage.timeline.empty").draw(in: rect, withAttributes: attributes)
    }

    private func timelineFont(
        size: CGFloat,
        maximumPointSize: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle,
        usesMonospacedDigits: Bool = false
    ) -> UIFont {
        let base = usesMonospacedDigits
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: base,
            maximumPointSize: maximumPointSize,
            compatibleWith: traitCollection
        )
    }

    private func displayStage(_ stage: AppleHealthSleepStage) -> AppleHealthSleepStage {
        stage == .asleepUnspecified ? .core : stage
    }

    private func yPosition(for stage: AppleHealthSleepStage, in plot: CGRect) -> CGFloat {
        let displayedStage = displayStage(stage)
        let index = orderedStages.firstIndex(of: displayedStage) ?? 2
        let rowHeight = plot.height / CGFloat(orderedStages.count)
        return plot.minY + rowHeight * (CGFloat(index) + 0.5)
    }

    private func stageTitle(_ stage: AppleHealthSleepStage) -> String {
        switch stage {
        case .awake: L10n.text("sleep.stage.awake")
        case .rem: L10n.text("sleep.stage.rem")
        case .core, .asleepUnspecified: L10n.text("sleep.stage.light")
        case .deep: L10n.text("sleep.stage.deep")
        }
    }

    private func stageColor(_ stage: AppleHealthSleepStage) -> UIColor {
        switch stage {
        case .awake: WellnarioPalette.pink
        case .rem: WellnarioPalette.fuchsia
        case .core: WellnarioPalette.information
        case .deep: WellnarioPalette.violet
        case .asleepUnspecified: WellnarioPalette.textSecondary
        }
    }
}

@MainActor
final class WellnessSummaryCard: PremiumCardView {
    private let symbolContainer = UIView()
    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let detailLabel = UILabel()
    private let chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))

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
        value: String,
        detail: String,
        tone: UIColor,
        showsDisclosure: Bool = true
    ) {
        titleLabel.text = title
        symbolView.image = UIImage(systemName: symbolName)
        symbolView.tintColor = tone
        symbolContainer.backgroundColor = tone.withAlphaComponent(0.14)
        valueLabel.text = value
        detailLabel.text = detail
        chevronView.isHidden = !showsDisclosure
        accessibilityLabel = title
        accessibilityValue = [value, detail].filter { !$0.isEmpty }.joined(separator: ", ")
        accessibilityTraits = showsDisclosure ? [.button] : [.summaryElement]
        isPressable = showsDisclosure
    }

    private func setUp() {
        symbolContainer.applyContinuousCorners(11)
        NSLayoutConstraint.activate([
            symbolContainer.widthAnchor.constraint(equalToConstant: 34),
            symbolContainer.heightAnchor.constraint(equalTo: symbolContainer.widthAnchor)
        ])

        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        symbolView.contentMode = .scaleAspectFit
        symbolContainer.addForAutoLayout(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor)
        ])

        chevronView.tintColor = WellnarioPalette.textTertiary
        chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.applyWellnarioStyle(.summaryTitle, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.78
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        valueLabel.applyWellnarioStyle(.summaryMetric, color: WellnarioPalette.textPrimary)
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.76
        valueLabel.numberOfLines = 1

        detailLabel.applyWellnarioStyle(.summaryDetail, color: WellnarioPalette.textSecondary)
        detailLabel.numberOfLines = 2

        let heading = UIStackView(
            arrangedSubviews: [symbolContainer, titleLabel, UIView(), chevronView],
            axis: .horizontal,
            spacing: 7,
            alignment: .center
        )
        let stack = UIStackView(
            arrangedSubviews: [heading, valueLabel, detailLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        contentView.addForAutoLayout(stack)
        stack.pinEdges(to: contentView, insets: .all(WellnarioSpacing.xSmall))
        heightAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true
        isAccessibilityElement = true
    }
}

@MainActor
final class QuickActionControl: UIControl {
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override var isHighlighted: Bool {
        didSet {
            WellnarioMotion.spring(duration: 0.16) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.975, y: 0.975)
                    : .identity
                self.alpha = self.isHighlighted ? 0.82 : 1
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(title: String, detail: String, symbolName: String, tone: UIColor) {
        titleLabel.text = title
        detailLabel.text = detail
        iconView.image = UIImage(systemName: symbolName)
        iconView.tintColor = tone
        iconContainer.backgroundColor = tone.withAlphaComponent(0.14)
        accessibilityLabel = title
        accessibilityHint = detail
    }

    private func setUp() {
        backgroundColor = WellnarioPalette.surface
        applyContinuousCorners(WellnarioRadius.card)
        layer.borderWidth = 1
        layer.borderColor = WellnarioPalette.hairline.cgColor

        iconContainer.applyContinuousCorners(13)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 42),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor)
        ])
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        iconContainer.addForAutoLayout(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
        ])

        titleLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 2
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        detailLabel.numberOfLines = 2

        let textStack = UIStackView(
            arrangedSubviews: [titleLabel, detailLabel],
            axis: .vertical,
            spacing: 3
        )
        let stack = UIStackView(
            arrangedSubviews: [iconContainer, textStack],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        stack.isUserInteractionEnabled = false
        addForAutoLayout(stack)
        stack.pinEdges(to: self, insets: .all(WellnarioSpacing.small))
        heightAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true

        isAccessibilityElement = true
        accessibilityTraits = [.button]
    }
}

enum WellnessTrendSmoothing {
    static func movingAverage(_ values: [Double?], window: Int) -> [Double?] {
        guard window > 1, !values.isEmpty else { return values }
        let leadingRadius = window / 2
        let trailingRadius = max(window - leadingRadius - 1, 0)
        return values.indices.map { index in
            guard values[index] != nil else { return nil }
            let lowerBound = max(values.startIndex, index - leadingRadius)
            let upperBound = min(values.index(before: values.endIndex), index + trailingRadius)
            let samples = values[lowerBound...upperBound].compactMap { $0 }
            guard !samples.isEmpty else { return nil }
            return samples.reduce(0, +) / Double(samples.count)
        }
    }
}

struct WellnessTrendBounds: Equatable {
    let lower: Double
    let upper: Double
}

enum WellnessTrendScale {
    static func bounds(for values: [Double?]) -> WellnessTrendBounds? {
        let validValues = values.compactMap { $0 }
        guard let minimum = validValues.min(), let maximum = validValues.max() else { return nil }

        let spread = maximum - minimum
        let padding = spread > 0
            ? max(spread * 0.12, max(abs(maximum) * 0.015, 0.08))
            : max(abs(maximum) * 0.05, 0.25)
        let lower = max(0, minimum - padding)
        return WellnessTrendBounds(
            lower: lower,
            upper: max(maximum + padding, lower + 0.001)
        )
    }
}

struct WellnessLinearTrend: Equatable {
    let startPosition: Double
    let startValue: Double
    let endPosition: Double
    let endValue: Double
}

enum WellnessLinearRegression {
    static func fit(values: [Double?]) -> WellnessLinearTrend? {
        let samples = values.enumerated().compactMap { index, value -> (x: Double, y: Double)? in
            guard let value else { return nil }
            return (Double(index), value)
        }
        guard samples.count >= 2, values.count >= 2 else { return nil }

        let sampleCount = Double(samples.count)
        let meanX = samples.reduce(0) { $0 + $1.x } / sampleCount
        let meanY = samples.reduce(0) { $0 + $1.y } / sampleCount
        let denominator = samples.reduce(0) { result, sample in
            let distance = sample.x - meanX
            return result + distance * distance
        }
        guard denominator > .ulpOfOne else { return nil }

        let numerator = samples.reduce(0) { result, sample in
            result + (sample.x - meanX) * (sample.y - meanY)
        }
        let slope = numerator / denominator
        let intercept = meanY - slope * meanX
        let positionRange = Double(values.count - 1)
        let startX = samples[0].x
        let endX = samples[samples.count - 1].x
        return WellnessLinearTrend(
            startPosition: startX / positionRange,
            startValue: intercept + slope * startX,
            endPosition: endX / positionRange,
            endValue: intercept + slope * endX
        )
    }
}

enum WellnessTrendReferenceLine: Int, CaseIterable {
    case average
    case linearTrend
}

@MainActor
final class WellnessTrendChartView: UIView {
    var values: [Double?] = [] {
        didSet {
            selectedIndex = nil
            setNeedsDisplay()
        }
    }
    var labels: [String] = [] { didSet { setNeedsDisplay() } }
    var selectionLabels: [String] = [] { didSet { setNeedsDisplay() } }
    var lineColor = WellnarioPalette.violet { didSet { setNeedsDisplay() } }
    var emptyText = "" { didSet { setNeedsDisplay() } }
    var smoothingWindow = 1 { didSet { setNeedsDisplay() } }
    var averageTitle = "" { didSet { setNeedsDisplay() } }
    var averageColor = WellnarioPalette.cyan { didSet { setNeedsDisplay() } }
    var linearTrend: WellnessLinearTrend? { didSet { setNeedsDisplay() } }
    var referenceLine = WellnessTrendReferenceLine.linearTrend { didSet { setNeedsDisplay() } }
    var linearTrendColor: UIColor {
        guard let linearTrend else { return WellnarioPalette.textSecondary }
        if linearTrend.endValue > linearTrend.startValue { return WellnarioPalette.success }
        if linearTrend.endValue < linearTrend.startValue { return WellnarioPalette.danger }
        return WellnarioPalette.textSecondary
    }
    var valueFormatter: (Double) -> String = { String(format: "%.1f", $0) } {
        didSet { setNeedsDisplay() }
    }
    private(set) var selectedIndex: Int? {
        didSet { setNeedsDisplay() }
    }
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = [.image, .adjustable]

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSelectionPan))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 190)
    }

    override func draw(_ rect: CGRect) {
        let chartRect = plotRect(in: rect)
        drawGrid(in: chartRect)
        drawLabels(in: chartRect)

        let plottedValues = plottedValues
        let trendScaleValues: [Double?] = referenceLine == .linearTrend
            ? [linearTrend?.startValue, linearTrend?.endValue]
            : []
        let scaleValues = plottedValues + trendScaleValues
        guard plottedValues.contains(where: { $0 != nil }),
              let bounds = WellnessTrendScale.bounds(for: scaleValues) else {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: WellnarioTypography.font(for: .secondary),
                .foregroundColor: WellnarioPalette.textTertiary,
                .paragraphStyle: paragraph
            ]
            let emptyRect = CGRect(
                x: chartRect.minX + 12,
                y: chartRect.midY - 30,
                width: max(chartRect.width - 24, 0),
                height: 60
            )
            (emptyText as NSString).draw(
                with: emptyRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
            return
        }

        let lower = bounds.lower
        let upper = bounds.upper
        let range = upper - lower
        let periodValues = values.compactMap { $0 }
        let average = periodValues.reduce(0, +) / Double(periodValues.count)
        drawYAxisLabels(minimum: lower, maximum: upper, in: chartRect)

        let pointCount = max(values.count, 2)

        var points: [CGPoint] = []
        for (index, value) in plottedValues.enumerated() {
            guard let value else { continue }
            points.append(CGPoint(
                x: chartRect.minX + chartRect.width * CGFloat(index) / CGFloat(pointCount - 1),
                y: chartRect.maxY - chartRect.height * CGFloat((value - lower) / range)
            ))
        }
        guard points.count > 1 else {
            if let point = points.first {
                lineColor.withAlphaComponent(0.20).setFill()
                UIBezierPath(ovalIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)).fill()
                lineColor.setFill()
                UIBezierPath(ovalIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)).fill()
            }
            drawReferenceLine(average: average, lower: lower, range: range, in: chartRect)
            drawSelection(plottedValues: plottedValues, lower: lower, range: range, in: chartRect)
            return
        }

        let fillPath = UIBezierPath()
        fillPath.move(to: CGPoint(x: points[0].x, y: chartRect.maxY))
        fillPath.addLine(to: points[0])
        addSmoothCurve(points: points, to: fillPath)
        fillPath.addLine(to: CGPoint(x: points.last!.x, y: chartRect.maxY))
        fillPath.close()
        lineColor.withAlphaComponent(0.12).setFill()
        fillPath.fill()

        let linePath = UIBezierPath()
        linePath.move(to: points[0])
        addSmoothCurve(points: points, to: linePath)
        lineColor.setStroke()
        linePath.lineWidth = 3
        linePath.lineCapStyle = .round
        linePath.lineJoinStyle = .round
        linePath.stroke()

        drawReferenceLine(average: average, lower: lower, range: range, in: chartRect)

        if let last = points.last {
            lineColor.withAlphaComponent(0.20).setFill()
            UIBezierPath(ovalIn: CGRect(x: last.x - 7, y: last.y - 7, width: 14, height: 14)).fill()
            lineColor.setFill()
            UIBezierPath(ovalIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7)).fill()
        }
        drawSelection(plottedValues: plottedValues, lower: lower, range: range, in: chartRect)
    }

    func updateSelection(atX locationX: CGFloat) {
        let plottedValues = plottedValues
        guard plottedValues.count > 1 else {
            selectIndex(
                plottedValues.indices.first(where: { plottedValues[$0] != nil }),
                providesFeedback: true
            )
            return
        }
        let chartRect = plotRect(in: bounds)
        guard chartRect.width > 0 else { return }
        let relativeX = min(max((locationX - chartRect.minX) / chartRect.width, 0), 1)
        let targetIndex = Int((relativeX * CGFloat(plottedValues.count - 1)).rounded())
        let newIndex = plottedValues.indices
            .filter { plottedValues[$0] != nil }
            .min { abs($0 - targetIndex) < abs($1 - targetIndex) }
        selectIndex(newIndex, providesFeedback: true)
    }

    func clearSelection() {
        selectedIndex = nil
    }

    override func accessibilityIncrement() {
        moveAccessibleSelection(forward: true)
    }

    override func accessibilityDecrement() {
        moveAccessibleSelection(forward: false)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) >= abs(velocity.y)
    }

    @objc private func handleSelectionPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            selectionFeedbackGenerator.prepare()
            updateSelection(atX: recognizer.location(in: self).x)
        case .changed:
            updateSelection(atX: recognizer.location(in: self).x)
        case .ended, .cancelled, .failed:
            clearSelection()
        default:
            break
        }
    }

    private func selectIndex(_ index: Int?, providesFeedback: Bool) {
        guard selectedIndex != index else { return }
        selectedIndex = index
        guard providesFeedback, index != nil else { return }
        selectionFeedbackGenerator.selectionChanged()
        selectionFeedbackGenerator.prepare()
    }

    private func moveAccessibleSelection(forward: Bool) {
        let plottedValues = plottedValues
        let validIndexes = plottedValues.indices.filter { plottedValues[$0] != nil }
        guard !validIndexes.isEmpty else { return }
        if let selectedIndex, let position = validIndexes.firstIndex(of: selectedIndex) {
            let offset = forward ? 1 : -1
            let nextPosition = min(max(position + offset, 0), validIndexes.count - 1)
            self.selectedIndex = validIndexes[nextPosition]
        } else {
            selectedIndex = forward ? validIndexes.first : validIndexes.last
        }
        if let selectionText = selectionText(for: plottedValues) {
            accessibilityValue = selectionText
            UIAccessibility.post(notification: .announcement, argument: selectionText)
        }
    }

    private func plotRect(in rect: CGRect) -> CGRect {
        rect.inset(by: UIEdgeInsets(top: 18, left: 42, bottom: 30, right: 7))
    }

    private func drawYAxisLabels(minimum: Double, maximum: Double, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: WellnarioTypography.font(for: .summaryDetail),
            .foregroundColor: WellnarioPalette.textSecondary
        ]
        let maximumText = valueFormatter(maximum)
        let minimumText = valueFormatter(minimum)
        let maximumSize = maximumText.size(withAttributes: attributes)
        let minimumSize = minimumText.size(withAttributes: attributes)
        maximumText.draw(
            at: CGPoint(x: rect.minX - maximumSize.width - 7, y: rect.minY - maximumSize.height / 2),
            withAttributes: attributes
        )
        minimumText.draw(
            at: CGPoint(x: rect.minX - minimumSize.width - 7, y: rect.maxY - minimumSize.height / 2),
            withAttributes: attributes
        )
    }

    private func drawAverageLine(value: Double, lower: Double, range: Double, in rect: CGRect) {
        let y = rect.maxY - rect.height * CGFloat((value - lower) / range)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
        path.setLineDash([6, 4], count: 2, phase: 0)
        averageColor.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        guard !averageTitle.isEmpty else { return }
        let text = "\(averageTitle) \(valueFormatter(value))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: WellnarioTypography.font(for: .summaryDetail),
            .foregroundColor: averageColor
        ]
        let size = text.size(withAttributes: attributes)
        let labelRect = CGRect(
            x: rect.maxX - size.width - 8,
            y: min(max(rect.minY + 3, y - size.height - 5), rect.maxY - size.height - 3),
            width: size.width + 8,
            height: size.height + 3
        )
        let background = UIBezierPath(roundedRect: labelRect, cornerRadius: 5)
        WellnarioPalette.surfaceElevated.withAlphaComponent(0.92).setFill()
        background.fill()
        text.draw(
            at: CGPoint(x: labelRect.minX + 4, y: labelRect.minY + 1),
            withAttributes: attributes
        )
    }

    private func drawReferenceLine(average: Double, lower: Double, range: Double, in rect: CGRect) {
        switch referenceLine {
        case .average:
            drawAverageLine(value: average, lower: lower, range: range, in: rect)
        case .linearTrend:
            drawLinearTrend(lower: lower, range: range, in: rect)
        }
    }

    private func drawLinearTrend(lower: Double, range: Double, in rect: CGRect) {
        guard let linearTrend else { return }
        let startX = rect.minX + rect.width * CGFloat(linearTrend.startPosition)
        let endX = rect.minX + rect.width * CGFloat(linearTrend.endPosition)
        let startY = rect.maxY - rect.height * CGFloat((linearTrend.startValue - lower) / range)
        let endY = rect.maxY - rect.height * CGFloat((linearTrend.endValue - lower) / range)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: startX, y: startY))
        path.addLine(to: CGPoint(x: endX, y: endY))
        path.setLineDash([10, 4, 2, 4], count: 4, phase: 0)
        linearTrendColor.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.stroke()

        drawLinearTrendEndpointValues(
            start: CGPoint(x: startX, y: startY),
            end: CGPoint(x: endX, y: endY),
            in: rect
        )
    }

    private func drawLinearTrendEndpointValues(start: CGPoint, end: CGPoint, in rect: CGRect) {
        guard let linearTrend else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: WellnarioTypography.font(for: .summaryDetail),
            .foregroundColor: linearTrendColor
        ]
        let startText = valueFormatter(linearTrend.startValue)
        let endText = valueFormatter(linearTrend.endValue)
        let startRect = trendEndpointLabelRect(
            textSize: startText.size(withAttributes: attributes),
            anchor: start,
            alignsTrailing: false,
            prefersAbove: true,
            in: rect
        )
        var endRect = trendEndpointLabelRect(
            textSize: endText.size(withAttributes: attributes),
            anchor: end,
            alignsTrailing: true,
            prefersAbove: true,
            in: rect
        )
        if startRect.insetBy(dx: -2, dy: -2).intersects(endRect) {
            endRect = trendEndpointLabelRect(
                textSize: endText.size(withAttributes: attributes),
                anchor: end,
                alignsTrailing: true,
                prefersAbove: false,
                in: rect
            )
        }
        drawTrendEndpointLabel(startText, in: startRect, attributes: attributes)
        drawTrendEndpointLabel(endText, in: endRect, attributes: attributes)
    }

    private func trendEndpointLabelRect(
        textSize: CGSize,
        anchor: CGPoint,
        alignsTrailing: Bool,
        prefersAbove: Bool,
        in rect: CGRect
    ) -> CGRect {
        let size = CGSize(width: textSize.width + 8, height: textSize.height + 4)
        let proposedX = alignsTrailing ? anchor.x - size.width : anchor.x
        let x = min(max(proposedX, rect.minX), rect.maxX - size.width)
        let aboveY = anchor.y - size.height - 3
        let belowY = anchor.y + 3
        let y: CGFloat
        if prefersAbove {
            y = aboveY >= rect.minY ? aboveY : min(belowY, rect.maxY - size.height)
        } else {
            y = belowY + size.height <= rect.maxY ? belowY : max(aboveY, rect.minY)
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func drawTrendEndpointLabel(
        _ text: String,
        in rect: CGRect,
        attributes: [NSAttributedString.Key: Any]
    ) {
        WellnarioPalette.surfaceElevated.withAlphaComponent(0.94).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 5).fill()
        text.draw(
            at: CGPoint(x: rect.minX + 4, y: rect.minY + 2),
            withAttributes: attributes
        )
    }

    private func drawSelection(
        plottedValues: [Double?],
        lower: Double,
        range: Double,
        in rect: CGRect
    ) {
        guard let selectedIndex,
              plottedValues.indices.contains(selectedIndex),
              let value = plottedValues[selectedIndex] else {
            return
        }

        let pointCount = max(values.count, 2)
        let x = rect.minX + rect.width * CGFloat(selectedIndex) / CGFloat(pointCount - 1)
        let y = rect.maxY - rect.height * CGFloat((value - lower) / range)

        let guide = UIBezierPath()
        guide.move(to: CGPoint(x: x, y: rect.minY))
        guide.addLine(to: CGPoint(x: x, y: rect.maxY))
        lineColor.withAlphaComponent(0.62).setStroke()
        guide.lineWidth = 1
        guide.stroke()

        WellnarioPalette.surfaceElevated.setFill()
        UIBezierPath(ovalIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)).fill()
        lineColor.setFill()
        UIBezierPath(ovalIn: CGRect(x: x - 3.5, y: y - 3.5, width: 7, height: 7)).fill()

        guard let selectionText = selectionText(for: plottedValues) else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: WellnarioPalette.textPrimary
        ]
        let textSize = selectionText.size(withAttributes: attributes)
        let bubbleSize = CGSize(
            width: min(textSize.width + 18, rect.width - 8),
            height: textSize.height + 10
        )
        let bubbleX = min(max(x - bubbleSize.width / 2, rect.minX + 4), rect.maxX - bubbleSize.width - 4)
        let bubbleRect = CGRect(
            x: bubbleX,
            y: rect.minY + 5,
            width: bubbleSize.width,
            height: bubbleSize.height
        )
        let bubble = UIBezierPath(roundedRect: bubbleRect, cornerRadius: bubbleRect.height / 2)
        WellnarioPalette.surfaceElevated.withAlphaComponent(0.98).setFill()
        bubble.fill()
        lineColor.withAlphaComponent(0.75).setStroke()
        bubble.lineWidth = 1
        bubble.stroke()
        selectionText.draw(
            at: CGPoint(
                x: bubbleRect.midX - textSize.width / 2,
                y: bubbleRect.midY - textSize.height / 2
            ),
            withAttributes: attributes
        )
    }

    private func selectionText(for plottedValues: [Double?]) -> String? {
        guard let selectedIndex,
              plottedValues.indices.contains(selectedIndex),
              let value = plottedValues[selectedIndex] else {
            return nil
        }
        let date = selectionLabels.indices.contains(selectedIndex) ? selectionLabels[selectedIndex] : ""
        return [date, valueFormatter(value)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var plottedValues: [Double?] {
        WellnessTrendSmoothing.movingAverage(values, window: smoothingWindow)
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

    private func drawLabels(in rect: CGRect) {
        guard labels.count > 1 else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: WellnarioTypography.font(for: .caption),
            .foregroundColor: WellnarioPalette.textTertiary
        ]
        var previousLabelMaxX = -CGFloat.greatestFiniteMagnitude
        for (index, label) in labels.enumerated() {
            guard !label.isEmpty else { continue }
            let size = label.size(withAttributes: attributes)
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(labels.count - 1)
            let labelX = min(max(rect.minX, x - size.width / 2), rect.maxX - size.width)
            guard labelX >= previousLabelMaxX + 12 else { continue }
            label.draw(
                at: CGPoint(x: labelX, y: rect.maxY + 10),
                withAttributes: attributes
            )
            previousLabelMaxX = labelX + size.width
        }
    }

    private func addSmoothCurve(points: [CGPoint], to path: UIBezierPath) {
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let controlX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                controlPoint1: CGPoint(x: controlX, y: previous.y),
                controlPoint2: CGPoint(x: controlX, y: current.y)
            )
        }
    }
}

@MainActor
final class BiomarkerRowView: UIView {
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let valueLabel = UILabel()

    init(title: String, detail: String, value: String, symbolName: String, tone: UIColor) {
        super.init(frame: .zero)
        iconContainer.backgroundColor = tone.withAlphaComponent(0.13)
        iconContainer.applyContinuousCorners(12)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 40),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor)
        ])
        iconView.image = UIImage(systemName: symbolName)
        iconView.tintColor = tone
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        iconContainer.addForAutoLayout(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
        ])

        titleLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        titleLabel.text = title
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        detailLabel.text = detail
        valueLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textSecondary)
        valueLabel.text = value
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel], axis: .vertical, spacing: 3)
        let stack = UIStackView(
            arrangedSubviews: [iconContainer, labels, valueLabel],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        addForAutoLayout(stack)
        stack.pinEdges(to: self, insets: NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityValue = [value, detail].joined(separator: ", ")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
