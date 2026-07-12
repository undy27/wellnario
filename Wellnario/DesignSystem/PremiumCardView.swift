import UIKit

/// A reusable dark card with a subtle surface gradient, continuous corners and
/// an optional signature accent. It behaves like a control when `isPressable`
/// is enabled and automatically softens its motion for Reduce Motion users.
class PremiumCardView: UIControl {
    let contentView = UIView()

    var showsAccent: Bool = false {
        didSet { accentLayer.isHidden = !showsAccent }
    }

    var isPressable: Bool = false {
        didSet {
            // A pressable card owns its hit testing; a structural card leaves
            // its content interactive so embedded buttons continue to work.
            contentView.isUserInteractionEnabled = !isPressable
            isAccessibilityElement = isPressable
            accessibilityTraits = isPressable ? [.button] : []
        }
    }

    override var accessibilityLabel: String? {
        get {
            if let explicitLabel = super.accessibilityLabel, !explicitLabel.isEmpty {
                return explicitLabel
            }
            guard isPressable else { return nil }
            return accessibilityText(in: contentView)
                .filter { !$0.isEmpty }
                .joined(separator: ". ")
        }
        set { super.accessibilityLabel = newValue }
    }

    override var isHighlighted: Bool {
        didSet { updatePressedState() }
    }

    private let surfaceLayer = CAGradientLayer()
    private let borderLayer = CAShapeLayer()
    private let accentLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        surfaceLayer.frame = bounds
        surfaceLayer.cornerRadius = WellnarioRadius.card
        borderLayer.frame = bounds
        borderLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerRadius: WellnarioRadius.card
        ).cgPath

        let accentHeight: CGFloat = 3
        accentLayer.frame = CGRect(
            x: 1,
            y: max(0, bounds.height - accentHeight - 1),
            width: max(0, bounds.width - 2),
            height: accentHeight
        )
        accentLayer.cornerRadius = accentHeight / 2
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: WellnarioRadius.card
        ).cgPath
    }

    private func setUp() {
        backgroundColor = .clear
        clipsToBounds = false
        layer.cornerCurve = .continuous
        applyPremiumShadow()

        surfaceLayer.colors = WellnarioPalette.surfaceGradient.map(\.cgColor)
        surfaceLayer.startPoint = CGPoint(x: 0.5, y: 0)
        surfaceLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer.insertSublayer(surfaceLayer, at: 0)

        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = WellnarioPalette.cardTopHighlight.cgColor
        borderLayer.lineWidth = 1
        layer.addSublayer(borderLayer)

        accentLayer.colors = WellnarioPalette.signatureGradient.map(\.cgColor)
        accentLayer.startPoint = CGPoint(x: 0, y: 0.5)
        accentLayer.endPoint = CGPoint(x: 1, y: 0.5)
        accentLayer.isHidden = true
        layer.addSublayer(accentLayer)

        addForAutoLayout(contentView)
        contentView.pinEdges(to: self)
        isUserInteractionEnabled = true

        isPressable = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityAppearanceDidChange),
            name: UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            object: nil
        )
    }

    private func updatePressedState() {
        guard isPressable else { return }
        let transform = isHighlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
        WellnarioMotion.spring(duration: isHighlighted ? 0.10 : 0.30) {
            self.transform = transform
            self.layer.shadowOpacity = self.isHighlighted ? 0.14 : 0.30
        }
    }

    @objc private func accessibilityAppearanceDidChange() {
        borderLayer.strokeColor = WellnarioPalette.cardTopHighlight.cgColor
    }

    private func accessibilityText(in view: UIView) -> [String] {
        var result: [String] = []
        if let label = view as? UILabel, let text = label.text {
            result.append(text)
        } else if view !== contentView,
                  view.isAccessibilityElement,
                  let label = view.accessibilityLabel {
            result.append(label)
        }
        for subview in view.subviews {
            result.append(contentsOf: accessibilityText(in: subview))
        }
        return result
    }
}
