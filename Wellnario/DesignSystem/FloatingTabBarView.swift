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

    var selectedIndex: Int {
        get { storedSelectedIndex }
        set { setSelectedIndex(newValue, animated: true) }
    }

    private var storedSelectedIndex = 0
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let selectionPill = UIView()
    private let stackView = UIStackView()
    private var buttons: [UIButton] = []
    private let borderLayer = CAShapeLayer()
    private var selectionAnimationGeneration = 0
    private var isSelectionAnimationInFlight = false

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
        blurView.layoutIfNeeded()
        stackView.layoutIfNeeded()
        borderLayer.frame = bounds
        borderLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerRadius: bounds.height / 2
        ).cgPath
        if !isSelectionAnimationInFlight {
            updatePillFrame(animated: false)
        }
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
    }

    func setSelectedIndex(_ index: Int, animated: Bool) {
        let clamped = items.isEmpty ? 0 : min(max(0, index), items.count - 1)
        guard storedSelectedIndex != clamped else { return }
        storedSelectedIndex = clamped
        updateSelection(animated: animated)
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

        selectionPill.backgroundColor = WellnarioPalette.fuchsia
        selectionPill.isUserInteractionEnabled = false
        selectionPill.layer.cornerCurve = .continuous
        selectionPill.layer.shadowColor = WellnarioPalette.fuchsia.cgColor
        selectionPill.layer.shadowOpacity = 0.24
        selectionPill.layer.shadowRadius = 8
        selectionPill.layer.shadowOffset = .zero
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
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (self: FloatingTabBarView, _: UITraitCollection) in
            self.updateTransparency()
            self.updateSelection(animated: false)
            self.updateLayerColors()
        }
        updateLayerColors()
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
        storedSelectedIndex = min(storedSelectedIndex, max(0, items.count - 1))
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
            let changes = {
                var configuration = button.configuration
                configuration?.title = title
                configuration?.image = UIImage(systemName: symbol)
                configuration?.baseForegroundColor = selected
                    ? UIColor.white
                    : WellnarioPalette.textSecondary
                button.configuration = configuration
                button.accessibilityLabel = title
                button.accessibilityTraits = selected ? [.button, .selected] : [.button]
            }
            if animated && WellnarioMotion.animationsEnabled {
                UIView.transition(
                    with: button,
                    duration: WellnarioMotion.standard,
                    options: [
                        .transitionCrossDissolve,
                        .allowAnimatedContent,
                        .allowUserInteraction,
                        .beginFromCurrentState
                    ],
                    animations: changes
                )
            } else {
                changes()
            }
        }
        updatePillFrame(animated: animated)
    }

    private func updatePillFrame(animated: Bool) {
        guard buttons.indices.contains(selectedIndex) else {
            selectionPill.frame = .zero
            return
        }
        let target = pillFrame(for: selectedIndex)
        let changes = {
            self.selectionPill.frame = target
            self.selectionPill.layer.cornerRadius = target.height / 2
            self.selectionPill.alpha = 1
        }
        if animated && WellnarioMotion.animationsEnabled {
            selectionAnimationGeneration += 1
            let generation = selectionAnimationGeneration
            isSelectionAnimationInFlight = true

            let presentationFrame = selectionPill.layer.presentation()?.frame
            let presentationAlpha = selectionPill.layer.presentation().map { CGFloat($0.opacity) }
            selectionPill.layer.removeAllAnimations()
            selectionPill.frame = presentationFrame ?? selectionPill.frame
            selectionPill.alpha = presentationAlpha ?? selectionPill.alpha

            let start = selectionPill.frame
            let startExpanded = constrainedPillFrame(start.insetBy(dx: -8, dy: -5))
            let bridge = constrainedPillFrame(start.union(target).insetBy(dx: -8, dy: -5))
            let targetExpanded = constrainedPillFrame(target.insetBy(dx: -10, dy: -5))

            UIView.animateKeyframes(
                withDuration: WellnarioMotion.emphasized,
                delay: 0,
                options: [
                    .calculationModeCubic,
                    .allowUserInteraction,
                    .beginFromCurrentState
                ],
                animations: {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.24) {
                        self.applyPillFrame(startExpanded, alpha: 0.44)
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.24, relativeDuration: 0.28) {
                        self.applyPillFrame(bridge, alpha: 0.30)
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.52, relativeDuration: 0.26) {
                        self.applyPillFrame(targetExpanded, alpha: 0.48)
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.78, relativeDuration: 0.22) {
                        changes()
                    }
                }
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.selectionAnimationGeneration == generation else { return }
                    self.isSelectionAnimationInFlight = false
                    self.updatePillFrame(animated: false)
                }
            }
        } else {
            selectionAnimationGeneration += 1
            isSelectionAnimationInFlight = false
            changes()
        }
    }

    private func pillFrame(for index: Int) -> CGRect {
        guard buttons.indices.contains(index) else { return .zero }
        let button = buttons[index]
        var frame = button.convert(button.bounds, to: blurView.contentView).insetBy(dx: 3, dy: 10)
        guard frame.width > 0, frame.height > 0 else { return .zero }

        let title = L10n.text(items[index].titleKey) as NSString
        let titleWidth = ceil(title.size(withAttributes: [
            .font: WellnarioTypography.font(for: .tab)
        ]).width)
        let contentWidth = titleWidth + 16
        if contentWidth > frame.width {
            let centerX = frame.midX
            frame.size.width = contentWidth
            frame.origin.x = centerX - contentWidth / 2
        }
        return constrainedPillFrame(frame)
    }

    private func constrainedPillFrame(_ frame: CGRect) -> CGRect {
        let limits = blurView.contentView.bounds.insetBy(dx: 4, dy: 4)
        guard limits.width > 0, limits.height > 0 else { return frame }

        var result = frame
        result.size.width = min(result.width, limits.width)
        result.size.height = min(result.height, limits.height)
        result.origin.x = min(max(result.minX, limits.minX), limits.maxX - result.width)
        result.origin.y = min(max(result.minY, limits.minY), limits.maxY - result.height)
        return result
    }

    private func applyPillFrame(_ frame: CGRect, alpha: CGFloat) {
        selectionPill.frame = frame
        selectionPill.layer.cornerRadius = frame.height / 2
        selectionPill.alpha = alpha
    }

    private func updateTransparency() {
        if UIAccessibility.isReduceTransparencyEnabled {
            blurView.effect = nil
            blurView.backgroundColor = WellnarioPalette.glassSurface
        } else {
            blurView.backgroundColor = .clear
            blurView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
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
        updateLayerColors()
        setNeedsLayout()
    }

    private func updateLayerColors() {
        borderLayer.strokeColor = WellnarioPalette.hairline
            .resolvedColor(with: traitCollection)
            .cgColor
        selectionPill.layer.shadowColor = WellnarioPalette.fuchsia
            .resolvedColor(with: traitCollection)
            .cgColor
    }
}
