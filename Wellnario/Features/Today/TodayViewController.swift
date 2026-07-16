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
    private let reviewsCard = TodayMedicalReviewsSummaryCard()

    private let intakeAction = QuickActionControl()
    private let workoutAction = QuickActionControl()
    private let labAction = QuickActionControl()
    private let factorAction = QuickActionControl()

    private var summary: DashboardSummary?
    private var selectedDate = Date()
    private let appleHealthService: AppleHealthSyncing
    private let medicalReviewStore: MedicalReviewStore
    private let sleepManualOverrideStore: SleepManualOverrideStore

    init(
        repository: WellnarioRepositoryProtocol,
        appleHealthService: AppleHealthSyncing,
        medicalReviewStore: MedicalReviewStore = MedicalReviewStore(),
        sleepManualOverrideStore: SleepManualOverrideStore = SleepManualOverrideStore()
    ) {
        self.appleHealthService = appleHealthService
        self.medicalReviewStore = medicalReviewStore
        self.sleepManualOverrideStore = sleepManualOverrideStore
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sleepManualOverridesDidChange),
            name: .sleepManualOverridesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sleepQualityPreferencesDidChange),
            name: .sleepQualityPreferencesDidChange,
            object: nil
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
        reviewsCard.accessibilityIdentifier = "today.summary.reviews"

        sleepCard.addTarget(self, action: #selector(openSleep), for: .touchUpInside)
        recoveryCard.addTarget(self, action: #selector(openHealth), for: .touchUpInside)
        stressCard.addTarget(self, action: #selector(openHealth), for: .touchUpInside)
        supplementsCard.addTarget(self, action: #selector(openSupplements), for: .touchUpInside)
        fitnessCard.addTarget(self, action: #selector(openFitness), for: .touchUpInside)
        reviewsCard.addTarget(self, action: #selector(openHealth), for: .touchUpInside)
    }

    private func configureStaticCards() {
        let noData = L10n.text("wellness.no_data")
        let snapshot = sleepManualOverrideStore.applying(to: appleHealthService.snapshot)
        let isToday = Calendar.autoupdatingCurrent.isDateInToday(selectedDate)
        let selectedDay = LocalDay(containing: selectedDate, in: .current)
        let manualOverride = sleepManualOverrideStore.override(for: selectedDay)
        let selectedSleepDay = snapshot.sleepTrend.last {
            LocalDay(containing: $0.date, in: .current) == selectedDay
        }

        let sleepValue: String
        let sleepDetail: String
        if let hours = selectedSleepDay?.hours {
            sleepValue = AppleHealthUIFormatting.duration(hours * 3_600)
            if manualOverride != nil {
                var details = [L10n.text("sleep.manual.source")]
                if let quality = selectedSleepDay?.qualityScore {
                    details.append(L10n.text("sleep.manual.quality", Int(quality.rounded())))
                }
                sleepDetail = details.joined(separator: " · ")
            } else if isToday, let session = snapshot.latestSleepSession {
                var details = [AppleHealthUIFormatting.sleepRange(session)]
                if let quality = selectedSleepDay?.qualityScore {
                    details.append(L10n.text("sleep.manual.quality", Int(quality.rounded())))
                }
                sleepDetail = details.joined(separator: " · ")
            } else if let quality = selectedSleepDay?.qualityScore {
                sleepDetail = L10n.text("sleep.manual.quality", Int(quality.rounded()))
            } else {
                sleepDetail = noData
            }
        } else if isToday, let session = snapshot.latestSleepSession {
            sleepValue = AppleHealthUIFormatting.duration(session.asleepSeconds)
            if manualOverride != nil {
                var details = [L10n.text("sleep.manual.source")]
                if let quality = selectedSleepDay?.qualityScore {
                    details.append(L10n.text("sleep.manual.quality", Int(quality.rounded())))
                }
                sleepDetail = details.joined(separator: " · ")
            } else {
                sleepDetail = AppleHealthUIFormatting.sleepRange(session)
            }
        } else {
            sleepValue = "—"
            if let quality = selectedSleepDay?.qualityScore {
                sleepDetail = L10n.text("sleep.manual.quality", Int(quality.rounded()))
            } else {
                sleepDetail = WellnessLocalStore.lastSleepFactor ?? noData
            }
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
        reviewsCard.configure(
            reviews: medicalReviewStore.reviews,
            referenceDate: Date()
        )
    }

    private func makeSummaryGrid() -> UIView {
        let firstRow = equalRow(sleepCard, recoveryCard)
        let secondRow = equalRow(stressCard, supplementsCard)
        let thirdRow = equalRow(fitnessCard, reviewsCard)
        return UIStackView(
            arrangedSubviews: [firstRow, secondRow, thirdRow],
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
    @objc private func sleepManualOverridesDidChange() { reloadContent() }
    @objc private func sleepQualityPreferencesDidChange() { reloadContent() }
}

@MainActor
final class TodayMedicalReviewsSummaryCard: PremiumCardView {
    let symbolContainer = UIView()
    private let symbolView = UIImageView(image: UIImage(systemName: "calendar.badge.clock"))
    let titleLabel = UILabel()
    private let reviewsStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    func configure(
        reviews: [MedicalReview],
        referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        titleLabel.text = L10n.text("today.reviews.title")
        reviewsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let entries = MedicalReviewTimeline.entries(
            from: reviews,
            referenceDate: referenceDate,
            calendar: calendar
        )

        if entries.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.applyWellnarioStyle(.summaryDetail, color: WellnarioPalette.textTertiary)
            emptyLabel.text = L10n.text("today.reviews.empty")
            emptyLabel.numberOfLines = 2
            reviewsStack.addArrangedSubview(emptyLabel)
            accessibilityValue = emptyLabel.text
        } else {
            for (index, entry) in entries.enumerated() {
                reviewsStack.addArrangedSubview(
                    TodayMedicalReviewRow(
                        entry: entry,
                        index: index,
                        referenceDate: referenceDate,
                        calendar: calendar
                    )
                )
            }
            accessibilityValue = entries.map {
                [
                    $0.review.title,
                    MedicalReviewFormatting.dueStatus(
                        $0.review,
                        referenceDate: referenceDate,
                        calendar: calendar
                    )
                ].joined(separator: ", ")
            }.joined(separator: ". ")
        }

        accessibilityLabel = L10n.text("today.reviews.title")
    }

    private func setUp() {
        symbolContainer.applyContinuousCorners(11)
        symbolContainer.backgroundColor = WellnarioPalette.fuchsia.withAlphaComponent(0.14)
        NSLayoutConstraint.activate([
            symbolContainer.widthAnchor.constraint(equalToConstant: 34),
            symbolContainer.heightAnchor.constraint(equalTo: symbolContainer.widthAnchor)
        ])

        symbolView.tintColor = WellnarioPalette.fuchsia
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 15,
            weight: .semibold
        )
        symbolContainer.addForAutoLayout(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: symbolContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: symbolContainer.centerYAnchor)
        ])

        titleLabel.applyWellnarioStyle(.summaryTitle, color: WellnarioPalette.textPrimary)
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = UIStackView(
            arrangedSubviews: [symbolContainer, titleLabel, UIView()],
            axis: .horizontal,
            spacing: 7,
            alignment: .center
        )
        header.setContentHuggingPriority(.required, for: .vertical)
        header.setContentCompressionResistancePriority(.required, for: .vertical)
        reviewsStack.axis = .vertical
        reviewsStack.spacing = 1
        contentView.addForAutoLayout(header)
        contentView.addForAutoLayout(reviewsStack)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: WellnarioSpacing.xSmall
            ),
            header.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: WellnarioSpacing.xSmall
            ),
            header.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -WellnarioSpacing.xSmall
            ),
            reviewsStack.topAnchor.constraint(
                equalTo: header.bottomAnchor,
                constant: WellnarioSpacing.xxxSmall
            ),
            reviewsStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            reviewsStack.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            reviewsStack.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor,
                constant: -WellnarioSpacing.xSmall
            )
        ])
        heightAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true
        isPressable = true
    }
}

@MainActor
final class TodayMedicalReviewRow: UIStackView {
    private(set) var urgency: MedicalReviewDueUrgency
    let reviewTitleLabel = UILabel()

    init(
        entry: MedicalReviewTimelineEntry,
        index: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        urgency = entry.urgency
        super.init(frame: .zero)
        accessibilityIdentifier = "today.summary.reviews.row.\(index)"
        axis = .horizontal
        spacing = 5
        alignment = .center

        let color = Self.color(for: entry.urgency)
        let marker = UIView()
        marker.backgroundColor = color
        marker.applyContinuousCorners(4)
        NSLayoutConstraint.activate([
            marker.widthAnchor.constraint(equalToConstant: 7),
            marker.heightAnchor.constraint(equalTo: marker.widthAnchor)
        ])

        reviewTitleLabel.applyWellnarioStyle(.summaryDetail, color: color)
        reviewTitleLabel.text = [
            entry.review.title,
            MedicalReviewFormatting.relativeDayStatus(
                dueDate: entry.dueDate,
                referenceDate: referenceDate,
                calendar: calendar
            )
        ].joined(separator: " · ")
        reviewTitleLabel.numberOfLines = 2
        reviewTitleLabel.lineBreakMode = .byWordWrapping
        addArrangedSubview(marker)
        addArrangedSubview(reviewTitleLabel)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func color(for urgency: MedicalReviewDueUrgency) -> UIColor {
        switch urgency {
        case .upcoming: WellnarioPalette.success
        case .overdueUnderQuarter: WellnarioPalette.yellow
        case .overdueFromQuarterThroughThreeQuarters: WellnarioPalette.orange
        case .overdueOverThreeQuarters: WellnarioPalette.danger
        }
    }
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
