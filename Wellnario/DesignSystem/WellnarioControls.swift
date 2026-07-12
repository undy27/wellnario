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
        gradientLayer.colors = WellnarioPalette.signatureGradient.map(\.cgColor)
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
    }

    private func updateAppearance() {
        alpha = isEnabled ? 1 : 0.52
        layer.borderWidth = 0
        gradientLayer.isHidden = true

        switch style {
        case .primary:
            gradientLayer.isHidden = false
            backgroundColor = WellnarioPalette.violet
            setTitleColor(WellnarioPalette.textPrimary, for: .normal)
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
    }

    private func updateAppearance() {
        if isSelected {
            backgroundColor = WellnarioPalette.cyan.withAlphaComponent(0.16)
            layer.borderColor = WellnarioPalette.cyan.withAlphaComponent(0.62).cgColor
            setTitleColor(WellnarioPalette.cyan, for: .normal)
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
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)

        var unitConfiguration = UIButton.Configuration.plain()
        unitConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
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
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 16),
            textField.topAnchor.constraint(equalTo: fieldContainer.topAnchor, constant: 8),
            textField.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor, constant: -8),
            textToEdgeConstraint!,
            unitButton.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -10),
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

    @objc private func textDidChange() {
        textField.accessibilityValue = [textField.text, unitTitle]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    @objc private func unitTapped() {
        onUnitTap?()
    }
}
