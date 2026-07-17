import UIKit

@MainActor
final class InstanceEditorViewController: EditorViewController {
    private var instance: SupplementInstance?
    private let preferredSupplementID: UUID?
    private let productField = SelectionFieldView(title: L10n.Supplements.products)
    private let labelField = FormFieldView()
    private let remainingQuantityField = FormFieldView()
    private let notesField = TextAreaFieldView()
    private let expirySwitch = UISwitch()
    private let expiryPicker = UIDatePicker()
    private let artworkContainer = UIView()
    private let presentationArtwork = PresentationArtworkView()
    private let productPhotoView = UIImageView()

    private var supplements: [Supplement] = []
    private var presentations: [PresentationType] = []
    private var selectedSupplementID: UUID?
    private var hasEditedRemainingQuantity = false

    init(
        repository: WellnarioRepositoryProtocol,
        instance: SupplementInstance? = nil,
        supplementID: UUID? = nil
    ) {
        self.instance = instance
        self.preferredSupplementID = supplementID
        self.selectedSupplementID = instance?.supplementID ?? supplementID
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = instance == nil ? L10n.Inventory.add : L10n.text("inventory.edit")
        view.accessibilityIdentifier = "instance.editor"
        loadOptions()
        configureFields()
        buildForm()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadContent()
    }

    override func performSave() {
        remainingQuantityField.setError(nil)
        guard let selectedSupplementID else {
            saveButton.isLoading = false
            showError(RepositoryError.validation(L10n.Error.required))
            return
        }
        let remainingText = normalized(remainingQuantityField.textField.text)
        let remainingQuantity: Decimal?
        if let remainingText {
            guard let parsed = FeatureFormatting.parseDecimal(remainingText), parsed >= 0 else {
                remainingQuantityField.setError(L10n.text("error.nonnegative_amount"))
                saveButton.isLoading = false
                return
            }
            remainingQuantity = parsed
        } else {
            remainingQuantity = nil
        }
        let remainingUnit = remainingQuantity == nil ? nil : remainingContentUnit
        if remainingQuantity != nil, remainingUnit == nil {
            remainingQuantityField.setError(L10n.Error.required)
            saveButton.isLoading = false
            return
        }
        let expirationDay = expirySwitch.isOn
            ? LocalDay(containing: expiryPicker.date, in: .current)
            : nil
        let draft = SupplementInstanceDraft(
            supplementID: selectedSupplementID,
            label: normalized(labelField.textField.text),
            expirationDay: expirationDay,
            notes: normalized(notesField.text),
            totalQuantity: remainingQuantity,
            totalUnit: remainingUnit
        )

        do {
            if let instance {
                _ = try repository.updateInstance(id: instance.id, with: draft)
            } else {
                _ = try repository.createInstance(draft)
            }
            finishSaving()
        } catch {
            saveButton.isLoading = false
            showError(error)
        }
    }

    override func reloadContent() {
        guard let instance, !hasEditedRemainingQuantity else { return }
        do {
            guard let refreshedInstance = try repository.instance(id: instance.id) else { return }
            self.instance = refreshedInstance
            remainingQuantityField.textField.text = refreshedInstance.totalQuantity.map {
                FeatureFormatting.decimal($0)
            }
            updateRemainingContentUnit()
        } catch {
            showError(error)
        }
    }

    private func loadOptions() {
        do {
            supplements = try repository.fetchSupplements(includeArchived: false)
            presentations = try repository.fetchPresentationTypes()
            if selectedSupplementID == nil { selectedSupplementID = supplements.first?.id }
        } catch { showError(error) }
    }

    private func configureFields() {
        rebuildProductMenu()
        productField.button.isEnabled = instance == nil || preferredSupplementID == nil

        labelField.configure(
            title: L10n.Form.identifier,
            placeholder: L10n.text("inventory.label.placeholder"),
            text: instance?.label
        )
        labelField.textField.accessibilityIdentifier = "instance.label"
        labelField.helperText = L10n.text("inventory.label.helper")

        remainingQuantityField.configure(
            title: L10n.text("inventory.remaining_content"),
            placeholder: "0",
            text: instance?.totalQuantity.map { FeatureFormatting.decimal($0) },
            keyboardType: .decimalPad
        )
        remainingQuantityField.textField.accessibilityIdentifier = "instance.remaining_quantity"
        remainingQuantityField.unitButton.accessibilityIdentifier = "instance.remaining_unit"
        remainingQuantityField.helperText = L10n.text("inventory.remaining_content.helper")
        remainingQuantityField.textField.addTarget(
            self,
            action: #selector(remainingQuantityChanged),
            for: .editingChanged
        )
        updateRemainingContentUnit()

        notesField.title = L10n.Common.notes
        notesField.placeholder = L10n.text("inventory.notes.placeholder")
        notesField.text = instance?.notes ?? ""

        expirySwitch.isOn = instance?.expirationDay != nil
        expirySwitch.onTintColor = WellnarioPalette.violet
        expirySwitch.addTarget(self, action: #selector(expiryToggled), for: .valueChanged)

        expiryPicker.datePickerMode = .date
        expiryPicker.preferredDatePickerStyle = .compact
        expiryPicker.minimumDate = Calendar.current.date(byAdding: .year, value: -10, to: Date())
        expiryPicker.maximumDate = Calendar.current.date(byAdding: .year, value: 20, to: Date())
        if let day = instance?.expirationDay,
           let date = FeatureFormatting.localDayDate(day) {
            expiryPicker.date = date
        }
        expiryPicker.tintColor = WellnarioPalette.cyan
        expiryPicker.isHidden = !expirySwitch.isOn
    }

    private func buildForm() {
        artworkContainer.accessibilityIdentifier = "instance.artwork"
        presentationArtwork.accessibilityIdentifier = "instance.presentation_artwork"
        productPhotoView.accessibilityIdentifier = "instance.product_photo"
        productPhotoView.contentMode = .scaleAspectFit
        productPhotoView.clipsToBounds = true
        productPhotoView.applyContinuousCorners(WellnarioRadius.card)

        artworkContainer.addForAutoLayout(presentationArtwork)
        artworkContainer.addForAutoLayout(productPhotoView)
        NSLayoutConstraint.activate([
            artworkContainer.widthAnchor.constraint(equalToConstant: 132),
            artworkContainer.heightAnchor.constraint(equalTo: artworkContainer.widthAnchor)
        ])
        presentationArtwork.pinEdges(to: artworkContainer)
        productPhotoView.pinEdges(to: artworkContainer)
        updateArtwork()

        let expiryLabel = UILabel()
        expiryLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        expiryLabel.text = L10n.Inventory.expiryDate
        let expiryRow = UIStackView(arrangedSubviews: [expiryLabel, UIView(), expirySwitch], axis: .horizontal, spacing: 8, alignment: .center)

        addSection(
            title: L10n.Form.basics,
            views: [artworkContainer, productField, labelField, remainingQuantityField]
        )
        addSection(title: L10n.Form.details, views: [expiryRow, expiryPicker, notesField])
        if let instance, !instance.isArchived {
            let logIntakeButton = PrimaryButton(
                title: L10n.Today.logIntake,
                style: .secondary
            )
            logIntakeButton.setImage(
                UIImage(systemName: "plus.circle.fill"),
                for: .normal
            )
            logIntakeButton.tintColor = WellnarioPalette.fuchsia
            logIntakeButton.accessibilityIdentifier = "instance.log_intake"
            logIntakeButton.addTarget(
                self,
                action: #selector(logIntake),
                for: .touchUpInside
            )
            contentStack.addArrangedSubview(logIntakeButton)
        }
        addSaveButton()
    }

    private var selectedSupplement: Supplement? {
        supplements.first { $0.id == selectedSupplementID }
    }

    private var remainingContentUnit: DoseUnit? {
        if instance?.supplementID == selectedSupplementID, let unit = instance?.totalUnit {
            return unit
        }
        return selectedSupplement?.basisUnit
    }

    private var presentationKind: PresentationKind {
        guard let supplement = selectedSupplement,
              let presentation = presentations.first(where: { $0.id == supplement.presentationTypeID }) else {
            return .other
        }
        return PresentationKind(name: presentation.localizedName(language: catalogLanguage))
    }

    private func rebuildProductMenu() {
        productField.value = selectedSupplement.map { "\($0.brand) · \($0.name)" } ?? L10n.Common.required
        productField.menu = UIMenu(children: supplements.map { supplement in
            UIAction(
                title: "\(supplement.brand) · \(supplement.name)",
                state: supplement.id == selectedSupplementID ? .on : .off
            ) { [weak self] _ in
                self?.selectedSupplementID = supplement.id
                self?.rebuildProductMenu()
                self?.updateRemainingContentUnit()
                self?.updateArtwork()
            }
        })
    }

    private func updateRemainingContentUnit() {
        remainingQuantityField.unitTitle = remainingContentUnit?
            .symbol(languageCode: catalogLanguage.rawValue)
    }

    private func updateArtwork() {
        presentationArtwork.kind = presentationKind
        let photo = selectedSupplement.flatMap {
            SupplementPhotoStore.image(reference: $0.imageReference, databaseURL: repository.databaseURL)
        }
        productPhotoView.image = photo
        productPhotoView.isHidden = photo == nil
        presentationArtwork.isHidden = photo != nil
    }

    @objc private func expiryToggled() {
        WellnarioMotion.animate {
            self.expiryPicker.isHidden = !self.expirySwitch.isOn
            self.view.layoutIfNeeded()
        }
    }

    @objc private func remainingQuantityChanged() {
        hasEditedRemainingQuantity = true
    }

    @objc private func logIntake() {
        guard let instance, !instance.isArchived else { return }
        view.endEditing(true)
        presentSheet(
            IntakeEditorViewController(
                repository: repository,
                preferredInstanceID: instance.id
            ),
            largeOnly: true
        )
    }

    private func normalized(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
