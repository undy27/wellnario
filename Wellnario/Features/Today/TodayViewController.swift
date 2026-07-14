import UIKit
import UniformTypeIdentifiers

@MainActor
final class TodayViewController: FeatureViewController {
    var onOpenSettings: (() -> Void)?
    var onShowSupplements: (() -> Void)?
    var onShowSleep: (() -> Void)?
    var onShowHealth: (() -> Void)?
    var onShowFitness: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let dateButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)

    private let sleepCard = WellnessSummaryCard()
    private let recoveryCard = WellnessSummaryCard()
    private let stressCard = WellnessSummaryCard()
    private let supplementsCard = WellnessSummaryCard()
    private let fitnessCard = WellnessSummaryCard()

    private let intakeAction = QuickActionControl()
    private let workoutAction = QuickActionControl()
    private let labAction = QuickActionControl()
    private let factorAction = QuickActionControl()

    private let recentCard = PremiumCardView()
    private let recentContent = UIStackView()

    private var summary: DashboardSummary?
    private var selectedDate = Date()
    private let appleHealthService: AppleHealthSyncing

    init(
        repository: WellnarioRepositoryProtocol,
        appleHealthService: AppleHealthSyncing
    ) {
        self.appleHealthService = appleHealthService
        super.init(repository: repository)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appleHealthDidChange),
            name: .appleHealthSyncDidChange,
            object: appleHealthService
        )
        applyLocalizedCopy()
        reloadContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        reloadContent()
    }

    override func applyLocalizedCopy() {
        navigationItem.accessibilityLabel = L10n.Tab.today
        dateButton.setTitle(WellnarioFormatters.dateHeader(selectedDate), for: .normal)
        settingsButton.accessibilityLabel = L10n.Settings.title
        configureStaticCards()
        configureQuickActions()
        if let summary { render(summary) }
    }

    override func reloadContent() {
        configureStaticCards()
        do {
            let summary = try repository.dashboard(
                on: LocalDay(containing: selectedDate, in: .current),
                expiringWithinDays: 30
            )
            self.summary = summary
            render(summary)
        } catch {
            showError(error)
        }
    }

    private func setUpView() {
        navigationController?.setNavigationBarHidden(true, animated: false)
        view.accessibilityIdentifier = "today.root"

        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .always
        scrollView.showsVerticalScrollIndicator = false
        view.addForAutoLayout(scrollView)
        scrollView.pinEdges(to: view)

        contentStack.axis = .vertical
        contentStack.spacing = WellnarioSpacing.cardGap
        scrollView.addForAutoLayout(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.leadingAnchor,
                constant: WellnarioSpacing.screenHorizontal
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.trailingAnchor,
                constant: -WellnarioSpacing.screenHorizontal
            ),
            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: WellnarioSpacing.medium
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

        let header = makeHeader()
        contentStack.addArrangedSubview(header)
        contentStack.setCustomSpacing(WellnarioSpacing.large, after: header)

        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("today.wellness_summary")))
        setUpSummaryCards()
        contentStack.addArrangedSubview(makeSummaryGrid())

        let summaryGrid = contentStack.arrangedSubviews.last!
        contentStack.setCustomSpacing(WellnarioSpacing.large, after: summaryGrid)
        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("today.quick_actions")))
        setUpQuickActions()
        contentStack.addArrangedSubview(makeQuickActionsGrid())

        let actionsGrid = contentStack.arrangedSubviews.last!
        contentStack.setCustomSpacing(WellnarioSpacing.large, after: actionsGrid)
        setUpRecentCard()
        contentStack.addArrangedSubview(recentCard)
    }

    private func makeHeader() -> UIView {
        dateButton.titleLabel?.font = WellnarioTypography.font(for: .pageTitle)
        dateButton.titleLabel?.adjustsFontForContentSizeCategory = true
        dateButton.titleLabel?.adjustsFontSizeToFitWidth = true
        dateButton.titleLabel?.minimumScaleFactor = 0.80
        dateButton.setTitleColor(WellnarioPalette.textPrimary, for: .normal)
        dateButton.contentHorizontalAlignment = .left
        dateButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        dateButton.tintColor = WellnarioPalette.textSecondary
        dateButton.semanticContentAttribute = .forceRightToLeft
        dateButton.addTarget(self, action: #selector(selectDate), for: .touchUpInside)

        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        settingsButton.setImage(UIImage(systemName: "gearshape.fill", withConfiguration: configuration), for: .normal)
        settingsButton.tintColor = WellnarioPalette.textPrimary
        settingsButton.backgroundColor = WellnarioPalette.surfaceElevated
        settingsButton.applyContinuousCorners(24)
        settingsButton.layer.borderWidth = 1
        settingsButton.layer.borderColor = WellnarioPalette.hairline.cgColor
        settingsButton.accessibilityIdentifier = "today.settings"
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        NSLayoutConstraint.activate([
            settingsButton.widthAnchor.constraint(equalToConstant: 48),
            settingsButton.heightAnchor.constraint(equalTo: settingsButton.widthAnchor)
        ])

        return UIStackView(
            arrangedSubviews: [dateButton, settingsButton],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
    }

    private func makeSectionTitle(_ title: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        label.text = title
        label.numberOfLines = 0
        return label
    }

    private func setUpSummaryCards() {
        sleepCard.accessibilityIdentifier = "today.summary.sleep"
        recoveryCard.accessibilityIdentifier = "today.summary.recovery"
        stressCard.accessibilityIdentifier = "today.summary.stress"
        supplementsCard.accessibilityIdentifier = "today.summary.supplements"
        fitnessCard.accessibilityIdentifier = "today.summary.fitness"

        sleepCard.addTarget(self, action: #selector(openSleep), for: .touchUpInside)
        recoveryCard.addTarget(self, action: #selector(openHealth), for: .touchUpInside)
        stressCard.addTarget(self, action: #selector(openHealth), for: .touchUpInside)
        supplementsCard.addTarget(self, action: #selector(openSupplements), for: .touchUpInside)
        fitnessCard.addTarget(self, action: #selector(openFitness), for: .touchUpInside)
    }

    private func configureStaticCards() {
        let noData = L10n.text("wellness.no_data")
        let snapshot = appleHealthService.snapshot
        let isToday = Calendar.autoupdatingCurrent.isDateInToday(selectedDate)

        let sleepValue: String
        let sleepDetail: String
        if isToday, let session = snapshot.latestSleepSession {
            sleepValue = AppleHealthUIFormatting.duration(session.asleepSeconds)
            sleepDetail = AppleHealthUIFormatting.sleepRange(session)
        } else {
            sleepValue = "—"
            sleepDetail = WellnessLocalStore.lastSleepFactor ?? noData
        }
        sleepCard.configure(
            title: L10n.text("wellness.sleep"),
            symbolName: "moon.stars.fill",
            value: sleepValue,
            detail: sleepDetail,
            tone: WellnarioPalette.violet
        )

        let hrv = isToday ? snapshot.heartRateVariability : nil
        recoveryCard.configure(
            title: L10n.text("wellness.recovery"),
            symbolName: "figure.cooldown",
            value: hrv.map { "\(AppleHealthUIFormatting.number($0.value)) ms" } ?? "—",
            detail: hrv == nil ? noData : L10n.text("apple_health.recovery.hrv_context"),
            tone: WellnarioPalette.success
        )

        let restingHeartRate = isToday ? snapshot.restingHeartRate : nil
        stressCard.configure(
            title: L10n.text("wellness.stress"),
            symbolName: "waveform.path.ecg",
            value: restingHeartRate.map {
                "\(AppleHealthUIFormatting.number($0.value)) \(L10n.text("apple_health.unit.bpm"))"
            } ?? "—",
            detail: restingHeartRate == nil
                ? noData
                : L10n.text("apple_health.stress.resting_hr_context"),
            tone: WellnarioPalette.warning
        )

        let workouts = isToday ? snapshot.workoutsThisWeek.count : 0
        let steps = isToday ? snapshot.stepsToday : nil
        fitnessCard.configure(
            title: L10n.text("wellness.fitness"),
            symbolName: "figure.run",
            value: "\(workouts)",
            detail: steps.map {
                L10n.text("apple_health.steps_today", AppleHealthUIFormatting.number($0))
            } ?? L10n.text("fitness.workouts_this_week"),
            tone: WellnarioPalette.magenta
        )
    }

    private func makeSummaryGrid() -> UIView {
        let firstRow = equalRow(sleepCard, recoveryCard)
        let secondRow = equalRow(stressCard, supplementsCard)
        return UIStackView(
            arrangedSubviews: [firstRow, secondRow, fitnessCard],
            axis: .vertical,
            spacing: 10
        )
    }

    private func setUpQuickActions() {
        intakeAction.accessibilityIdentifier = "today.quick.intake"
        workoutAction.accessibilityIdentifier = "today.quick.workout"
        labAction.accessibilityIdentifier = "today.quick.lab"
        factorAction.accessibilityIdentifier = "today.quick.sleep_factor"

        intakeAction.addTarget(self, action: #selector(logIntake), for: .touchUpInside)
        workoutAction.addTarget(self, action: #selector(startWorkout), for: .touchUpInside)
        labAction.addTarget(self, action: #selector(importLab), for: .touchUpInside)
        factorAction.addTarget(self, action: #selector(addSleepFactor), for: .touchUpInside)
    }

    private func configureQuickActions() {
        intakeAction.configure(
            title: L10n.text("quick.intake.title"),
            detail: L10n.text("quick.intake.detail"),
            symbolName: "pills.fill",
            tone: WellnarioPalette.cyan
        )
        workoutAction.configure(
            title: L10n.text("quick.workout.title"),
            detail: L10n.text("quick.workout.detail"),
            symbolName: "play.fill",
            tone: WellnarioPalette.magenta
        )
        labAction.configure(
            title: L10n.text("quick.lab.title"),
            detail: L10n.text("quick.lab.detail"),
            symbolName: "doc.badge.plus",
            tone: WellnarioPalette.information
        )
        factorAction.configure(
            title: L10n.text("quick.factor.title"),
            detail: L10n.text("quick.factor.detail"),
            symbolName: "moon.badge.plus.fill",
            tone: WellnarioPalette.violet
        )
    }

    private func makeQuickActionsGrid() -> UIView {
        UIStackView(
            arrangedSubviews: [intakeAction, workoutAction, labAction, factorAction],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )
    }

    private func equalRow(_ first: UIView, _ second: UIView) -> UIStackView {
        let row = UIStackView(
            arrangedSubviews: [first, second],
            axis: .horizontal,
            spacing: 10,
            alignment: .fill,
            distribution: .fillEqually
        )
        first.widthAnchor.constraint(equalTo: second.widthAnchor).isActive = true
        return row
    }

    private func setUpRecentCard() {
        recentContent.axis = .vertical
        recentContent.spacing = WellnarioSpacing.xSmall
        recentCard.contentView.addForAutoLayout(recentContent)
        recentContent.pinEdges(to: recentCard.contentView, insets: .all(WellnarioSpacing.cardPadding))
        recentCard.accessibilityIdentifier = "today.recent_supplements"
    }

    private func render(_ summary: DashboardSummary) {
        supplementsCard.configure(
            title: L10n.text("wellness.supplements"),
            symbolName: "pills.fill",
            value: "\(summary.consumptionCount)",
            detail: summary.consumptionCount == 1
                ? L10n.text("today.intake.singular")
                : L10n.text("today.intake.plural"),
            tone: summary.consumptionCount == 0 ? WellnarioPalette.textSecondary : WellnarioPalette.cyan
        )
        rebuildRecentCard(summary)
    }

    private func rebuildRecentCard(_ summary: DashboardSummary) {
        recentContent.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let title = UILabel()
        title.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        title.text = L10n.text("today.supplements.title")
        let icon = UIImageView(image: UIImage(systemName: "pills.fill"))
        icon.tintColor = WellnarioPalette.cyan
        let heading = UIStackView(
            arrangedSubviews: [title, UIView(), icon],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .center
        )
        recentContent.addArrangedSubview(heading)

        if summary.recentConsumptions.isEmpty {
            let label = UILabel()
            label.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
            label.text = L10n.text("today.supplements.empty")
            label.numberOfLines = 0
            recentContent.addArrangedSubview(label)
        } else {
            summary.recentConsumptions.prefix(3).forEach { recentContent.addArrangedSubview(consumptionRow($0)) }
        }

        let button = PrimaryButton(title: L10n.text("quick.intake.title"), style: .secondary)
        button.addTarget(self, action: #selector(logIntake), for: .touchUpInside)
        recentContent.addArrangedSubview(button)
    }

    private func consumptionRow(_ consumption: Consumption) -> UIView {
        let artwork = PresentationArtworkView(kind: .capsule)
        artwork.showsBackground = true
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 44),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor)
        ])

        let title = UILabel()
        title.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        title.text = consumption.supplementNameSnapshot
        title.numberOfLines = 1
        let detail = UILabel()
        detail.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detail.text = "\(FeatureFormatting.decimal(consumption.quantity)) \(consumption.unit.symbol(languageCode: catalogLanguage.rawValue)) · \(WellnarioFormatters.time(consumption.consumedAt, timeZoneID: consumption.timeZoneID))"
        detail.numberOfLines = 1
        let labels = UIStackView(arrangedSubviews: [title, detail], axis: .vertical, spacing: 2)
        return UIStackView(
            arrangedSubviews: [artwork, labels],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
    }

    @objc private func selectDate() {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.maximumDate = Date()
        picker.date = selectedDate

        let controller = UIViewController()
        controller.view.backgroundColor = WellnarioPalette.background
        controller.view.addForAutoLayout(picker)
        picker.pinEdges(to: controller.view.safeAreaLayoutGuide, insets: .all(WellnarioSpacing.small))
        controller.preferredContentSize = CGSize(width: 360, height: 420)
        picker.addAction(UIAction { [weak self, weak controller] action in
            guard let picker = action.sender as? UIDatePicker else { return }
            self?.selectedDate = picker.date
            self?.applyLocalizedCopy()
            self?.reloadContent()
            controller?.dismiss(animated: true)
        }, for: .valueChanged)
        presentSheet(controller)
    }

    @objc private func logIntake() {
        do {
            let instances = try repository.fetchInstances(supplementID: nil, includeArchived: false)
            guard !instances.isEmpty else {
                let alert = UIAlertController(
                    title: L10n.Inventory.noItemsTitle,
                    message: L10n.text("intake.requires_batch"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
                alert.addAction(UIAlertAction(title: L10n.Today.addFirstSupplement, style: .default) { [weak self] _ in
                    self?.onShowSupplements?()
                })
                present(alert, animated: true)
                return
            }
            presentSheet(IntakeEditorViewController(repository: repository), largeOnly: true)
        } catch {
            showError(error)
        }
    }

    @objc private func startWorkout() {
        let controller = WorkoutStarterViewController()
        controller.onStarted = { [weak self] type in
            guard let self else { return }
            _ = FeedbackPresenter.show(
                message: L10n.text("workout.started", type),
                tone: .success,
                in: self.view
            )
        }
        presentSheet(controller)
    }

    @objc private func addSleepFactor() {
        let controller = SleepFactorPickerViewController()
        controller.onLogged = { [weak self] factor in
            guard let self else { return }
            self.configureStaticCards()
            _ = FeedbackPresenter.show(
                message: L10n.text("sleep.factor.logged", factor),
                tone: .success,
                in: self.view
            )
        }
        presentSheet(controller)
    }

    @objc private func importLab() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openSupplements() { onShowSupplements?() }
    @objc private func openSleep() { onShowSleep?() }
    @objc private func openHealth() { onShowHealth?() }
    @objc private func openFitness() { onShowFitness?() }
    @objc private func appleHealthDidChange() { reloadContent() }
}

extension TodayViewController: UIDocumentPickerDelegate {
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
}
