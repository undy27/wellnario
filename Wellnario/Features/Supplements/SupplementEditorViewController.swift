import UIKit

@MainActor
final class SupplementEditorViewController: EditorViewController {
    private let supplement: Supplement?
    private let artwork = PresentationArtworkView(kind: .capsule)
    private let nameField = FormFieldView()
    private let brandField = FormFieldView()
    private let categoryField = FormFieldView()
    private let descriptionField = TextAreaFieldView()
    private let priceField = FormFieldView()
    private let presentationField = SelectionFieldView(title: L10n.Form.presentation)
    private let basisField = FormFieldView()
    private let componentsStack = UIStackView()
    private let addComponentButton = PrimaryButton(style: .secondary)

    private var presentations: [PresentationType] = []
    private var actives: [Active] = []
    private var selectedPresentationID: UUID?
    private var basisUnit: DoseUnit = .capsule
    private var componentRows: [ComponentEditorRow] = []

    init(repository: WellnarioRepositoryProtocol, supplement: Supplement? = nil) {
        self.supplement = supplement
        self.selectedPresentationID = supplement?.presentationTypeID
        self.basisUnit = supplement?.basisUnit ?? .capsule
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = supplement == nil ? L10n.Supplements.addSupplement : L10n.text("supplements.edit")
        view.accessibilityIdentifier = "supplement.editor"
        loadOptions()
        configureFields()
        buildForm()
        loadComponents()
    }

    override func performSave() {
        clearErrors()
        let name = normalized(nameField.textField.text)
        let brand = normalized(brandField.textField.text)
        guard let name else {
            nameField.setError(L10n.Error.required)
            saveButton.isLoading = false
            return
        }
        guard let brand else {
            brandField.setError(L10n.Error.required)
            saveButton.isLoading = false
            return
        }
        guard let presentationID = selectedPresentationID else {
            saveButton.isLoading = false
            showError(RepositoryError.validation(L10n.Error.required))
            return
        }
        guard let basis = FeatureFormatting.parseDecimal(basisField.textField.text), basis > 0 else {
            basisField.setError(L10n.Error.positiveAmount)
            saveButton.isLoading = false
            return
        }

        var drafts: [SupplementComponentDraft] = []
        var seen = Set<UUID>()
        for row in componentRows {
            guard let activeID = row.selectedActiveID,
                  let amount = FeatureFormatting.parseDecimal(row.amountField.textField.text),
                  amount > 0 else {
                row.amountField.setError(L10n.Error.positiveAmount)
                saveButton.isLoading = false
                return
            }
            guard seen.insert(activeID).inserted else {
                row.amountField.setError(L10n.text("error.duplicate_active"))
                saveButton.isLoading = false
                return
            }
            drafts.append(SupplementComponentDraft(activeID: activeID, amount: amount, unit: row.selectedUnit))
        }
        guard !drafts.isEmpty else {
            saveButton.isLoading = false
            showError(RepositoryError.validation(L10n.text("error.component_required")))
            return
        }

        let priceText = normalized(priceField.textField.text)
        let price = priceText.flatMap { FeatureFormatting.parseDecimal($0) }
        if priceText != nil, price == nil {
            priceField.setError(L10n.Error.invalidNumber)
            saveButton.isLoading = false
            return
        }

        let draft = SupplementDraft(
            name: name,
            brand: brand,
            details: normalized(descriptionField.text),
            category: normalized(categoryField.textField.text),
            price: price,
            currencyCode: price == nil ? nil : "EUR",
            imageReference: selectedPresentation?.illustrations.first?.assetKey,
            presentationTypeID: presentationID,
            basisQuantity: basis,
            basisUnit: basisUnit,
            components: drafts
        )

        do {
            if let supplement {
                _ = try repository.updateSupplement(id: supplement.id, with: draft)
            } else {
                _ = try repository.createSupplement(draft)
            }
            finishSaving()
        } catch {
            saveButton.isLoading = false
            showError(error)
        }
    }

    private var selectedPresentation: PresentationType? {
        presentations.first { $0.id == selectedPresentationID }
    }

    private func loadOptions() {
        do {
            presentations = try repository.fetchPresentationTypes()
            let existingActiveIDs = Set(supplement?.components.map(\.activeID) ?? [])
            actives = try repository
                .fetchActives(includeArchived: supplement != nil)
                .filter { !$0.isArchived || existingActiveIDs.contains($0.id) }
            if selectedPresentationID == nil {
                selectedPresentationID = presentations.first?.id
                basisUnit = presentations.first?.defaultUnit ?? .capsule
            }
        } catch { showError(error) }
    }

    private func configureFields() {
        nameField.configure(
            title: L10n.Form.name,
            placeholder: L10n.text("supplements.name.placeholder"),
            text: supplement?.name,
            contentType: .name
        )
        nameField.textField.accessibilityIdentifier = "supplement.name"
        brandField.configure(
            title: L10n.Form.brand,
            placeholder: L10n.text("supplements.brand.placeholder"),
            text: supplement?.brand,
            contentType: .organizationName
        )
        brandField.textField.accessibilityIdentifier = "supplement.brand"
        categoryField.configure(
            title: L10n.Form.category,
            placeholder: L10n.text("supplements.category.placeholder"),
            text: supplement?.category
        )
        descriptionField.title = L10n.Form.description
        descriptionField.placeholder = L10n.text("supplements.description.placeholder")
        descriptionField.text = supplement?.details ?? ""
        priceField.configure(
            title: L10n.Form.price,
            placeholder: L10n.Common.optional,
            text: supplement?.price.map { FeatureFormatting.decimal($0, maximumFractionDigits: 2) },
            keyboardType: .decimalPad
        )
        priceField.unitTitle = supplement?.currencyCode ?? "EUR"
        basisField.configure(
            title: L10n.Form.supplementAmount,
            placeholder: "1",
            text: supplement.map { FeatureFormatting.decimal($0.basisQuantity) } ?? "1",
            keyboardType: .decimalPad
        )
        basisField.helperText = L10n.text("supplements.basis.helper")
        rebuildPresentationMenu()
        updatePresentationArtwork()
    }

    private func buildForm() {
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 148),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor)
        ])
        let artContainer = UIView()
        artContainer.addForAutoLayout(artwork)
        NSLayoutConstraint.activate([
            artwork.centerXAnchor.constraint(equalTo: artContainer.centerXAnchor),
            artwork.topAnchor.constraint(equalTo: artContainer.topAnchor),
            artwork.bottomAnchor.constraint(equalTo: artContainer.bottomAnchor)
        ])

        addSection(title: L10n.Form.basics, views: [artContainer, nameField, brandField, presentationField, basisField])
        addSection(title: L10n.Form.details, views: [categoryField, descriptionField, priceField])

        componentsStack.axis = .vertical
        componentsStack.spacing = WellnarioSpacing.small
        addComponentButton.setTitle(L10n.text("supplements.component.add"), for: .normal)
        addComponentButton.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        addComponentButton.tintColor = WellnarioPalette.cyan
        addComponentButton.addTarget(self, action: #selector(addComponent), for: .touchUpInside)
        addSection(title: L10n.Supplements.composition, views: [componentsStack, addComponentButton])
        addSaveButton()
    }

    private func loadComponents() {
        if let supplement, !supplement.components.isEmpty {
            supplement.components.forEach { component in
                appendComponent(activeID: component.activeID, amount: component.amount, unit: component.unit)
            }
        } else if let first = actives.first {
            appendComponent(activeID: first.id, amount: nil, unit: first.baseUnit)
        }
        updateComponentRemoveButtons()
    }

    @objc private func addComponent() {
        guard !actives.isEmpty else {
            let alert = UIAlertController(title: L10n.Actives.noItemsTitle, message: L10n.text("supplements.component.requires_active"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: L10n.Actives.add, style: .default) { [weak self] _ in
                guard let self else { return }
                self.presentSheet(ActiveEditorViewController(repository: self.repository), largeOnly: true)
            })
            present(alert, animated: true)
            return
        }
        let unused = actives.first { active in !componentRows.contains { $0.selectedActiveID == active.id } }
        let selected = unused ?? actives[0]
        appendComponent(activeID: selected.id, amount: nil, unit: selected.baseUnit)
        updateComponentRemoveButtons()
        let row = componentRows.last!
        scrollView.scrollRectToVisible(row.convert(row.bounds, to: scrollView).insetBy(dx: 0, dy: -24), animated: true)
    }

    private func appendComponent(activeID: UUID?, amount: Decimal?, unit: DoseUnit) {
        let row = ComponentEditorRow(actives: actives, language: catalogLanguage)
        row.configure(activeID: activeID, amount: amount, unit: unit)
        row.onRemove = { [weak self, weak row] in
            guard let self, let row else { return }
            self.componentRows.removeAll { $0 === row }
            self.componentsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
            self.updateComponentRemoveButtons()
        }
        componentRows.append(row)
        componentsStack.addArrangedSubview(row)
    }

    private func updateComponentRemoveButtons() {
        componentRows.forEach { $0.removeButton.isHidden = componentRows.count <= 1 }
    }

    private func rebuildPresentationMenu() {
        presentationField.value = selectedPresentation?.localizedName(language: catalogLanguage) ?? L10n.Common.required
        presentationField.menu = UIMenu(children: presentations.map { presentation in
            UIAction(
                title: presentation.localizedName(language: catalogLanguage),
                state: presentation.id == selectedPresentationID ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                self.selectedPresentationID = presentation.id
                self.basisUnit = presentation.defaultUnit
                self.rebuildPresentationMenu()
                self.updatePresentationArtwork()
            }
        })
        basisField.unitTitle = basisUnit.symbol(languageCode: catalogLanguage.rawValue)
    }

    private func updatePresentationArtwork() {
        guard let selectedPresentation else { return }
        artwork.kind = PresentationKind(name: selectedPresentation.localizedName(language: catalogLanguage))
        let palette: [(UIColor, UIColor)] = [
            (WellnarioPalette.cyan, WellnarioPalette.violet),
            (WellnarioPalette.violet, WellnarioPalette.magenta),
            (WellnarioPalette.pink, WellnarioPalette.warning)
        ]
        let index = abs(selectedPresentation.id.hashValue) % palette.count
        artwork.primaryColor = palette[index].0
        artwork.secondaryColor = palette[index].1
    }

    private func clearErrors() {
        nameField.setError(nil)
        brandField.setError(nil)
        basisField.setError(nil)
        priceField.setError(nil)
        componentRows.forEach { $0.amountField.setError(nil) }
    }

    private func normalized(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

@MainActor
private final class ComponentEditorRow: UIView {
    let amountField = FormFieldView()
    let removeButton = UIButton(type: .system)
    private let activeField = SelectionFieldView(title: L10n.Form.active)
    private let unitField = SelectionFieldView(title: L10n.Form.unit)
    private let actives: [Active]
    private let language: CatalogLanguage

    var selectedActiveID: UUID?
    var selectedUnit: DoseUnit = .milligram
    var onRemove: (() -> Void)?

    init(actives: [Active], language: CatalogLanguage) {
        self.actives = actives
        self.language = language
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(activeID: UUID?, amount: Decimal?, unit: DoseUnit) {
        selectedActiveID = activeID ?? actives.first?.id
        selectedUnit = unit
        amountField.textField.text = amount.map { FeatureFormatting.decimal($0) }
        rebuildMenus()
    }

    private var active: Active? { actives.first { $0.id == selectedActiveID } }

    private func setUp() {
        backgroundColor = WellnarioPalette.background.withAlphaComponent(0.28)
        applyContinuousCorners(WellnarioRadius.control)
        layer.borderWidth = 1
        layer.borderColor = WellnarioPalette.hairline.cgColor

        amountField.configure(title: L10n.Form.activeAmount, placeholder: "0", keyboardType: .decimalPad)
        amountField.textField.accessibilityIdentifier = "supplement.component.amount"
        removeButton.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
        removeButton.tintColor = WellnarioPalette.danger
        removeButton.accessibilityLabel = L10n.Common.delete
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        removeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: WellnarioLayout.minimumTouchTarget).isActive = true

        let top = UIStackView(arrangedSubviews: [activeField, removeButton], axis: .horizontal, spacing: 8, alignment: .bottom)
        let row = UIStackView(arrangedSubviews: [amountField, unitField], axis: .horizontal, spacing: 10, alignment: .top, distribution: .fillEqually)
        let stack = UIStackView(arrangedSubviews: [top, row], axis: .vertical, spacing: 12)
        addForAutoLayout(stack)
        stack.pinEdges(to: self, insets: .all(12))
    }

    private func rebuildMenus() {
        activeField.value = active?.localizedName(language: language) ?? L10n.Common.required
        activeField.menu = UIMenu(children: actives.map { active in
            UIAction(
                title: active.localizedName(language: language),
                state: active.id == selectedActiveID ? .on : .off
            ) { [weak self] _ in
                self?.selectedActiveID = active.id
                self?.selectedUnit = active.baseUnit
                self?.rebuildMenus()
            }
        })

        let allowed = DoseUnit.allCases.filter { $0.isCompatible(with: active?.baseUnit ?? selectedUnit) }
        if !allowed.contains(selectedUnit), let first = allowed.first { selectedUnit = first }
        unitField.value = selectedUnit.symbol(languageCode: language.rawValue)
        amountField.unitTitle = selectedUnit.symbol(languageCode: language.rawValue)
        unitField.menu = UIMenu(children: allowed.map { unit in
            UIAction(
                title: unit.symbol(languageCode: language.rawValue),
                state: unit == selectedUnit ? .on : .off
            ) { [weak self] _ in
                self?.selectedUnit = unit
                self?.rebuildMenus()
            }
        })
    }

    @objc private func removeTapped() { onRemove?() }
}
