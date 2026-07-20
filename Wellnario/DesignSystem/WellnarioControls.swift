import UIKit

/// Primary actions and their quieter secondary variants.
final class PrimaryButton: UIButton {
    enum Style: Sendable {
        case primary
        case secondary
        case destructive
        case ghost
    }

    var style: Style = .primary {
        didSet { updateAppearance() }
    }

    var isLoading: Bool = false {
        didSet { updateLoadingState() }
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet { updateHighlightedState() }
    }

    private let gradientLayer = CAGradientLayer()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    init(title: String? = nil, style: Style = .primary) {
        self.style = style
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = WellnarioRadius.button
    }

    override var intrinsicContentSize: CGSize {
        let content = super.intrinsicContentSize
        return CGSize(
            width: content.width + 40,
            height: max(WellnarioLayout.primaryButtonHeight, content.height + 24)
        )
    }

    override func contentRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: UIEdgeInsets(top: 12, left: 20, bottom: 12, right: 20))
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.primaryButtonHeight).isActive = true
        applyContinuousCorners(WellnarioRadius.button)
        clipsToBounds = true

        titleLabel?.font = WellnarioTypography.font(for: .button)
        titleLabel?.adjustsFontForContentSizeCategory = true
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.82
        // UIButton's legacy image/title layout has no built-in gap. Keep a
        // consistent breathing space so icon-bearing actions never overlap.
        imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.insertSublayer(gradientLayer, at: 0)

        activityIndicator.color = WellnarioPalette.textPrimary
        activityIndicator.hidesWhenStopped = true
        addForAutoLayout(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        accessibilityTraits.insert(.button)
        updateAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (self: PrimaryButton, _: UITraitCollection) in
            self.updateAppearance()
        }
    }

    private func updateAppearance() {
        gradientLayer.colors = WellnarioPalette.signatureGradient.map {
            $0.resolvedColor(with: traitCollection).cgColor
        }
        alpha = isEnabled ? 1 : 0.52
        layer.borderWidth = 0
        gradientLayer.isHidden = true

        switch style {
        case .primary:
            gradientLayer.isHidden = false
            backgroundColor = WellnarioPalette.violet
            setTitleColor(WellnarioPalette.onAccent, for: .normal)
        case .secondary:
            backgroundColor = WellnarioPalette.surfaceElevated
            layer.borderWidth = 1
            layer.borderColor = WellnarioPalette.hairline.cgColor
            setTitleColor(WellnarioPalette.textPrimary, for: .normal)
        case .destructive:
            backgroundColor = WellnarioPalette.danger.withAlphaComponent(0.15)
            layer.borderWidth = 1
            layer.borderColor = WellnarioPalette.danger.withAlphaComponent(0.45).cgColor
            setTitleColor(WellnarioPalette.danger, for: .normal)
        case .ghost:
            backgroundColor = .clear
            setTitleColor(WellnarioPalette.cyan, for: .normal)
        }
    }

    private func updateLoadingState() {
        titleLabel?.alpha = isLoading ? 0 : 1
        imageView?.alpha = isLoading ? 0 : 1
        isUserInteractionEnabled = !isLoading
        accessibilityValue = isLoading ? L10n.Common.loading : nil
        if isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    private func updateHighlightedState() {
        let transform = isHighlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
        WellnarioMotion.spring(duration: isHighlighted ? 0.10 : 0.28) {
            self.transform = transform
            self.alpha = self.isHighlighted ? 0.84 : (self.isEnabled ? 1 : 0.52)
        }
    }
}

/// A compact navigation-bar control that matches the animated fuchsia actions
/// in Supplements. The animation honours the system Reduce Motion setting.
@MainActor
final class BreathingNavigationButton: UIButton {
    private let animationKey = "wellnario.navigation.breathing"
    private var isBreathingActive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBreathingAnimation()
    }

    func setBreathingActive(_ isActive: Bool) {
        isBreathingActive = isActive
        updateBreathingAnimation()
    }

    private func configure() {
        frame.size = CGSize(width: 36, height: WellnarioLayout.minimumTouchTarget)
        widthAnchor.constraint(equalToConstant: 36).isActive = true
        heightAnchor.constraint(equalToConstant: WellnarioLayout.minimumTouchTarget).isActive = true
        imageView?.contentMode = .scaleAspectFit
        isAccessibilityElement = true
        accessibilityTraits = .button
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionDidChange),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }

    private func updateBreathingAnimation() {
        guard isBreathingActive, window != nil, WellnarioMotion.animationsEnabled else {
            layer.removeAnimation(forKey: animationKey)
            return
        }
        guard layer.animation(forKey: animationKey) == nil else { return }

        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1.0
        animation.toValue = 1.3125
        animation.duration = 0.92
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: animationKey)
    }

    @objc private func reduceMotionDidChange() {
        updateBreathingAnimation()
    }
}

/// A single-line secondary label that loops horizontally only when its text
/// does not fit. Reduce Motion falls back to ordinary tail truncation.
final class ContinuousMarqueeLabel: UIView {
    override var accessibilityIdentifier: String? {
        didSet { primaryLabel.accessibilityIdentifier = accessibilityIdentifier }
    }

    var text: String? {
        didSet {
            primaryLabel.text = text
            repeatedLabel.text = text
            accessibilityLabel = text
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    var isMarqueeEnabled = false {
        didSet {
            guard oldValue != isMarqueeEnabled else { return }
            setNeedsLayout()
        }
    }

    var textAlignment: NSTextAlignment = .left {
        didSet {
            [primaryLabel, repeatedLabel].forEach { $0.textAlignment = textAlignment }
        }
    }

    private(set) var isOverflowing = false

    private let primaryLabel = UILabel()
    private let repeatedLabel = UILabel()
    private let animationKey = "wellnario.continuousMarquee"
    private var animatedDistance: CGFloat?

    func applyTextStyle(_ style: WellnarioTextStyle, color: UIColor) {
        [primaryLabel, repeatedLabel].forEach {
            $0.applyWellnarioStyle(style, color: color)
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var intrinsicContentSize: CGSize {
        primaryLabel.intrinsicContentSize
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopAnimation() }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutText()
    }

    private func setUp() {
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .staticText

        [primaryLabel, repeatedLabel].forEach { label in
            label.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.textAlignment = textAlignment
            label.isAccessibilityElement = false
            addSubview(label)
        }
        repeatedLabel.isHidden = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }

    private func layoutText() {
        let textWidth = ceil(primaryLabel.intrinsicContentSize.width)
        isOverflowing = bounds.width > 0 && textWidth > bounds.width + 1
        let shouldAnimate = isMarqueeEnabled
            && WellnarioMotion.animationsEnabled
            && window != nil
            && isOverflowing

        guard shouldAnimate else {
            stopAnimation()
            repeatedLabel.isHidden = true
            primaryLabel.lineBreakMode = .byTruncatingTail
            primaryLabel.frame = bounds
            return
        }

        let gap: CGFloat = 28
        let distance = textWidth + gap
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        primaryLabel.lineBreakMode = .byClipping
        repeatedLabel.lineBreakMode = .byClipping
        primaryLabel.frame = CGRect(x: 0, y: 0, width: textWidth, height: bounds.height)
        repeatedLabel.frame = CGRect(x: distance, y: 0, width: textWidth, height: bounds.height)
        repeatedLabel.isHidden = false
        CATransaction.commit()

        guard animatedDistance != distance
                || primaryLabel.layer.animation(forKey: animationKey) == nil else {
            return
        }
        stopAnimation()
        let duration = max(6, TimeInterval(distance / 26))
        [primaryLabel, repeatedLabel].forEach { label in
            let animation = CABasicAnimation(keyPath: "transform.translation.x")
            animation.fromValue = 0
            animation.toValue = -distance
            animation.duration = duration
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = false
            label.layer.add(animation, forKey: animationKey)
        }
        animatedDistance = distance
    }

    private func stopAnimation() {
        primaryLabel.layer.removeAnimation(forKey: animationKey)
        repeatedLabel.layer.removeAnimation(forKey: animationKey)
        animatedDistance = nil
    }

    @objc private func reduceMotionChanged() {
        setNeedsLayout()
    }
}

/// A compact, accessible filter or segmented-choice button.
final class ChipButton: UIButton {
    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet {
            WellnarioMotion.spring(duration: 0.12) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.96, y: 0.96)
                    : .identity
            }
        }
    }

    init(title: String? = nil) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    override var intrinsicContentSize: CGSize {
        let content = super.intrinsicContentSize
        return CGSize(
            width: content.width + 28,
            height: max(WellnarioLayout.minimumTouchTarget, content.height + 16)
        )
    }

    override func contentRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14))
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.minimumTouchTarget).isActive = true
        titleLabel?.font = WellnarioTypography.font(for: .caption)
        titleLabel?.adjustsFontForContentSizeCategory = true
        applyContinuousCorners(WellnarioRadius.control)
        layer.borderWidth = 1
        accessibilityTraits.insert(.button)
        updateAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (self: ChipButton, _: UITraitCollection) in
            self.updateAppearance()
        }
    }

    private func updateAppearance() {
        if isSelected {
            backgroundColor = WellnarioPalette.fuchsia.withAlphaComponent(0.18)
            layer.borderColor = WellnarioPalette.fuchsia.withAlphaComponent(0.68).cgColor
            setTitleColor(WellnarioPalette.fuchsia, for: .normal)
            accessibilityTraits.insert(.selected)
        } else {
            backgroundColor = WellnarioPalette.surfaceElevated
            layer.borderColor = WellnarioPalette.hairline.cgColor
            setTitleColor(WellnarioPalette.textSecondary, for: .normal)
            accessibilityTraits.remove(.selected)
        }
    }
}

/// A labeled text field with optional unit affordance, help text and an inline
/// validation state. Errors are conveyed with both an icon and text.
final class FormFieldView: UIView {
    let textField = UITextField()
    let unitButton = UIButton(type: .system)

    var onUnitTap: (() -> Void)?

    /// Horizontal gap between the unit selector and the field's trailing edge.
    /// Most fields keep a small inset; some compact editors can opt into a
    /// flush selector so it aligns with the container edge.
    var unitButtonTrailingInset: CGFloat = 10 {
        didSet { unitButtonTrailingConstraint?.constant = -unitButtonTrailingInset }
    }

    var title: String = "" {
        didSet {
            titleLabel.text = title
            textField.accessibilityLabel = title
        }
    }

    var helperText: String? {
        didSet {
            if errorMessage == nil { updateSupportingText() }
        }
    }

    var errorMessage: String? {
        didSet { updateSupportingText() }
    }

    var unitTitle: String? {
        didSet {
            let hasUnit = unitTitle != nil
            unitButton.setTitle(unitTitle, for: .normal)
            unitButton.isHidden = !hasUnit
            textToUnitConstraint?.isActive = hasUnit
            unitMinimumWidthConstraint?.isActive = hasUnit
            textToEdgeConstraint?.isActive = !hasUnit
            textField.accessibilityValue = [textField.text, unitTitle]
                .compactMap { $0 }
                .joined(separator: " ")
            unitButton.accessibilityLabel = L10n.Form.unit
            unitButton.accessibilityValue = unitTitle
            unitButton.accessibilityHint = L10n.text("accessibility.opens_menu")
        }
    }

    private let titleLabel = UILabel()
    private let fieldContainer = UIView()
    private let supportingLabel = UILabel()
    private var textToUnitConstraint: NSLayoutConstraint?
    private var textToEdgeConstraint: NSLayoutConstraint?
    private var unitMinimumWidthConstraint: NSLayoutConstraint?
    private var unitButtonTrailingConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    /// Convenience configuration for the most common form-field properties.
    func configure(
        title: String,
        placeholder: String? = nil,
        text: String? = nil,
        keyboardType: UIKeyboardType = .default,
        contentType: UITextContentType? = nil
    ) {
        self.title = title
        textField.placeholder = placeholder
        textField.text = text
        textField.keyboardType = keyboardType
        textField.textContentType = contentType
    }

    /// Applies or clears an accessible validation error.
    func setError(_ message: String?) {
        errorMessage = message
        if let message {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        titleLabel.numberOfLines = 0
        titleLabel.isAccessibilityElement = false

        fieldContainer.backgroundColor = WellnarioPalette.fieldBackground
        fieldContainer.applyContinuousCorners(WellnarioRadius.control)
        fieldContainer.layer.borderWidth = 1
        fieldContainer.layer.borderColor = WellnarioPalette.hairline.cgColor
        fieldContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.fieldMinimumHeight).isActive = true

        textField.textColor = WellnarioPalette.textPrimary
        textField.tintColor = WellnarioPalette.cyan
        textField.font = WellnarioTypography.font(for: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .done
        textField.addTarget(self, action: #selector(editingDidBegin), for: .editingDidBegin)
        textField.addTarget(self, action: #selector(editingDidEnd), for: .editingDidEnd)
        textField.addTarget(self, action: #selector(editingDidEndOnExit), for: .editingDidEndOnExit)
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)

        var unitConfiguration = UIButton.Configuration.plain()
        unitConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
        unitConfiguration.image = UIImage(systemName: "chevron.down")
        unitConfiguration.imagePlacement = .trailing
        unitConfiguration.imagePadding = 4
        unitConfiguration.baseForegroundColor = WellnarioPalette.cyan
        unitConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = WellnarioTypography.font(for: .caption)
            return outgoing
        }
        unitButton.configuration = unitConfiguration
        unitButton.backgroundColor = WellnarioPalette.cyan.withAlphaComponent(0.10)
        unitButton.applyContinuousCorners(10)
        unitButton.isHidden = true
        unitButton.setContentHuggingPriority(.required, for: .horizontal)
        unitButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        unitButton.addTarget(self, action: #selector(unitTapped), for: .touchUpInside)

        supportingLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        supportingLabel.numberOfLines = 0
        supportingLabel.isHidden = true
        supportingLabel.isAccessibilityElement = false

        fieldContainer.addForAutoLayout(textField)
        fieldContainer.addForAutoLayout(unitButton)
        textToUnitConstraint = textField.trailingAnchor.constraint(equalTo: unitButton.leadingAnchor, constant: -8)
        textToEdgeConstraint = textField.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -16)
        unitMinimumWidthConstraint = unitButton.widthAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.minimumTouchTarget)
        unitButtonTrailingConstraint = unitButton.trailingAnchor.constraint(
            equalTo: fieldContainer.trailingAnchor,
            constant: -unitButtonTrailingInset
        )
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 16),
            textField.topAnchor.constraint(
                equalTo: fieldContainer.topAnchor,
                constant: WellnarioLayout.fieldVerticalPadding
            ),
            textField.bottomAnchor.constraint(
                equalTo: fieldContainer.bottomAnchor,
                constant: -WellnarioLayout.fieldVerticalPadding
            ),
            textToEdgeConstraint!,
            unitButtonTrailingConstraint!,
            unitButton.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            unitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.minimumTouchTarget)
        ])

        let stack = UIStackView(
            arrangedSubviews: [titleLabel, fieldContainer, supportingLabel],
            axis: .vertical,
            spacing: 7
        )
        addForAutoLayout(stack)
        stack.pinEdges(to: self)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (self: FormFieldView, _: UITraitCollection) in
            self.updateSupportingText()
        }
    }

    private func updateSupportingText() {
        if let errorMessage {
            supportingLabel.text = "⚠︎ \(errorMessage)"
            supportingLabel.textColor = WellnarioPalette.danger
            supportingLabel.isHidden = false
            fieldContainer.layer.borderColor = WellnarioPalette.danger.cgColor
            textField.accessibilityHint = errorMessage
        } else {
            supportingLabel.text = helperText
            supportingLabel.textColor = WellnarioPalette.textTertiary
            supportingLabel.isHidden = helperText == nil
            fieldContainer.layer.borderColor = textField.isFirstResponder
                ? WellnarioPalette.cyan.cgColor
                : WellnarioPalette.hairline.cgColor
            textField.accessibilityHint = helperText
        }
    }

    @objc private func editingDidBegin() {
        guard errorMessage == nil else { return }
        fieldContainer.layer.borderColor = WellnarioPalette.cyan.cgColor
    }

    @objc private func editingDidEnd() {
        guard errorMessage == nil else { return }
        fieldContainer.layer.borderColor = WellnarioPalette.hairline.cgColor
    }

    @objc private func editingDidEndOnExit() {
        textField.resignFirstResponder()
    }

    @objc private func textDidChange() {
        textField.accessibilityValue = [textField.text, unitTitle]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    @objc private func unitTapped() {
        onUnitTap?()
    }
}
