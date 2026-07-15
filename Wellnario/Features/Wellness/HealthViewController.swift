import UIKit
import UniformTypeIdentifiers

enum HealthCardKind: String, CaseIterable, WellnessCardKind, Sendable {
    case biologicalAge
    case biomarkers
    case medicalReviews

    static let storageNamespace = "health"

    @MainActor
    var title: String {
        switch self {
        case .biologicalAge: L10n.text("health.biological_age.title")
        case .biomarkers: L10n.text("health.biomarkers.title")
        case .medicalReviews: L10n.text("health.medical_reviews.title")
        }
    }

    var symbolName: String {
        switch self {
        case .biologicalAge: "figure.stand"
        case .biomarkers: "waveform.path.ecg"
        case .medicalReviews: "calendar.badge.clock"
        }
    }
}

typealias HealthCardLayoutPreferences = WellnessCardLayoutPreferences<HealthCardKind>

@MainActor
final class HealthViewController: WellnessScrollViewController, UIDocumentPickerDelegate {
    private static let sourceBannerHeight: CGFloat = 76

    var onOpenSettings: (() -> Void)?
    private let appleHealthService: AppleHealthSyncing
    private let medicalReviewStore: MedicalReviewStore
    private let cardLayoutPreferences: HealthCardLayoutPreferences
    private let sourceBanner = FeedbackBannerView()
    private var isSourceBannerVisible = false
    private var appliedSourceBannerInset: CGFloat = 0

    init(
        appleHealthService: AppleHealthSyncing,
        medicalReviewStore: MedicalReviewStore = MedicalReviewStore(),
        defaults: UserDefaults = .standard
    ) {
        self.appleHealthService = appleHealthService
        self.medicalReviewStore = medicalReviewStore
        cardLayoutPreferences = HealthCardLayoutPreferences(defaults: defaults)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("health.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "health.root"
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        settingsButton.accessibilityLabel = L10n.Settings.title
        settingsButton.accessibilityIdentifier = "health.settings"
        let editCardsButton = UIBarButtonItem(
            image: UIImage(systemName: "square.grid.2x2"),
            style: .plain,
            target: self,
            action: #selector(openCardEditor)
        )
        editCardsButton.tintColor = WellnarioPalette.fuchsia
        editCardsButton.accessibilityLabel = L10n.text("health.cards.edit")
        editCardsButton.accessibilityIdentifier = "health.cards.edit"
        navigationItem.rightBarButtonItems = [settingsButton, editCardsButton]
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appleHealthDidChange),
            name: .appleHealthSyncDidChange,
            object: appleHealthService
        )
        setUpSourceBanner()
        buildContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never
        buildContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateScrollInsetsForSourceBanner()
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        updateSourceBanner()
        let visibleCards = cardLayoutPreferences.orderedCards.filter(cardLayoutPreferences.isVisible)
        if visibleCards.isEmpty {
            contentStack.addArrangedSubview(makeNoVisibleCardsView())
        } else {
            for (index, card) in visibleCards.enumerated() {
                let section = makeCardSection(card)
                contentStack.addArrangedSubview(section)
                if index < visibleCards.count - 1 {
                    contentStack.setCustomSpacing(WellnarioSpacing.large, after: section)
                }
            }
        }

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
    }

    private func makeCardSection(_ card: HealthCardKind) -> UIView {
        let views: [UIView]
        switch card {
        case .biologicalAge:
            views = [
                makeSectionTitle(L10n.text("health.biological_age.estimate")),
                makeBiologicalAgeCard()
            ]
        case .biomarkers:
            views = [
                makeSectionTitle(
                    L10n.text("health.biomarkers.title"),
                    detail: L10n.text("health.biomarkers.current")
                ),
                makeBiomarkersCard()
            ]
        case .medicalReviews:
            views = [makeMedicalReviewsCard()]
        }
        let section = UIStackView(
            arrangedSubviews: views,
            axis: .vertical,
            spacing: WellnarioSpacing.cardGap
        )
        section.accessibilityIdentifier = "health.card.section.\(card.rawValue)"
        return section
    }

    private func makeNoVisibleCardsView() -> EmptyStateView {
        let emptyState = EmptyStateView()
        emptyState.accessibilityIdentifier = "health.cards.empty"
        emptyState.configure(
            kind: .other,
            title: L10n.text("health.cards.empty.title"),
            message: L10n.text("health.cards.empty.body"),
            actionTitle: L10n.text("health.cards.edit")
        )
        emptyState.onAction = { [weak self] in self?.openCardEditor() }
        emptyState.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        return emptyState
    }

    private func makeMedicalReviewsCard() -> PremiumCardView {
        let reviews = medicalReviewStore.reviews
        let icon = UIImageView(image: UIImage(systemName: "calendar.badge.clock"))
        icon.tintColor = WellnarioPalette.fuchsia
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 23, weight: .semibold)

        let iconContainer = UIView()
        iconContainer.backgroundColor = WellnarioPalette.fuchsia.withAlphaComponent(0.14)
        iconContainer.applyContinuousCorners(18)
        iconContainer.addForAutoLayout(icon)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 48),
            iconContainer.heightAnchor.constraint(equalTo: iconContainer.widthAnchor),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor)
        ])

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text("health.medical_reviews.title")
        titleLabel.numberOfLines = 0
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = WellnarioPalette.textTertiary
        let header = UIStackView(
            arrangedSubviews: [iconContainer, titleLabel, UIView(), chevron],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )

        let countLabel = UILabel()
        countLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        countLabel.text = reviews.count == 1
            ? L10n.text("health.medical_reviews.count.one")
            : L10n.text("health.medical_reviews.count.many", reviews.count)
        countLabel.numberOfLines = 0

        let detailLabel = UILabel()
        detailLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        if let nextReview = reviews.first {
            detailLabel.text = L10n.text(
                "health.medical_reviews.next_summary",
                nextReview.title,
                MedicalReviewFormatting.dueStatus(nextReview)
            )
        } else {
            detailLabel.text = L10n.text("health.medical_reviews.card.empty")
        }
        detailLabel.numberOfLines = 0

        let content = UIStackView(
            arrangedSubviews: [header, countLabel, detailLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        content.isUserInteractionEnabled = false
        let button = UIButton(type: .system)
        button.addForAutoLayout(content)
        content.pinEdges(to: button)
        button.accessibilityIdentifier = "health.medical_reviews.open"
        button.accessibilityLabel = L10n.text("health.medical_reviews.title")
        button.accessibilityValue = [countLabel.text, detailLabel.text].compactMap { $0 }.joined(separator: ". ")
        button.accessibilityHint = L10n.text("health.medical_reviews.open.hint")
        button.addTarget(self, action: #selector(openMedicalReviews), for: .touchUpInside)
        let card = makeCard(containing: button, identifier: "health.medical_reviews.card")
        return card
    }

    private func setUpSourceBanner() {
        sourceBanner.accessibilityIdentifier = "health.source.banner"
        sourceBanner.backgroundOpacityOverride = WellnarioPalette.synchronizationBannerOpacity
        sourceBanner.isHidden = true
        view.addForAutoLayout(sourceBanner)
        NSLayoutConstraint.activate([
            sourceBanner.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            sourceBanner.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            sourceBanner.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: WellnarioSpacing.xxxSmall
            ),
            sourceBanner.heightAnchor.constraint(equalToConstant: Self.sourceBannerHeight)
        ])
        view.bringSubviewToFront(sourceBanner)
    }

    private func updateSourceBanner() {
        guard appleHealthService.isConfigured else {
            isSourceBannerVisible = false
            sourceBanner.isHidden = true
            view.setNeedsLayout()
            return
        }

        isSourceBannerVisible = true
        sourceBanner.isHidden = false
        configureSourceBanner(sourceBanner)
        view.bringSubviewToFront(sourceBanner)
        view.setNeedsLayout()
    }

    private func updateScrollInsetsForSourceBanner() {
        let targetInset = isSourceBannerVisible
            ? sourceBanner.bounds.height + WellnarioSpacing.xxxSmall
            : 0
        guard abs(targetInset - appliedSourceBannerInset) > 0.5 else { return }

        let previousAdjustedTop = scrollView.adjustedContentInset.top
        let wasAtTop = scrollView.contentOffset.y <= -previousAdjustedTop + 1
        appliedSourceBannerInset = targetInset
        scrollView.contentInset.top = targetInset
        scrollView.verticalScrollIndicatorInsets.top = targetInset
        if wasAtTop {
            scrollView.contentOffset.y = -scrollView.adjustedContentInset.top
        }
    }

    private func makeBiologicalAgeCard() -> PremiumCardView {
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

        let labels = UIStackView(arrangedSubviews: [ageRow, detail], axis: .vertical, spacing: 8)
        let content = UIStackView(
            arrangedSubviews: [labels, rings],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        let card = makeCard(containing: content, identifier: "health.biological_age")
        card.isAccessibilityElement = true
        card.accessibilityLabel = L10n.text("health.biological_age.title")
        card.accessibilityValue = L10n.text("sleep.no_data")
        return card
    }

    private func makeBiomarkersCard() -> PremiumCardView {
        let snapshot = appleHealthService.snapshot
        let rows = [
            BiomarkerRowView(
                title: L10n.text("health.biomarker.hrv"),
                detail: measurementDetail(
                    unitKey: "health.biomarker.hrv.unit",
                    measurement: snapshot.heartRateVariability
                ),
                value: measurementValue(snapshot.heartRateVariability, fractionDigits: 0),
                symbolName: "waveform.path.ecg",
                tone: WellnarioPalette.cyan
            ),
            BiomarkerRowView(
                title: L10n.text("health.biomarker.resting_hr"),
                detail: measurementDetail(
                    unitKey: "health.biomarker.resting_hr.unit",
                    measurement: snapshot.restingHeartRate
                ),
                value: measurementValue(snapshot.restingHeartRate, fractionDigits: 0),
                symbolName: "heart.fill",
                tone: WellnarioPalette.pink
            ),
            BiomarkerRowView(
                title: L10n.text("health.biomarker.vo2"),
                detail: measurementDetail(
                    unitKey: "health.biomarker.vo2.unit",
                    measurement: snapshot.vo2Max
                ),
                value: measurementValue(snapshot.vo2Max, fractionDigits: 1),
                symbolName: "lungs.fill",
                tone: WellnarioPalette.violet
            ),
            BiomarkerRowView(
                title: L10n.text("health.biomarker.glucose"),
                detail: measurementDetail(
                    unitKey: "health.biomarker.glucose.unit",
                    measurement: snapshot.bloodGlucose
                ),
                value: measurementValue(snapshot.bloodGlucose, fractionDigits: 0),
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

    private func measurementValue(
        _ measurement: AppleHealthMeasurement?,
        fractionDigits: Int
    ) -> String {
        measurement.map {
            AppleHealthUIFormatting.number($0.value, maximumFractionDigits: fractionDigits)
        } ?? "—"
    }

    private func measurementDetail(
        unitKey: String,
        measurement: AppleHealthMeasurement?
    ) -> String {
        let unit = L10n.text(unitKey)
        guard let measurement else { return unit }
        return L10n.text(
            "apple_health.measurement.detail",
            unit,
            WellnarioFormatters.relativeDay(measurement.date),
            measurement.sourceName
        )
    }

    private func configureSourceBanner(_ banner: FeedbackBannerView) {
        banner.onAction = nil
        switch appleHealthService.state {
        case .unavailable:
            banner.configure(message: L10n.text("apple_health.unavailable"), tone: .warning)
        case .notConfigured:
            banner.configure(
                message: L10n.text("health.source.empty"),
                tone: .information,
                actionTitle: L10n.text("integrations.connect")
            )
            banner.onAction = { [weak self] in self?.onOpenSettings?() }
        case .syncing:
            banner.configure(message: L10n.text("apple_health.syncing"), tone: .information)
        case .failed:
            banner.configure(
                message: L10n.text("apple_health.sync_failed"),
                tone: .warning,
                actionTitle: AppleHealthUIFormatting.twoLineSyncNowActionTitle
            )
            banner.onAction = { [weak self] in self?.syncNow() }
        case .ready:
            let message = appleHealthService.snapshot.lastSyncedAt.map(AppleHealthUIFormatting.syncedAt)
                ?? L10n.text("apple_health.configured")
            banner.configure(
                message: message,
                tone: .success,
                actionTitle: AppleHealthUIFormatting.twoLineSyncNowActionTitle
            )
            banner.onAction = { [weak self] in self?.syncNow() }
        }
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
    @objc private func openCardEditor() {
        let editor = WellnessCardEditorViewController(
            preferences: cardLayoutPreferences,
            configuration: WellnessCardEditorConfiguration(
                title: L10n.text("health.cards.editor.title"),
                sectionTitle: L10n.text("health.cards.editor.section"),
                footer: L10n.text("health.cards.editor.footer"),
                visibleText: L10n.text("health.cards.visible"),
                hiddenText: L10n.text("health.cards.hidden"),
                visibilityAccessibilityFormatKey: "health.cards.visibility.accessibility",
                accessibilityPrefix: "health.cards"
            )
        )
        editor.onLayoutChange = { [weak self] in self?.buildContent() }
        navigationController?.pushViewController(editor, animated: true)
    }
    @objc private func openMedicalReviews() {
        navigationController?.pushViewController(
            MedicalReviewsViewController(store: medicalReviewStore),
            animated: true
        )
    }
    @objc private func appleHealthDidChange() { buildContent() }

    private func syncNow() {
        Task { try? await appleHealthService.sync() }
    }
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
