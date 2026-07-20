import UIKit

@MainActor
final class SleepFactorCategoryTabsView: UIView {
    var onSelection: ((SleepFactorCategory) -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [(category: SleepFactorCategory, button: ChipButton)] = []
    private(set) var selectedCategory: SleepFactorCategory

    init(selectedCategory: SleepFactorCategory = .automatic) {
        self.selectedCategory = selectedCategory
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        selectedCategory = .automatic
        super.init(coder: coder)
        setUp()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 46)
    }

    func select(_ category: SleepFactorCategory, notify: Bool = false) {
        guard selectedCategory != category || buttons.isEmpty else { return }
        selectedCategory = category
        updateSelection()
        guard notify else { return }
        onSelection?(category)
    }

    private func setUp() {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        addForAutoLayout(scrollView)
        scrollView.pinEdges(to: self)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = WellnarioSpacing.xSmall
        scrollView.addForAutoLayout(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        buttons = SleepFactorCategory.allCases.enumerated().map { index, category in
            let button = ChipButton()
            button.setTitle(category.title, for: .normal)
            button.tag = index
            button.accessibilityIdentifier = "sleep.factors.category.\(category.rawValue)"
            button.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            return (category, button)
        }
        updateSelection()
    }

    private func updateSelection() {
        buttons.forEach { item in item.button.isSelected = item.category == selectedCategory }
        guard let selectedButton = buttons.first(where: { $0.category == selectedCategory })?.button else {
            return
        }
        layoutIfNeeded()
        scrollView.scrollRectToVisible(
            selectedButton.frame.insetBy(dx: -WellnarioSpacing.small, dy: 0),
            animated: !UIAccessibility.isReduceMotionEnabled
        )
    }

    @objc private func categoryTapped(_ sender: ChipButton) {
        guard SleepFactorCategory.allCases.indices.contains(sender.tag) else { return }
        select(SleepFactorCategory.allCases[sender.tag], notify: true)
    }
}

@MainActor
final class SleepFactorsViewController: WellnessScrollViewController {
    private let appleHealthService: AppleHealthSyncing?
    private let sleepManualOverrideStore: SleepManualOverrideStore
    private let repository: WellnarioRepositoryProtocol?

    init(
        appleHealthService: AppleHealthSyncing? = nil,
        sleepManualOverrideStore: SleepManualOverrideStore = SleepManualOverrideStore(),
        repository: WellnarioRepositoryProtocol? = nil
    ) {
        self.appleHealthService = appleHealthService
        self.sleepManualOverrideStore = sleepManualOverrideStore
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("sleep.factors.manage.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "sleep.factors.root"
        buildContent()
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        contentStack.addArrangedSubview(makeMenuCard(
            symbolName: "slider.horizontal.3",
            title: L10n.text("sleep.factors.manage.configure.title"),
            body: L10n.text("sleep.factors.manage.configure.body"),
            tone: WellnarioPalette.fuchsia,
            identifier: "sleep.factors.configure"
        ) { [weak self] in
            self?.navigationController?.pushViewController(
                SleepFactorConfigurationViewController(repository: self?.repository),
                animated: true
            )
        })
        contentStack.addArrangedSubview(makeMenuCard(
            symbolName: "calendar.badge.plus",
            title: L10n.text("sleep.factors.manage.daily.title"),
            body: L10n.text("sleep.factors.manage.daily.body"),
            tone: WellnarioPalette.cyan,
            identifier: "sleep.factors.daily_log"
        ) { [weak self] in
            guard let self else { return }
            self.navigationController?.pushViewController(
                SleepFactorDailyLogViewController(
                    appleHealthService: self.appleHealthService,
                    repository: self.repository
                ),
                animated: true
            )
        })
        contentStack.addArrangedSubview(makeMenuCard(
            symbolName: "chart.line.uptrend.xyaxis",
            title: L10n.text("sleep.factors.manage.analysis.title"),
            body: L10n.text("sleep.factors.manage.analysis.body"),
            tone: WellnarioPalette.violet,
            identifier: "sleep.factors.analysis"
        ) { [weak self] in
            guard let self else { return }
            self.navigationController?.pushViewController(
                SleepFactorAnalysisViewController(
                    appleHealthService: self.appleHealthService,
                    sleepManualOverrideStore: self.sleepManualOverrideStore,
                    repository: self.repository
                ),
                animated: true
            )
        })
    }

    private func makeMenuCard(
        symbolName: String,
        title: String,
        body: String,
        tone: UIColor,
        identifier: String,
        action: @escaping () -> Void
    ) -> PremiumCardView {
        let symbol = UIImageView(image: UIImage(systemName: symbolName))
        symbol.tintColor = tone
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        symbol.widthAnchor.constraint(equalToConstant: 28).isActive = true
        symbol.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        titleLabel.text = title
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        bodyLabel.text = body
        bodyLabel.numberOfLines = 0

        let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
        chevron.tintColor = WellnarioPalette.textTertiary
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let labels = UIStackView(
            arrangedSubviews: [titleLabel, bodyLabel],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        let row = UIStackView(
            arrangedSubviews: [symbol, labels, chevron],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = title
        button.accessibilityHint = body
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.addForAutoLayout(row)
        row.pinEdges(to: button, insets: .all(WellnarioSpacing.cardPadding))
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        let card = PremiumCardView()
        card.contentView.addForAutoLayout(button)
        button.pinEdges(to: card.contentView)
        return card
    }
}

@MainActor
final class SleepFactorConfigurationViewController: UIViewController {
    private let tabs = SleepFactorCategoryTabsView()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let repository: WellnarioRepositoryProtocol?
    private var selectedCategory = SleepFactorCategory.automatic

    init(repository: WellnarioRepositoryProtocol? = nil) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("sleep.factors.manage.configure.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "sleep.factors.configure.root"
        view.backgroundColor = WellnarioPalette.background

        tabs.onSelection = { [weak self] category in
            self?.selectedCategory = category
            self?.updateAddButton()
            self?.tableView.setContentOffset(.zero, animated: false)
            self?.tableView.reloadData()
        }
        view.addForAutoLayout(tabs)

        tableView.backgroundColor = .clear
        tableView.tintColor = WellnarioPalette.fuchsia
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 68
        view.addForAutoLayout(tableView)

        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: WellnarioSpacing.screenHorizontal),
            tabs.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: WellnarioSpacing.xxSmall),
            tabs.heightAnchor.constraint(equalToConstant: 46),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: WellnarioSpacing.xxxSmall),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        updateAddButton()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    private var definitions: [SleepFactorDefinition] {
        WellnessLocalStore.allSleepFactorDefinitions(repository: repository).filter {
            $0.category == selectedCategory
        }
    }

    private func updateAddButton() {
        guard selectedCategory == .custom else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        let item = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addCustomFactor)
        )
        item.accessibilityIdentifier = "sleep.factors.configure.add"
        navigationItem.rightBarButtonItem = item
    }

    @objc private func addCustomFactor() {
        let editor = SleepCustomFactorEditorViewController()
        editor.onSave = { [weak self] in self?.tableView.reloadData() }
        navigationController?.pushViewController(editor, animated: true)
    }
}

extension SleepFactorConfigurationViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        definitions.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier = "SleepFactorConfigurationCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let definition = definitions[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = definition.title
        content.textProperties.color = WellnarioPalette.textPrimary
        content.textProperties.font = WellnarioTypography.font(for: .body)
        content.secondaryText = secondaryText(for: definition)
        content.secondaryTextProperties.color = WellnarioPalette.textSecondary
        content.secondaryTextProperties.font = WellnarioTypography.font(for: .caption)
        content.image = UIImage(systemName: definition.symbolName)
        content.imageProperties.tintColor = definition.source == .automatic
            ? WellnarioPalette.cyan
            : WellnarioPalette.fuchsia
        cell.contentConfiguration = content
        cell.backgroundColor = WellnarioPalette.surface
        cell.accessoryType = WellnessLocalStore.isSleepFactorEnabled(
            definition.id,
            repository: repository
        )
            ? .checkmark
            : .none
        cell.accessibilityIdentifier = "sleep.factors.configure.factor.\(definition.id)"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let definition = definitions[indexPath.row]
        let newValue = !WellnessLocalStore.isSleepFactorEnabled(
            definition.id,
            repository: repository
        )
        WellnessLocalStore.setSleepFactor(definition.id, enabled: newValue)
        UISelectionFeedbackGenerator().selectionChanged()
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        selectedCategory == .custom
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete else { return }
        WellnessLocalStore.removeCustomSleepFactor(definitions[indexPath.row].title)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    private func secondaryText(for definition: SleepFactorDefinition) -> String {
        if definition.source == .automatic {
            return L10n.text("sleep.factors.automatic.source")
        }
        switch definition.valueKind {
        case .discrete:
            return L10n.text("sleep.factors.value.discrete")
        case let .numeric(unit):
            return L10n.text("sleep.factors.value.numeric", unit)
        }
    }
}

@MainActor
final class SleepCustomFactorEditorViewController: WellnessScrollViewController {
    var onSave: (() -> Void)?

    private let nameField = FormFieldView()
    private let kindControl = UISegmentedControl(items: [
        L10n.text("sleep.factors.value.discrete.short"),
        L10n.text("sleep.factors.value.numeric.short")
    ])
    private let unitField = FormFieldView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("sleep.factor.custom.add.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "sleep.factors.custom.editor"

        nameField.configure(
            title: L10n.text("sleep.factors.custom.name"),
            placeholder: L10n.text("sleep.factor.custom.placeholder")
        )
        kindControl.selectedSegmentIndex = 0
        kindControl.selectedSegmentTintColor = WellnarioPalette.fuchsia
        kindControl.addTarget(self, action: #selector(kindChanged), for: .valueChanged)
        unitField.configure(
            title: L10n.text("sleep.factors.custom.unit"),
            placeholder: L10n.text("sleep.factors.custom.unit.placeholder")
        )
        unitField.isHidden = true

        let saveButton = PrimaryButton(title: L10n.Common.save)
        saveButton.accessibilityIdentifier = "sleep.factors.custom.save"
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)

        contentStack.addArrangedSubview(nameField)
        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("sleep.factors.custom.kind")))
        contentStack.addArrangedSubview(kindControl)
        contentStack.addArrangedSubview(unitField)
        contentStack.addArrangedSubview(saveButton)
    }

    @objc private func kindChanged() {
        unitField.isHidden = kindControl.selectedSegmentIndex == 0
    }

    @objc private func save() {
        let name = nameField.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            nameField.setError(L10n.Common.required)
            return
        }
        let valueKind: SleepFactorValueKind
        if kindControl.selectedSegmentIndex == 0 {
            valueKind = .discrete
        } else {
            let unit = unitField.textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !unit.isEmpty else {
                unitField.setError(L10n.Common.required)
                return
            }
            valueKind = .numeric(unit: unit)
        }
        WellnessLocalStore.addCustomSleepFactor(name, valueKind: valueKind)
        UIImpactFeedbackGenerator.wellnarioSuccess()
        onSave?()
        navigationController?.popViewController(animated: true)
    }
}

@MainActor
final class SleepFactorDailyLogViewController: WellnessScrollViewController {
    var onLogged: ((String) -> Void)?

    private let appleHealthService: AppleHealthSyncing?
    private let repository: WellnarioRepositoryProtocol?
    private let datePicker = UIDatePicker()
    private let tabs = SleepFactorCategoryTabsView()
    private let calendar = Calendar.autoupdatingCurrent
    private var selectedCategory = SleepFactorCategory.automatic

    init(
        appleHealthService: AppleHealthSyncing? = nil,
        date: Date = Date(),
        repository: WellnarioRepositoryProtocol? = nil
    ) {
        self.appleHealthService = appleHealthService
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
        datePicker.date = date
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("sleep.factors.manage.daily.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "sleep.factors.daily.root"
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.maximumDate = Date()
        datePicker.addTarget(self, action: #selector(dateDidChange), for: .valueChanged)
        tabs.onSelection = { [weak self] category in
            self?.selectedCategory = category
            self?.buildContent()
        }
        buildContent()
    }

    private var definitions: [SleepFactorDefinition] {
        WellnessLocalStore.enabledSleepFactorDefinitions(repository: repository).filter {
            $0.category == selectedCategory
        }
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        contentStack.addArrangedSubview(makeDateCard())
        contentStack.addArrangedSubview(tabs)
        if selectedCategory == .automatic {
            contentStack.addArrangedSubview(makeAutomaticExplanation())
        }
        contentStack.addArrangedSubview(makeFactorCard())
    }

    private func makeDateCard() -> PremiumCardView {
        let label = UILabel()
        label.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        label.text = L10n.text("sleep.factors.daily.date")
        let row = UIStackView(
            arrangedSubviews: [label, UIView(), datePicker],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        return makeCard(containing: row, identifier: "sleep.factors.daily.date")
    }

    private func makeAutomaticExplanation() -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        label.text = L10n.text("sleep.factors.automatic.explanation")
        label.numberOfLines = 0
        return label
    }

    private func makeFactorCard() -> PremiumCardView {
        guard !definitions.isEmpty else {
            let label = UILabel()
            label.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
            label.text = L10n.text("sleep.factors.category.empty")
            label.numberOfLines = 0
            label.textAlignment = .center
            return makeCard(containing: label, identifier: "sleep.factors.daily.empty")
        }
        let rows = definitions.map { definition -> UIView in
            definition.source == .automatic
                ? makeAutomaticRow(definition)
                : makeManualRow(definition)
        }
        let stack = UIStackView(
            arrangedSubviews: rows,
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        return makeCard(containing: stack, identifier: "sleep.factors.daily.selection")
    }

    private func makeAutomaticRow(_ definition: SleepFactorDefinition) -> UIView {
        let icon = factorIcon(definition)
        let title = factorTitle(definition)
        let value = UILabel()
        value.applyWellnarioStyle(.caption, color: WellnarioPalette.cyan)
        value.text = formattedAutomaticValue(for: definition)
        value.textAlignment = .right
        value.numberOfLines = 2
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(
            arrangedSubviews: [icon, title, UIView(), value],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        row.accessibilityIdentifier = "sleep.factors.daily.factor.\(definition.id)"
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        return row
    }

    private func makeManualRow(_ definition: SleepFactorDefinition) -> UIView {
        let entry = WellnessLocalStore.sleepFactorEntry(
            for: definition,
            on: datePicker.date,
            calendar: calendar
        )
        let icon = factorIcon(definition)
        let title = factorTitle(definition)
        let value = UILabel()
        value.applyWellnarioStyle(
            .caption,
            color: entry == nil ? WellnarioPalette.textTertiary : WellnarioPalette.fuchsia
        )
        value.text = formattedManualValue(entry, definition: definition)
        value.textAlignment = .right
        value.numberOfLines = 2
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        let indicatorName = definition.isNumeric
            ? "chevron.forward"
            : (entry == nil ? "circle" : "checkmark.circle.fill")
        let indicator = UIImageView(image: UIImage(systemName: indicatorName))
        indicator.tintColor = entry == nil ? WellnarioPalette.textTertiary : WellnarioPalette.fuchsia
        indicator.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(
            arrangedSubviews: [icon, title, UIView(), value, indicator],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "sleep.factors.daily.factor.\(definition.id)"
        button.accessibilityLabel = definition.title
        button.accessibilityValue = value.text
        button.addAction(UIAction { [weak self] _ in
            self?.edit(definition)
        }, for: .touchUpInside)
        button.addForAutoLayout(row)
        row.pinEdges(to: button)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        return button
    }

    private func factorIcon(_ definition: SleepFactorDefinition) -> UIImageView {
        let imageView = UIImageView(image: UIImage(systemName: definition.symbolName))
        imageView.tintColor = definition.source == .automatic
            ? WellnarioPalette.cyan
            : WellnarioPalette.fuchsia
        imageView.widthAnchor.constraint(equalToConstant: 25).isActive = true
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        return imageView
    }

    private func factorTitle(_ definition: SleepFactorDefinition) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        label.text = definition.title
        label.numberOfLines = 0
        return label
    }

    private func formattedAutomaticValue(for definition: SleepFactorDefinition) -> String {
        if SleepSupplementFactorCatalog.isSupplementFactor(definition.id) {
            guard let repository,
                  let value = SleepSupplementFactorCatalog.value(
                    for: definition,
                    sleepDate: datePicker.date,
                    sleepStartDate: sleepStartDate(for: datePicker.date),
                    repository: repository,
                    calendar: calendar
                  ) else {
                return L10n.text("sleep.no_data")
            }
            return value > 0
                ? L10n.text("sleep.factors.daily.selected")
                : L10n.text("sleep.factors.daily.not_selected")
        }
        guard let factorDay = appleHealthService?.snapshot.automaticSleepFactors?.first(where: {
            calendar.isDate($0.date, inSameDayAs: datePicker.date)
        }), let value = factorDay.value(for: definition.id) else {
            return L10n.text("sleep.no_data")
        }
        switch definition.valueKind {
        case .discrete:
            return value > 0
                ? L10n.text("sleep.factors.daily.selected")
                : L10n.text("sleep.factors.daily.not_selected")
        case .numeric:
            return formatted(value: value, definition: definition)
        }
    }

    private func sleepStartDate(for sleepDate: Date) -> Date? {
        appleHealthService?.snapshot.sleepTrend.first(where: {
            calendar.isDate($0.date, inSameDayAs: sleepDate)
        })?.sleepStartDate
    }

    private func formattedManualValue(
        _ entry: SleepFactorLogEntry?,
        definition: SleepFactorDefinition
    ) -> String {
        switch definition.valueKind {
        case .discrete:
            return entry == nil
                ? L10n.text("sleep.factors.daily.not_selected")
                : L10n.text("sleep.factors.daily.selected")
        case .numeric:
            guard let value = entry?.numericValue else {
                return L10n.text("sleep.factors.daily.not_recorded")
            }
            return formatted(value: value, definition: definition)
        }
    }

    private func formatted(value: Double, definition: SleepFactorDefinition) -> String {
        let number = value.rounded() == value
            ? String(Int(value))
            : String(format: "%.1f", value)
        return [number, definition.valueKind.unit].compactMap { $0 }.joined(separator: " ")
    }

    private func edit(_ definition: SleepFactorDefinition) {
        switch definition.valueKind {
        case .discrete:
            let existing = WellnessLocalStore.sleepFactorEntry(
                for: definition,
                on: datePicker.date,
                calendar: calendar
            )
            WellnessLocalStore.setSleepFactorValue(
                existing == nil ? 1 : nil,
                for: definition,
                on: datePicker.date,
                calendar: calendar
            )
            didLog(definition.title)
        case let .numeric(unit):
            presentNumericEditor(definition, unit: unit)
        }
    }

    private func presentNumericEditor(_ definition: SleepFactorDefinition, unit: String) {
        let existing = WellnessLocalStore.sleepFactorEntry(
            for: definition,
            on: datePicker.date,
            calendar: calendar
        )
        let alert = UIAlertController(
            title: definition.title,
            message: L10n.text("sleep.factors.numeric.prompt", unit),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.keyboardType = .decimalPad
            field.text = existing?.numericValue.map {
                $0.rounded() == $0 ? String(Int($0)) : String(format: "%.1f", $0)
            }
            field.placeholder = unit
            field.accessibilityIdentifier = "sleep.factors.numeric.value"
        }
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        if existing != nil {
            alert.addAction(UIAlertAction(
                title: L10n.Common.delete,
                style: .destructive
            ) { [weak self] _ in
                guard let self else { return }
                WellnessLocalStore.setSleepFactorValue(
                    nil,
                    for: definition,
                    on: self.datePicker.date,
                    calendar: self.calendar
                )
                self.didLog(definition.title)
            })
        }
        alert.addAction(UIAlertAction(title: L10n.Common.save, style: .default) {
            [weak self, weak alert] _ in
            guard let self,
                  let text = alert?.textFields?.first?.text,
                  let value = Double(text.replacingOccurrences(of: ",", with: ".")),
                  value.isFinite else {
                return
            }
            WellnessLocalStore.setSleepFactorValue(
                value,
                for: definition,
                on: self.datePicker.date,
                calendar: self.calendar
            )
            self.didLog(definition.title)
        })
        present(alert, animated: true)
    }

    private func didLog(_ factor: String) {
        UIImpactFeedbackGenerator.wellnarioSuccess()
        onLogged?(factor)
        buildContent()
    }

    @objc private func dateDidChange() { buildContent() }
}
