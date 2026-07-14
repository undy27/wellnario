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
        symbolContainer.applyContinuousCorners(14)
        NSLayoutConstraint.activate([
            symbolContainer.widthAnchor.constraint(equalToConstant: 40),
            symbolContainer.heightAnchor.constraint(equalTo: symbolContainer.widthAnchor)
        ])

        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        symbolView.contentMode = .scaleAspectFit
        symbolContainer.addForAutoLayout(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor)
        ])

        chevronView.tintColor = WellnarioPalette.textTertiary
        chevronView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 2
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        valueLabel.applyWellnarioStyle(.metric, color: WellnarioPalette.textPrimary)
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.74
        valueLabel.numberOfLines = 1

        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detailLabel.numberOfLines = 2

        let heading = UIStackView(
            arrangedSubviews: [symbolContainer, UIView(), chevronView],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .center
        )
        let stack = UIStackView(
            arrangedSubviews: [heading, titleLabel, valueLabel, detailLabel],
            axis: .vertical,
            spacing: 6
        )
        stack.setCustomSpacing(WellnarioSpacing.xSmall, after: heading)
        contentView.addForAutoLayout(stack)
        stack.pinEdges(to: contentView, insets: .all(WellnarioSpacing.small))
        heightAnchor.constraint(greaterThanOrEqualToConstant: 166).isActive = true
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

@MainActor
final class WellnessTrendChartView: UIView {
    var values: [Double?] = [] { didSet { setNeedsDisplay() } }
    var labels: [String] = [] { didSet { setNeedsDisplay() } }
    var lineColor = WellnarioPalette.violet { didSet { setNeedsDisplay() } }
    var emptyText = "" { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = [.image]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = [.image]
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 190)
    }

    override func draw(_ rect: CGRect) {
        let chartRect = rect.inset(by: UIEdgeInsets(top: 14, left: 8, bottom: 30, right: 8))
        drawGrid(in: chartRect)
        drawLabels(in: chartRect)

        let validValues = values.compactMap { $0 }
        guard !validValues.isEmpty else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: WellnarioTypography.font(for: .secondary),
                .foregroundColor: WellnarioPalette.textTertiary
            ]
            let size = emptyText.size(withAttributes: attributes)
            emptyText.draw(
                at: CGPoint(x: rect.midX - size.width / 2, y: chartRect.midY - size.height / 2),
                withAttributes: attributes
            )
            accessibilityLabel = emptyText
            return
        }

        let minimum = validValues.min() ?? 0
        let maximum = validValues.max() ?? 1
        let padding = max((maximum - minimum) * 0.18, 0.4)
        let lower = minimum - padding
        let range = max((maximum + padding) - lower, 0.001)
        let pointCount = max(values.count, 2)

        var points: [CGPoint] = []
        for (index, value) in values.enumerated() {
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

        if let last = points.last {
            lineColor.withAlphaComponent(0.20).setFill()
            UIBezierPath(ovalIn: CGRect(x: last.x - 7, y: last.y - 7, width: 14, height: 14)).fill()
            lineColor.setFill()
            UIBezierPath(ovalIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7)).fill()
        }
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
        for (index, label) in labels.enumerated() {
            let size = label.size(withAttributes: attributes)
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(labels.count - 1)
            label.draw(
                at: CGPoint(x: min(max(rect.minX, x - size.width / 2), rect.maxX - size.width), y: rect.maxY + 10),
                withAttributes: attributes
            )
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
