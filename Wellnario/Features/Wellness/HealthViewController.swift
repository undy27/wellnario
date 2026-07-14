import UIKit
import UniformTypeIdentifiers

@MainActor
final class HealthViewController: WellnessScrollViewController, UIDocumentPickerDelegate {
    var onOpenSettings: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("health.title")
        view.accessibilityIdentifier = "health.root"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = L10n.Settings.title
        buildContent()
    }

    private func buildContent() {
        contentStack.addArrangedSubview(makeBiologicalAgeCard())
        contentStack.setCustomSpacing(WellnarioSpacing.large, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(makeSectionTitle(
            L10n.text("health.biomarkers.title"),
            detail: L10n.text("health.biomarkers.current")
        ))
        contentStack.addArrangedSubview(makeBiomarkersCard())

        let importButton = PrimaryButton(style: .secondary)
        importButton.configuration = actionConfiguration(
            title: L10n.text("quick.lab.title"),
            symbolName: "doc.badge.plus",
            color: WellnarioPalette.cyan
        )
        importButton.style = .secondary
        importButton.accessibilityIdentifier = "health.import_lab"
        importButton.addTarget(self, action: #selector(importLab), for: .touchUpInside)
        contentStack.addArrangedSubview(importButton)

        let sourceBanner = FeedbackBannerView()
        sourceBanner.configure(
            message: L10n.text("health.source.empty"),
            tone: .information,
            actionTitle: L10n.text("integrations.connect")
        )
        sourceBanner.onAction = { [weak self] in self?.onOpenSettings?() }
        contentStack.addArrangedSubview(sourceBanner)
    }

    private func makeBiologicalAgeCard() -> PremiumCardView {
        let eyebrow = UILabel()
        eyebrow.applyWellnarioStyle(.caption, color: WellnarioPalette.warning)
        eyebrow.text = L10n.text("health.biological_age.estimate")

        let ageLabel = UILabel()
        ageLabel.applyWellnarioStyle(.metric, color: WellnarioPalette.textPrimary)
        ageLabel.text = "—"
        let unitLabel = UILabel()
        unitLabel.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textSecondary)
        unitLabel.text = L10n.text("health.biological_age.years")
        let ageRow = UIStackView(
            arrangedSubviews: [ageLabel, unitLabel, UIView()],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .lastBaseline
        )

        let detail = UILabel()
        detail.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        detail.text = L10n.text("health.biological_age.empty")
        detail.numberOfLines = 0

        let rings = BiologicalAgeRingsView()
        rings.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rings.widthAnchor.constraint(equalToConstant: 92),
            rings.heightAnchor.constraint(equalTo: rings.widthAnchor)
        ])

        let labels = UIStackView(arrangedSubviews: [eyebrow, ageRow, detail], axis: .vertical, spacing: 8)
        let content = UIStackView(
            arrangedSubviews: [labels, rings],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        let card = makeCard(containing: content, identifier: "health.biological_age")
        card.showsAccent = true
        card.isAccessibilityElement = true
        card.accessibilityLabel = L10n.text("health.biological_age.title")
        card.accessibilityValue = L10n.text("sleep.no_data")
        return card
    }

    private func makeBiomarkersCard() -> PremiumCardView {
        let rows = [
            BiomarkerRowView(
                title: L10n.text("health.biomarker.hrv"),
                detail: L10n.text("health.biomarker.hrv.unit"),
                value: "—",
                symbolName: "waveform.path.ecg",
                tone: WellnarioPalette.cyan
            ),
            BiomarkerRowView(
                title: L10n.text("health.biomarker.resting_hr"),
                detail: L10n.text("health.biomarker.resting_hr.unit"),
                value: "—",
                symbolName: "heart.fill",
                tone: WellnarioPalette.pink
            ),
            BiomarkerRowView(
                title: L10n.text("health.biomarker.vo2"),
                detail: L10n.text("health.biomarker.vo2.unit"),
                value: "—",
                symbolName: "lungs.fill",
                tone: WellnarioPalette.violet
            ),
            BiomarkerRowView(
                title: L10n.text("health.biomarker.glucose"),
                detail: L10n.text("health.biomarker.glucose.unit"),
                value: "—",
                symbolName: "drop.fill",
                tone: WellnarioPalette.information
            )
        ]

        let stack = UIStackView(
            arrangedSubviews: [],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = UIView()
                separator.backgroundColor = WellnarioPalette.hairline
                separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
                stack.addArrangedSubview(separator)
            }
            stack.addArrangedSubview(row)
        }
        return makeCard(containing: stack, identifier: "health.biomarkers.card")
    }

    private func actionConfiguration(title: String, symbolName: String, color: UIColor) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: symbolName)
        configuration.imagePadding = 8
        configuration.baseForegroundColor = color
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = WellnarioTypography.font(for: .button)
            outgoing.foregroundColor = WellnarioPalette.textPrimary
            return outgoing
        }
        return configuration
    }

    @objc private func importLab() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let alert = UIAlertController(
            title: L10n.text("lab.imported.title"),
            message: L10n.text("lab.imported.message", url.lastPathComponent),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
        present(alert, animated: true)
    }

    @objc private func openSettings() { onOpenSettings?() }
}

@MainActor
private final class BiologicalAgeRingsView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let colors = [WellnarioPalette.warning, WellnarioPalette.magenta, WellnarioPalette.violet]
        for (index, color) in colors.enumerated() {
            let radius = CGFloat(36 - index * 9)
            let path = UIBezierPath(
                arcCenter: center,
                radius: radius,
                startAngle: -.pi / 2,
                endAngle: .pi * 1.35,
                clockwise: true
            )
            color.withAlphaComponent(CGFloat(0.85 - Double(index) * 0.18)).setStroke()
            path.lineWidth = 6
            path.lineCapStyle = .round
            path.stroke()
        }
    }
}
