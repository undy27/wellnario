import PhotosUI
import UIKit
import UniformTypeIdentifiers

enum SupplementPhotoStore {
    private static let referencePrefix = "user-photo:"
    private static let directoryName = "SupplementPhotos"

    @MainActor
    static func save(_ image: UIImage, databaseURL: URL, fileManager: FileManager = .default) throws -> String {
        let directory = databaseURL.deletingLastPathComponent().appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let maximumDimension: CGFloat = 1_600
        let sourceSize = image.size
        let scale = min(1, maximumDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, sourceSize.height * scale)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = normalized.jpegData(compressionQuality: 0.84) else {
            throw RepositoryError.storage("The selected product photo could not be encoded.")
        }

        let fileName = "\(UUID().uuidString).jpg"
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        return referencePrefix + fileName
    }

    @MainActor
    static func image(reference: String?, databaseURL: URL) -> UIImage? {
        guard let reference, !reference.isEmpty else { return nil }
        guard reference.hasPrefix(referencePrefix) else { return UIImage(named: reference) }
        let fileName = String(reference.dropFirst(referencePrefix.count))
        let url = databaseURL.deletingLastPathComponent()
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        return UIImage(contentsOfFile: url.path)
    }

    static func remove(reference: String?, databaseURL: URL, fileManager: FileManager = .default) {
        guard let reference, reference.hasPrefix(referencePrefix) else { return }
        let fileName = String(reference.dropFirst(referencePrefix.count))
        let url = databaseURL.deletingLastPathComponent()
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
        try? fileManager.removeItem(at: url)
    }
}

@MainActor
private final class ProductPackageWizardState {
    enum DoseStyle { case discrete, continuous }

    var brand = ""
    var name = ""
    var price: Decimal?
    var currencyCode = Locale.autoupdatingCurrent.currency?.identifier ?? "EUR"
    var photo: UIImage?
    var doseStyle: DoseStyle = .discrete
    var totalQuantity: Decimal = 1
    var totalUnit: DoseUnit = .capsule
    var hasConfiguredTotal = false
    var presentationID: UUID?
    var basisQuantity: Decimal = 1
    var basisUnit: DoseUnit = .capsule
    var hasConfiguredBasis = false
    var components: [SupplementComponentDraft] = []
    var presentationImageReference: String?
    var initialInventoryCount = 1
    var initialInventoryLabels: [String] = []
    var initialInventoryExpirations: [LocalDay?] = []
    let reminderDraftProductID = UUID()
    var reminderDrafts: [SupplementProductReminder] = []
}

@MainActor
final class ProductPackageWizardViewController: EditorViewController, PHPickerViewControllerDelegate {
    private let state = ProductPackageWizardState()
    private let brandField = FormFieldView()
    private let nameField = FormFieldView()
    private let priceField = FormFieldView()
    private let photoContainer = UIView()
    private let photoPreview = UIImageView()
    private let photoButton = UIButton(type: .custom)
    private let photoPlaceholder = UIStackView()
    private let removePhotoButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("supplements.wizard.title")
        view.accessibilityIdentifier = "supplement.package.wizard.step1"
        saveButton.setTitle(L10n.Common.next, for: .normal)
        saveButton.accessibilityIdentifier = "supplement.package.wizard.next"
        configureFields()
        buildForm()
    }

    override func performSave() {
        nameField.setError(nil)
        priceField.setError(nil)
        let name = normalized(nameField.textField.text)
        guard let name else {
            nameField.setError(L10n.Error.required)
            saveButton.isLoading = false
            return
        }

        let priceText = normalized(priceField.textField.text)
        let price = priceText.flatMap { FeatureFormatting.parseDecimal($0) }
        if priceText != nil {
            guard let price, price >= 0 else {
                priceField.setError(L10n.Error.invalidNumber)
                saveButton.isLoading = false
                return
            }
        }

        state.brand = normalized(brandField.textField.text) ?? ""
        state.name = name
        state.price = price

        saveButton.isLoading = false
        navigationController?.pushViewController(
            ProductPackageAmountStepViewController(repository: repository, state: state),
            animated: true
        )
    }

    private func configureFields() {
        brandField.configure(
            title: L10n.text("supplements.wizard.brand_optional"),
            placeholder: L10n.text("supplements.brand.placeholder"),
            contentType: .organizationName
        )
        brandField.textField.accessibilityIdentifier = "supplement.package.brand"
        nameField.configure(
            title: L10n.Form.name,
            placeholder: L10n.text("supplements.name.placeholder"),
            contentType: .name
        )
        nameField.textField.accessibilityIdentifier = "supplement.package.name"
        priceField.configure(
            title: L10n.text("supplements.wizard.price_optional"),
            placeholder: L10n.Common.optional,
            keyboardType: .decimalPad
        )
        priceField.unitTitle = state.currencyCode
        priceField.textField.accessibilityIdentifier = "supplement.package.price"
        priceField.unitButton.accessibilityIdentifier = "supplement.package.currency"
        priceField.unitButton.showsMenuAsPrimaryAction = true
        rebuildCurrencyMenu()

        photoContainer.backgroundColor = WellnarioPalette.fieldBackground
        photoContainer.applyContinuousCorners(WellnarioRadius.control)
        photoContainer.layer.borderWidth = 1
        photoContainer.layer.borderColor = WellnarioPalette.hairline.cgColor
        photoContainer.clipsToBounds = true
        photoContainer.heightAnchor.constraint(equalToConstant: 176).isActive = true

        photoPreview.contentMode = .scaleAspectFill
        photoPreview.backgroundColor = WellnarioPalette.fieldBackground
        photoPreview.clipsToBounds = true
        photoPreview.accessibilityIdentifier = "supplement.package.photo.preview"

        let placeholderIcon = UIImageView(image: UIImage(systemName: "camera.fill"))
        placeholderIcon.tintColor = WellnarioPalette.fuchsia
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        placeholderIcon.heightAnchor.constraint(equalTo: placeholderIcon.widthAnchor).isActive = true
        let placeholderLabel = UILabel()
        placeholderLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        placeholderLabel.text = L10n.text("supplements.wizard.photo.tap")
        placeholderLabel.textAlignment = .center
        placeholderLabel.numberOfLines = 0
        photoPlaceholder.axis = .vertical
        photoPlaceholder.spacing = 10
        photoPlaceholder.alignment = .center
        photoPlaceholder.isUserInteractionEnabled = false
        photoPlaceholder.addArrangedSubview(placeholderIcon)
        photoPlaceholder.addArrangedSubview(placeholderLabel)

        photoButton.accessibilityIdentifier = "supplement.package.photo.choose"
        photoButton.accessibilityLabel = L10n.text("form.choose_photo")
        photoButton.accessibilityHint = L10n.text("supplements.wizard.photo.tap")
        photoButton.addTarget(self, action: #selector(choosePhoto), for: .touchUpInside)

        var removeConfiguration = UIButton.Configuration.filled()
        removeConfiguration.image = UIImage(systemName: "xmark")
        removeConfiguration.baseBackgroundColor = WellnarioPalette.background.withAlphaComponent(0.82)
        removeConfiguration.baseForegroundColor = WellnarioPalette.textPrimary
        removeConfiguration.cornerStyle = .capsule
        removePhotoButton.configuration = removeConfiguration
        removePhotoButton.isHidden = true
        removePhotoButton.accessibilityLabel = L10n.text("form.remove_photo")
        removePhotoButton.addTarget(self, action: #selector(removePhoto), for: .touchUpInside)

        photoContainer.addForAutoLayout(photoPreview)
        photoContainer.addForAutoLayout(photoPlaceholder)
        photoContainer.addForAutoLayout(photoButton)
        photoContainer.addForAutoLayout(removePhotoButton)
        photoPreview.pinEdges(to: photoContainer)
        photoButton.pinEdges(to: photoContainer)
        NSLayoutConstraint.activate([
            photoPlaceholder.centerXAnchor.constraint(equalTo: photoContainer.centerXAnchor),
            photoPlaceholder.centerYAnchor.constraint(equalTo: photoContainer.centerYAnchor),
            photoPlaceholder.leadingAnchor.constraint(greaterThanOrEqualTo: photoContainer.leadingAnchor, constant: 24),
            photoPlaceholder.trailingAnchor.constraint(lessThanOrEqualTo: photoContainer.trailingAnchor, constant: -24),
            removePhotoButton.topAnchor.constraint(equalTo: photoContainer.topAnchor, constant: 10),
            removePhotoButton.trailingAnchor.constraint(equalTo: photoContainer.trailingAnchor, constant: -10),
            removePhotoButton.widthAnchor.constraint(equalToConstant: WellnarioLayout.minimumTouchTarget),
            removePhotoButton.heightAnchor.constraint(equalTo: removePhotoButton.widthAnchor)
        ])
    }

    private func buildForm() {
        contentStack.addArrangedSubview(stepLabel(number: 1))

        addSection(
            title: L10n.text("supplements.wizard.step1.title"),
            views: [brandField, nameField, priceField]
        )
        addSection(
            title: L10n.text("supplements.wizard.photo_optional"),
            views: [photoContainer]
        )
        addSaveButton()
    }

    @objc private func choosePhoto() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func removePhoto() {
        state.photo = nil
        photoPreview.image = nil
        photoPlaceholder.isHidden = false
        removePhotoButton.isHidden = true
    }

    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        Task { @MainActor in picker.dismiss(animated: true) }
        guard let provider = results.first?.itemProvider,
              provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor [weak self] in
                guard let self, let image = UIImage(data: data) else { return }
                self.state.photo = image
                self.photoPreview.image = image
                self.photoPlaceholder.isHidden = true
                self.removePhotoButton.isHidden = false
            }
        }
    }

    private func rebuildCurrencyMenu() {
        let preferredCodes = [
            state.currencyCode, "EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD", "CNY"
        ].reduce(into: [String]()) { result, code in
            if !result.contains(code) { result.append(code) }
        }
        let allCodes = Locale.Currency.isoCurrencies
            .map(\.identifier)
            .sorted { currencyName($0).localizedCaseInsensitiveCompare(currencyName($1)) == .orderedAscending }

        let action: (String) -> UIAction = { [weak self] code in
            UIAction(
                title: self?.currencyMenuTitle(code) ?? code,
                state: code == self?.state.currencyCode ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                self.state.currencyCode = code
                self.priceField.unitTitle = code
                self.rebuildCurrencyMenu()
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        let allCurrencies = UIMenu(
            title: L10n.text("supplements.wizard.currency.all"),
            image: UIImage(systemName: "globe"),
            children: allCodes.map(action)
        )
        priceField.unitButton.menu = UIMenu(children: preferredCodes.map(action) + [allCurrencies])
        priceField.unitButton.accessibilityValue = state.currencyCode
    }

    private func currencyMenuTitle(_ code: String) -> String {
        "\(currencyName(code)) (\(code))"
    }

    private func currencyName(_ code: String) -> String {
        Locale.autoupdatingCurrent.localizedString(forCurrencyCode: code) ?? code
    }

    private func normalized(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

@MainActor
private final class ProductPackageAmountStepViewController: EditorViewController {
    private let state: ProductPackageWizardState
    private let styleControl = UISegmentedControl(items: [
        L10n.text("supplements.wizard.dose.discrete"),
        L10n.text("supplements.wizard.dose.continuous")
    ])
    private let totalField = FormFieldView()
    private let helperLabel = UILabel()
    private var presentations: [PresentationType] = []
    private var selectedUnit: DoseUnit

    private let discreteUnits: [DoseUnit] = [.capsule, .tablet, .sachet, .drop, .gummy, .scoop]
    private let continuousUnits: [DoseUnit] = [.microgram, .milligram, .gram, .milliliter, .liter]

    init(repository: WellnarioRepositoryProtocol, state: ProductPackageWizardState) {
        self.state = state
        self.selectedUnit = state.totalUnit
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("supplements.wizard.title")
        view.accessibilityIdentifier = "supplement.package.wizard.step2"
        configureBackButton()
        saveButton.setTitle(L10n.Common.next, for: .normal)
        saveButton.accessibilityIdentifier = "supplement.package.wizard.next"
        loadPresentations()
        configureFields()
        buildForm()
    }

    override func performSave() {
        totalField.setError(nil)
        guard let total = FeatureFormatting.parseDecimal(totalField.textField.text), total > 0 else {
            totalField.setError(L10n.Error.positiveAmount)
            saveButton.isLoading = false
            return
        }
        guard let presentation = presentation(for: selectedUnit) else {
            saveButton.isLoading = false
            showError(RepositoryError.validation(L10n.text("supplements.wizard.presentation_missing")))
            return
        }

        state.doseStyle = styleControl.selectedSegmentIndex == 0 ? .discrete : .continuous
        state.totalQuantity = total
        state.totalUnit = selectedUnit
        state.hasConfiguredTotal = true
        state.presentationID = presentation.id
        if state.doseStyle == .discrete {
            state.basisQuantity = 1
            state.basisUnit = selectedUnit
        } else if state.basisUnit.family != selectedUnit.family {
            state.basisQuantity = 1
            state.basisUnit = selectedUnit
        }

        saveButton.isLoading = false
        navigationController?.pushViewController(
            ProductPackageCompositionStepViewController(repository: repository, state: state),
            animated: true
        )
    }

    private func loadPresentations() {
        do { presentations = try repository.fetchPresentationTypes() }
        catch { showError(error) }
    }

    private func configureFields() {
        styleControl.selectedSegmentIndex = state.doseStyle == .discrete ? 0 : 1
        styleControl.selectedSegmentTintColor = WellnarioPalette.fuchsia
        styleControl.backgroundColor = WellnarioPalette.surface
        styleControl.addTarget(self, action: #selector(styleChanged), for: .valueChanged)
        styleControl.accessibilityIdentifier = "supplement.package.dose_style"

        totalField.configure(
            title: L10n.text("supplements.wizard.total_amount"),
            placeholder: "60",
            text: state.hasConfiguredTotal ? FeatureFormatting.decimal(state.totalQuantity) : nil,
            keyboardType: .decimalPad
        )
        totalField.textField.accessibilityIdentifier = "supplement.package.total"
        totalField.unitButton.accessibilityIdentifier = "supplement.package.total_unit"
        totalField.unitButton.showsMenuAsPrimaryAction = true
        helperLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        helperLabel.numberOfLines = 0
        rebuildUnitMenu()
    }

    private func buildForm() {
        contentStack.addArrangedSubview(stepLabel(number: 2))
        addSection(
            title: L10n.text("supplements.wizard.step2.title"),
            views: [styleControl, helperLabel, totalField]
        )
        addSaveButton()
    }

    @objc private func styleChanged() {
        let discrete = styleControl.selectedSegmentIndex == 0
        selectedUnit = discrete ? .capsule : .gram
        rebuildUnitMenu()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func rebuildUnitMenu() {
        let units = styleControl.selectedSegmentIndex == 0 ? discreteUnits : continuousUnits
        if !units.contains(selectedUnit) { selectedUnit = units[0] }
        totalField.unitTitle = displayName(for: selectedUnit)
        totalField.unitButton.menu = UIMenu(children: units.map { unit in
            UIAction(
                title: displayName(for: unit),
                state: unit == selectedUnit ? .on : .off
            ) { [weak self] _ in
                self?.selectedUnit = unit
                self?.rebuildUnitMenu()
                UISelectionFeedbackGenerator().selectionChanged()
            }
        })
        helperLabel.text = styleControl.selectedSegmentIndex == 0
            ? L10n.text("supplements.wizard.discrete.help")
            : L10n.text("supplements.wizard.continuous.help")
    }

    private func presentation(for unit: DoseUnit) -> PresentationType? {
        presentations.first { $0.defaultUnit == unit }
            ?? presentations.first { $0.defaultUnit.family == unit.family }
    }

    private func displayName(for unit: DoseUnit) -> String {
        guard unit.family == .discrete else {
            return unit.symbol(languageCode: catalogLanguage.rawValue)
        }
        return presentations.first { $0.defaultUnit == unit }?
            .localizedName(language: catalogLanguage)
            ?? unit.symbol(languageCode: catalogLanguage.rawValue)
    }

    private func configureBackButton() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.Common.back,
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
    }

    @objc private func backTapped() { navigationController?.popViewController(animated: true) }
}

@MainActor
private final class ProductPackageCompositionStepViewController: EditorViewController {
    private let state: ProductPackageWizardState
    private let basisField = FormFieldView()
    private let componentsStack = UIStackView()
    private let addComponentButton = PrimaryButton(style: .secondary)
    private let favoriteActivesHint = UILabel()
    private weak var compositionSection: FormSectionView?
    private var presentations: [PresentationType] = []
    private var actives: [Active] = []
    private var componentRows: [ComponentEditorRow] = []
    private var selectedBasisUnit: DoseUnit

    init(repository: WellnarioRepositoryProtocol, state: ProductPackageWizardState) {
        self.state = state
        self.selectedBasisUnit = state.basisUnit
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("supplements.wizard.title")
        view.accessibilityIdentifier = "supplement.package.wizard.step3"
        configureBackButton()
        saveButton.setTitle(L10n.Common.next, for: .normal)
        saveButton.accessibilityIdentifier = "supplement.package.wizard.next"
        loadOptions()
        configureFields()
        buildForm()
        appendInitialComponent()
    }

    override func performSave() {
        componentRows.forEach { $0.amountField.setError(nil) }
        let basisQuantity: Decimal
        if state.doseStyle == .continuous {
            guard let parsed = FeatureFormatting.parseDecimal(basisField.textField.text), parsed > 0 else {
                basisField.setError(L10n.Error.positiveAmount)
                saveButton.isLoading = false
                return
            }
            basisQuantity = parsed
        } else {
            basisQuantity = 1
            selectedBasisUnit = state.totalUnit
        }

        var components: [SupplementComponentDraft] = []
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
            components.append(SupplementComponentDraft(activeID: activeID, amount: amount, unit: row.selectedUnit))
        }
        guard !components.isEmpty, let presentationID = state.presentationID else {
            saveButton.isLoading = false
            showError(RepositoryError.validation(L10n.text("error.component_required")))
            return
        }

        state.basisQuantity = basisQuantity
        state.basisUnit = selectedBasisUnit
        state.hasConfiguredBasis = true
        state.components = components
        state.presentationImageReference = presentations
            .first { $0.id == presentationID }?
            .illustrations.first?.assetKey

        saveButton.isLoading = false
        navigationController?.pushViewController(
            ProductPackageInventoryStepViewController(repository: repository, state: state),
            animated: true
        )
    }

    private func loadOptions() {
        do {
            presentations = try repository.fetchPresentationTypes()
            actives = try repository.fetchActives(includeArchived: false).filter(\.isFavorite)
        } catch { showError(error) }
    }

    private func configureFields() {
        basisField.configure(
            title: L10n.text("supplements.wizard.composition_basis"),
            placeholder: "100",
            text: state.hasConfiguredBasis ? FeatureFormatting.decimal(state.basisQuantity) : nil,
            keyboardType: .decimalPad
        )
        basisField.textField.accessibilityIdentifier = "supplement.package.basis"
        basisField.textField.addTarget(self, action: #selector(basisChanged), for: .editingChanged)
        basisField.unitButton.accessibilityIdentifier = "supplement.package.basis_unit"
        basisField.unitButton.showsMenuAsPrimaryAction = true
        rebuildBasisUnitMenu()

        componentsStack.axis = .vertical
        componentsStack.spacing = WellnarioSpacing.small
        addComponentButton.setTitle(L10n.text("supplements.wizard.component.add"), for: .normal)
        addComponentButton.setImage(nil, for: .normal)
        addComponentButton.tintColor = WellnarioPalette.fuchsia
        addComponentButton.accessibilityIdentifier = "supplement.package.component.add"
        addComponentButton.addTarget(self, action: #selector(addComponent), for: .touchUpInside)
        favoriteActivesHint.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        favoriteActivesHint.text = L10n.text("supplements.component.requires_favorite")
        favoriteActivesHint.numberOfLines = 0
        favoriteActivesHint.isHidden = !actives.isEmpty
        addComponentButton.isHidden = actives.isEmpty
    }

    private func buildForm() {
        contentStack.addArrangedSubview(stepLabel(number: 3))
        let views: [UIView] = state.doseStyle == .continuous
            ? [basisField, componentsStack, favoriteActivesHint, addComponentButton]
            : [componentsStack, favoriteActivesHint, addComponentButton]
        compositionSection = addSection(
            title: compositionTitle(),
            views: views
        )
        addSaveButton()
    }

    private func appendInitialComponent() {
        guard let first = actives.first else {
            addComponentButton.isEnabled = false
            return
        }
        appendComponent(activeID: first.id, unit: first.baseUnit)
    }

    @objc private func addComponent() {
        guard let active = actives.first(where: { candidate in
            !componentRows.contains { $0.selectedActiveID == candidate.id }
        }) ?? actives.first else { return }
        appendComponent(activeID: active.id, unit: active.baseUnit)
        updateRemoveButtons()
        if let row = componentRows.last {
            scrollView.scrollRectToVisible(
                row.convert(row.bounds, to: scrollView).insetBy(dx: 0, dy: -24),
                animated: true
            )
        }
    }

    private func appendComponent(activeID: UUID, unit: DoseUnit) {
        let row = ComponentEditorRow(actives: actives, language: catalogLanguage)
        row.configure(activeID: activeID, amount: nil, unit: unit)
        row.onRemove = { [weak self, weak row] in
            guard let self, let row else { return }
            self.componentRows.removeAll { $0 === row }
            self.componentsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
            self.updateRemoveButtons()
        }
        componentRows.append(row)
        componentsStack.addArrangedSubview(row)
        updateRemoveButtons()
    }

    private func updateRemoveButtons() {
        componentRows.forEach { $0.removeButton.isHidden = componentRows.count <= 1 }
    }

    @objc private func basisChanged() { updateCompositionTitle() }

    private func rebuildBasisUnitMenu() {
        let units = DoseUnit.allCases.filter { $0.family == state.totalUnit.family }
        if !units.contains(selectedBasisUnit) { selectedBasisUnit = state.totalUnit }
        basisField.unitTitle = selectedBasisUnit.symbol(languageCode: catalogLanguage.rawValue)
        basisField.unitButton.menu = UIMenu(children: units.map { unit in
            UIAction(
                title: unit.symbol(languageCode: catalogLanguage.rawValue),
                state: unit == selectedBasisUnit ? .on : .off
            ) { [weak self] _ in
                self?.selectedBasisUnit = unit
                self?.rebuildBasisUnitMenu()
                self?.updateCompositionTitle()
                UISelectionFeedbackGenerator().selectionChanged()
            }
        })
    }

    private func updateCompositionTitle() {
        compositionSection?.titleLabel.text = compositionTitle()
    }

    private func compositionTitle() -> String {
        let type: String
        if state.doseStyle == .discrete {
            type = discreteUnitName(state.totalUnit)
        } else {
            let amount = basisField.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            type = amount.isEmpty
                ? L10n.text("supplements.wizard.composition.reference")
                : "\(amount) \(selectedBasisUnit.symbol(languageCode: catalogLanguage.rawValue))"
        }
        return L10n.text("supplements.wizard.composition.per", type)
    }

    private func discreteUnitName(_ unit: DoseUnit) -> String {
        switch unit {
        case .capsule: return L10n.text("supplements.wizard.unit.capsule")
        case .tablet: return L10n.text("supplements.wizard.unit.tablet")
        case .sachet: return L10n.text("supplements.wizard.unit.sachet")
        case .drop: return L10n.text("supplements.wizard.unit.drop")
        case .gummy: return L10n.text("supplements.wizard.unit.gummy")
        case .scoop: return L10n.text("supplements.wizard.unit.scoop")
        default: return unit.symbol(languageCode: catalogLanguage.rawValue)
        }
    }

    private func configureBackButton() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.Common.back,
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
    }

    @objc private func backTapped() { navigationController?.popViewController(animated: true) }
}

@MainActor
private final class ProductPackageInventoryStepViewController: EditorViewController {
    private struct InventoryInput {
        let labelField: FormFieldView?
        let expirySwitch: UISwitch
        let expiryPicker: UIDatePicker
        let container: UIView
    }

    private let state: ProductPackageWizardState
    private let countLabel = UILabel()
    private let helperLabel = UILabel()
    private let startedPackageAdviceLabel = UILabel()
    private let identificationAdviceLabel = UILabel()
    private let identificationStack = UIStackView()
    private let decrementButton = UIButton(type: .system)
    private let incrementButton = UIButton(type: .system)
    private var inventoryInputs: [InventoryInput] = []

    init(repository: WellnarioRepositoryProtocol, state: ProductPackageWizardState) {
        self.state = state
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("supplements.wizard.title")
        view.accessibilityIdentifier = "supplement.package.wizard.step4"
        configureBackButton()
        saveButton.setTitle(L10n.Common.next, for: .normal)
        saveButton.accessibilityIdentifier = "supplement.package.wizard.next"
        configureFields()
        buildForm()
    }

    override func performSave() {
        guard state.presentationID != nil, !state.components.isEmpty else {
            saveButton.isLoading = false
            showError(RepositoryError.validation(L10n.text("error.component_required")))
            return
        }
        persistInventoryInputs()

        saveButton.isLoading = false
        navigationController?.pushViewController(
            ProductPackageReminderStepViewController(repository: repository, state: state),
            animated: true
        )
    }

    private func configureFields() {
        countLabel.applyWellnarioStyle(.metric, color: WellnarioPalette.textPrimary)
        countLabel.textAlignment = .center
        countLabel.accessibilityIdentifier = "supplement.package.inventory.count"
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true

        configureAdjustmentButton(
            decrementButton,
            symbol: "minus",
            accessibilityIdentifier: "supplement.package.inventory.decrement",
            accessibilityLabel: L10n.text("supplements.wizard.inventory.decrement")
        )
        decrementButton.addTarget(self, action: #selector(decrementCount), for: .touchUpInside)
        configureAdjustmentButton(
            incrementButton,
            symbol: "plus",
            accessibilityIdentifier: "supplement.package.inventory.increment",
            accessibilityLabel: L10n.text("supplements.wizard.inventory.increment")
        )
        incrementButton.addTarget(self, action: #selector(incrementCount), for: .touchUpInside)

        helperLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        helperLabel.text = L10n.text("supplements.wizard.inventory.help")
        helperLabel.textAlignment = .center
        helperLabel.numberOfLines = 0

        startedPackageAdviceLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        startedPackageAdviceLabel.text = L10n.text("supplements.wizard.inventory.started.advice")
        startedPackageAdviceLabel.numberOfLines = 0
        startedPackageAdviceLabel.accessibilityIdentifier = "supplement.package.inventory.started.advice"

        identificationAdviceLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        identificationAdviceLabel.text = L10n.text("supplements.wizard.inventory.labels.advice")
        identificationAdviceLabel.numberOfLines = 0
        identificationAdviceLabel.accessibilityIdentifier = "supplement.package.inventory.labels.advice"

        identificationStack.axis = .vertical
        identificationStack.spacing = WellnarioSpacing.small
        identificationStack.accessibilityIdentifier = "supplement.package.inventory.details"
        identificationStack.addArrangedSubview(identificationAdviceLabel)
        identificationStack.setCustomSpacing(WellnarioSpacing.medium, after: identificationAdviceLabel)
        identificationStack.isHidden = true

        updateCount(animated: false)
    }

    private func buildForm() {
        contentStack.addArrangedSubview(stepLabel(number: 4))
        let counter = UIStackView(
            arrangedSubviews: [decrementButton, countLabel, incrementButton],
            axis: .horizontal,
            spacing: WellnarioSpacing.medium,
            alignment: .center
        )
        counter.distribution = .equalCentering
        addSection(
            title: L10n.text("supplements.wizard.step4.title"),
            views: [counter, helperLabel, startedPackageAdviceLabel, identificationStack]
        )
        addSaveButton()
    }

    private func configureAdjustmentButton(
        _ button: UIButton,
        symbol: String,
        accessibilityIdentifier: String,
        accessibilityLabel: String
    ) {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: symbol)
        configuration.baseForegroundColor = WellnarioPalette.onAccent
        configuration.baseBackgroundColor = WellnarioPalette.fuchsia
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        button.accessibilityIdentifier = accessibilityIdentifier
        button.accessibilityLabel = accessibilityLabel
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 52),
            button.heightAnchor.constraint(equalTo: button.widthAnchor)
        ])
    }

    @objc private func decrementCount() {
        guard state.initialInventoryCount > 0 else { return }
        persistInventoryInputs()
        state.initialInventoryCount -= 1
        updateCount()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @objc private func incrementCount() {
        guard state.initialInventoryCount < Int.max else { return }
        persistInventoryInputs()
        state.initialInventoryCount += 1
        updateCount()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func updateCount(animated: Bool = true) {
        countLabel.text = "\(state.initialInventoryCount)"
        countLabel.accessibilityValue = "\(state.initialInventoryCount)"
        decrementButton.isEnabled = state.initialInventoryCount > 0
        rebuildInventoryInputs()

        let updates = {
            self.identificationStack.isHidden = self.state.initialInventoryCount == 0
            self.view.layoutIfNeeded()
        }
        if animated {
            WellnarioMotion.animate(animations: updates)
        } else {
            updates()
        }
    }

    private func rebuildInventoryInputs() {
        inventoryInputs.forEach {
            identificationStack.removeArrangedSubview($0.container)
            $0.container.removeFromSuperview()
        }
        inventoryInputs.removeAll()

        guard state.initialInventoryCount > 0 else { return }
        if state.initialInventoryLabels.count < state.initialInventoryCount {
            state.initialInventoryLabels.append(
                contentsOf: repeatElement(
                    "",
                    count: state.initialInventoryCount - state.initialInventoryLabels.count
                )
            )
        }
        if state.initialInventoryExpirations.count < state.initialInventoryCount {
            state.initialInventoryExpirations.append(
                contentsOf: repeatElement(
                    nil,
                    count: state.initialInventoryCount - state.initialInventoryExpirations.count
                )
            )
        }
        identificationAdviceLabel.isHidden = state.initialInventoryCount <= 1

        for index in 0..<state.initialInventoryCount {
            let labelField: FormFieldView?
            if state.initialInventoryCount > 1 {
                let field = FormFieldView()
                field.configure(
                    title: L10n.text("supplements.wizard.inventory.label", index + 1),
                    placeholder: L10n.text("supplements.wizard.inventory.label.placeholder"),
                    text: state.initialInventoryLabels[index]
                )
                field.textField.accessibilityIdentifier = "supplement.package.inventory.label.\(index + 1)"
                labelField = field
            } else {
                labelField = nil
            }

            let expirySwitch = UISwitch()
            expirySwitch.onTintColor = WellnarioPalette.fuchsia
            expirySwitch.isOn = state.initialInventoryExpirations[index] != nil
            expirySwitch.accessibilityIdentifier = "supplement.package.inventory.expiry.toggle.\(index + 1)"

            let expiryPicker = UIDatePicker()
            expiryPicker.datePickerMode = .date
            expiryPicker.preferredDatePickerStyle = .compact
            expiryPicker.minimumDate = Calendar.current.date(byAdding: .year, value: -10, to: Date())
            expiryPicker.maximumDate = Calendar.current.date(byAdding: .year, value: 20, to: Date())
            expiryPicker.tintColor = WellnarioPalette.fuchsia
            expiryPicker.isHidden = !expirySwitch.isOn
            expiryPicker.accessibilityIdentifier = "supplement.package.inventory.expiry.date.\(index + 1)"
            if let day = state.initialInventoryExpirations[index],
               let date = try? day.startDate(in: .current) {
                expiryPicker.date = date
            }

            let expiryLabel = UILabel()
            expiryLabel.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
            expiryLabel.text = L10n.text("supplements.wizard.expiry_optional")
            let expiryRow = UIStackView(
                arrangedSubviews: [expiryLabel, UIView(), expirySwitch],
                axis: .horizontal,
                spacing: 8,
                alignment: .center
            )

            let itemViews = [labelField, expiryRow, expiryPicker].compactMap { $0 }
            let itemStack = UIStackView(
                arrangedSubviews: itemViews,
                axis: .vertical,
                spacing: WellnarioSpacing.small
            )
            if index > 0 {
                let separator = UIView()
                separator.backgroundColor = WellnarioPalette.hairline
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                itemStack.insertArrangedSubview(separator, at: 0)
                itemStack.setCustomSpacing(WellnarioSpacing.medium, after: separator)
            }
            expirySwitch.addAction(UIAction { [weak self, weak expirySwitch, weak expiryPicker] _ in
                guard let self, let expirySwitch, let expiryPicker else { return }
                WellnarioMotion.animate {
                    expiryPicker.isHidden = !expirySwitch.isOn
                    self.view.layoutIfNeeded()
                }
            }, for: .valueChanged)

            let input = InventoryInput(
                labelField: labelField,
                expirySwitch: expirySwitch,
                expiryPicker: expiryPicker,
                container: itemStack
            )
            inventoryInputs.append(input)
            identificationStack.addArrangedSubview(itemStack)
        }
    }

    private func persistInventoryInputs() {
        for (index, input) in inventoryInputs.enumerated() {
            if state.initialInventoryLabels.indices.contains(index), let labelField = input.labelField {
                state.initialInventoryLabels[index] = labelField.textField.text ?? ""
            }
            if state.initialInventoryExpirations.indices.contains(index) {
                state.initialInventoryExpirations[index] = input.expirySwitch.isOn
                    ? LocalDay(containing: input.expiryPicker.date, in: .current)
                    : nil
            }
        }
    }

    private func instanceLabel(at index: Int) -> String? {
        guard state.initialInventoryLabels.indices.contains(index) else { return nil }
        let label = state.initialInventoryLabels[index]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    private func instanceExpiration(at index: Int) -> LocalDay? {
        guard state.initialInventoryExpirations.indices.contains(index) else { return nil }
        return state.initialInventoryExpirations[index]
    }

    private func configureBackButton() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.Common.back,
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
    }

    @objc private func backTapped() {
        persistInventoryInputs()
        navigationController?.popViewController(animated: true)
    }
}

@MainActor
private final class ProductPackageReminderStepViewController: EditorViewController {
    private let state: ProductPackageWizardState
    private let summaryLabel = UILabel()
    private let configureButton = PrimaryButton(style: .secondary)
    private let reminderStore = SupplementProductReminderStore()

    init(repository: WellnarioRepositoryProtocol, state: ProductPackageWizardState) {
        self.state = state
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("supplements.reminders.title")
        view.accessibilityIdentifier = "supplement.package.wizard.step5"
        configureBackButton()
        saveButton.setTitle(L10n.text("supplements.wizard.create"), for: .normal)
        saveButton.accessibilityIdentifier = "supplement.package.wizard.create"
        configureFields()
        buildForm()
        updateSummary()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateSummary()
    }

    override func performSave() {
        guard let presentationID = state.presentationID, !state.components.isEmpty else {
            saveButton.isLoading = false
            showError(RepositoryError.validation(L10n.text("error.component_required")))
            return
        }

        var storedPhotoReference: String?
        var createdSupplement: Supplement?
        do {
            if let photo = state.photo {
                storedPhotoReference = try SupplementPhotoStore.save(photo, databaseURL: repository.databaseURL)
            }
            let supplement = try repository.createSupplement(SupplementDraft(
                name: state.name,
                brand: state.brand,
                price: state.price,
                currencyCode: state.price == nil ? nil : state.currencyCode,
                imageReference: storedPhotoReference ?? state.presentationImageReference,
                presentationTypeID: presentationID,
                basisQuantity: state.basisQuantity,
                basisUnit: state.basisUnit,
                components: state.components
            ))
            createdSupplement = supplement

            for index in 0..<state.initialInventoryCount {
                _ = try repository.createInstance(SupplementInstanceDraft(
                    supplementID: supplement.id,
                    label: instanceLabel(at: index),
                    expirationDay: instanceExpiration(at: index),
                    totalQuantity: state.totalQuantity,
                    totalUnit: state.totalUnit,
                    initialQuantity: state.totalQuantity,
                    initialUnit: state.totalUnit
                ))
            }

            let reminders = state.reminderDrafts.map {
                SupplementProductReminder(
                    id: $0.id,
                    supplementID: supplement.id,
                    timeMinutes: $0.timeMinutes,
                    recurrence: $0.recurrence,
                    weekdaysMask: $0.weekdaysMask,
                    intervalDays: $0.intervalDays,
                    anchorDay: $0.anchorDay
                )
            }
            reminderStore.set(reminders, for: supplement.id)
            SupplementReminderNotificationScheduler(repository: repository, store: reminderStore).reschedule()

            saveButton.isLoading = false
            UIImpactFeedbackGenerator.wellnarioSuccess()
            navigationController?.dismiss(animated: true)
        } catch {
            if let createdSupplement { _ = try? repository.deleteSupplement(id: createdSupplement.id) }
            SupplementPhotoStore.remove(reference: storedPhotoReference, databaseURL: repository.databaseURL)
            saveButton.isLoading = false
            showError(error)
        }
    }

    private func configureFields() {
        summaryLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        summaryLabel.numberOfLines = 0
        configureButton.tintColor = WellnarioPalette.fuchsia
        configureButton.addTarget(self, action: #selector(configureReminders), for: .touchUpInside)
        configureButton.accessibilityIdentifier = "supplement.package.reminders.configure"
    }

    private func buildForm() {
        contentStack.addArrangedSubview(stepLabel(number: 5))
        addSection(
            title: L10n.text("supplements.wizard.step5.title"),
            views: [summaryLabel, configureButton]
        )
        addSaveButton()
    }

    private func updateSummary() {
        if state.reminderDrafts.isEmpty {
            summaryLabel.text = L10n.text("supplements.wizard.reminders.empty")
            configureButton.setTitle(L10n.text("supplements.reminders.add"), for: .normal)
            return
        }
        let calendar = Calendar.autoupdatingCurrent
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.timeStyle = .short
        let times = state.reminderDrafts.map { reminder in
            formatter.string(from: calendar.date(
                bySettingHour: reminder.timeMinutes / 60,
                minute: reminder.timeMinutes % 60,
                second: 0,
                of: Date()
            ) ?? Date())
        }.joined(separator: " · ")
        summaryLabel.text = L10n.text("supplements.wizard.reminders.summary", times)
        configureButton.setTitle(L10n.Common.edit, for: .normal)
    }

    @objc private func configureReminders() {
        guard let preview = reminderPreviewSupplement() else { return }
        let editor = SupplementReminderEditorViewController(
            repository: repository,
            supplement: preview,
            onSaveDraft: { [weak self] reminders in
                self?.state.reminderDrafts = reminders
            }
        )
        navigationController?.pushViewController(editor, animated: true)
    }

    private func reminderPreviewSupplement() -> Supplement? {
        guard let presentationID = state.presentationID else { return nil }
        let now = Date()
        let id = state.reminderDraftProductID
        let components = state.components.enumerated().map { index, component in
            SupplementComponent(
                id: UUID(),
                supplementID: id,
                activeID: component.activeID,
                amount: component.amount,
                unit: component.unit,
                displayOrder: index
            )
        }
        return Supplement(
            id: id,
            name: state.name,
            brand: state.brand,
            details: nil,
            category: nil,
            price: state.price,
            currencyCode: state.price == nil ? nil : state.currencyCode,
            imageReference: state.presentationImageReference,
            presentationTypeID: presentationID,
            basisQuantity: state.basisQuantity,
            basisUnit: state.basisUnit,
            components: components,
            createdAt: now,
            updatedAt: now,
            archivedAt: nil
        )
    }

    private func instanceLabel(at index: Int) -> String? {
        guard state.initialInventoryLabels.indices.contains(index) else { return nil }
        let label = state.initialInventoryLabels[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    private func instanceExpiration(at index: Int) -> LocalDay? {
        guard state.initialInventoryExpirations.indices.contains(index) else { return nil }
        return state.initialInventoryExpirations[index]
    }

    private func configureBackButton() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.Common.back,
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
    }

    @objc private func backTapped() { navigationController?.popViewController(animated: true) }
}

@MainActor
private func stepLabel(number: Int) -> UILabel {
    let label = UILabel()
    label.applyWellnarioStyle(.caption, color: WellnarioPalette.fuchsia)
    label.text = L10n.text("supplements.wizard.step", number, 5)
    label.textAlignment = .center
    label.accessibilityIdentifier = "supplement.package.wizard.progress"
    return label
}
