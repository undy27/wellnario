import UIKit

@MainActor
class EditorViewController: FeatureViewController, UIGestureRecognizerDelegate {
    let scrollView = UIScrollView()
    let contentStack = UIStackView()
    let saveButton = PrimaryButton()
    var minimumBottomContentInset: CGFloat { 0 }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpEditor()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    func performSave() {}

    func finishSaving(message: String = L10n.text("feedback.saved")) {
        saveButton.isLoading = false
        UIImpactFeedbackGenerator.wellnarioSuccess()
        closeEditor(animated: true)
    }

    private func setUpEditor() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.Common.cancel,
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.leftBarButtonItem?.tintColor = WellnarioPalette.textSecondary

        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInset.bottom = minimumBottomContentInset
        scrollView.verticalScrollIndicatorInsets.bottom = minimumBottomContentInset
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)

        contentStack.axis = .vertical
        contentStack.spacing = WellnarioSpacing.cardGap
        scrollView.addForAutoLayout(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -WellnarioSpacing.screenHorizontal),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: WellnarioSpacing.medium),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -WellnarioSpacing.large),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -(WellnarioSpacing.screenHorizontal * 2))
        ])

        saveButton.setTitle(L10n.Common.save, for: .normal)
        saveButton.accessibilityIdentifier = "editor.save"
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        let tap = UITapGestureRecognizer(target: self, action: #selector(endEditing))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardHidden(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @discardableResult
    func addSection(title: String, views: [UIView]) -> FormSectionView {
        let section = FormSectionView(title: title, views: views)
        contentStack.addArrangedSubview(section)
        return section
    }

    func addSaveButton() {
        guard saveButton.superview == nil else { return }
        contentStack.setCustomSpacing(WellnarioSpacing.large, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(saveButton)
    }

    @objc private func saveTapped() {
        guard !saveButton.isLoading else { return }
        endEditing()
        saveButton.isLoading = true
        performSave()
    }

    @objc private func cancelTapped() {
        closeEditor(animated: true)
    }

    private func closeEditor(animated: Bool) {
        // Intake and the other editors are normally wrapped in a page-sheet
        // navigation controller. During the end of a sheet presentation,
        // `presentingViewController` can briefly be nil even though the
        // navigation controller still owns the sheet. Dismiss the sheet by
        // its presentation style as well so saving never leaves the editor
        // stranded on screen.
        if let navigationController,
           navigationController.presentingViewController != nil
            || navigationController.sheetPresentationController != nil {
            navigationController.dismiss(animated: animated)
            return
        }
        if presentingViewController != nil || sheetPresentationController != nil {
            dismiss(animated: animated)
            return
        }
        if let navigationController,
           navigationController.topViewController === self,
           navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: animated)
        }
    }

    @objc private func endEditing() {
        view.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView: UIView? = touch.view
        while let candidate = touchedView, candidate !== view {
            if candidate is UIControl { return false }
            touchedView = candidate.superview
        }
        return true
    }

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let converted = view.convert(frame, from: nil)
        scrollView.contentInset.bottom = max(
            minimumBottomContentInset,
            max(0, view.bounds.maxY - converted.minY) + WellnarioSpacing.small
        )
        scrollView.verticalScrollIndicatorInsets.bottom = scrollView.contentInset.bottom
    }

    @objc private func keyboardHidden(_ notification: Notification) {
        scrollView.contentInset.bottom = minimumBottomContentInset
        scrollView.verticalScrollIndicatorInsets.bottom = minimumBottomContentInset
    }
}

@MainActor
final class FormSectionView: PremiumCardView {
    let stackView = UIStackView()
    let titleLabel = UILabel()

    init(title: String, views: [UIView]) {
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 0

        stackView.axis = .vertical
        stackView.spacing = WellnarioSpacing.small
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(WellnarioSpacing.medium, after: titleLabel)
        views.forEach(stackView.addArrangedSubview)
        contentView.addForAutoLayout(stackView)
        stackView.pinEdges(to: contentView, insets: .all(WellnarioSpacing.cardPadding))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
final class SelectionFieldView: UIView {
    let button = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let leadingImageView = UIImageView()
    private let accessoryImageView = UIImageView(image: UIImage(systemName: "chevron.up.chevron.down"))

    var title: String = "" {
        didSet {
            titleLabel.text = title
            titleLabel.isHidden = title.isEmpty
        }
    }
    var value: String = "" { didSet { updateValue() } }
    var leadingImage: UIImage? { didSet { updateValue() } }
    var menu: UIMenu? { didSet { button.menu = menu } }
    var usesCompactHorizontalPadding = false { didSet { updateValue() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    convenience init(title: String) {
        self.init(frame: .zero)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        titleLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        titleLabel.isHidden = title.isEmpty
        button.titleLabel?.font = WellnarioTypography.font(for: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.contentHorizontalAlignment = .leading
        button.applyContinuousCorners(WellnarioRadius.control)
        button.clipsToBounds = true
        button.showsMenuAsPrimaryAction = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.fieldMinimumHeight).isActive = true

        leadingImageView.contentMode = .scaleAspectFit
        leadingImageView.clipsToBounds = true
        leadingImageView.isHidden = true
        leadingImageView.isUserInteractionEnabled = false
        leadingImageView.accessibilityIdentifier = "selection.leading_image"
        accessoryImageView.contentMode = .scaleAspectFit
        accessoryImageView.tintColor = WellnarioPalette.textTertiary
        accessoryImageView.isUserInteractionEnabled = false
        button.addForAutoLayout(leadingImageView)
        button.addForAutoLayout(accessoryImageView)
        NSLayoutConstraint.activate([
            leadingImageView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            leadingImageView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            leadingImageView.widthAnchor.constraint(equalToConstant: 34),
            leadingImageView.heightAnchor.constraint(equalTo: leadingImageView.widthAnchor),
            accessoryImageView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -16),
            accessoryImageView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            accessoryImageView.widthAnchor.constraint(equalToConstant: 14),
            accessoryImageView.heightAnchor.constraint(equalToConstant: 14)
        ])

        let stack = UIStackView(arrangedSubviews: [titleLabel, button], axis: .vertical, spacing: 7)
        addForAutoLayout(stack)
        stack.pinEdges(to: self)
    }

    private func updateValue() {
        var configuration = UIButton.Configuration.plain()
        configuration.title = value
        configuration.baseForegroundColor = WellnarioPalette.textPrimary
        let leadingInset: CGFloat
        if leadingImage == nil {
            leadingInset = usesCompactHorizontalPadding ? 10 : 16
        } else {
            leadingInset = usesCompactHorizontalPadding ? 48 : 56
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 10,
            leading: leadingInset,
            bottom: 10,
            trailing: usesCompactHorizontalPadding ? 30 : 44
        )
        configuration.cornerStyle = .fixed
        configuration.background.backgroundColor = WellnarioPalette.fieldBackground
        configuration.background.cornerRadius = WellnarioRadius.control
        configuration.background.strokeColor = WellnarioPalette.hairline
        configuration.background.strokeWidth = 1
        button.configuration = configuration
        leadingImageView.image = leadingImage
        leadingImageView.isHidden = leadingImage == nil
        button.accessibilityLabel = title
        button.accessibilityValue = value
    }
}

@MainActor
final class TextAreaFieldView: UIView, UITextViewDelegate {
    let textView = UITextView()
    private let titleLabel = UILabel()
    let placeholderLabel = UILabel()
    private var minimumHeightConstraint: NSLayoutConstraint?

    var title: String = "" { didSet { titleLabel.text = title; textView.accessibilityLabel = title } }
    var placeholder: String = "" { didSet { placeholderLabel.text = placeholder } }
    var text: String {
        get { textView.text }
        set { textView.text = newValue; updatePlaceholder() }
    }
    var minimumHeight: CGFloat = WellnarioLayout.textAreaMinimumHeight {
        didSet { minimumHeightConstraint?.constant = minimumHeight }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func textViewDidChange(_ textView: UITextView) { updatePlaceholder() }

    private func setUp() {
        titleLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)

        textView.delegate = self
        textView.backgroundColor = WellnarioPalette.fieldBackground
        textView.textColor = WellnarioPalette.textPrimary
        textView.tintColor = WellnarioPalette.cyan
        textView.font = WellnarioTypography.font(for: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(
            top: WellnarioLayout.textAreaVerticalPadding,
            left: 12,
            bottom: WellnarioLayout.textAreaVerticalPadding,
            right: 12
        )
        textView.applyContinuousCorners(WellnarioRadius.control)
        textView.layer.borderWidth = 1
        textView.layer.borderColor = WellnarioPalette.hairline.cgColor
        minimumHeightConstraint = textView.heightAnchor.constraint(
            greaterThanOrEqualToConstant: minimumHeight
        )
        minimumHeightConstraint?.isActive = true

        placeholderLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textTertiary)
        placeholderLabel.numberOfLines = 0
        placeholderLabel.lineBreakMode = .byWordWrapping
        textView.addForAutoLayout(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 16),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -16),
            placeholderLabel.topAnchor.constraint(
                equalTo: textView.topAnchor,
                constant: WellnarioLayout.textAreaVerticalPadding + 1
            )
        ])

        let stack = UIStackView(arrangedSubviews: [titleLabel, textView], axis: .vertical, spacing: 7)
        addForAutoLayout(stack)
        stack.pinEdges(to: self)
        updatePlaceholder()
    }

    private func updatePlaceholder() { placeholderLabel.isHidden = !textView.text.isEmpty }
}
