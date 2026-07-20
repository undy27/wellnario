import UIKit

@MainActor
final class LabImportReviewViewController: UIViewController {
    var onConfirm: ((LabImportDraft) -> Void)?

    private var draft: LabImportDraft
    private let biomarkersByID: [UUID: HealthBiomarker]
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let datePicker = UIDatePicker()
    private let laboratoryField = FormFieldView()
    private let resultsStack = UIStackView()
    private var resultViews: [LabResultInputView] = []

    init(draft: LabImportDraft, favoriteBiomarkers: [HealthBiomarker]) {
        self.draft = draft
        biomarkersByID = Dictionary(uniqueKeysWithValues: favoriteBiomarkers.map { ($0.id, $0) })
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("health.analytics.import.review.title")
        view.backgroundColor = WellnarioPalette.background
        navigationItem.largeTitleDisplayMode = .never
        let confirm = UIBarButtonItem(
            title: L10n.text("health.analytics.import.review.confirm"),
            style: .done,
            target: self,
            action: #selector(confirmImport)
        )
        confirm.tintColor = WellnarioPalette.fuchsia
        confirm.accessibilityIdentifier = "health.analytics.import.confirm"
        navigationItem.rightBarButtonItem = confirm
        configureContent()
    }

    private func configureContent() {
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

        let summaryCard = PremiumCardView()
        let summaryTitle = UILabel()
        summaryTitle.applyWellnarioStyle(.bodyBold, color: WellnarioPalette.textPrimary)
        summaryTitle.text = draft.fileName
        summaryTitle.numberOfLines = 2

        let summary = UILabel()
        summary.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        summary.text = recognitionSummary()
        summary.numberOfLines = 0

        let caution = UILabel()
        caution.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        caution.text = L10n.text("health.analytics.import.review.body")
        caution.numberOfLines = 0

        let summaryStack = UIStackView(
            arrangedSubviews: [summaryTitle, summary, caution],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )
        summaryCard.contentView.addForAutoLayout(summaryStack)
        summaryStack.pinEdges(
            to: summaryCard.contentView,
            insets: .all(WellnarioSpacing.small)
        )

        let dateTitle = formTitle(L10n.text("health.analytics.editor.date"))
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.maximumDate = Date()
        datePicker.date = draft.collectedAt
        datePicker.tintColor = WellnarioPalette.fuchsia

        laboratoryField.configure(
            title: L10n.text("health.analytics.editor.laboratory"),
            placeholder: L10n.text("health.analytics.editor.optional"),
            text: draft.laboratory
        )

        let resultsTitle = formTitle(L10n.text("health.analytics.editor.results"))
        resultsStack.axis = .vertical
        resultsStack.spacing = WellnarioSpacing.xSmall

        [
            summaryCard,
            dateTitle,
            datePicker,
            laboratoryField,
            resultsTitle,
            resultsStack
        ].forEach(contentStack.addArrangedSubview)

        for importedResult in draft.results {
            guard let biomarker = biomarkersByID[importedResult.biomarkerID] else { continue }
            appendResult(
                biomarker: biomarker,
                result: importedResult.labResult()
            )
        }
    }

    private func appendResult(biomarker: HealthBiomarker, result: LabResult) {
        let resultView = LabResultInputView(biomarker: biomarker, result: result)
        resultView.onDelete = { [weak self, weak resultView] in
            guard let self, let resultView else { return }
            resultViews.removeAll { $0 === resultView }
            resultsStack.removeArrangedSubview(resultView)
            resultView.removeFromSuperview()
            navigationItem.rightBarButtonItem?.isEnabled = !resultViews.isEmpty
        }
        resultViews.append(resultView)
        resultsStack.addArrangedSubview(resultView)
    }

    private func formTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    private func recognitionSummary() -> String {
        var methods: [String] = []
        if draft.usedEmbeddedText {
            methods.append(L10n.text("health.analytics.import.method.embedded"))
        }
        if draft.usedOCR {
            methods.append(L10n.text("health.analytics.import.method.ocr"))
        }
        if draft.usedStructuredRecognition {
            methods.append(L10n.text("health.analytics.import.method.structured"))
        }
        if draft.usedFoundationModels {
            methods.append(L10n.text("health.analytics.import.method.foundation_models"))
        }
        return L10n.text(
            "health.analytics.import.review.summary",
            draft.results.count,
            methods.joined(separator: " · ")
        )
    }

    @objc private func confirmImport() {
        do {
            let results = try resultViews.map { try $0.makeResult() }
            guard !results.isEmpty else {
                throw RepositoryError.validation(
                    L10n.text("health.analytics.editor.results.required")
                )
            }
            draft.collectedAt = datePicker.date
            draft.laboratory = laboratoryField.textField.text
            draft.results = results.map {
                ImportedLabResult(
                    biomarkerID: $0.biomarkerID,
                    value: $0.value,
                    unit: $0.unit,
                    referenceLower: $0.referenceLower,
                    referenceUpper: $0.referenceUpper,
                    notes: $0.notes
                )
            }
            onConfirm?(draft)
            navigationController?.popViewController(animated: true)
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: L10n.Common.error,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
        present(alert, animated: true)
    }
}
