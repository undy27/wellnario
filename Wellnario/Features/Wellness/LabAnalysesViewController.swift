import UIKit
import UniformTypeIdentifiers

@MainActor
final class LabAnalysesViewController: UITableViewController, UIDocumentInteractionControllerDelegate {
    private let store: HealthDataStore
    private let emptyState = EmptyStateView()
    private var analyses: [LabAnalysis] = []
    private var documentInteractionController: UIDocumentInteractionController?

    init(store: HealthDataStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "health.analytics.root"
        tableView.backgroundColor = .clear
        tableView.separatorColor = WellnarioPalette.hairline
        tableView.contentInset.bottom = WellnarioSpacing.bottomNavigationInset
        tableView.verticalScrollIndicatorInsets.bottom = WellnarioSpacing.bottomNavigationInset
        emptyState.contentVerticalOffset = -96
        emptyState.onAction = { [weak self] in self?.addAnalysis() }
        reloadContent()
    }

    func reloadContent() {
        analyses = store.analyses()
        tableView.reloadData()
        if analyses.isEmpty {
            emptyState.configure(
                kind: .laboratory,
                title: L10n.text("health.analytics.empty.title"),
                message: L10n.text("health.analytics.empty.body"),
                actionTitle: L10n.text("health.analytics.add")
            )
            tableView.backgroundView = emptyState
        } else {
            tableView.backgroundView = nil
        }
    }

    func addAnalysis() {
        guard store.biomarkers().contains(where: \.isFavorite) else {
            let alert = UIAlertController(
                title: L10n.text("health.biomarkers.empty.title"),
                message: L10n.text("health.analytics.editor.requires_favorite"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
            present(alert, animated: true)
            return
        }
        presentEditor(analysis: nil)
    }

    private func presentEditor(analysis: LabAnalysis?) {
        let editor = LabAnalysisEditorViewController(
            store: store,
            analysis: analysis
        )
        editor.onSave = { [weak self] analysis in
            guard let self else { return }
            do {
                try store.saveAnalysis(analysis)
                reloadContent()
                dismiss(animated: true)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                editor.showError(error)
            }
        }
        let navigation = WellnarioNavigationController(rootViewController: editor)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = WellnarioRadius.card
        }
        present(navigation, animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        analyses.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let analysis = analyses[indexPath.row]
        var configuration = cell.defaultContentConfiguration()
        // Keep the text column aligned across rows, while leaving non-PDF rows
        // visually free of an icon.
        configuration.image = UIImage(systemName: "doc.text.fill")
        configuration.imageProperties.tintColor = analysis.importedPDFPath == nil
            ? .clear
            : WellnarioPalette.fuchsia
        configuration.imageProperties.maximumSize = CGSize(width: 28, height: 28)
        configuration.text = WellnarioFormatters.shortDate(analysis.collectedAt)
        let resultCount = analysis.results.count == 1
            ? L10n.text("health.analytics.result_count.one")
            : L10n.text("health.analytics.result_count.many", analysis.results.count)
        let outOfRangeCount = L10n.text(
            "health.analytics.out_of_range_count",
            analysis.outOfRangeResultCount
        )
        configuration.secondaryText = [analysis.laboratory, resultCount, outOfRangeCount]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        configuration.textProperties.color = WellnarioPalette.textPrimary
        configuration.secondaryTextProperties.color = WellnarioPalette.textSecondary
        configuration.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = configuration
        cell.backgroundColor = WellnarioPalette.surface
        if analysis.importedPDFPath != nil {
            cell.accessoryType = .disclosureIndicator
            addPDFButton(for: analysis, to: cell)
        } else {
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    private func addPDFButton(for analysis: LabAnalysis, to cell: UITableViewCell) {
        let pdfButton = UIButton(type: .system)
        pdfButton.accessibilityLabel = L10n.text("health.analytics.pdf.open")
        pdfButton.accessibilityIdentifier = "health.analytics.pdf.\(analysis.id.uuidString)"
        pdfButton.addAction(UIAction { [weak self, weak pdfButton] _ in
            guard let pdfButton else { return }
            self?.openImportedPDF(for: analysis, from: pdfButton)
        }, for: .touchUpInside)
        pdfButton.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(pdfButton)
        NSLayoutConstraint.activate([
            pdfButton.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 4),
            pdfButton.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            pdfButton.widthAnchor.constraint(equalToConstant: 44),
            pdfButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func openImportedPDF(for analysis: LabAnalysis, from sourceView: UIView) {
        guard let url = LabPDFDocumentStore.url(for: analysis.importedPDFPath) else {
            let alert = UIAlertController(
                title: L10n.Common.error,
                message: L10n.text("health.analytics.pdf.unavailable"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
            present(alert, animated: true)
            return
        }

        let interaction = UIDocumentInteractionController(url: url)
        interaction.delegate = self
        documentInteractionController = interaction
        if !interaction.presentPreview(animated: true) {
            interaction.presentOptionsMenu(from: sourceView.bounds, in: sourceView, animated: true)
        }
    }

    func documentInteractionControllerViewControllerForPreview(
        _ controller: UIDocumentInteractionController
    ) -> UIViewController {
        self
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        presentEditor(analysis: analyses[indexPath.row])
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let analysis = analyses[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: L10n.Common.delete) {
            [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            let alert = UIAlertController(
                title: L10n.text("health.analytics.delete.title"),
                message: L10n.text("health.analytics.delete.body"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel) { _ in
                completion(false)
            })
            alert.addAction(UIAlertAction(title: L10n.Common.delete, style: .destructive) { _ in
                do {
                    try self.store.deleteAnalysis(id: analysis.id)
                    self.reloadContent()
                    completion(true)
                } catch {
                    completion(false)
                }
            })
            self.present(alert, animated: true)
        }
        delete.image = UIImage(systemName: "trash")
        let configuration = UISwipeActionsConfiguration(actions: [delete])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}

@MainActor
private final class LabAnalysisEditorViewController: UIViewController, UIDocumentPickerDelegate {
    var onSave: ((LabAnalysis) -> Void)?

    private let store: HealthDataStore
    private let original: LabAnalysis?
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let datePicker = UIDatePicker()
    private let laboratoryField = FormFieldView()
    private let notesView = UITextView()
    private let resultsStack = UIStackView()
    private let favoriteBiomarkersHint = UILabel()
    private let importPDFButton = PrimaryButton(style: .secondary)
    private var resultViews: [LabResultInputView] = []
    private var importTask: Task<Void, Never>?
    private var importedPDFPath: String?
    private var importedPDFName: String?

    init(store: HealthDataStore, analysis: LabAnalysis?) {
        self.store = store
        original = analysis
        importedPDFPath = analysis?.importedPDFPath
        importedPDFName = analysis?.importedPDFName
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = original == nil
            ? L10n.text("health.analytics.editor.add.title")
            : L10n.text("health.analytics.editor.edit.title")
        view.backgroundColor = WellnarioPalette.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
        let save = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(save)
        )
        save.tintColor = WellnarioPalette.fuchsia
        navigationItem.rightBarButtonItem = save
        configureForm()
    }

    private func configureForm() {
        scrollView.keyboardDismissMode = .interactive
        view.addForAutoLayout(scrollView)
        contentStack.axis = .vertical
        contentStack.spacing = WellnarioSpacing.small
        scrollView.addForAutoLayout(contentStack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: WellnarioSpacing.small
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -WellnarioSpacing.bottomNavigationInset
            ),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -(WellnarioSpacing.screenHorizontal * 2)
            )
        ])

        let dateTitle = formTitle(L10n.text("health.analytics.editor.date"))
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.maximumDate = Date()
        datePicker.date = original?.collectedAt ?? Date()
        datePicker.tintColor = WellnarioPalette.fuchsia

        laboratoryField.configure(
            title: L10n.text("health.analytics.editor.laboratory"),
            placeholder: L10n.text("health.analytics.editor.optional"),
            text: original?.laboratory
        )

        let notesTitle = formTitle(L10n.text("health.analytics.editor.notes"))
        notesView.text = original?.notes
        notesView.font = WellnarioTypography.font(for: .body)
        notesView.textColor = WellnarioPalette.textPrimary
        notesView.backgroundColor = WellnarioPalette.fieldBackground
        notesView.tintColor = WellnarioPalette.fuchsia
        notesView.applyContinuousCorners(WellnarioRadius.control)
        notesView.layer.borderWidth = 1
        notesView.layer.borderColor = WellnarioPalette.hairline.cgColor
        notesView.heightAnchor.constraint(equalToConstant: 74).isActive = true
        notesView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        let resultsTitle = formTitle(L10n.text("health.analytics.editor.results"))
        resultsStack.axis = .vertical
        resultsStack.spacing = WellnarioSpacing.xSmall

        favoriteBiomarkersHint.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        favoriteBiomarkersHint.text = L10n.text("health.analytics.editor.requires_favorite")
        favoriteBiomarkersHint.numberOfLines = 0
        favoriteBiomarkersHint.isHidden = store.biomarkers().contains(where: \.isFavorite)

        let addResultButton = PrimaryButton(style: .secondary)
        addResultButton.setTitle(L10n.text("health.analytics.editor.add_result"), for: .normal)
        addResultButton.setImage(UIImage(systemName: "plus.circle"), for: .normal)
        addResultButton.tintColor = WellnarioPalette.fuchsia
        addResultButton.isHidden = !favoriteBiomarkersHint.isHidden
        addResultButton.addTarget(self, action: #selector(addResult), for: .touchUpInside)

        importPDFButton.setTitle(L10n.text("health.analytics.import.pdf"), for: .normal)
        importPDFButton.setImage(UIImage(systemName: "doc.text.viewfinder"), for: .normal)
        importPDFButton.tintColor = WellnarioPalette.fuchsia
        importPDFButton.accessibilityIdentifier = "health.analytics.import.pdf"
        importPDFButton.addTarget(self, action: #selector(selectPDF), for: .touchUpInside)

        [
            dateTitle,
            datePicker,
            laboratoryField,
            notesTitle,
            notesView,
            resultsTitle,
            resultsStack,
            favoriteBiomarkersHint,
            addResultButton,
            importPDFButton
        ].forEach(contentStack.addArrangedSubview)

        if let original {
            let biomarkers = Dictionary(uniqueKeysWithValues: store.biomarkers().map { ($0.id, $0) })
            for result in original.results {
                guard let biomarker = biomarkers[result.biomarkerID] else { continue }
                appendResult(biomarker: biomarker, result: result)
            }
        }
        updateResultsEmptyState()
    }

    private func formTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    private func appendResult(biomarker: HealthBiomarker, result: LabResult? = nil) {
        insertResult(biomarker: biomarker, result: result, at: resultViews.endIndex)
    }

    private func insertResult(
        biomarker: HealthBiomarker,
        result: LabResult?,
        at index: Int
    ) {
        let resultView = LabResultInputView(biomarker: biomarker, result: result)
        resultView.onDelete = { [weak self, weak resultView] in
            guard let self, let resultView else { return }
            resultViews.removeAll { $0 === resultView }
            resultsStack.removeArrangedSubview(resultView)
            resultView.removeFromSuperview()
            updateResultsEmptyState()
        }
        let safeIndex = min(max(0, index), resultViews.endIndex)
        resultViews.insert(resultView, at: safeIndex)
        resultsStack.insertArrangedSubview(resultView, at: safeIndex)
        updateResultsEmptyState()
    }

    private func updateResultsEmptyState() {
        resultsStack.isHidden = resultViews.isEmpty
    }

    func showError(_ error: Error) {
        let alert = UIAlertController(
            title: L10n.Common.error,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
        present(alert, animated: true)
    }

    @objc private func addResult() {
        let selected = Set(resultViews.map(\.biomarker.id))
        let favoriteBiomarkers = store.biomarkers().filter(\.isFavorite)
        guard !favoriteBiomarkers.isEmpty else {
            let alert = UIAlertController(
                title: L10n.text("health.biomarkers.empty.title"),
                message: L10n.text("health.analytics.editor.requires_favorite"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
            present(alert, animated: true)
            return
        }
        let available = favoriteBiomarkers.filter { !selected.contains($0.id) }
        guard !available.isEmpty else {
            let alert = UIAlertController(
                title: L10n.text("health.analytics.editor.select_biomarker"),
                message: L10n.text("health.analytics.editor.no_favorite_available"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
            present(alert, animated: true)
            return
        }
        let picker = BiomarkerPickerViewController(biomarkers: available)
        picker.onSelect = { [weak self] biomarker in
            self?.appendResult(biomarker: biomarker)
            self?.dismiss(animated: true)
        }
        let navigation = WellnarioNavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigation, animated: true)
    }

    @objc private func save() {
        do {
            let results = try resultViews.map { try $0.makeResult() }
            guard !results.isEmpty else {
                throw RepositoryError.validation(L10n.text("health.analytics.editor.results.required"))
            }
            onSave?(LabAnalysis(
                id: original?.id ?? UUID(),
                collectedAt: datePicker.date,
                laboratory: laboratoryField.textField.text,
                notes: notesView.text,
                results: results,
                importedPDFPath: importedPDFPath,
                importedPDFName: importedPDFName
            ))
        } catch {
            showError(error)
        }
    }

    @objc private func cancel() {
        importTask?.cancel()
        dismiss(animated: true)
    }

    @objc private func selectPDF() {
        view.endEditing(true)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let url = urls.first else { return }
        importTask?.cancel()
        importPDFButton.isLoading = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        let favoriteBiomarkers = store.biomarkers().filter(\.isFavorite)
        let descriptors = favoriteBiomarkers.map(LabImportBiomarkerDescriptor.init)

        importTask = Task { [weak self] in
            guard let self else { return }
            let hasSecurityAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            var copiedPDFURL: URL?
            do {
                let localPDFURL = try LabPDFDocumentStore.persistCopy(of: url)
                copiedPDFURL = localPDFURL
                var draft = try await LabPDFImportService().importPDF(
                    at: localPDFURL,
                    favoriteBiomarkers: descriptors
                )
                draft.fileName = url.lastPathComponent
                try Task.checkCancellation()
                importPDFButton.isLoading = false
                navigationItem.rightBarButtonItem?.isEnabled = true
                presentImportReview(draft, favoriteBiomarkers: favoriteBiomarkers)
            } catch is CancellationError {
                if let copiedPDFURL { try? FileManager.default.removeItem(at: copiedPDFURL) }
                importPDFButton.isLoading = false
                navigationItem.rightBarButtonItem?.isEnabled = true
            } catch {
                if let copiedPDFURL { try? FileManager.default.removeItem(at: copiedPDFURL) }
                importPDFButton.isLoading = false
                navigationItem.rightBarButtonItem?.isEnabled = true
                showError(error)
            }
        }
    }

    private func presentImportReview(
        _ draft: LabImportDraft,
        favoriteBiomarkers: [HealthBiomarker]
    ) {
        let review = LabImportReviewViewController(
            draft: draft,
            favoriteBiomarkers: favoriteBiomarkers
        )
        review.onConfirm = { [weak self] reviewedDraft in
            self?.applyImportedDraft(reviewedDraft)
        }
        navigationController?.pushViewController(review, animated: true)
    }

    private func applyImportedDraft(_ draft: LabImportDraft) {
        datePicker.date = draft.collectedAt
        if let laboratory = draft.laboratory, !laboratory.isEmpty {
            laboratoryField.textField.text = laboratory
        }
        importedPDFPath = draft.importedPDFURL.map(LabPDFDocumentStore.storageReference(for:))
        importedPDFName = draft.fileName

        let biomarkerByID = Dictionary(
            uniqueKeysWithValues: store.biomarkers().map { ($0.id, $0) }
        )
        for importedResult in draft.results {
            guard let biomarker = biomarkerByID[importedResult.biomarkerID] else { continue }
            let result = importedResult.labResult()
            if let existingIndex = resultViews.firstIndex(
                where: { $0.biomarker.id == importedResult.biomarkerID }
            ) {
                let existingView = resultViews.remove(at: existingIndex)
                resultsStack.removeArrangedSubview(existingView)
                existingView.removeFromSuperview()
                insertResult(biomarker: biomarker, result: result, at: existingIndex)
            } else {
                appendResult(biomarker: biomarker, result: result)
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

@MainActor
final class LabResultInputView: UIView {
    let biomarker: HealthBiomarker
    var onDelete: (() -> Void)?

    private let resultID: UUID
    private let valueField = FormFieldView()
    private let referenceLowerField = FormFieldView()
    private let referenceUpperField = FormFieldView()
    private let notesField = FormFieldView()
    private var selectedUnit: String
    private let availableUnits: [String]

    init(biomarker: HealthBiomarker, result: LabResult?) {
        self.biomarker = biomarker
        resultID = result?.id ?? UUID()
        let storedUnit = result?.unit ?? biomarker.defaultUnit
        selectedUnit = storedUnit
        availableUnits = ([storedUnit] + biomarker.typicalLabUnits).reduce(into: []) { units, unit in
            if !units.contains(unit) { units.append(unit) }
        }
        super.init(frame: .zero)
        backgroundColor = WellnarioPalette.surface
        applyContinuousCorners(WellnarioRadius.small)
        layer.borderWidth = 1
        layer.borderColor = WellnarioPalette.hairline.cgColor

        let imageView = UIImageView(
            image: biomarker.imageKey.flatMap(UIImage.init(named:))
                ?? UIImage(systemName: biomarker.sampleType.symbolName)
        )
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.applyContinuousCorners(10)

        let nameLabel = UILabel()
        nameLabel.applyWellnarioStyle(.analysisMarkerTitle, color: WellnarioPalette.textPrimary)
        nameLabel.text = biomarker.name
        nameLabel.numberOfLines = 2

        valueField.configure(
            title: L10n.text("health.analytics.editor.value"),
            placeholder: L10n.text("health.analytics.editor.value"),
            text: result.map { FeatureFormatting.decimal($0.value) },
            keyboardType: .decimalPad
        )
        valueField.unitButtonTrailingInset = 0
        valueField.unitButton.showsMenuAsPrimaryAction = true
        valueField.unitButton.accessibilityIdentifier = "health.analytics.result.unit"
        rebuildUnitMenu()

        referenceLowerField.configure(
            title: L10n.text("health.analytics.editor.reference.lower"),
            placeholder: L10n.text("health.analytics.editor.optional"),
            text: result?.referenceLower.map { FeatureFormatting.decimal($0) },
            keyboardType: .decimalPad
        )
        referenceUpperField.configure(
            title: L10n.text("health.analytics.editor.reference.upper"),
            placeholder: L10n.text("health.analytics.editor.optional"),
            text: result?.referenceUpper.map { FeatureFormatting.decimal($0) },
            keyboardType: .decimalPad
        )
        notesField.configure(
            title: L10n.text("health.analytics.editor.result.notes"),
            placeholder: L10n.text("health.analytics.editor.optional"),
            text: result?.notes
        )
        notesField.textField.accessibilityIdentifier = "health.analytics.result.notes"

        let delete = UIButton(type: .system)
        delete.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        delete.tintColor = WellnarioPalette.textTertiary
        delete.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        let header = UIStackView(
            arrangedSubviews: [imageView, nameLabel, UIView(), delete],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
        let referenceTitle = UILabel()
        referenceTitle.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        referenceTitle.text = L10n.text("health.analytics.editor.reference.title")
        referenceTitle.numberOfLines = 0

        let referenceFields = UIStackView(
            arrangedSubviews: [referenceLowerField, referenceUpperField],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            distribution: .fillEqually
        )
        let stack = UIStackView(
            arrangedSubviews: [header, valueField, referenceTitle, referenceFields, notesField],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        addForAutoLayout(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            imageView.widthAnchor.constraint(equalToConstant: 34),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            delete.widthAnchor.constraint(equalToConstant: 36),
            delete.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func makeResult() throws -> LabResult {
        valueField.setError(nil)
        referenceLowerField.setError(nil)
        referenceUpperField.setError(nil)
        guard let value = FeatureFormatting.parseDecimal(valueField.textField.text) else {
            throw RepositoryError.validation(
                L10n.text("health.analytics.editor.value.required", biomarker.name)
            )
        }
        let referenceLower = try referenceValue(
            from: referenceLowerField,
            validationKey: "health.analytics.editor.reference.lower.invalid"
        )
        let referenceUpper = try referenceValue(
            from: referenceUpperField,
            validationKey: "health.analytics.editor.reference.upper.invalid"
        )
        if let referenceLower, let referenceUpper, referenceLower > referenceUpper {
            let message = L10n.text("health.analytics.editor.reference.invalid_range")
            referenceUpperField.setError(message)
            throw RepositoryError.validation(message)
        }
        return LabResult(
            id: resultID,
            biomarkerID: biomarker.id,
            value: value,
            unit: selectedUnit,
            referenceLower: referenceLower,
            referenceUpper: referenceUpper,
            notes: notesField.textField.text
        )
    }

    @objc private func deleteTapped() {
        onDelete?()
    }

    private func rebuildUnitMenu() {
        valueField.unitTitle = displayUnit(selectedUnit)
        valueField.unitButton.menu = UIMenu(children: availableUnits.map { unit in
            UIAction(
                title: displayUnit(unit),
                state: unit == selectedUnit ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                selectedUnit = unit
                rebuildUnitMenu()
                UISelectionFeedbackGenerator().selectionChanged()
            }
        })
    }

    private func displayUnit(_ unit: String) -> String {
        unit.isEmpty ? L10n.text("health.analytics.editor.unit.none") : unit
    }

    private func referenceValue(
        from field: FormFieldView,
        validationKey: String
    ) throws -> Decimal? {
        let text = field.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return nil }
        guard let value = FeatureFormatting.parseDecimal(text) else {
            let message = L10n.text(validationKey)
            field.setError(message)
            throw RepositoryError.validation(message)
        }
        return value
    }
}

@MainActor
private final class BiomarkerPickerViewController: UITableViewController {
    var onSelect: ((HealthBiomarker) -> Void)?

    private let allBiomarkers: [HealthBiomarker]
    private var displayed: [HealthBiomarker]
    private let searchController = UISearchController(searchResultsController: nil)

    init(biomarkers: [HealthBiomarker]) {
        allBiomarkers = biomarkers
        displayed = biomarkers
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("health.analytics.editor.select_biomarker")
        view.backgroundColor = WellnarioPalette.background
        tableView.backgroundColor = .clear
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.Common.search
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancel)
        )
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displayed.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let biomarker = displayed[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var configuration = cell.defaultContentConfiguration()
        configuration.image = biomarker.imageKey.flatMap(UIImage.init(named:))
            ?? UIImage(systemName: biomarker.sampleType.symbolName)
        configuration.imageProperties.maximumSize = CGSize(width: 38, height: 38)
        configuration.imageProperties.cornerRadius = 9
        configuration.text = biomarker.name
        configuration.secondaryText = [biomarker.sampleType.title, biomarker.defaultUnit]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        configuration.textProperties.color = WellnarioPalette.textPrimary
        configuration.secondaryTextProperties.color = WellnarioPalette.textSecondary
        cell.contentConfiguration = configuration
        cell.backgroundColor = WellnarioPalette.surface
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect?(displayed[indexPath.row])
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }
}

extension BiomarkerPickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if query.isEmpty {
            displayed = allBiomarkers
        } else {
            displayed = allBiomarkers.filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
        }
        tableView.reloadData()
    }
}

private extension UITextField {
    func setLeftPadding(_ value: CGFloat) {
        let padding = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
        leftView = padding
        leftViewMode = .always
    }
}
