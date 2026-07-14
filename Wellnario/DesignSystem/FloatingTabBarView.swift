import UIKit

/// One destination in the custom floating navigation bar. Titles are resolved
/// at display time so changing language can update the bar without recreating it.
struct FloatingTabItem: Equatable, Sendable {
    let titleKey: String
    let symbolName: String
    let selectedSymbolName: String

    init(titleKey: String, symbolName: String, selectedSymbolName: String? = nil) {
        self.titleKey = titleKey
        self.symbolName = symbolName
        self.selectedSymbolName = selectedSymbolName ?? symbolName
    }

    static let wellnarioDefaults: [FloatingTabItem] = [
        FloatingTabItem(titleKey: "tab.today", symbolName: "sun.max", selectedSymbolName: "sun.max.fill"),
        FloatingTabItem(titleKey: "tab.supplements", symbolName: "pills", selectedSymbolName: "pills.fill"),
        FloatingTabItem(titleKey: "tab.sleep", symbolName: "moon.stars", selectedSymbolName: "moon.stars.fill"),
        FloatingTabItem(titleKey: "tab.health", symbolName: "heart", selectedSymbolName: "heart.fill"),
        FloatingTabItem(titleKey: "tab.fitness", symbolName: "figure.run", selectedSymbolName: "figure.run")
    ]
}

/// A custom Peakwatch-inspired tab bar. It uses a floating glass capsule, a
/// smoothly moving selection pill and equal-width accessible destinations.
final class FloatingTabBarView: UIView {
    var onSelection: ((Int) -> Void)?

    var items: [FloatingTabItem] = FloatingTabItem.wellnarioDefaults {
        didSet { rebuildButtons() }
    }

    var selectedIndex: Int = 0 {
        didSet {
            guard !items.isEmpty else { return }
            let clamped = min(max(0, selectedIndex), items.count - 1)
            guard selectedIndex == clamped else {
                selectedIndex = clamped
                return
            }
            updateSelection(animated: oldValue != selectedIndex)
        }
    }

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let selectionPill = UIView()
    private let stackView = UIStackView()
    private var buttons: [UIButton] = []
    private let borderLayer = CAShapeLayer()

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

    override var intrinsicContentSize: CGSize {
        let height: CGFloat = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 88 : WellnarioLayout.floatingTabBarHeight
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        borderLayer.frame = bounds
        borderLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerRadius: bounds.height / 2
        ).cgPath
        updatePillFrame(animated: false)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
    }

    private func setUp() {
        backgroundColor = .clear
        applyContinuousCorners(WellnarioRadius.floatingBar)
        applyPremiumShadow(opacity: 0.45)

        blurView.clipsToBounds = true
        blurView.layer.cornerCurve = .continuous
        blurView.layer.cornerRadius = WellnarioRadius.floatingBar
        addForAutoLayout(blurView)
        blurView.pinEdges(to: self)

        selectionPill.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        selectionPill.isUserInteractionEnabled = false
        selectionPill.layer.cornerCurve = .continuous
        blurView.contentView.addSubview(selectionPill)

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.alignment = .fill
        stackView.spacing = 0
        blurView.contentView.addForAutoLayout(stackView)
        stackView.pinEdges(to: blurView.contentView, insets: NSDirectionalEdgeInsets(top: 4, leading: 5, bottom: 4, trailing: 5))

        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = WellnarioPalette.hairline.cgColor
        borderLayer.lineWidth = 1
        layer.addSublayer(borderLayer)

        accessibilityIdentifier = "wellnario.floatingTabBar"
        rebuildButtons()
        updateTransparency()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localizationDidChange),
            name: LocalizationManager.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityAppearanceDidChange),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityAppearanceDidChange),
            name: UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            object: nil
        )

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (self: FloatingTabBarView, _: UITraitCollection) in
            self.invalidateIntrinsicContentSize()
            self.updateButtonFonts()
        }
    }

    private func rebuildButtons() {
        buttons.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        buttons = items.enumerated().map { index, item in
            var configuration = UIButton.Configuration.plain()
            configuration.imagePlacement = .top
            configuration.imagePadding = 3
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 2, bottom: 3, trailing: 2)
            configuration.titleAlignment = .center
            configuration.titleLineBreakMode = .byTruncatingTail

            let button = UIButton(configuration: configuration)
            button.tag = index
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.textAlignment = .center
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.72
            button.accessibilityIdentifier = "tab.\(item.titleKey)"
            stackView.addArrangedSubview(button)
            return button
        }
        selectedIndex = min(selectedIndex, max(0, items.count - 1))
        updateButtonFonts()
        updateSelection(animated: false)
    }

    private func updateButtonFonts() {
        for button in buttons {
            var configuration = button.configuration
            configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = WellnarioTypography.font(for: .tab)
                return outgoing
            }
            button.configuration = configuration
            button.titleLabel?.adjustsFontForContentSizeCategory = true
        }
    }

    private func updateSelection(animated: Bool) {
        for (index, button) in buttons.enumerated() {
            let item = items[index]
            let selected = index == selectedIndex
            let title = L10n.text(item.titleKey)
            let symbol = selected ? item.selectedSymbolName : item.symbolName
            var configuration = button.configuration
            configuration?.title = title
            configuration?.image = UIImage(systemName: symbol)
            configuration?.baseForegroundColor = selected ? WellnarioPalette.cyan : WellnarioPalette.textSecondary
            button.configuration = configuration
            button.accessibilityLabel = title
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
        updatePillFrame(animated: animated)
    }

    private func updatePillFrame(animated: Bool) {
        guard buttons.indices.contains(selectedIndex) else {
            selectionPill.frame = .zero
            return
        }
        let button = buttons[selectedIndex]
        let target = button.convert(button.bounds, to: blurView.contentView).insetBy(dx: 3, dy: 2)
        let changes = {
            self.selectionPill.frame = target
            self.selectionPill.layer.cornerRadius = target.height / 2
        }
        if animated {
            WellnarioMotion.spring(duration: 0.34, animations: changes)
        } else {
            changes()
        }
    }

    private func updateTransparency() {
        if UIAccessibility.isReduceTransparencyEnabled {
            blurView.effect = nil
            blurView.backgroundColor = WellnarioPalette.glassSurface
        } else {
            blurView.backgroundColor = .clear
            blurView.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        }
    }

    @objc private func tabTapped(_ sender: UIButton) {
        guard sender.tag != selectedIndex else { return }
        selectedIndex = sender.tag
        UISelectionFeedbackGenerator().selectionChanged()
        onSelection?(selectedIndex)
    }

    @objc private func localizationDidChange() {
        updateSelection(animated: false)
    }

    @objc private func accessibilityAppearanceDidChange() {
        updateTransparency()
        borderLayer.strokeColor = WellnarioPalette.hairline.cgColor
        setNeedsLayout()
    }
}
