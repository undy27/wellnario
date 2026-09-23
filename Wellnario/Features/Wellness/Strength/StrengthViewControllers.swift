import UIKit

@MainActor
final class StrengthWorkoutStartViewController: WellnessScrollViewController {
    private let store: StrengthDataStore
    private let appleHealthService: AppleHealthSyncing?

    init(store: StrengthDataStore, appleHealthService: AppleHealthSyncing? = nil) {
        self.store = store
        self.appleHealthService = appleHealthService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("strength.start.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "strength.start"
        buildContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        buildContent()
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        contentStack.addArrangedSubview(hubCard(
            titleKey: "strength.hub.workouts",
            detailKey: "strength.hub.workouts.detail",
            symbol: "clock.arrow.circlepath",
            identifier: "strength.hub.workouts",
            action: #selector(showWorkouts)
        ))
        contentStack.addArrangedSubview(hubCard(
            titleKey: "strength.hub.exercises",
            detailKey: "strength.hub.exercises.detail",
            symbol: "dumbbell.fill",
            identifier: "strength.hub.exercises",
            action: #selector(showExercises)
        ))
        contentStack.addArrangedSubview(hubCard(
            titleKey: "strength.hub.templates",
            detailKey: "strength.hub.templates.detail",
            symbol: "rectangle.stack.badge.play",
            identifier: "strength.hub.templates",
            action: #selector(showTemplates)
        ))
        contentStack.addArrangedSubview(hubCard(
            titleKey: "strength.hub.metrics",
            detailKey: "strength.hub.metrics.detail",
            symbol: "figure.arms.open",
            identifier: "strength.hub.metrics",
            action: #selector(showBodyMetrics)
        ))
        contentStack.addArrangedSubview(hubCard(
            titleKey: "strength.hub.reports",
            detailKey: "strength.hub.reports.detail",
            symbol: "chart.xyaxis.line",
            identifier: "strength.hub.reports",
            action: #selector(showReports)
        ))
    }

    private func hubCard(
        titleKey: String,
        detailKey: String,
        symbol: String,
        identifier: String,
        action: Selector
    ) -> PremiumCardView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = WellnarioPalette.cyan
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        icon.widthAnchor.constraint(equalToConstant: 34).isActive = true

        let title = UILabel()
        title.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        title.text = L10n.text(titleKey)
        let detail = UILabel()
        detail.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detail.text = L10n.text(detailKey)
        detail.numberOfLines = 2
        let labels = UIStackView(arrangedSubviews: [title, detail], axis: .vertical, spacing: 2)
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = WellnarioPalette.textTertiary
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        let card = makeCard(containing: UIStackView(
            arrangedSubviews: [icon, labels, UIView(), chevron],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        ), identifier: identifier)
        card.isPressable = true
        card.addTarget(self, action: action, for: .touchUpInside)
        return card
    }

    @objc private func showWorkouts() {
        navigationController?.pushViewController(
            StrengthWorkoutsViewController(store: store, appleHealthService: appleHealthService),
            animated: true
        )
    }

    @objc private func showExercises() {
        navigationController?.pushViewController(
            StrengthExercisePickerViewController(
                store: store,
                allowsMultipleSelection: false,
                allowsRenaming: true
            ),
            animated: true
        )
    }

    @objc private func showTemplates() {
        navigationController?.pushViewController(
            StrengthTemplatesViewController(store: store),
            animated: true
        )
    }

    @objc private func showBodyMetrics() {
        navigationController?.pushViewController(
            StrengthBodyMetricsViewController(store: store),
            animated: true
        )
    }

    @objc private func showReports() {
        navigationController?.pushViewController(
            StrengthReportsViewController(store: store),
            animated: true
        )
    }
}

@MainActor
final class StrengthTemplateEditorViewController: WellnessScrollViewController {
    private let store: StrengthDataStore
    private let nameField = FormFieldView()
    private let existingTemplate: StrengthWorkoutTemplate?
    private var templateExercises: [StrengthWorkoutTemplateExercise]

    init(store: StrengthDataStore, template: StrengthWorkoutTemplate? = nil) {
        self.store = store
        existingTemplate = template
        templateExercises = template?.exercises ?? []
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = existingTemplate == nil
            ? L10n.text("strength.template.editor.title")
            : L10n.text("strength.template.editor.edit.title")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = WellnarioNavigationButton.item(
            title: L10n.Common.save,
            style: .done,
            target: self,
            action: #selector(save)
        )
        nameField.configure(
            title: L10n.text("strength.template.editor.name"),
            placeholder: L10n.text("strength.template.editor.name.placeholder"),
            text: existingTemplate.map(templateDisplayName),
            contentType: .name
        )
        nameField.textField.accessibilityIdentifier = "strength.template.name"
        buildContent()
    }

    private func buildContent() {
        let retainedName = nameField.textField.text
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        nameField.textField.text = retainedName
        contentStack.addArrangedSubview(makeCard(containing: nameField, identifier: "strength.template.name.card"))
        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("strength.template.editor.exercises")))

        if templateExercises.isEmpty {
            let empty = UILabel()
            empty.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
            empty.text = L10n.text("strength.template.editor.exercises.empty")
            empty.numberOfLines = 0
            contentStack.addArrangedSubview(makeCard(containing: empty))
        } else {
            for templateExercise in templateExercises {
                contentStack.addArrangedSubview(selectedExerciseRow(templateExercise))
            }
        }

        let add = PrimaryButton(title: L10n.text("strength.exercise.add"), style: .secondary)
        add.accessibilityIdentifier = "strength.template.add_exercise"
        add.addTarget(self, action: #selector(addExercises), for: .touchUpInside)
        contentStack.addArrangedSubview(add)
    }

    private func selectedExerciseRow(_ templateExercise: StrengthWorkoutTemplateExercise) -> PremiumCardView {
        let exercise = templateExercise.exercise
        let label = UILabel()
        label.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        label.text = exercise.localizedName(language: LocalizationManager.shared.language)
        label.numberOfLines = 2

        let detail = UILabel()
        detail.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detail.text = templateExerciseSummary(templateExercise)
        let labels = UIStackView(arrangedSubviews: [label, detail], axis: .vertical, spacing: 2)

        let remove = UIButton(type: .system)
        remove.setImage(UIImage(systemName: "minus.circle"), for: .normal)
        remove.tintColor = WellnarioPalette.textSecondary
        remove.accessibilityLabel = L10n.text("strength.exercise.remove", label.text ?? "")
        remove.addAction(UIAction { [weak self] _ in
            self?.templateExercises.removeAll { $0.id == templateExercise.id }
            self?.buildContent()
        }, for: .touchUpInside)
        let configure = UIButton(type: .system)
        configure.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        configure.tintColor = WellnarioPalette.cyan
        configure.accessibilityLabel = L10n.text("strength.template.editor.configure", label.text ?? "")
        configure.addAction(UIAction { [weak self] _ in
            self?.configure(templateExercise)
        }, for: .touchUpInside)
        let card = makeCard(containing: UIStackView(
            arrangedSubviews: [labels, UIView(), configure, remove],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        ))
        card.isPressable = true
        card.addAction(UIAction { [weak self] _ in self?.configure(templateExercise) }, for: .touchUpInside)
        return card
    }

    @objc private func addExercises() {
        let picker = StrengthExercisePickerViewController(
            store: store,
            allowsMultipleSelection: true,
            selectedExerciseIDs: Set(templateExercises.map(\.exercise.id))
        )
        picker.onExercisesPicked = { [weak self] exercises in
            guard let self else { return }
            let knownIDs = Set(self.templateExercises.map(\.exercise.id))
            self.templateExercises += exercises.filter { !knownIDs.contains($0.id) }.enumerated().map { index, exercise in
                self.defaultTemplateExercise(exercise, order: self.templateExercises.count + index)
            }
            self.buildContent()
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    @objc private func save() {
        view.endEditing(true)
        let exerciseTemplates = templateExercises.enumerated().map { index, item in
            var normalized = item
            normalized.order = index
            return normalized
        }
        do {
            let draft = StrengthWorkoutTemplateDraft(
                name: nameField.textField.text ?? "",
                exercises: exerciseTemplates
            )
            if let existingTemplate {
                _ = try store.updateTemplate(id: existingTemplate.id, draft: draft)
            } else {
                _ = try store.saveTemplate(draft)
            }
            UIImpactFeedbackGenerator.wellnarioSuccess()
            navigationController?.popViewController(animated: true)
        } catch {
            presentStrengthError(error)
        }
    }

    private func defaultTemplateExercise(_ exercise: StrengthExercise, order: Int) -> StrengthWorkoutTemplateExercise {
        StrengthWorkoutTemplateExercise(
            id: UUID(), exercise: exercise, order: order, defaultRestSeconds: 90,
            sets: (1...3).map { StrengthWorkoutSet(order: $0, repetitions: 8, restSeconds: 90) }
        )
    }

    private func templateExerciseSummary(_ item: StrengthWorkoutTemplateExercise) -> String {
        let repetitions = item.sets.first?.repetitions.map(String.init) ?? "—"
        let weight = item.sets.first?.weight.map { " · \(StrengthFormat.decimal($0)) kg" } ?? ""
        let rest = item.defaultRestSeconds ?? item.sets.first?.restSeconds ?? 90
        return L10n.text("strength.template.editor.exercise.summary", item.sets.count, repetitions, weight, StrengthFormat.rest(rest))
    }

    private func templateDisplayName(_ template: StrengthWorkoutTemplate) -> String {
        template.nameKey.map { L10n.text($0) } ?? template.name
    }

    private func configure(_ item: StrengthWorkoutTemplateExercise) {
        let alert = UIAlertController(
            title: item.exercise.localizedName(language: LocalizationManager.shared.language),
            message: L10n.text("strength.template.editor.configure.message"),
            preferredStyle: .alert
        )
        let firstSet = item.sets.first
        let fields: [(String, String)] = [
            (L10n.text("strength.template.editor.set_count"), String(max(1, item.sets.count))),
            (L10n.text("strength.template.editor.reps"), firstSet?.repetitions.map(String.init) ?? "8"),
            (L10n.text("strength.template.editor.weight"), firstSet?.weight.map(StrengthFormat.decimal) ?? ""),
            (L10n.text("strength.template.editor.rest"), StrengthFormat.rest(item.defaultRestSeconds ?? firstSet?.restSeconds ?? 90))
        ]
        for (index, field) in fields.enumerated() {
            alert.addTextField { textField in
                textField.placeholder = field.0
                textField.text = field.1
                textField.keyboardType = index == 2 ? .decimalPad : .numbersAndPunctuation
            }
        }
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.save, style: .default) { [weak self, weak alert] _ in
            guard let self, let alert,
                  let count = Int(alert.textFields?[0].text ?? ""), count > 0,
                  let repetitions = Int(alert.textFields?[1].text ?? ""), repetitions >= 0,
                  let rest = StrengthFormat.parseRest(alert.textFields?[3].text) else { return }
            let weight = StrengthFormat.parseDecimal(alert.textFields?[2].text)
            guard let index = self.templateExercises.firstIndex(where: { $0.id == item.id }) else { return }
            self.templateExercises[index].defaultRestSeconds = rest
            self.templateExercises[index].sets = (1...count).map {
                StrengthWorkoutSet(order: $0, weight: weight, repetitions: repetitions, restSeconds: rest)
            }
            self.buildContent()
        })
        present(alert, animated: true)
    }
}

@MainActor
final class StrengthWorkoutViewController: WellnessScrollViewController {
    private let store: StrengthDataStore
    private let appleHealthService: AppleHealthSyncing?
    private let maximumHeartRatePreferences = FitnessMaximumHeartRatePreferences()
    private var workout: StrengthWorkout
    private let isEditingExistingWorkout: Bool
    var onWorkoutFinished: (() -> Void)?
    private let durationLabel = UILabel()
    private var timer: Timer?
    private var heartRateSamples: [AppleHealthTimedQuantity]?
    private var restingHeartRateAverage: Double?

    override var contentHorizontalInset: CGFloat { WellnarioSpacing.xSmall }

    init(
        store: StrengthDataStore,
        workout: StrengthWorkout,
        isEditingExistingWorkout: Bool = false,
        appleHealthService: AppleHealthSyncing? = nil
    ) {
        self.store = store
        self.workout = workout
        self.isEditingExistingWorkout = isEditingExistingWorkout
        self.appleHealthService = appleHealthService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = workout.title
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = WellnarioNavigationButton.item(
            title: isEditingExistingWorkout ? L10n.Common.save : L10n.text("strength.workout.finish"),
            style: .done,
            target: self,
            action: #selector(finishWorkout)
        )
        view.accessibilityIdentifier = "strength.workout"
        buildContent()
        if !isEditingExistingWorkout { startTimer() }
        loadHeartRateIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController == nil { timer?.invalidate() }
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        contentStack.spacing = WellnarioSpacing.small
        contentStack.addArrangedSubview(makeTimerHeader())
        if isEditingExistingWorkout, workout.endedAt != nil, appleHealthService != nil {
            contentStack.addArrangedSubview(makeHeartRateSection())
        }

        if workout.exercises.isEmpty {
            let empty = UILabel()
            empty.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
            empty.text = L10n.text("strength.workout.empty")
            empty.numberOfLines = 0
            empty.textAlignment = .center
            empty.accessibilityIdentifier = "strength.workout.empty"
            contentStack.addArrangedSubview(empty)
        } else {
            for exercise in workout.exercises {
                contentStack.addArrangedSubview(makeExerciseSection(exercise))
            }
        }

        let addExerciseButton = PrimaryButton(title: L10n.text("strength.exercise.add"), style: .secondary)
        addExerciseButton.accessibilityIdentifier = "strength.workout.add_exercise"
        addExerciseButton.addTarget(self, action: #selector(addExercise), for: .touchUpInside)
        contentStack.addArrangedSubview(addExerciseButton)
    }

    private func makeTimerHeader() -> UIView {
        let title = UILabel()
        title.applyWellnarioStyle(.caption, color: WellnarioPalette.magenta)
        title.text = isEditingExistingWorkout
            ? L10n.text("strength.workout.editing")
            : L10n.text("strength.workout.in_progress")

        durationLabel.applyWellnarioStyle(.summaryMetric, color: WellnarioPalette.textPrimary)
        durationLabel.text = StrengthFormat.duration((workout.endedAt ?? Date()).timeIntervalSince(workout.startedAt))
        durationLabel.accessibilityIdentifier = "strength.workout.duration"

        let detail = UILabel()
        detail.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detail.text = L10n.text("strength.workout.duration")
        let labels = UIStackView(arrangedSubviews: [title, detail], axis: .vertical, spacing: 2)
        return UIStackView(
            arrangedSubviews: [labels, UIView(), durationLabel],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )
    }

    private func makeHeartRateSection() -> UIView {
        let title = UILabel()
        title.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        title.text = L10n.text("strength.heart_rate.title")

        guard let heartRateSamples else {
            let loading = UILabel()
            loading.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
            loading.text = L10n.text("strength.heart_rate.loading")
            return UIStackView(
                arrangedSubviews: [title, loading],
                axis: .vertical,
                spacing: WellnarioSpacing.xSmall
            )
        }

        guard !heartRateSamples.isEmpty else {
            let unavailable = UILabel()
            unavailable.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
            unavailable.text = L10n.text("strength.heart_rate.unavailable")
            unavailable.numberOfLines = 0
            return UIStackView(
                arrangedSubviews: [title, unavailable],
                axis: .vertical,
                spacing: WellnarioSpacing.xSmall
            )
        }

        let maximum = estimatedMaximumHeartRate()
        let average = heartRateSamples.map(\.value).reduce(0, +) / Double(heartRateSamples.count)
        let peak = heartRateSamples.map(\.value).max() ?? 0
        let summary = UILabel()
        summary.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        summary.text = L10n.text(
            "strength.heart_rate.summary",
            AppleHealthUIFormatting.number(average),
            AppleHealthUIFormatting.number(peak)
        )

        let zones = StrengthHeartRateZone.estimated(maximum: maximum)
        let chart = StrengthHeartRateChartView()
        chart.configure(
            samples: heartRateSamples,
            workoutStart: workout.startedAt,
            workoutEnd: workout.endedAt ?? Date(),
            zones: zones
        )
        chart.heightAnchor.constraint(equalToConstant: 128).isActive = true
        chart.accessibilityLabel = L10n.text("strength.heart_rate.chart.accessibility")
        chart.accessibilityValue = summary.text

        let section = UIStackView(
            arrangedSubviews: [title, summary, chart],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )
        section.accessibilityIdentifier = "strength.workout.heart_rate"
        return section
    }

    private func loadHeartRateIfNeeded() {
        guard isEditingExistingWorkout,
              heartRateSamples == nil,
              let appleHealthService,
              let endedAt = workout.endedAt,
              workout.startedAt < endedAt else { return }
        let workoutStart = workout.startedAt
        let estimationEnd = Date()
        let estimationStart = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: -30,
            to: estimationEnd
        ) ?? estimationEnd
        Task { [weak self] in
            let samples = await appleHealthService.heartRateSamples(
                from: workoutStart,
                through: endedAt
            )
            let restingSamples = await appleHealthService.restingHeartRateSamples(
                from: estimationStart,
                through: estimationEnd
            )
            guard let self, !Task.isCancelled else { return }
            self.heartRateSamples = samples.filter {
                $0.value > 0 && $0.endDate >= workoutStart && $0.endDate <= endedAt
            }
            let validRestingSamples = restingSamples.filter { $0.value > 0 }
            self.restingHeartRateAverage = validRestingSamples.isEmpty
                ? nil
                : validRestingSamples.map(\.value).reduce(0, +) / Double(validRestingSamples.count)
            self.buildContent()
        }
    }

    private func estimatedMaximumHeartRate() -> Double {
        if let manualMaximum = maximumHeartRatePreferences.manualMaximumHeartRate {
            return Double(manualMaximum)
        }
        return Double(FitnessMaximumHeartRateEstimator.estimate(
            snapshot: appleHealthService?.snapshot ?? .empty,
            restingHeartRate: restingHeartRateAverage
        ).value)
    }

    private func makeExerciseSection(_ workoutExercise: StrengthWorkoutExercise) -> UIView {
        let title = UILabel()
        title.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        title.text = workoutExercise.exercise.localizedName(language: LocalizationManager.shared.language)
        title.numberOfLines = 2

        let remove = UIButton(type: .system)
        remove.setImage(UIImage(systemName: "trash"), for: .normal)
        remove.tintColor = WellnarioPalette.textSecondary
        remove.accessibilityLabel = L10n.text("strength.exercise.remove", title.text ?? "")
        remove.addAction(UIAction { [weak self] _ in
            self?.workout.exercises.removeAll { $0.id == workoutExercise.id }
            self?.reindexExercises()
            self?.buildContent()
        }, for: .touchUpInside)

        let header = UIStackView(
            arrangedSubviews: [title, UIView(), remove],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        )

        let restLabel = UILabel()
        restLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        restLabel.text = L10n.text("strength.exercise.rest")
        let restButton = UIButton(type: .system)
        configureRestButton(restButton, seconds: workoutExercise.restSeconds ?? 90)
        restButton.addAction(UIAction { [weak self] _ in
            self?.selectRest(for: workoutExercise.id, current: workoutExercise.restSeconds ?? 90)
        }, for: .touchUpInside)
        let restLine = UIStackView(
            arrangedSubviews: [restLabel, restButton, UIView()],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .center
        )
        let columnHeader = StrengthSetColumnHeaderView()
        let setRows = UIStackView(arrangedSubviews: [], axis: .vertical, spacing: 6)
        for set in workoutExercise.sets {
            let previous = try? store.previousSet(
                exerciseID: workoutExercise.exercise.id,
                setOrder: set.order,
                excludingWorkoutID: isEditingExistingWorkout ? workout.id : nil
            )
            let row = StrengthSetRowView(
                set: set,
                previousSet: previous,
                allowsDeletion: workoutExercise.sets.count > 1
            )
            row.accessibilityIdentifier = "strength.workout.exercise.\(workoutExercise.id.uuidString).set.\(set.id.uuidString)"
            row.onChange = { [weak self] changedSet in
                self?.replace(changedSet, in: workoutExercise.id)
            }
            row.onDelete = { [weak self] in
                self?.deleteSet(set.id, from: workoutExercise.id)
            }
            setRows.addArrangedSubview(row)
        }

        let addSet = UIButton(type: .system)
        addSet.setTitle(L10n.text("strength.set.add"), for: .normal)
        addSet.titleLabel?.font = WellnarioTypography.font(for: .caption)
        addSet.contentHorizontalAlignment = .left
        addSet.tintColor = WellnarioPalette.cyan
        addSet.accessibilityIdentifier = "strength.workout.add_set.\(workoutExercise.id.uuidString)"
        addSet.heightAnchor.constraint(equalToConstant: WellnarioLayout.textButtonHeight).isActive = true
        addSet.addAction(UIAction { [weak self] _ in self?.addSet(to: workoutExercise.id) }, for: .touchUpInside)

        let divider = UIView()
        divider.backgroundColor = WellnarioPalette.hairline
        divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        let section = UIStackView(
            arrangedSubviews: [header, restLine, columnHeader, setRows, addSet, divider],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        )
        section.accessibilityIdentifier = "strength.workout.exercise.\(workoutExercise.id.uuidString)"
        return section
    }

    private func configureRestButton(_ button: UIButton, seconds: Int) {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = StrengthFormat.rest(seconds)
        configuration.image = UIImage(systemName: "timer")
        configuration.imagePadding = 6
        configuration.contentInsets = .init(top: 7, leading: 10, bottom: 7, trailing: 10)
        configuration.baseForegroundColor = WellnarioPalette.cyan
        configuration.baseBackgroundColor = WellnarioPalette.surfaceElevated
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        button.titleLabel?.font = WellnarioTypography.font(for: .caption)
        button.accessibilityLabel = L10n.text("strength.set.rest")
        button.accessibilityValue = StrengthFormat.rest(seconds)
        button.accessibilityIdentifier = "strength.workout.rest"
        button.heightAnchor.constraint(equalToConstant: WellnarioLayout.fieldMinimumHeight).isActive = true
    }

    private func replace(_ set: StrengthWorkoutSet, in exerciseID: UUID) {
        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == set.id }) else { return }
        var normalizedSet = set
        normalizedSet.restSeconds = workout.exercises[exerciseIndex].restSeconds
        workout.exercises[exerciseIndex].sets[setIndex] = normalizedSet
    }

    private func updateRest(_ restSeconds: Int, for exerciseID: UUID) {
        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        workout.exercises[exerciseIndex].restSeconds = restSeconds
        for setIndex in workout.exercises[exerciseIndex].sets.indices {
            workout.exercises[exerciseIndex].sets[setIndex].restSeconds = restSeconds
        }
        buildContent()
    }

    private func selectRest(for exerciseID: UUID, current: Int) {
        let picker = StrengthRestPickerViewController(initialSeconds: current)
        picker.onSelected = { [weak self] restSeconds in
            self?.updateRest(restSeconds, for: exerciseID)
        }
        presentSheet(picker)
    }

    private func addSet(to exerciseID: UUID) {
        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let existing = workout.exercises[exerciseIndex].sets
        let last = existing.last
        workout.exercises[exerciseIndex].sets.append(StrengthWorkoutSet(
            order: existing.count + 1,
            weight: last?.weight,
            repetitions: last?.repetitions,
            restSeconds: workout.exercises[exerciseIndex].restSeconds ?? 90
        ))
        buildContent()
    }

    private func deleteSet(_ setID: UUID, from exerciseID: UUID) {
        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
              workout.exercises[exerciseIndex].sets.count > 1 else { return }
        workout.exercises[exerciseIndex].sets.removeAll { $0.id == setID }
        for index in workout.exercises[exerciseIndex].sets.indices {
            workout.exercises[exerciseIndex].sets[index].order = index + 1
        }
        buildContent()
    }

    private func reindexExercises() {
        for index in workout.exercises.indices { workout.exercises[index].order = index }
    }

    @objc private func addExercise() {
        let picker = StrengthExercisePickerViewController(
            store: store,
            allowsMultipleSelection: true,
            selectedExerciseIDs: Set(workout.exercises.map(\.exercise.id))
        )
        picker.onExercisesPicked = { [weak self] exercises in
            guard let self else { return }
            let knownIDs = Set(self.workout.exercises.map(\.exercise.id))
            for exercise in exercises where !knownIDs.contains(exercise.id) {
                self.workout.exercises.append(StrengthWorkoutExercise(
                    exercise: exercise,
                    order: self.workout.exercises.count
                ))
            }
            self.buildContent()
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    @objc private func finishWorkout() {
        view.endEditing(true)
        guard !workout.exercises.isEmpty else {
            presentStrengthError(StrengthDataStoreError.invalidWorkout)
            return
        }
        do {
            if isEditingExistingWorkout {
                _ = try store.updateWorkout(workout)
            } else {
                workout.endedAt = Date()
                _ = try store.saveWorkout(workout)
            }
            UIImpactFeedbackGenerator.wellnarioSuccess()
            onWorkoutFinished?()
            navigationController?.popViewController(animated: true)
        } catch {
            presentStrengthError(error)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.durationLabel.text = StrengthFormat.duration(Date().timeIntervalSince(self.workout.startedAt))
            }
        }
    }
}

@MainActor
private final class StrengthRestPickerViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    var onSelected: ((Int) -> Void)?
    private let minutes = Array(0...10)
    private let seconds = [0, 15, 30, 45]
    private let initialSeconds: Int
    private let picker = UIPickerView()

    init(initialSeconds: Int) {
        self.initialSeconds = max(0, initialSeconds)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("strength.rest_picker.title")
        view.backgroundColor = WellnarioPalette.background
        picker.dataSource = self
        picker.delegate = self
        picker.accessibilityIdentifier = "strength.workout.rest.picker"
        view.addForAutoLayout(picker)
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            picker.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            picker.heightAnchor.constraint(equalToConstant: 216)
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.Common.cancel,
            style: .plain,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = WellnarioNavigationButton.item(
            title: L10n.Common.done,
            style: .done,
            target: self,
            action: #selector(done)
        )
        let minute = min(initialSeconds / 60, minutes.last ?? 0)
        let second = initialSeconds % 60
        picker.selectRow(minute, inComponent: 0, animated: false)
        picker.selectRow(nearestSecondIndex(to: second), inComponent: 1, animated: false)
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        component == 0 ? minutes.count : seconds.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        component == 0
            ? L10n.text("strength.rest_picker.minutes", minutes[row])
            : L10n.text("strength.rest_picker.seconds", seconds[row])
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func done() {
        let selected = minutes[picker.selectedRow(inComponent: 0)] * 60
            + seconds[picker.selectedRow(inComponent: 1)]
        onSelected?(selected)
        dismiss(animated: true)
    }

    private func nearestSecondIndex(to value: Int) -> Int {
        seconds.enumerated().min { abs($0.element - value) < abs($1.element - value) }?.offset ?? 0
    }
}

@MainActor
private struct StrengthHeartRateZone {
    let shortLabel: String
    let lowerBound: Double
    let upperBound: Double
    let color: UIColor

    static func estimated(maximum: Double) -> [StrengthHeartRateZone] {
        [
            ("z1", 0.50, 0.60, WellnarioPalette.cyan),
            ("z2", 0.60, 0.70, WellnarioPalette.success),
            ("z3", 0.70, 0.80, WellnarioPalette.yellow),
            ("z4", 0.80, 0.90, WellnarioPalette.orange),
            ("z5", 0.90, 1.00, WellnarioPalette.danger)
        ].map {
            StrengthHeartRateZone(
                shortLabel: L10n.text("strength.heart_rate.zone.\($0.0)"),
                lowerBound: maximum * $0.1,
                upperBound: maximum * $0.2,
                color: $0.3
            )
        }
    }
}

@MainActor
private final class StrengthHeartRateChartView: UIView {
    private var samples: [AppleHealthTimedQuantity] = []
    private var workoutStart = Date()
    private var workoutEnd = Date()
    private var zones: [StrengthHeartRateZone] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(
        samples: [AppleHealthTimedQuantity],
        workoutStart: Date,
        workoutEnd: Date,
        zones: [StrengthHeartRateZone]
    ) {
        self.samples = Self.downsample(samples)
        self.workoutStart = workoutStart
        self.workoutEnd = workoutEnd
        self.zones = zones
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard workoutEnd > workoutStart, !samples.isEmpty else { return }
        let minimum = zones.map(\.lowerBound).min() ?? 60
        let maximum = max(minimum + 10, zones.map(\.upperBound).max() ?? 180)
        let chartRect = rect.inset(by: .init(top: 6, left: 2, bottom: 18, right: 2))
        let duration = workoutEnd.timeIntervalSince(workoutStart)
        let yPosition: (Double) -> CGFloat = { value in
            let boundedValue = min(max(value, minimum), maximum)
            return chartRect.maxY - chartRect.height * CGFloat((boundedValue - minimum) / (maximum - minimum))
        }

        for zone in zones {
            let top = yPosition(zone.upperBound)
            let bottom = yPosition(zone.lowerBound)
            let band = CGRect(
                x: chartRect.minX,
                y: max(chartRect.minY, top),
                width: chartRect.width,
                height: max(0, min(chartRect.maxY, bottom) - max(chartRect.minY, top))
            )
            zone.color.withAlphaComponent(0.11).setFill()
            UIBezierPath(rect: band).fill()
            zone.color.withAlphaComponent(0.33).setStroke()
            let boundary = UIBezierPath()
            boundary.move(to: CGPoint(x: chartRect.minX, y: max(chartRect.minY, min(chartRect.maxY, top))))
            boundary.addLine(to: CGPoint(x: chartRect.maxX, y: max(chartRect.minY, min(chartRect.maxY, top))))
            boundary.lineWidth = 0.7
            boundary.setLineDash([2, 3], count: 2, phase: 0)
            boundary.stroke()
            drawZoneLabel(zone.shortLabel, in: band, color: zone.color)
        }

        let path = UIBezierPath()
        for (index, sample) in samples.enumerated() {
            let progress = min(max(sample.endDate.timeIntervalSince(workoutStart) / duration, 0), 1)
            let point = CGPoint(x: chartRect.minX + chartRect.width * progress, y: yPosition(sample.value))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        WellnarioPalette.fuchsia.setStroke()
        path.lineWidth = 2.5
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()

        let startLabel = StrengthFormat.duration(0)
        let endLabel = StrengthFormat.duration(duration)
        drawAxisLabel(startLabel, at: CGPoint(x: chartRect.minX, y: chartRect.maxY + 3), alignment: .left)
        drawAxisLabel(endLabel, at: CGPoint(x: chartRect.maxX, y: chartRect.maxY + 3), alignment: .right)
    }

    private func drawAxisLabel(_ text: String, at point: CGPoint, alignment: NSTextAlignment) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: WellnarioTypography.font(for: .summaryDetail),
            .foregroundColor: WellnarioPalette.textTertiary
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let originX: CGFloat
        switch alignment {
        case .right: originX = point.x - size.width
        default: originX = point.x
        }
        (text as NSString).draw(at: CGPoint(x: originX, y: point.y), withAttributes: attributes)
    }

    private func drawZoneLabel(_ text: String, in band: CGRect, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: WellnarioTypography.font(for: .summaryDetail),
            .foregroundColor: color.withAlphaComponent(0.95)
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let point = CGPoint(
            x: band.maxX - size.width - 5,
            y: band.midY - size.height / 2
        )
        (text as NSString).draw(at: point, withAttributes: attributes)
    }

    private static func downsample(_ samples: [AppleHealthTimedQuantity]) -> [AppleHealthTimedQuantity] {
        let sorted = samples.sorted { $0.endDate < $1.endDate }
        guard sorted.count > 80,
              let first = sorted.first?.endDate,
              let last = sorted.last?.endDate,
              last > first else { return sorted }
        let interval = last.timeIntervalSince(first) / 60
        var buckets: [[AppleHealthTimedQuantity]] = Array(repeating: [], count: 60)
        for sample in sorted {
            let rawIndex = Int(sample.endDate.timeIntervalSince(first) / interval)
            buckets[min(max(rawIndex, 0), buckets.count - 1)].append(sample)
        }
        return buckets.compactMap { bucket in
            guard let firstSample = bucket.first else { return nil }
            let value = bucket.map(\.value).reduce(0, +) / Double(bucket.count)
            return AppleHealthTimedQuantity(
                startDate: firstSample.startDate,
                endDate: bucket.last?.endDate ?? firstSample.endDate,
                value: value
            )
        }
    }
}

@MainActor
final class StrengthExercisePickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private let store: StrengthDataStore
    private let allowsMultipleSelection: Bool
    private let allowsRenaming: Bool
    private var selectedExerciseIDs: Set<String>
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var exercises: [StrengthExercise] = []
    private var filteredExercises: [StrengthExercise] = []
    private var selectedEquipment: String?
    private var selectedPrimaryMuscle: String?
    private var favoriteExerciseIDs: Set<String> = []
    private var showsFavoritesOnly = false
    private let searchController = UISearchController(searchResultsController: nil)
    private let filterHeader = UIView()
    private let equipmentFilterButton = ChipButton()
    private let primaryMuscleFilterButton = ChipButton()
    private let favoritesFilterButton = UIButton(type: .system)
    private let filterHeaderFixedHeight: CGFloat = 64
    private var filterHeaderHeight: CGFloat = 0
    private var originalContentInset: UIEdgeInsets?
    private var originalVerticalScrollIndicatorInsets: UIEdgeInsets?
    private var originalHorizontalScrollIndicatorInsets: UIEdgeInsets?
    var onExercisesPicked: (([StrengthExercise]) -> Void)?

    init(
        store: StrengthDataStore,
        allowsMultipleSelection: Bool,
        selectedExerciseIDs: Set<String> = [],
        allowsRenaming: Bool = false
    ) {
        self.store = store
        self.allowsMultipleSelection = allowsMultipleSelection
        self.selectedExerciseIDs = selectedExerciseIDs
        self.allowsRenaming = allowsRenaming
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("strength.exercise.picker.title")
        view.backgroundColor = WellnarioPalette.background
        tableView.dataSource = self
        tableView.delegate = self
        view.addForAutoLayout(tableView)
        tableView.pinEdges(to: view)
        tableView.accessibilityIdentifier = "strength.exercise.picker"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 62
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.text("strength.exercise.search")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        configureFilterHeader()
        if allowsMultipleSelection {
            let done = WellnarioNavigationButton.item(
                title: L10n.Common.done,
                style: .done,
                target: self,
                action: #selector(done)
            )
            done.accessibilityIdentifier = "strength.exercise.picker.done"
            navigationItem.rightBarButtonItem = done
        }
        refreshExercises()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let headerHeight = filterHeaderFixedHeight
        view.bringSubviewToFront(filterHeader)
        filterHeader.bringSubviewToFront(equipmentFilterButton)
        filterHeader.bringSubviewToFront(primaryMuscleFilterButton)
        filterHeader.bringSubviewToFront(favoritesFilterButton)
        keepFilterButtonsRounded()

        if originalContentInset == nil {
            originalContentInset = tableView.contentInset
            originalVerticalScrollIndicatorInsets = tableView.verticalScrollIndicatorInsets
            originalHorizontalScrollIndicatorInsets = tableView.horizontalScrollIndicatorInsets
        }
        if abs(filterHeaderHeight - headerHeight) > 0.5 {
            filterHeaderHeight = headerHeight
            var contentInset = originalContentInset ?? .zero
            contentInset.top += headerHeight
            tableView.contentInset = contentInset
            var verticalScrollIndicatorInsets = originalVerticalScrollIndicatorInsets ?? .zero
            verticalScrollIndicatorInsets.top += headerHeight
            tableView.verticalScrollIndicatorInsets = verticalScrollIndicatorInsets
            tableView.horizontalScrollIndicatorInsets = originalHorizontalScrollIndicatorInsets ?? .zero
        }
    }

    private func configureFilterHeader() {
        let filters = UIStackView(
            arrangedSubviews: [equipmentFilterButton, primaryMuscleFilterButton, favoritesFilterButton],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .fill,
            distribution: .fill
        )
        [equipmentFilterButton, primaryMuscleFilterButton].forEach {
            $0.titleLabel?.lineBreakMode = .byTruncatingTail
            $0.semanticContentAttribute = .forceLeftToRight
            $0.showsMenuAsPrimaryAction = true
        }
        equipmentFilterButton.widthAnchor.constraint(equalTo: primaryMuscleFilterButton.widthAnchor).isActive = true
        favoritesFilterButton.widthAnchor.constraint(equalToConstant: WellnarioLayout.minimumTouchTarget).isActive = true
        configureFavoritesFilterButton()
        equipmentFilterButton.accessibilityIdentifier = "strength.exercise.filter.equipment"
        primaryMuscleFilterButton.accessibilityIdentifier = "strength.exercise.filter.primary_muscle"
        favoritesFilterButton.accessibilityIdentifier = "strength.exercise.filter.favorites"
        filterHeader.addForAutoLayout(filters)
        filters.pinEdges(
            to: filterHeader,
            insets: .init(
                top: WellnarioSpacing.xxSmall,
                leading: WellnarioSpacing.small,
                bottom: WellnarioSpacing.xxSmall,
                trailing: WellnarioSpacing.small
            )
        )
        filterHeader.backgroundColor = WellnarioPalette.background
        view.addForAutoLayout(filterHeader)
        filterHeader.heightAnchor.constraint(equalToConstant: filterHeaderFixedHeight).isActive = true
        NSLayoutConstraint.activate([
            filterHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterHeader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        ])
        keepFilterButtonsRounded()
        configureFilterMenus()
    }

    private func keepFilterButtonsRounded() {
        [equipmentFilterButton, primaryMuscleFilterButton].forEach {
            $0.layer.cornerRadius = WellnarioRadius.control
            $0.layer.cornerCurve = .continuous
            $0.layer.masksToBounds = true
        }
    }

    private func configureFavoritesFilterButton() {
        favoritesFilterButton.contentHorizontalAlignment = .center
        favoritesFilterButton.contentVerticalAlignment = .center
        favoritesFilterButton.imageView?.contentMode = .scaleAspectFit
        favoritesFilterButton.layer.cornerRadius = WellnarioRadius.control
        favoritesFilterButton.layer.cornerCurve = .continuous
        favoritesFilterButton.layer.borderWidth = 1
        favoritesFilterButton.layer.masksToBounds = true
        favoritesFilterButton.accessibilityLabel = L10n.text("strength.filter.favorites")
        favoritesFilterButton.addTarget(self, action: #selector(toggleFavoritesFilter), for: .touchUpInside)
    }

    private func configureFilterMenus() {
        configureFilter(
            button: equipmentFilterButton,
            titleKey: "strength.filter.equipment",
            allTitleKey: "strength.filter.all_equipment",
            values: Array(Set(exercises.compactMap(\.equipment))).sorted(),
            selectedValue: selectedEquipment,
            localizationKey: "strength.equipment"
        ) { [weak self] value in
            self?.selectedEquipment = value
        }
        configureFilter(
            button: primaryMuscleFilterButton,
            titleKey: "strength.filter.primary_muscle",
            allTitleKey: "strength.filter.all_primary_muscles",
            values: Array(Set(exercises.flatMap(\.primaryMuscles))).sorted(),
            selectedValue: selectedPrimaryMuscle,
            localizationKey: "strength.muscle"
        ) { [weak self] value in
            self?.selectedPrimaryMuscle = value
        }
        favoritesFilterButton.setImage(
            UIImage(systemName: showsFavoritesOnly ? "star.fill" : "star"),
            for: .normal
        )
        favoritesFilterButton.backgroundColor = showsFavoritesOnly
            ? WellnarioPalette.fuchsia.withAlphaComponent(0.18)
            : WellnarioPalette.surfaceElevated
        favoritesFilterButton.layer.borderColor = (showsFavoritesOnly
            ? WellnarioPalette.fuchsia.withAlphaComponent(0.68)
            : WellnarioPalette.hairline
        ).cgColor
        favoritesFilterButton.tintColor = showsFavoritesOnly
            ? WellnarioPalette.fuchsia
            : WellnarioPalette.textSecondary
        favoritesFilterButton.accessibilityValue = showsFavoritesOnly
            ? L10n.text("strength.filter.favorites.on")
            : L10n.text("strength.filter.favorites.off")
    }

    private func configureFilter(
        button: ChipButton,
        titleKey: String,
        allTitleKey: String,
        values: [String],
        selectedValue: String?,
        localizationKey: String,
        onSelection: @escaping (String?) -> Void
    ) {
        let title = selectedValue.map { L10n.text("\(localizationKey).\($0)") } ?? L10n.text(titleKey)
        button.setTitle(title, for: .normal)
        button.isSelected = selectedValue != nil
        let allAction = UIAction(
            title: L10n.text(allTitleKey),
            state: selectedValue == nil ? .on : .off
        ) { [weak self] _ in
            onSelection(nil)
            self?.configureFilterMenus()
            self?.applyFilters()
        }
        let actions = values.map { value in
            UIAction(
                title: L10n.text("\(localizationKey).\(value)"),
                state: selectedValue == value ? .on : .off
            ) { [weak self] _ in
                onSelection(value)
                self?.configureFilterMenus()
                self?.applyFilters()
            }
        }
        button.menu = UIMenu(children: [allAction] + actions)
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredExercises.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let reuseIdentifier = StrengthExercisePickerCell.reuseIdentifier
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier) as? StrengthExercisePickerCell
            ?? StrengthExercisePickerCell(style: .subtitle, reuseIdentifier: reuseIdentifier)
        let exercise = filteredExercises[indexPath.row]
        let details = exercise.primaryMuscles.map { L10n.text("strength.muscle.\($0)") }
        cell.configure(
            exerciseID: exercise.id,
            title: exercise.localizedName(language: LocalizationManager.shared.language),
            detail: details.joined(separator: " · "),
            isFavorite: favoriteExerciseIDs.contains(exercise.id),
            isSelected: selectedExerciseIDs.contains(exercise.id),
            onFavorite: { [weak self] in self?.toggleFavorite(exerciseID: exercise.id) }
        )
        cell.accessibilityIdentifier = "strength.exercise.\(exercise.id)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let exercise = filteredExercises[indexPath.row]
        guard !allowsRenaming else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        if allowsMultipleSelection {
            if selectedExerciseIDs.contains(exercise.id) {
                selectedExerciseIDs.remove(exercise.id)
            } else {
                selectedExerciseIDs.insert(exercise.id)
            }
            tableView.reloadRows(at: [indexPath], with: .none)
        } else {
            onExercisesPicked?([exercise])
            navigationController?.popViewController(animated: true)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard allowsRenaming else { return nil }
        let exercise = filteredExercises[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: L10n.Common.delete) { [weak self] _, _, completion in
            self?.hide(exercise: exercise)
            completion(true)
        }
        let edit = UIContextualAction(style: .normal, title: L10n.Common.edit) { [weak self] _, _, completion in
            self?.presentRename(for: exercise)
            completion(true)
        }
        edit.backgroundColor = WellnarioPalette.cyan
        return UISwipeActionsConfiguration(actions: [delete, edit])
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        applyFilters(query: query)
    }

    private func applyFilters(query: String? = nil) {
        let searchQuery = query ?? (searchController.searchBar.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        filteredExercises = exercises.filter { exercise in
            let matchesSearch = searchQuery.isEmpty || ([exercise.nameEnglish, exercise.nameSpanish]
                + [exercise.customName].compactMap { $0 }
                + exercise.primaryMuscles + exercise.secondaryMuscles)
                .contains(where: {
                    $0.range(of: searchQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            })
            let matchesEquipment = selectedEquipment == nil || exercise.equipment == selectedEquipment
            let matchesPrimaryMuscle = selectedPrimaryMuscle.map {
                exercise.primaryMuscles.contains($0)
            } ?? true
            let matchesFavorites = !showsFavoritesOnly || favoriteExerciseIDs.contains(exercise.id)
            return matchesSearch && matchesEquipment && matchesPrimaryMuscle && matchesFavorites
        }
        tableView.reloadData()
    }

    @objc private func toggleFavoritesFilter() {
        showsFavoritesOnly.toggle()
        configureFilterMenus()
        applyFilters()
    }

    private func toggleFavorite(exerciseID: String) {
        let isFavorite = !favoriteExerciseIDs.contains(exerciseID)
        do {
            try store.setExerciseFavorite(id: exerciseID, isFavorite: isFavorite)
            if isFavorite {
                favoriteExerciseIDs.insert(exerciseID)
            } else {
                favoriteExerciseIDs.remove(exerciseID)
            }
            UISelectionFeedbackGenerator().selectionChanged()
            applyFilters()
        } catch {
            presentStrengthError(error)
        }
    }

    private func refreshExercises() {
        do {
            let language = LocalizationManager.shared.language
            exercises = try store.fetchExercises().sorted {
                $0.localizedName(language: language)
                    .localizedCaseInsensitiveCompare($1.localizedName(language: language)) == .orderedAscending
            }
            favoriteExerciseIDs = try store.fetchFavoriteExerciseIDs()
            configureFilterMenus()
            applyFilters()
        } catch {
            presentStrengthError(error)
        }
    }

    private func presentRename(for exercise: StrengthExercise) {
        let alert = UIAlertController(
            title: L10n.text("strength.exercise.rename.title"),
            message: L10n.text("strength.exercise.rename.message"),
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.text = exercise.customName ?? exercise.localizedName(language: LocalizationManager.shared.language)
            textField.autocapitalizationType = .words
            textField.accessibilityIdentifier = "strength.exercise.rename.field"
        }
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        if exercise.customName != nil {
            alert.addAction(UIAlertAction(title: L10n.text("strength.exercise.rename.restore"), style: .destructive) { [weak self] _ in
                self?.saveCustomName(nil, for: exercise.id)
            })
        }
        alert.addAction(UIAlertAction(title: L10n.Common.save, style: .default) { [weak self, weak alert] _ in
            self?.saveCustomName(alert?.textFields?.first?.text, for: exercise.id)
        })
        present(alert, animated: true)
    }

    private func saveCustomName(_ name: String?, for exerciseID: String) {
        do {
            try store.setExerciseCustomName(id: exerciseID, name: name)
            UIImpactFeedbackGenerator.wellnarioSuccess()
            refreshExercises()
        } catch {
            presentStrengthError(error)
        }
    }

    private func hide(exercise: StrengthExercise) {
        do {
            try store.hideExercise(id: exercise.id)
            favoriteExerciseIDs.remove(exercise.id)
            selectedExerciseIDs.remove(exercise.id)
            UIImpactFeedbackGenerator.wellnarioSuccess()
            refreshExercises()
        } catch {
            presentStrengthError(error)
        }
    }

    @objc private func done() {
        let picked = exercises.filter { selectedExerciseIDs.contains($0.id) }
        onExercisesPicked?(picked)
        navigationController?.popViewController(animated: true)
    }
}

@MainActor
private final class StrengthExercisePickerCell: UITableViewCell {
    static let reuseIdentifier = "strength.exercise.cell"

    private let selectionImageView = UIImageView()
    private let favoriteButton = UIButton(type: .system)
    private var onFavorite: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(
        exerciseID: String,
        title: String,
        detail: String,
        isFavorite: Bool,
        isSelected: Bool,
        onFavorite: @escaping () -> Void
    ) {
        textLabel?.font = WellnarioTypography.font(for: .secondary)
        textLabel?.textColor = WellnarioPalette.textPrimary
        textLabel?.numberOfLines = 2
        textLabel?.text = title
        detailTextLabel?.font = WellnarioTypography.font(for: .caption)
        detailTextLabel?.textColor = WellnarioPalette.textSecondary
        detailTextLabel?.numberOfLines = 2
        detailTextLabel?.text = detail
        self.onFavorite = onFavorite
        selectionImageView.image = isSelected ? UIImage(systemName: "checkmark") : nil
        selectionImageView.tintColor = WellnarioPalette.cyan
        favoriteButton.setImage(UIImage(systemName: isFavorite ? "star.fill" : "star"), for: .normal)
        favoriteButton.tintColor = isFavorite ? WellnarioPalette.fuchsia : WellnarioPalette.textTertiary
        favoriteButton.accessibilityLabel = isFavorite
            ? L10n.text("strength.exercise.favorite.selected", title)
            : L10n.text("strength.exercise.favorite.add", title)
        favoriteButton.accessibilityValue = isFavorite
            ? L10n.text("strength.filter.favorites.on")
            : L10n.text("strength.filter.favorites.off")
        favoriteButton.accessibilityIdentifier = "strength.exercise.favorite.\(exerciseID)"
    }

    private func setUp() {
        selectionStyle = .default
        selectionImageView.contentMode = .scaleAspectFit
        selectionImageView.widthAnchor.constraint(equalToConstant: 18).isActive = true
        favoriteButton.widthAnchor.constraint(equalToConstant: 38).isActive = true
        favoriteButton.heightAnchor.constraint(equalToConstant: WellnarioLayout.minimumTouchTarget).isActive = true
        favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
        let accessory = UIStackView(
            arrangedSubviews: [selectionImageView, favoriteButton],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .center
        )
        accessory.frame = CGRect(x: 0, y: 0, width: 64, height: WellnarioLayout.minimumTouchTarget)
        accessoryView = accessory
    }

    @objc private func favoriteTapped() { onFavorite?() }
}

@MainActor
private final class StrengthSetColumnHeaderView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        let labels = [
            header("strength.set.header.number"),
            header("strength.set.header.previous"),
            header("strength.set.header.weight"),
            header("strength.set.header.reps"),
            header("strength.set.header.completed")
        ]
        labels[0].widthAnchor.constraint(equalToConstant: 42).isActive = true
        labels[1].widthAnchor.constraint(equalToConstant: 68).isActive = true
        labels[2].widthAnchor.constraint(equalToConstant: 46).isActive = true
        labels[3].widthAnchor.constraint(equalToConstant: 46).isActive = true
        labels[4].widthAnchor.constraint(equalToConstant: 32).isActive = true
        let stack = UIStackView(arrangedSubviews: labels, axis: .horizontal, spacing: 6, alignment: .center)
        stack.distribution = .fill
        addForAutoLayout(stack)
        stack.pinEdges(to: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func header(_ key: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.summaryDetail, color: WellnarioPalette.textTertiary)
        label.text = L10n.text(key).uppercased()
        label.textAlignment = .center
        return label
    }
}

@MainActor
private final class StrengthSetRowView: UIView {
    var onChange: ((StrengthWorkoutSet) -> Void)?
    var onDelete: (() -> Void)?
    private var set: StrengthWorkoutSet
    private let previousSet: StrengthPreviousSet?
    private let setKindButton = UIButton(type: .system)
    private let previousLabel = UILabel()
    private let weightField = UITextField()
    private let repetitionsField = UITextField()
    private let completedButton = UIButton(type: .system)
    private let allowsDeletion: Bool

    init(
        set: StrengthWorkoutSet,
        previousSet: StrengthPreviousSet?,
        allowsDeletion: Bool = true
    ) {
        self.set = set
        self.previousSet = previousSet
        self.allowsDeletion = allowsDeletion
        super.init(frame: .zero)
        setUp()
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        [weightField, repetitionsField].forEach(configureField)
        weightField.keyboardType = .decimalPad
        repetitionsField.keyboardType = .numberPad
        weightField.accessibilityLabel = L10n.text("strength.set.weight")
        repetitionsField.accessibilityLabel = L10n.text("strength.set.reps")
        [weightField, repetitionsField].forEach {
            $0.addTarget(self, action: #selector(fieldsChanged), for: [.editingDidEnd, .editingDidEndOnExit])
        }

        configureSetKindButton()
        setKindButton.widthAnchor.constraint(equalToConstant: 42).isActive = true
        previousLabel.applyWellnarioStyle(.summaryDetail, color: WellnarioPalette.textSecondary)
        previousLabel.textAlignment = .center
        previousLabel.numberOfLines = 2
        previousLabel.widthAnchor.constraint(equalToConstant: 68).isActive = true
        weightField.widthAnchor.constraint(equalToConstant: 46).isActive = true
        repetitionsField.widthAnchor.constraint(equalToConstant: 46).isActive = true

        completedButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
        completedButton.addTarget(self, action: #selector(toggleCompleted), for: .touchUpInside)
        let stack = UIStackView(
            arrangedSubviews: [setKindButton, previousLabel, weightField, repetitionsField, completedButton],
            axis: .horizontal,
            spacing: 6,
            alignment: .center
        )
        addForAutoLayout(stack)
        stack.pinEdges(to: self)
        if allowsDeletion {
            let deleteSwipe = UISwipeGestureRecognizer(target: self, action: #selector(deleteWithSwipe))
            deleteSwipe.direction = .left
            addGestureRecognizer(deleteSwipe)
            accessibilityCustomActions = [
                UIAccessibilityCustomAction(
                    name: L10n.text("strength.set.delete"),
                    target: self,
                    selector: #selector(deleteWithAccessibilityAction)
                )
            ]
        }
    }

    private func configureField(_ field: UITextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = WellnarioTypography.font(for: .caption)
        field.textColor = WellnarioPalette.textPrimary
        field.textAlignment = .center
        field.backgroundColor = WellnarioPalette.surfaceElevated
        field.applyContinuousCorners(8)
        field.heightAnchor.constraint(equalToConstant: WellnarioLayout.fieldMinimumHeight).isActive = true
        field.adjustsFontForContentSizeCategory = true
    }

    private func configureSetKindButton() {
        setKindButton.titleLabel?.font = WellnarioTypography.font(for: .caption)
        setKindButton.backgroundColor = WellnarioPalette.surfaceElevated
        setKindButton.tintColor = WellnarioPalette.textPrimary
        setKindButton.applyContinuousCorners(8)
        setKindButton.heightAnchor.constraint(equalToConstant: WellnarioLayout.fieldMinimumHeight).isActive = true
        setKindButton.showsMenuAsPrimaryAction = true
        setKindButton.accessibilityLabel = L10n.text("strength.set.kind")
    }

    private func render() {
        setKindButton.setTitle(setKindTitle, for: .normal)
        configureSetKindMenu()
        previousLabel.text = previousSet?.weight.map { "\(StrengthFormat.decimal($0)) kg" } ?? "—"
        weightField.text = set.weight.map(StrengthFormat.decimal)
        repetitionsField.text = set.repetitions.map(String.init)
        completedButton.setImage(
            UIImage(systemName: set.completedAt == nil ? "circle" : "checkmark.circle.fill"),
            for: .normal
        )
        completedButton.tintColor = set.completedAt == nil ? WellnarioPalette.textTertiary : WellnarioPalette.cyan
        completedButton.accessibilityLabel = L10n.text("strength.set.completed")
        completedButton.accessibilityValue = set.completedAt == nil ? L10n.text("strength.set.pending") : L10n.text("strength.set.done")
    }

    @objc private func fieldsChanged() {
        set.weight = StrengthFormat.parseDecimal(weightField.text)
        set.repetitions = Int(repetitionsField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        onChange?(set)
    }

    private var setKindTitle: String {
        if set.isWarmup { return L10n.text("strength.set.warmup.short") }
        if set.isFailure { return L10n.text("strength.set.failure.short") }
        if set.isDropSet { return L10n.text("strength.set.drop.short") }
        return "\(set.order)"
    }

    private func configureSetKindMenu() {
        let normal = UIAction(
            title: L10n.text("strength.set.kind.normal"),
            state: !set.isWarmup && !set.isFailure && !set.isDropSet ? .on : .off
        ) { [weak self] _ in
            self?.setKind(.normal)
        }
        let warmup = UIAction(
            title: L10n.text("strength.set.warmup"),
            state: set.isWarmup ? .on : .off
        ) { [weak self] _ in
            self?.setKind(.warmup)
        }
        let failure = UIAction(
            title: L10n.text("strength.set.failure"),
            state: set.isFailure ? .on : .off
        ) { [weak self] _ in
            self?.setKind(.failure)
        }
        let drop = UIAction(
            title: L10n.text("strength.set.drop"),
            state: set.isDropSet ? .on : .off
        ) { [weak self] _ in
            self?.setKind(.drop)
        }
        var actions = [normal, warmup, failure, drop]
        if allowsDeletion {
            actions.append(UIAction(
                title: L10n.text("strength.set.delete"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.onDelete?()
            })
        }
        setKindButton.menu = UIMenu(children: actions)
    }

    private func setKind(_ kind: SetKind) {
        set.isWarmup = kind == .warmup
        set.isFailure = kind == .failure
        set.isDropSet = kind == .drop
        render()
        onChange?(set)
    }

    @objc private func toggleCompleted() {
        set.completedAt = set.completedAt == nil ? Date() : nil
        render()
        onChange?(set)
    }

    @objc private func deleteWithSwipe() {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        feedback.impactOccurred()
        onDelete?()
    }

    @objc private func deleteWithAccessibilityAction() -> Bool {
        deleteWithSwipe()
        return true
    }

    private enum SetKind {
        case normal
        case warmup
        case failure
        case drop
    }
}

@MainActor
final class StrengthWorkoutsViewController: UITableViewController {
    private let store: StrengthDataStore
    private let appleHealthService: AppleHealthSyncing?
    private var workouts: [StrengthWorkoutSummary] = []

    init(store: StrengthDataStore, appleHealthService: AppleHealthSyncing? = nil) {
        self.store = store
        self.appleHealthService = appleHealthService
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("strength.workouts.title")
        view.backgroundColor = WellnarioPalette.background
        tableView.backgroundColor = WellnarioPalette.background
        tableView.accessibilityIdentifier = "strength.workouts"
        let newWorkoutButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .done,
            target: self,
            action: #selector(createWorkout)
        )
        newWorkoutButton.tintColor = WellnarioPalette.cyan
        newWorkoutButton.accessibilityIdentifier = "strength.workouts.new"
        navigationItem.rightBarButtonItem = newWorkoutButton
        reloadWorkouts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadWorkouts()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        workouts.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "strength.workouts.cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "strength.workouts.cell")
        let workout = workouts[indexPath.row]
        cell.textLabel?.font = WellnarioTypography.font(for: .secondary)
        cell.textLabel?.textColor = WellnarioPalette.textPrimary
        cell.textLabel?.text = workout.title
        cell.detailTextLabel?.font = WellnarioTypography.font(for: .caption)
        cell.detailTextLabel?.textColor = WellnarioPalette.textSecondary
        cell.detailTextLabel?.text = L10n.text(
            "strength.workouts.summary",
            Self.dateFormatter.string(from: workout.startedAt),
            workout.exerciseCount,
            StrengthFormat.decimal(Decimal(workout.totalVolume))
        )
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "strength.workout.\(workout.id.uuidString)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let summary = workouts[indexPath.row]
        do {
            let workout = try store.fetchWorkout(id: summary.id)
            let controller = StrengthWorkoutViewController(
                store: store,
                workout: workout,
                isEditingExistingWorkout: true,
                appleHealthService: appleHealthService
            )
            controller.onWorkoutFinished = { [weak self] in self?.reloadWorkouts() }
            navigationController?.pushViewController(controller, animated: true)
        } catch {
            presentStrengthError(error)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let workout = workouts[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: L10n.Common.delete) { [weak self] _, _, completion in
            self?.delete(workout: workout)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard workouts.isEmpty else { return nil }
        let label = UILabel()
        label.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = L10n.text("strength.workouts.empty")
        return label
    }

    @objc private func createWorkout() {
        let sheet = UIAlertController(
            title: L10n.text("strength.workouts.new"),
            message: L10n.text("strength.workouts.new.message"),
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: L10n.text("strength.start.empty"), style: .default) { [weak self] _ in
            self?.startEmptyWorkout()
        })
        do {
            for template in try store.fetchTemplates() {
                sheet.addAction(UIAlertAction(title: templateDisplayName(template), style: .default) { [weak self] _ in
                    self?.start(template: template)
                })
            }
        } catch {
            presentStrengthError(error)
            return
        }
        sheet.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(sheet, animated: true)
    }

    private func startEmptyWorkout() {
        let controller = StrengthWorkoutViewController(
            store: store,
            workout: store.workout(from: nil, title: L10n.text("strength.workout.untitled")),
            appleHealthService: appleHealthService
        )
        controller.onWorkoutFinished = { [weak self] in self?.reloadWorkouts() }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func start(template: StrengthWorkoutTemplate) {
        let controller = StrengthWorkoutViewController(
            store: store,
            workout: store.workout(from: template, title: templateDisplayName(template)),
            appleHealthService: appleHealthService
        )
        controller.onWorkoutFinished = { [weak self] in self?.reloadWorkouts() }
        navigationController?.pushViewController(controller, animated: true)
    }

    private func reloadWorkouts() {
        do {
            workouts = try store.fetchWorkoutSummaries()
            tableView.reloadData()
        } catch {
            presentStrengthError(error)
        }
    }

    private func delete(workout: StrengthWorkoutSummary) {
        do {
            try store.deleteWorkout(id: workout.id)
            UIImpactFeedbackGenerator.wellnarioSuccess()
            reloadWorkouts()
        } catch {
            presentStrengthError(error)
        }
    }

    private func templateDisplayName(_ template: StrengthWorkoutTemplate) -> String {
        template.nameKey.map { L10n.text($0) } ?? template.name
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

@MainActor
final class StrengthTemplatesViewController: UITableViewController {
    private let store: StrengthDataStore
    private var templates: [StrengthWorkoutTemplate] = []

    init(store: StrengthDataStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("strength.templates.title")
        view.backgroundColor = WellnarioPalette.background
        tableView.backgroundColor = WellnarioPalette.background
        tableView.accessibilityIdentifier = "strength.templates"
        let createTemplateButton = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .done,
            target: self,
            action: #selector(createTemplate)
        )
        createTemplateButton.tintColor = WellnarioPalette.cyan
        createTemplateButton.accessibilityIdentifier = "strength.templates.create"
        navigationItem.rightBarButtonItem = createTemplateButton
        reloadTemplates()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadTemplates()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        templates.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "strength.templates.cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "strength.templates.cell")
        let template = templates[indexPath.row]
        cell.textLabel?.font = WellnarioTypography.font(for: .secondary)
        cell.textLabel?.textColor = WellnarioPalette.textPrimary
        cell.textLabel?.text = templateDisplayName(template)
        cell.detailTextLabel?.font = WellnarioTypography.font(for: .caption)
        cell.detailTextLabel?.textColor = WellnarioPalette.textSecondary
        cell.detailTextLabel?.text = L10n.text("strength.templates.exercise_count", template.exercises.count)
        let startButton = UIButton(type: .system)
        startButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        startButton.tintColor = WellnarioPalette.cyan
        startButton.accessibilityLabel = L10n.text("strength.templates.start", templateDisplayName(template))
        startButton.addAction(UIAction { [weak self] _ in self?.start(template: template) }, for: .touchUpInside)
        cell.accessoryView = startButton
        cell.accessibilityIdentifier = "strength.template.\(template.id.uuidString)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let editor = StrengthTemplateEditorViewController(store: store, template: templates[indexPath.row])
        navigationController?.pushViewController(editor, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let template = templates[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: L10n.Common.delete) { [weak self] _, _, completion in
            self?.delete(template: template)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard templates.isEmpty else { return nil }
        let label = UILabel()
        label.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = L10n.text("strength.templates.empty")
        return label
    }

    @objc private func createTemplate() {
        navigationController?.pushViewController(StrengthTemplateEditorViewController(store: store), animated: true)
    }

    private func start(template: StrengthWorkoutTemplate) {
        let controller = StrengthWorkoutViewController(
            store: store,
            workout: store.workout(from: template, title: templateDisplayName(template))
        )
        navigationController?.pushViewController(controller, animated: true)
    }

    private func delete(template: StrengthWorkoutTemplate) {
        do {
            try store.deleteTemplate(id: template.id)
            UIImpactFeedbackGenerator.wellnarioSuccess()
            reloadTemplates()
        } catch {
            presentStrengthError(error)
        }
    }

    private func reloadTemplates() {
        do {
            templates = try store.fetchTemplates()
            tableView.reloadData()
        } catch {
            presentStrengthError(error)
        }
    }

    private func templateDisplayName(_ template: StrengthWorkoutTemplate) -> String {
        template.nameKey.map { L10n.text($0) } ?? template.name
    }
}

@MainActor
final class StrengthBodyMetricsViewController: UITableViewController {
    private let store: StrengthDataStore
    private var metrics: [StrengthBodyMetric] = []

    init(store: StrengthDataStore) {
        self.store = store
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("strength.metrics.title")
        view.backgroundColor = WellnarioPalette.background
        tableView.backgroundColor = WellnarioPalette.background
        tableView.accessibilityIdentifier = "strength.metrics"
        let newMetricButton = WellnarioNavigationButton.item(
            title: L10n.text("strength.metrics.new"),
            style: .done,
            target: self,
            action: #selector(createMetric)
        )
        newMetricButton.accessibilityIdentifier = "strength.metrics.new"
        navigationItem.rightBarButtonItem = newMetricButton
        reloadMetrics()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadMetrics()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { metrics.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "strength.metrics.cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "strength.metrics.cell")
        let metric = metrics[indexPath.row]
        cell.textLabel?.font = WellnarioTypography.font(for: .secondary)
        cell.textLabel?.textColor = WellnarioPalette.textPrimary
        cell.textLabel?.text = metric.name
        cell.detailTextLabel?.font = WellnarioTypography.font(for: .caption)
        cell.detailTextLabel?.textColor = WellnarioPalette.textSecondary
        cell.detailTextLabel?.text = L10n.text(
            "strength.metrics.summary",
            StrengthFormat.decimal(metric.value),
            metric.unit ?? "",
            Self.dateFormatter.string(from: metric.measuredAt)
        )
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let metric = metrics[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: L10n.Common.delete) { [weak self] _, _, completion in
            self?.delete(metric: metric)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard metrics.isEmpty else { return nil }
        let label = UILabel()
        label.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = L10n.text("strength.metrics.empty")
        return label
    }

    @objc private func createMetric() {
        navigationController?.pushViewController(StrengthBodyMetricEditorViewController(store: store), animated: true)
    }

    private func delete(metric: StrengthBodyMetric) {
        do {
            try store.deleteBodyMetric(id: metric.id)
            UIImpactFeedbackGenerator.wellnarioSuccess()
            reloadMetrics()
        } catch {
            presentStrengthError(error)
        }
    }

    private func reloadMetrics() {
        do {
            metrics = try store.fetchBodyMetrics()
            tableView.reloadData()
        } catch {
            presentStrengthError(error)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

@MainActor
private final class StrengthBodyMetricEditorViewController: WellnessScrollViewController {
    private let store: StrengthDataStore
    private let nameField = FormFieldView()
    private let valueField = FormFieldView()
    private let unitField = FormFieldView()
    private let datePicker = UIDatePicker()

    init(store: StrengthDataStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("strength.metrics.new")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = WellnarioNavigationButton.item(
            title: L10n.Common.save,
            style: .done,
            target: self,
            action: #selector(save)
        )
        nameField.configure(title: L10n.text("strength.metrics.name"), placeholder: L10n.text("strength.metrics.name.placeholder"), text: nil, contentType: .name)
        valueField.configure(title: L10n.text("strength.metrics.value"), placeholder: "0", text: nil)
        valueField.textField.keyboardType = .decimalPad
        unitField.configure(title: L10n.text("strength.metrics.unit"), placeholder: L10n.text("strength.metrics.unit.placeholder"), text: nil)
        datePicker.datePickerMode = .date
        datePicker.locale = LocalizationManager.shared.locale
        datePicker.tintColor = WellnarioPalette.cyan
        datePicker.accessibilityLabel = L10n.text("strength.metrics.date")
        contentStack.addArrangedSubview(makeCard(containing: nameField))
        contentStack.addArrangedSubview(makeCard(containing: valueField))
        contentStack.addArrangedSubview(makeCard(containing: unitField))
        let dateStack = UIStackView(arrangedSubviews: [dateLabel(), datePicker], axis: .vertical, spacing: WellnarioSpacing.xSmall)
        contentStack.addArrangedSubview(makeCard(containing: dateStack))
    }

    @objc private func save() {
        view.endEditing(true)
        guard let value = StrengthFormat.parseDecimal(valueField.textField.text) else {
            presentStrengthError(StrengthDataStoreError.invalidBodyMetric)
            return
        }
        do {
            _ = try store.saveBodyMetric(StrengthBodyMetricDraft(
                name: nameField.textField.text ?? "",
                value: value,
                unit: unitField.textField.text,
                measuredAt: datePicker.date
            ))
            UIImpactFeedbackGenerator.wellnarioSuccess()
            navigationController?.popViewController(animated: true)
        } catch {
            presentStrengthError(error)
        }
    }

    private func dateLabel() -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        label.text = L10n.text("strength.metrics.date")
        return label
    }
}

@MainActor
final class StrengthReportsViewController: WellnessScrollViewController {
    private let store: StrengthDataStore

    init(store: StrengthDataStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("strength.reports.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "strength.reports"
        buildContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        buildContent()
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        do {
            let report = try store.fetchReport()
            guard !report.sessionVolumes.isEmpty else {
                let label = UILabel()
                label.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
                label.textAlignment = .center
                label.numberOfLines = 0
                label.text = L10n.text("strength.reports.empty")
                contentStack.addArrangedSubview(makeCard(containing: label))
                return
            }

            let total = report.sessionVolumes.reduce(0) { $0 + $1.volume }
            let volumeCard = MetricCardView()
            volumeCard.configure(
                title: L10n.text("strength.reports.session_volume"),
                symbolName: "chart.line.uptrend.xyaxis",
                value: StrengthFormat.decimal(Decimal(total)),
                unit: " kg",
                status: L10n.text("strength.reports.sessions", report.sessionVolumes.count),
                tone: .accent
            )
            let sparkline = SparklineView()
            sparkline.values = report.sessionVolumes.map(\.volume)
            sparkline.lineColor = WellnarioPalette.cyan
            sparkline.includesZeroBaseline = true
            sparkline.heightAnchor.constraint(equalToConstant: 72).isActive = true
            sparkline.accessibilityLabel = L10n.text("strength.reports.session_volume")
            volumeCard.setVisualization(sparkline)
            contentStack.addArrangedSubview(volumeCard)

            contentStack.addArrangedSubview(reportCard(
                title: L10n.text("strength.reports.exercise_volume"),
                subtitle: L10n.text("strength.reports.exercise_volume.detail"),
                points: Array(report.exerciseVolumes.prefix(6))
            ))

            let average = MetricCardView()
            average.configure(
                title: L10n.text("strength.reports.average_set_volume"),
                symbolName: "scalemass.fill",
                value: StrengthFormat.decimal(Decimal(report.averageSetVolume)),
                unit: " kg",
                status: L10n.text("strength.reports.average_set_volume.detail"),
                tone: .neutral
            )
            let averageGraphic = StrengthBarListView()
            averageGraphic.configure(points: [StrengthReportPoint(id: "average", label: "", value: report.averageSetVolume)])
            average.setVisualization(averageGraphic)
            contentStack.addArrangedSubview(average)

            contentStack.addArrangedSubview(reportCard(
                title: L10n.text("strength.reports.muscles"),
                subtitle: L10n.text("strength.reports.muscles.detail"),
                points: Array(report.muscleVolumes.prefix(6))
            ))
        } catch {
            presentStrengthError(error)
        }
    }

    private func reportCard(title: String, subtitle: String, points: [StrengthReportPoint]) -> PremiumCardView {
        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = title
        let subtitleLabel = UILabel()
        subtitleLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        subtitleLabel.text = subtitle
        subtitleLabel.numberOfLines = 2
        let bars = StrengthBarListView()
        bars.configure(points: points)
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, bars], axis: .vertical, spacing: WellnarioSpacing.xSmall)
        return makeCard(containing: stack)
    }
}

@MainActor
private final class StrengthBarListView: UIView {
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .vertical
        stack.spacing = WellnarioSpacing.xSmall
        addForAutoLayout(stack)
        stack.pinEdges(to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(points: [StrengthReportPoint]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let maximum = points.map(\.value).max(), maximum > 0 else {
            let empty = UILabel()
            empty.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
            empty.text = L10n.text("strength.reports.no_volume")
            stack.addArrangedSubview(empty)
            return
        }
        for point in points {
            let label = UILabel()
            label.applyWellnarioStyle(.caption, color: WellnarioPalette.textPrimary)
            label.text = point.label
            label.lineBreakMode = .byTruncatingTail
            let value = UILabel()
            value.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
            value.text = StrengthFormat.decimal(Decimal(point.value)) + " kg"
            value.textAlignment = .right
            value.setContentCompressionResistancePriority(.required, for: .horizontal)
            let top = UIStackView(arrangedSubviews: [label, UIView(), value], axis: .horizontal, spacing: WellnarioSpacing.xxSmall)
            let progress = UIProgressView(progressViewStyle: .default)
            progress.progressTintColor = WellnarioPalette.cyan
            progress.trackTintColor = WellnarioPalette.surfaceElevated
            progress.progress = Float(point.value / maximum)
            progress.heightAnchor.constraint(equalToConstant: 6).isActive = true
            progress.applyContinuousCorners(3)
            stack.addArrangedSubview(UIStackView(arrangedSubviews: [top, progress], axis: .vertical, spacing: 4))
        }
    }
}

@MainActor
enum StrengthFormat {
    static func decimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }

    static func parseDecimal(_ text: String?) -> Decimal? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = text.replacingOccurrences(of: separator, with: ".")
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), value >= 0 else {
            return nil
        }
        return value
    }

    static func rest(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let remainder = max(0, seconds) % 60
        return "\(minutes):\(String(format: "%02d", remainder))"
    }

    static func parseRest(_ text: String?) -> Int? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let seconds = Int(text), seconds >= 0 { return seconds }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]),
              minutes >= 0, (0..<60).contains(seconds) else { return nil }
        return minutes * 60 + seconds
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        return rest(seconds)
    }
}

@MainActor
extension UIViewController {
    func presentStrengthError(_ error: Error) {
        let alert = UIAlertController(
            title: L10n.Common.error,
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.Common.done, style: .default))
        present(alert, animated: true)
    }
}
