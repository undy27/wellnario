import UIKit

@MainActor
final class InstanceEditorViewController: EditorViewController {
    private let instance: SupplementInstance?
    private let preferredSupplementID: UUID?
    private let productField = SelectionFieldView(title: L10n.Supplements.products)
    private let labelField = FormFieldView()
    private let notesField = TextAreaFieldView()
    private let expirySwitch = UISwitch()
    private let expiryPicker = UIDatePicker()

    private var supplements: [Supplement] = []
    private var presentations: [PresentationType] = []
    private var selectedSupplementID: UUID?

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

    override func performSave() {
        guard let selectedSupplementID else {
            saveButton.isLoading = false
            showError(RepositoryError.validation(L10n.Error.required))
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
            totalQuantity: instance?.totalQuantity,
            totalUnit: instance?.totalUnit
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
        let artwork = PresentationArtworkView(kind: presentationKind)
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 132),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor)
        ])
        let artContainer = UIView()
        artContainer.addForAutoLayout(artwork)
        NSLayoutConstraint.activate([
            artwork.centerXAnchor.constraint(equalTo: artContainer.centerXAnchor),
            artwork.topAnchor.constraint(equalTo: artContainer.topAnchor),
            artwork.bottomAnchor.constraint(equalTo: artContainer.bottomAnchor)
        ])

        let expiryLabel = UILabel()
        expiryLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        expiryLabel.text = L10n.Inventory.expiryDate
        let expiryRow = UIStackView(arrangedSubviews: [expiryLabel, UIView(), expirySwitch], axis: .horizontal, spacing: 8, alignment: .center)

        addSection(title: L10n.Form.basics, views: [artContainer, productField, labelField])
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
            }
        })
    }

    @objc private func expiryToggled() {
        WellnarioMotion.animate {
            self.expiryPicker.isHidden = !self.expirySwitch.isOn
            self.view.layoutIfNeeded()
        }
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
