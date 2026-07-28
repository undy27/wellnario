import UIKit

@MainActor
final class StrengthWorkoutStartViewController: WellnessScrollViewController {
    private let store: StrengthDataStore

    init(store: StrengthDataStore) {
        self.store = store
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

        let icon = UIImageView(image: UIImage(systemName: "figure.strengthtraining.traditional"))
        icon.tintColor = WellnarioPalette.magenta
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        titleLabel.text = L10n.text("strength.start.hero.title")
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let body = UILabel()
        body.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        body.text = L10n.text("strength.start.hero.body")
        body.textAlignment = .center
        body.numberOfLines = 0
        contentStack.addArrangedSubview(makeCard(containing: UIStackView(
            arrangedSubviews: [icon, titleLabel, body],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        ), identifier: "strength.start.hero"))

        let emptyWorkout = PrimaryButton(title: L10n.text("strength.start.empty"))
        emptyWorkout.accessibilityIdentifier = "strength.start.empty"
        emptyWorkout.addTarget(self, action: #selector(startEmptyWorkout), for: .touchUpInside)
        contentStack.addArrangedSubview(emptyWorkout)

        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("strength.templates.title")))
        do {
            let templates = try store.fetchTemplates()
            if templates.isEmpty {
                let empty = UILabel()
                empty.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
                empty.text = L10n.text("strength.templates.empty")
                empty.numberOfLines = 0
                contentStack.addArrangedSubview(makeCard(containing: empty, identifier: "strength.templates.empty"))
            } else {
                for template in templates {
                    contentStack.addArrangedSubview(templateButton(template))
                }
            }
        } catch {
            let failed = UILabel()
            failed.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
            failed.text = error.localizedDescription
            failed.numberOfLines = 0
            contentStack.addArrangedSubview(makeCard(containing: failed))
        }

        let createTemplateButton = PrimaryButton(title: L10n.text("strength.templates.create"), style: .secondary)
        createTemplateButton.accessibilityIdentifier = "strength.templates.create"
        createTemplateButton.addTarget(self, action: #selector(createTemplate), for: .touchUpInside)
        contentStack.addArrangedSubview(createTemplateButton)
    }

    private func templateButton(_ template: StrengthWorkoutTemplate) -> PremiumCardView {
        let icon = UIImageView(image: UIImage(systemName: "rectangle.stack.badge.play"))
        icon.tintColor = WellnarioPalette.cyan
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let title = UILabel()
        title.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        title.text = templateDisplayName(template)
        title.numberOfLines = 2

        let detail = UILabel()
        detail.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detail.text = L10n.text("strength.templates.exercise_count", template.exercises.count)
        let labels = UIStackView(arrangedSubviews: [title, detail], axis: .vertical, spacing: 2)

        let chevron = UIImageView(image: UIImage(systemName: "play.fill"))
        chevron.tintColor = WellnarioPalette.fuchsia
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        let card = makeCard(containing: UIStackView(
            arrangedSubviews: [icon, labels, UIView(), chevron],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        ), identifier: "strength.template.\(template.id.uuidString)")
        card.isPressable = true
        card.addAction(UIAction { [weak self] _ in self?.start(template: template) }, for: .primaryActionTriggered)
        return card
    }

    @objc private func startEmptyWorkout() {
        navigationController?.pushViewController(
            StrengthWorkoutViewController(
                store: store,
                workout: store.workout(from: nil, title: L10n.text("strength.workout.untitled"))
            ),
            animated: true
        )
    }

    private func start(template: StrengthWorkoutTemplate) {
        let title = templateDisplayName(template)
        navigationController?.pushViewController(
            StrengthWorkoutViewController(
                store: store,
                workout: store.workout(from: template, title: title)
            ),
            animated: true
        )
    }

    @objc private func createTemplate() {
        navigationController?.pushViewController(
            StrengthTemplateEditorViewController(store: store),
            animated: true
        )
    }

    private func templateDisplayName(_ template: StrengthWorkoutTemplate) -> String {
        template.nameKey.map { L10n.text($0) } ?? template.name
    }
}

@MainActor
private final class StrengthTemplateEditorViewController: WellnessScrollViewController {
    private let store: StrengthDataStore
    private let nameField = FormFieldView()
    private var selectedExercises: [StrengthExercise] = []

    init(store: StrengthDataStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("strength.template.editor.title")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.Common.save,
            style: .done,
            target: self,
            action: #selector(save)
        )
        nameField.configure(
            title: L10n.text("strength.template.editor.name"),
            placeholder: L10n.text("strength.template.editor.name.placeholder"),
            text: nil,
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

        if selectedExercises.isEmpty {
            let empty = UILabel()
            empty.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
            empty.text = L10n.text("strength.template.editor.exercises.empty")
            empty.numberOfLines = 0
            contentStack.addArrangedSubview(makeCard(containing: empty))
        } else {
            for exercise in selectedExercises {
                contentStack.addArrangedSubview(selectedExerciseRow(exercise))
            }
        }

        let add = PrimaryButton(title: L10n.text("strength.exercise.add"), style: .secondary)
        add.accessibilityIdentifier = "strength.template.add_exercise"
        add.addTarget(self, action: #selector(addExercises), for: .touchUpInside)
        contentStack.addArrangedSubview(add)
    }

    private func selectedExerciseRow(_ exercise: StrengthExercise) -> PremiumCardView {
        let label = UILabel()
        label.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        label.text = exercise.localizedName(language: LocalizationManager.shared.language)
        label.numberOfLines = 2

        let remove = UIButton(type: .system)
        remove.setImage(UIImage(systemName: "minus.circle"), for: .normal)
        remove.tintColor = WellnarioPalette.textSecondary
        remove.accessibilityLabel = L10n.text("strength.exercise.remove", label.text ?? "")
        remove.addAction(UIAction { [weak self] _ in
            self?.selectedExercises.removeAll { $0.id == exercise.id }
            self?.buildContent()
        }, for: .touchUpInside)
        return makeCard(containing: UIStackView(
            arrangedSubviews: [label, UIView(), remove],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .center
        ))
    }

    @objc private func addExercises() {
        let picker = StrengthExercisePickerViewController(
            store: store,
            allowsMultipleSelection: true,
            selectedExerciseIDs: Set(selectedExercises.map(\.id))
        )
        picker.onExercisesPicked = { [weak self] exercises in
            guard let self else { return }
            let knownIDs = Set(self.selectedExercises.map(\.id))
            self.selectedExercises += exercises.filter { !knownIDs.contains($0.id) }
            self.buildContent()
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    @objc private func save() {
        view.endEditing(true)
        let exerciseTemplates = selectedExercises.enumerated().map { index, exercise in
            StrengthWorkoutTemplateExercise(
                id: UUID(),
                exercise: exercise,
                order: index,
                defaultRestSeconds: 90,
                sets: (1...3).map { StrengthWorkoutSet(order: $0, repetitions: 8, restSeconds: 90) }
            )
        }
        do {
            _ = try store.saveTemplate(StrengthWorkoutTemplateDraft(
                name: nameField.textField.text ?? "",
                exercises: exerciseTemplates
            ))
            UIImpactFeedbackGenerator.wellnarioSuccess()
            navigationController?.popViewController(animated: true)
        } catch {
            presentStrengthError(error)
        }
    }
}

@MainActor
private final class StrengthWorkoutViewController: WellnessScrollViewController {
    private let store: StrengthDataStore
    private var workout: StrengthWorkout
    private let durationLabel = UILabel()
    private var timer: Timer?

    init(store: StrengthDataStore, workout: StrengthWorkout) {
        self.store = store
        self.workout = workout
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = workout.title
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.text("strength.workout.finish"),
            style: .done,
            target: self,
            action: #selector(finishWorkout)
        )
        view.accessibilityIdentifier = "strength.workout"
        buildContent()
        startTimer()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController == nil { timer?.invalidate() }
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        contentStack.addArrangedSubview(makeTimerCard())

        if workout.exercises.isEmpty {
            let empty = UILabel()
            empty.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
            empty.text = L10n.text("strength.workout.empty")
            empty.numberOfLines = 0
            empty.textAlignment = .center
            contentStack.addArrangedSubview(makeCard(containing: empty, identifier: "strength.workout.empty"))
        } else {
            for exercise in workout.exercises {
                contentStack.addArrangedSubview(makeExerciseCard(exercise))
            }
        }

        let addExerciseButton = PrimaryButton(title: L10n.text("strength.exercise.add"), style: .secondary)
        addExerciseButton.accessibilityIdentifier = "strength.workout.add_exercise"
        addExerciseButton.addTarget(self, action: #selector(addExercise), for: .touchUpInside)
        contentStack.addArrangedSubview(addExerciseButton)
    }

    private func makeTimerCard() -> PremiumCardView {
        let title = UILabel()
        title.applyWellnarioStyle(.caption, color: WellnarioPalette.magenta)
        title.text = L10n.text("strength.workout.in_progress")

        durationLabel.applyWellnarioStyle(.summaryMetric, color: WellnarioPalette.textPrimary)
        durationLabel.text = StrengthFormat.duration(Date().timeIntervalSince(workout.startedAt))
        durationLabel.accessibilityIdentifier = "strength.workout.duration"

        let detail = UILabel()
        detail.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        detail.text = L10n.text("strength.workout.duration")
        return makeCard(containing: UIStackView(
            arrangedSubviews: [title, durationLabel, detail],
            axis: .vertical,
            spacing: 3
        ), identifier: "strength.workout.timer")
    }

    private func makeExerciseCard(_ workoutExercise: StrengthWorkoutExercise) -> PremiumCardView {
        let title = UILabel()
        title.applyWellnarioStyle(.cardTitle, color: WellnarioPalette.textPrimary)
        title.text = workoutExercise.exercise.localizedName(language: LocalizationManager.shared.language)
        title.numberOfLines = 2

        let muscles = UILabel()
        muscles.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        muscles.text = workoutExercise.exercise.primaryMuscles
            .map { L10n.text("strength.muscle.\($0)") }
            .joined(separator: " · ")
        muscles.numberOfLines = 2

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
            arrangedSubviews: [UIStackView(arrangedSubviews: [title, muscles], axis: .vertical, spacing: 2), UIView(), remove],
            axis: .horizontal,
            spacing: WellnarioSpacing.xSmall,
            alignment: .top
        )
        let columnHeader = StrengthSetColumnHeaderView()
        let setRows = UIStackView(arrangedSubviews: [], axis: .vertical, spacing: 6)
        for set in workoutExercise.sets {
            let row = StrengthSetRowView(set: set)
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
        addSet.addAction(UIAction { [weak self] _ in self?.addSet(to: workoutExercise.id) }, for: .touchUpInside)

        return makeCard(containing: UIStackView(
            arrangedSubviews: [header, columnHeader, setRows, addSet],
            axis: .vertical,
            spacing: WellnarioSpacing.xSmall
        ), identifier: "strength.workout.exercise.\(workoutExercise.id.uuidString)")
    }

    private func replace(_ set: StrengthWorkoutSet, in exerciseID: UUID) {
        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == set.id }) else { return }
        workout.exercises[exerciseIndex].sets[setIndex] = set
    }

    private func addSet(to exerciseID: UUID) {
        guard let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let existing = workout.exercises[exerciseIndex].sets
        let last = existing.last
        workout.exercises[exerciseIndex].sets.append(StrengthWorkoutSet(
            order: existing.count + 1,
            weight: last?.weight,
            repetitions: last?.repetitions,
            restSeconds: last?.restSeconds ?? 90
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
            workout.endedAt = Date()
            _ = try store.saveWorkout(workout)
            UIImpactFeedbackGenerator.wellnarioSuccess()
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
private final class StrengthExercisePickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private let store: StrengthDataStore
    private let allowsMultipleSelection: Bool
    private var selectedExerciseIDs: Set<String>
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var exercises: [StrengthExercise] = []
    private var filteredExercises: [StrengthExercise] = []
    private var selectedEquipment: String?
    private var selectedPrimaryMuscle: String?
    private let searchController = UISearchController(searchResultsController: nil)
    private let filterHeader = UIView()
    private let equipmentFilterButton = ChipButton()
    private let primaryMuscleFilterButton = ChipButton()
    private var filterHeaderHeight: CGFloat = 0
    private var originalContentInset: UIEdgeInsets?
    private var originalVerticalScrollIndicatorInsets: UIEdgeInsets?
    private var originalHorizontalScrollIndicatorInsets: UIEdgeInsets?
    var onExercisesPicked: (([StrengthExercise]) -> Void)?

    init(
        store: StrengthDataStore,
        allowsMultipleSelection: Bool,
        selectedExerciseIDs: Set<String> = []
    ) {
        self.store = store
        self.allowsMultipleSelection = allowsMultipleSelection
        self.selectedExerciseIDs = selectedExerciseIDs
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
            let done = UIBarButtonItem(
                title: L10n.Common.done,
                style: .done,
                target: self,
                action: #selector(done)
            )
            done.accessibilityIdentifier = "strength.exercise.picker.done"
            navigationItem.rightBarButtonItem = done
        }
        do {
            let language = LocalizationManager.shared.language
            exercises = try store.fetchExercises().sorted {
                $0.localizedName(language: language)
                    .localizedCaseInsensitiveCompare($1.localizedName(language: language)) == .orderedAscending
            }
            configureFilterMenus()
            applyFilters()
        } catch {
            presentStrengthError(error)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let targetSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let headerHeight = filterHeader.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: headerHeight)
        if filterHeader.frame != frame {
            filterHeader.frame = frame
        }
        view.bringSubviewToFront(filterHeader)
        filterHeader.bringSubviewToFront(equipmentFilterButton)
        filterHeader.bringSubviewToFront(primaryMuscleFilterButton)
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
            arrangedSubviews: [equipmentFilterButton, primaryMuscleFilterButton],
            axis: .horizontal,
            spacing: WellnarioSpacing.xxSmall,
            alignment: .fill,
            distribution: .fillEqually
        )
        [equipmentFilterButton, primaryMuscleFilterButton].forEach {
            $0.titleLabel?.lineBreakMode = .byTruncatingTail
            $0.semanticContentAttribute = .forceLeftToRight
            $0.showsMenuAsPrimaryAction = true
        }
        equipmentFilterButton.accessibilityIdentifier = "strength.exercise.filter.equipment"
        primaryMuscleFilterButton.accessibilityIdentifier = "strength.exercise.filter.primary_muscle"
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
        view.addSubview(filterHeader)
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
        let reuseIdentifier = "strength.exercise.cell"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseIdentifier)
        let exercise = filteredExercises[indexPath.row]
        cell.textLabel?.font = WellnarioTypography.font(for: .secondary)
        cell.textLabel?.textColor = WellnarioPalette.textPrimary
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.text = exercise.localizedName(language: LocalizationManager.shared.language)
        cell.detailTextLabel?.font = WellnarioTypography.font(for: .caption)
        cell.detailTextLabel?.textColor = WellnarioPalette.textSecondary
        cell.detailTextLabel?.numberOfLines = 2
        let details = exercise.primaryMuscles.map { L10n.text("strength.muscle.\($0)") }
        cell.detailTextLabel?.text = details.joined(separator: " · ")
        cell.accessibilityIdentifier = "strength.exercise.\(exercise.id)"
        cell.accessoryType = selectedExerciseIDs.contains(exercise.id) ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let exercise = filteredExercises[indexPath.row]
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
                + exercise.primaryMuscles + exercise.secondaryMuscles)
                .contains(where: {
                    $0.range(of: searchQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            })
            let matchesEquipment = selectedEquipment == nil || exercise.equipment == selectedEquipment
            let matchesPrimaryMuscle = selectedPrimaryMuscle.map {
                exercise.primaryMuscles.contains($0)
            } ?? true
            return matchesSearch && matchesEquipment && matchesPrimaryMuscle
        }
        tableView.reloadData()
    }

    @objc private func done() {
        let picked = exercises.filter { selectedExerciseIDs.contains($0.id) }
        onExercisesPicked?(picked)
        navigationController?.popViewController(animated: true)
    }
}

@MainActor
private final class StrengthSetColumnHeaderView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        let labels = [
            header("strength.set.header.number"),
            header("strength.set.header.weight"),
            header("strength.set.header.reps"),
            header("strength.set.header.rest"),
            header("strength.set.header.kind")
        ]
        labels[0].widthAnchor.constraint(equalToConstant: 30).isActive = true
        labels[1].widthAnchor.constraint(equalToConstant: 48).isActive = true
        labels[2].widthAnchor.constraint(equalToConstant: 43).isActive = true
        labels[3].widthAnchor.constraint(equalToConstant: 48).isActive = true
        let stack = UIStackView(arrangedSubviews: labels, axis: .horizontal, spacing: 5, alignment: .center)
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
    private let numberLabel = UILabel()
    private let weightField = UITextField()
    private let repetitionsField = UITextField()
    private let restField = UITextField()
    private let warmupButton = ChipButton(title: "W")
    private let failureButton = ChipButton(title: "F")
    private let dropSetButton = ChipButton(title: "D")
    private let completedButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)

    init(set: StrengthWorkoutSet) {
        self.set = set
        super.init(frame: .zero)
        setUp()
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setUp() {
        [weightField, repetitionsField, restField].forEach(configureField)
        weightField.keyboardType = .decimalPad
        repetitionsField.keyboardType = .numberPad
        restField.keyboardType = .numbersAndPunctuation
        weightField.accessibilityLabel = L10n.text("strength.set.weight")
        repetitionsField.accessibilityLabel = L10n.text("strength.set.reps")
        restField.accessibilityLabel = L10n.text("strength.set.rest")
        [weightField, repetitionsField, restField].forEach {
            $0.addTarget(self, action: #selector(fieldsChanged), for: [.editingDidEnd, .editingDidEndOnExit])
        }

        numberLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        numberLabel.textAlignment = .center
        numberLabel.widthAnchor.constraint(equalToConstant: 30).isActive = true
        weightField.widthAnchor.constraint(equalToConstant: 48).isActive = true
        repetitionsField.widthAnchor.constraint(equalToConstant: 43).isActive = true
        restField.widthAnchor.constraint(equalToConstant: 48).isActive = true

        configure(kindButton: warmupButton, title: "W", labelKey: "strength.set.warmup")
        configure(kindButton: failureButton, title: "F", labelKey: "strength.set.failure")
        configure(kindButton: dropSetButton, title: "D", labelKey: "strength.set.drop")
        warmupButton.addTarget(self, action: #selector(toggleWarmup), for: .touchUpInside)
        failureButton.addTarget(self, action: #selector(toggleFailure), for: .touchUpInside)
        dropSetButton.addTarget(self, action: #selector(toggleDropSet), for: .touchUpInside)

        completedButton.widthAnchor.constraint(equalToConstant: 27).isActive = true
        completedButton.addTarget(self, action: #selector(toggleCompleted), for: .touchUpInside)
        deleteButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        deleteButton.setImage(UIImage(systemName: "minus.circle"), for: .normal)
        deleteButton.tintColor = WellnarioPalette.textTertiary
        deleteButton.accessibilityLabel = L10n.text("strength.set.delete")
        deleteButton.addTarget(self, action: #selector(deleteSet), for: .touchUpInside)

        let kinds = UIStackView(
            arrangedSubviews: [warmupButton, failureButton, dropSetButton],
            axis: .horizontal,
            spacing: 2
        )
        let stack = UIStackView(
            arrangedSubviews: [numberLabel, weightField, repetitionsField, restField, kinds, completedButton, deleteButton],
            axis: .horizontal,
            spacing: 5,
            alignment: .center
        )
        addForAutoLayout(stack)
        stack.pinEdges(to: self)
    }

    private func configureField(_ field: UITextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = WellnarioTypography.font(for: .caption)
        field.textColor = WellnarioPalette.textPrimary
        field.textAlignment = .center
        field.backgroundColor = WellnarioPalette.surfaceElevated
        field.applyContinuousCorners(8)
        field.heightAnchor.constraint(equalToConstant: 32).isActive = true
        field.adjustsFontForContentSizeCategory = true
    }

    private func configure(kindButton: ChipButton, title: String, labelKey: String) {
        kindButton.setTitle(title, for: .normal)
        kindButton.titleLabel?.font = WellnarioTypography.font(for: .summaryDetail)
        kindButton.widthAnchor.constraint(equalToConstant: 22).isActive = true
        kindButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        kindButton.accessibilityLabel = L10n.text(labelKey)
    }

    private func render() {
        numberLabel.text = "\(set.order)"
        weightField.text = set.weight.map(StrengthFormat.decimal)
        repetitionsField.text = set.repetitions.map(String.init)
        restField.text = set.restSeconds.map(StrengthFormat.rest)
        warmupButton.isSelected = set.isWarmup
        failureButton.isSelected = set.isFailure
        dropSetButton.isSelected = set.isDropSet
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
        set.restSeconds = StrengthFormat.parseRest(restField.text)
        onChange?(set)
    }

    @objc private func toggleWarmup() {
        set.isWarmup.toggle()
        render()
        onChange?(set)
    }

    @objc private func toggleFailure() {
        set.isFailure.toggle()
        render()
        onChange?(set)
    }

    @objc private func toggleDropSet() {
        set.isDropSet.toggle()
        render()
        onChange?(set)
    }

    @objc private func toggleCompleted() {
        set.completedAt = set.completedAt == nil ? Date() : nil
        render()
        onChange?(set)
    }

    @objc private func deleteSet() { onDelete?() }
}

@MainActor
private enum StrengthFormat {
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
private extension UIViewController {
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
