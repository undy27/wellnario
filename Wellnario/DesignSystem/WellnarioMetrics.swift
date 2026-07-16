import UIKit

/// Peakwatch-style metric card with a title, compact visualization, large value
/// and a textual status. The status always accompanies its color.
final class MetricCardView: PremiumCardView {
    let titleLabel = UILabel()
    let iconImageView = UIImageView()
    let visualizationContainer = UIView()
    let valueLabel = UILabel()
    let statusLabel = UILabel()

    private var unit = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpMetricCard()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpMetricCard()
    }

    /// Configures the visible metric and a single VoiceOver summary.
    func configure(
        title: String,
        symbolName: String,
        value: String,
        unit: String = "",
        status: String,
        tone: WellnarioTone = .neutral
    ) {
        self.unit = unit
        titleLabel.text = title
        iconImageView.image = UIImage(systemName: symbolName)
        setValue(value, unit: unit)
        statusLabel.text = status
        statusLabel.textColor = WellnarioPalette.color(for: tone)
        iconImageView.tintColor = WellnarioPalette.color(for: tone).withAlphaComponent(0.82)
        accessibilityLabel = title
        accessibilityValue = [value + unit, status].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Embeds a compact custom visualization, replacing the previous one.
    func setVisualization(_ view: UIView) {
        visualizationContainer.subviews.forEach { $0.removeFromSuperview() }
        visualizationContainer.addForAutoLayout(view)
        view.pinEdges(to: visualizationContainer)
        view.isAccessibilityElement = false
    }

    private func setValue(_ value: String, unit: String) {
        let result = NSMutableAttributedString(
            string: value,
            attributes: [
                .font: WellnarioTypography.font(for: .metric),
                .foregroundColor: WellnarioPalette.textPrimary
            ]
        )
        if !unit.isEmpty {
            result.append(NSAttributedString(
                string: unit,
                attributes: [
                    .font: WellnarioTypography.font(for: .sectionTitle),
                    .foregroundColor: WellnarioPalette.textPrimary
                ]
            ))
        }
        valueLabel.attributedText = result
    }

    private func setUpMetricCard() {
        isAccessibilityElement = true
        accessibilityTraits = [.summaryElement]

        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 2
        titleLabel.allowsDefaultTighteningForTruncation = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        iconImageView.tintColor = WellnarioPalette.textTertiary
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.setContentHuggingPriority(.required, for: .horizontal)

        let topRow = UIStackView(
            arrangedSubviews: [titleLabel, iconImageView],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .top
        )

        visualizationContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true

        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        statusLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        statusLabel.textAlignment = .right
        statusLabel.numberOfLines = 2
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let bottomRow = UIStackView(
            arrangedSubviews: [valueLabel, statusLabel],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .lastBaseline
        )

        let stack = UIStackView(
            arrangedSubviews: [topRow, visualizationContainer, bottomRow],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        contentView.addForAutoLayout(stack)
        stack.pinEdges(to: contentView, insets: .all(WellnarioSpacing.cardPadding))
        heightAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.metricCardMinimumHeight).isActive = true
    }
}

/// A compact line chart intended for metric cards. It deliberately exposes one
/// summary rather than making every point a VoiceOver stop.
final class SparklineView: UIView {
    var values: [Double] = [] {
        didSet { setNeedsDisplay() }
    }

    var lineColor = WellnarioPalette.cyan {
        didSet { setNeedsDisplay() }
    }

    var showsEndMarker = true {
        didSet { setNeedsDisplay() }
    }

    var includesZeroBaseline = false {
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

    override func draw(_ rect: CGRect) {
        guard values.count > 1 else { return }

        let valueMinimum = values.min() ?? 0
        let minimum = includesZeroBaseline ? min(0, valueMinimum) : valueMinimum
        let maximum = values.max() ?? 1
        let range = max(maximum - minimum, 0.0001)
        let inset = rect.insetBy(dx: 4, dy: 7)
        let points = values.enumerated().map { index, value in
            CGPoint(
                x: inset.minX + inset.width * CGFloat(index) / CGFloat(values.count - 1),
                y: inset.maxY - inset.height * CGFloat((value - minimum) / range)
            )
        }

        let grid = UIBezierPath()
        grid.move(to: CGPoint(x: inset.minX, y: inset.maxY))
        grid.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
        grid.setLineDash([2, 4], count: 2, phase: 0)
        WellnarioPalette.hairline.setStroke()
        grid.lineWidth = 1
        grid.stroke()

        let path = UIBezierPath()
        path.move(to: points[0])
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
        lineColor.setStroke()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        if showsEndMarker, let last = points.last {
            lineColor.withAlphaComponent(0.22).setFill()
            UIBezierPath(ovalIn: CGRect(x: last.x - 7, y: last.y - 7, width: 14, height: 14)).fill()
            lineColor.setFill()
            UIBezierPath(ovalIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)).fill()
        }
    }

    private func setUp() {
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = [.image]
    }
}

/// Displays a current value, a target range and a marker over one normalized
/// bar. `domain` must encompass the complete chart scale.
final class TargetProgressView: UIView {
    private let trackLayer = CALayer()
    private let fillLayer = CAGradientLayer()
    private let targetLayer = CALayer()
    private let markerLayer = CALayer()

    private var value: Double = 0
    private var targetRange: ClosedRange<Double> = 0...0
    private var domain: ClosedRange<Double> = 0...1

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 18)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayerFrames(animated: false)
    }

    func set(
        value: Double,
        targetRange: ClosedRange<Double>,
        domain: ClosedRange<Double>,
        unit: String,
        animated: Bool = true
    ) {
        self.value = value
        self.targetRange = targetRange
        self.domain = domain
        accessibilityLabel = L10n.Common.targetProgress
        accessibilityValue = L10n.text(
            "accessibility.target_progress.value",
            WellnarioFormatters.number(value),
            unit,
            WellnarioFormatters.number(targetRange.lowerBound),
            WellnarioFormatters.number(targetRange.upperBound)
        )
        setNeedsLayout()
        layoutIfNeeded()
        updateLayerFrames(animated: animated)
    }

    private func setUp() {
        isAccessibilityElement = true
        accessibilityTraits = [.image]

        trackLayer.backgroundColor = WellnarioPalette.textPrimary.withAlphaComponent(0.10).cgColor
        layer.addSublayer(trackLayer)

        fillLayer.colors = [WellnarioPalette.cyan.cgColor, WellnarioPalette.violet.cgColor]
        fillLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fillLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(fillLayer)

        targetLayer.backgroundColor = WellnarioPalette.success.withAlphaComponent(0.22).cgColor
        targetLayer.borderColor = WellnarioPalette.success.withAlphaComponent(0.72).cgColor
        targetLayer.borderWidth = 1
        layer.addSublayer(targetLayer)

        markerLayer.backgroundColor = WellnarioPalette.textPrimary.cgColor
        markerLayer.shadowColor = UIColor.black.cgColor
        markerLayer.shadowOpacity = 0.30
        markerLayer.shadowRadius = 3
        layer.addSublayer(markerLayer)
    }

    private func updateLayerFrames(animated: Bool) {
        guard bounds.width > 0 else { return }
        let height = min(12, bounds.height)
        let barFrame = CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        let lower = normalized(targetRange.lowerBound)
        let upper = normalized(targetRange.upperBound)
        let progress = normalized(value)

        let changes = {
            self.trackLayer.frame = barFrame
            self.trackLayer.cornerRadius = height / 2

            self.fillLayer.frame = CGRect(x: barFrame.minX, y: barFrame.minY, width: barFrame.width * progress, height: height)
            self.fillLayer.cornerRadius = height / 2

            self.targetLayer.frame = CGRect(
                x: barFrame.minX + barFrame.width * lower,
                y: barFrame.minY,
                width: max(2, barFrame.width * (upper - lower)),
                height: height
            )
            self.targetLayer.cornerRadius = height / 2

            self.markerLayer.frame = CGRect(
                x: min(barFrame.maxX - 2, max(barFrame.minX, barFrame.minX + barFrame.width * progress - 2)),
                y: barFrame.minY - 3,
                width: 4,
                height: height + 6
            )
            self.markerLayer.cornerRadius = 2
        }

        if animated && WellnarioMotion.animationsEnabled {
            WellnarioMotion.spring(duration: 0.42, animations: changes)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            changes()
            CATransaction.commit()
        }
    }

    private func normalized(_ value: Double) -> CGFloat {
        let span = max(domain.upperBound - domain.lowerBound, 0.0001)
        return CGFloat(min(1, max(0, (value - domain.lowerBound) / span)))
    }
}

/// A segmented completion bar ideal for “3 of 5 doses” summaries.
final class SegmentedProgressView: UIView {
    var totalSegments: Int = 1 {
        didSet { rebuildSegments() }
    }

    var completedSegments: Int = 0 {
        didSet { updateSegments(animated: true) }
    }

    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 12)
    }

    private func setUp() {
        isAccessibilityElement = true
        accessibilityTraits = [.image]
        stack.axis = .horizontal
        stack.spacing = 5
        stack.distribution = .fillEqually
        addForAutoLayout(stack)
        stack.pinEdges(to: self)
        rebuildSegments()
    }

    private func rebuildSegments() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for _ in 0..<max(1, totalSegments) {
            let segment = UIView()
            segment.applyContinuousCorners(6)
            stack.addArrangedSubview(segment)
        }
        updateSegments(animated: false)
    }

    private func updateSegments(animated: Bool) {
        let changes = {
            for (index, segment) in self.stack.arrangedSubviews.enumerated() {
                segment.backgroundColor = index < self.completedSegments
                    ? WellnarioPalette.cyan
                    : WellnarioPalette.textPrimary.withAlphaComponent(0.10)
            }
        }
        if animated {
            WellnarioMotion.animate(duration: 0.25, animations: changes)
        } else {
            changes()
        }
        accessibilityLabel = L10n.Common.dailyProgress
        accessibilityValue = L10n.text(
            "accessibility.progress.count",
            completedSegments,
            totalSegments
        )
    }
}
