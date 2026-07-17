import UIKit

@MainActor
final class IntakeEditorViewController: EditorViewController {
    private let consumption: Consumption?
    private let preferredInstanceID: UUID?
    private let instanceField = SelectionFieldView(title: L10n.Inventory.batch)
    private let fixedInstanceLabel = UILabel()
    private let quantityField = FormFieldView()
    private let datePicker = UIDatePicker()
    private let notesField = TextAreaFieldView()
    private let previewStack = UIStackView()
    private let warningLabel = UILabel()

    private var instances: [SupplementInstance] = []
    private var supplements: [Supplement] = []
    private var selectedInstanceID: UUID?

    init(
        repository: WellnarioRepositoryProtocol,
        consumption: Consumption? = nil,
        preferredInstanceID: UUID? = nil
    ) {
        self.consumption = consumption
        self.preferredInstanceID = preferredInstanceID
        self.selectedInstanceID = consumption?.instanceID ?? preferredInstanceID
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = consumption == nil ? L10n.Today.logIntake : L10n.text("intake.edit")
        view.accessibilityIdentifier = "intake.editor"
        saveButton.accessibilityIdentifier = "intake.save"
        loadOptions()
        configureFields()
        buildForm()
        rebuildPreview()
    }

    override func performSave() {
        quantityField.setError(nil)
        guard let instance = selectedInstance,
              let supplement = supplement(for: instance) else {
            saveButton.isLoading = false
            showError(RepositoryError.validation(L10n.Error.required))
            return
        }
        guard let quantity = FeatureFormatting.parseDecimal(quantityField.textField.text), quantity > 0 else {
            quantityField.setError(L10n.Error.positiveAmount)
            saveButton.isLoading = false
            return
        }
        guard datePicker.date <= Date().addingTimeInterval(300) else {
            saveButton.isLoading = false
            showError(RepositoryError.validation(L10n.Error.futureConsumption))
            return
        }

        let draft = ConsumptionDraft(
            instanceID: instance.id,
            quantity: quantity,
            unit: supplement.basisUnit,
            consumedAt: datePicker.date,
            timeZoneID: consumption?.timeZoneID ?? TimeZone.current.identifier,
            notes: normalized(notesField.text)
        )

        do {
            if let consumption {
                _ = try repository.updateConsumption(id: consumption.id, with: draft)
            } else {
                _ = try repository.createConsumption(draft)
            }
            finishSaving(message: L10n.text("intake.saved"))
        } catch {
            saveButton.isLoading = false
            showError(error)
        }
    }

    private func loadOptions() {
        do {
            let currentInstanceID = consumption?.instanceID
            instances = try repository
                .fetchInstances(supplementID: nil, includeArchived: currentInstanceID != nil)
                .filter { !$0.isArchived || $0.id == currentInstanceID }

            let currentSupplementID = instances.first(where: { $0.id == currentInstanceID })?.supplementID
            supplements = try repository
                .fetchSupplements(includeArchived: currentSupplementID != nil)
                .filter { !$0.isArchived || $0.id == currentSupplementID }
            if selectedInstanceID == nil { selectedInstanceID = instances.first?.id }
        } catch { showError(error) }
    }

    private func configureFields() {
        rebuildInstanceMenu()
        instanceField.button.accessibilityIdentifier = "intake.instance.selector"
        instanceField.usesCompactHorizontalPadding = true
        instanceField.button.isEnabled = !isPreferredInstanceLocked
        fixedInstanceLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        fixedInstanceLabel.text = L10n.text("intake.inventory.fixed")
        fixedInstanceLabel.numberOfLines = 0
        fixedInstanceLabel.isHidden = !isPreferredInstanceLocked
        instanceField.button.accessibilityHint = isPreferredInstanceLocked
            ? L10n.text("intake.inventory.fixed")
            : nil
        quantityField.configure(
            title: L10n.Form.amountConsumed,
            placeholder: "1",
            text: consumption.map { FeatureFormatting.decimal($0.quantity) } ?? "1",
            keyboardType: .decimalPad
        )
        quantityField.textField.accessibilityIdentifier = "intake.quantity"
        quantityField.textField.addTarget(self, action: #selector(quantityChanged), for: .editingChanged)
        quantityField.helperText = L10n.text("intake.quantity.helper")
        updateQuantityUnit()

        datePicker.datePickerMode = .dateAndTime
        datePicker.preferredDatePickerStyle = .compact
        datePicker.maximumDate = Date().addingTimeInterval(300)
        datePicker.timeZone = consumption
            .flatMap { TimeZone(identifier: $0.timeZoneID) }
            ?? .current
        datePicker.date = consumption?.consumedAt ?? Date()
        datePicker.tintColor = WellnarioPalette.cyan

        notesField.title = L10n.Common.notes
        notesField.placeholder = L10n.text("intake.notes.placeholder")
        notesField.text = consumption?.notes ?? ""

        warningLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.warning)
        warningLabel.numberOfLines = 0
        warningLabel.isHidden = true
        warningLabel.accessibilityTraits = [.staticText]
        updateExpirationWarning()
    }

    private func buildForm() {
        addSection(
            title: L10n.Form.basics,
            views: [instanceField, fixedInstanceLabel, warningLabel, quantityField]
        )

        let dateTitle = UILabel()
        dateTitle.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        dateTitle.text = "\(L10n.Form.date) · \(L10n.Form.time)"
        let dateStack = UIStackView(arrangedSubviews: [dateTitle, datePicker], axis: .vertical, spacing: 7)
        addSection(title: L10n.Form.details, views: [dateStack, notesField])

        previewStack.axis = .vertical
        previewStack.spacing = WellnarioSpacing.xSmall
        addSection(title: L10n.Form.activeContribution, views: [previewStack])
        addSaveButton()
    }

    private var selectedInstance: SupplementInstance? {
        instances.first { $0.id == selectedInstanceID }
    }

    private var isPreferredInstanceLocked: Bool {
        consumption == nil && preferredInstanceID != nil && selectedInstance != nil
    }

    private func supplement(for instance: SupplementInstance) -> Supplement? {
        supplements.first { $0.id == instance.supplementID }
    }

    private func rebuildInstanceMenu() {
        if let instance = selectedInstance, let supplement = supplement(for: instance) {
            instanceField.value = [supplement.name, instance.label]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        } else {
            instanceField.value = L10n.Common.required
        }
        instanceField.menu = UIMenu(children: instances.compactMap { instance in
            guard let supplement = supplement(for: instance) else { return nil }
            let productName = [supplement.brand, supplement.name]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            let title = [productName, instance.label]
                .filter { !$0.isEmpty }
                .joined(separator: " — ")
            return UIAction(
                title: title,
                image: SupplementPhotoStore.image(
                    reference: supplement.imageReference,
                    databaseURL: repository.databaseURL
                )?.withRenderingMode(.alwaysOriginal),
                state: instance.id == selectedInstanceID ? .on : .off
            ) { [weak self] _ in
                self?.selectedInstanceID = instance.id
                self?.rebuildInstanceMenu()
                self?.updateQuantityUnit()
                self?.updateExpirationWarning()
                self?.rebuildPreview()
            }
        })
    }

    private func updateQuantityUnit() {
        guard let instance = selectedInstance, let supplement = supplement(for: instance) else {
            quantityField.unitTitle = nil
            return
        }
        quantityField.unitTitle = supplement.basisUnit.symbol(languageCode: catalogLanguage.rawValue)
    }

    private func updateExpirationWarning() {
        guard let expiry = selectedInstance?.expirationDay else {
            warningLabel.isHidden = true
            return
        }
        let today = LocalDay(containing: Date(), in: .current)
        guard expiry <= today else {
            warningLabel.isHidden = true
            return
        }
        warningLabel.isHidden = false
        warningLabel.text = expiry < today
            ? L10n.text("intake.warning.expired")
            : L10n.text("intake.warning.expires_today")
    }

    @objc private func quantityChanged() { rebuildPreview() }

    private func rebuildPreview() {
        previewStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let instance = selectedInstance,
              let supplement = supplement(for: instance),
              let quantity = FeatureFormatting.parseDecimal(quantityField.textField.text),
              quantity > 0 else {
            let label = UILabel()
            label.applyWellnarioStyle(.body, color: WellnarioPalette.textTertiary)
            label.text = L10n.text("intake.preview.empty")
            previewStack.addArrangedSubview(label)
            return
        }

        do {
            if let consumption, consumption.instanceID == instance.id, consumption.quantity > 0 {
                let ratio = try DecimalMath.divide(quantity, consumption.quantity)
                for snapshot in consumption.activeSnapshots {
                    let amount = try DecimalMath.multiply(snapshot.amount, ratio)
                    previewStack.addArrangedSubview(previewRow(
                        name: snapshot.localizedActiveName(language: catalogLanguage),
                        amount: amount,
                        unit: snapshot.unit
                    ))
                }
            } else {
                let ratio = try DecimalMath.divide(quantity, supplement.basisQuantity)
                let actives = try repository.fetchActives(includeArchived: true)
                for component in supplement.components {
                    let amount = try DecimalMath.multiply(component.amount, ratio)
                    let name = actives.first(where: { $0.id == component.activeID })?.localizedName(language: catalogLanguage) ?? L10n.Form.active
                    previewStack.addArrangedSubview(previewRow(name: name, amount: amount, unit: component.unit))
                }
            }
        } catch {
            let label = UILabel()
            label.applyWellnarioStyle(.caption, color: WellnarioPalette.danger)
            label.text = error.localizedDescription
            label.numberOfLines = 0
            previewStack.addArrangedSubview(label)
        }
    }

    private func previewRow(name: String, amount: Decimal, unit: DoseUnit) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "sparkle"))
        icon.tintColor = WellnarioPalette.cyan
        let nameLabel = UILabel()
        nameLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        nameLabel.text = name
        let valueLabel = UILabel()
        valueLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.cyan)
        valueLabel.text = "\(FeatureFormatting.decimal(amount)) \(unit.symbol(languageCode: catalogLanguage.rawValue))"
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        return UIStackView(arrangedSubviews: [icon, nameLabel, valueLabel], axis: .horizontal, spacing: 10, alignment: .center)
    }

    private func normalized(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
