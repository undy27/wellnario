import UIKit

@MainActor
enum WellnessLocalStore {
    private static let customFactorsKey = "wellnario.sleep.customFactors"
    private static let lastSleepFactorKey = "wellnario.sleep.lastFactor"
    private static let lastSleepFactorDateKey = "wellnario.sleep.lastFactorDate"
    private static let lastWorkoutTypeKey = "wellnario.fitness.lastWorkoutType"
    private static let lastWorkoutDateKey = "wellnario.fitness.lastWorkoutDate"

    static var customSleepFactors: [String] {
        UserDefaults.standard.stringArray(forKey: customFactorsKey) ?? []
    }

    static var lastSleepFactor: String? {
        UserDefaults.standard.string(forKey: lastSleepFactorKey)
    }

    static func addCustomSleepFactor(_ name: String) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        var factors = customSleepFactors
        guard !factors.contains(where: { $0.localizedCaseInsensitiveCompare(normalized) == .orderedSame }) else {
            return
        }
        factors.append(normalized)
        UserDefaults.standard.set(factors.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, forKey: customFactorsKey)
    }

    static func logSleepFactor(_ name: String) {
        UserDefaults.standard.set(name, forKey: lastSleepFactorKey)
        UserDefaults.standard.set(Date(), forKey: lastSleepFactorDateKey)
    }

    static func startWorkout(type: String) {
        UserDefaults.standard.set(type, forKey: lastWorkoutTypeKey)
        UserDefaults.standard.set(Date(), forKey: lastWorkoutDateKey)
    }
}

@MainActor
final class SleepFactorPickerViewController: UITableViewController {
    var onLogged: ((String) -> Void)?

    private var suggestedFactors: [String] {
        [
            L10n.text("sleep.factor.nap"),
            L10n.text("sleep.factor.heavy_dinner"),
            L10n.text("sleep.factor.alcohol"),
            L10n.text("sleep.factor.late_training"),
            L10n.text("sleep.factor.stress"),
            L10n.text("sleep.factor.screen_time")
        ]
    }

    private var customFactors: [String] { WellnessLocalStore.customSleepFactors }

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("sleep.factor.add.title")
        view.backgroundColor = WellnarioPalette.background
        view.accessibilityIdentifier = "sleep.factor.picker"
        tableView.backgroundColor = .clear
        tableView.tintColor = WellnarioPalette.cyan
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.Common.cancel,
            style: .plain,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addCustomFactor)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "sleep.factor.add_custom"
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? suggestedFactors.count : customFactors.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? L10n.text("sleep.factor.suggested") : L10n.text("sleep.factor.custom")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1, customFactors.isEmpty else { return nil }
        return L10n.text("sleep.factor.custom.empty")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "SleepFactorCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
        let title = indexPath.section == 0 ? suggestedFactors[indexPath.row] : customFactors[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = title
        content.textProperties.color = WellnarioPalette.textPrimary
        content.textProperties.font = WellnarioTypography.font(for: .body)
        content.image = UIImage(systemName: indexPath.section == 0 ? "sparkles" : "person.crop.circle.badge.plus")
        content.imageProperties.tintColor = indexPath.section == 0 ? WellnarioPalette.violet : WellnarioPalette.cyan
        cell.contentConfiguration = content
        cell.backgroundColor = WellnarioPalette.surface
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let factor = indexPath.section == 0 ? suggestedFactors[indexPath.row] : customFactors[indexPath.row]
        WellnessLocalStore.logSleepFactor(factor)
        UIImpactFeedbackGenerator.wellnarioSuccess()
        onLogged?(factor)
        dismiss(animated: true)
    }

    @objc private func addCustomFactor() {
        let alert = UIAlertController(
            title: L10n.text("sleep.factor.custom.add.title"),
            message: L10n.text("sleep.factor.custom.add.message"),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = L10n.text("sleep.factor.custom.placeholder")
            field.clearButtonMode = .whileEditing
            field.accessibilityIdentifier = "sleep.factor.custom.name"
        }
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.add, style: .default) { [weak self, weak alert] _ in
            guard let name = alert?.textFields?.first?.text else { return }
            WellnessLocalStore.addCustomSleepFactor(name)
            self?.tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
        })
        present(alert, animated: true)
    }

    @objc private func cancel() { dismiss(animated: true) }
}

@MainActor
final class WorkoutStarterViewController: WellnessScrollViewController {
    var onStarted: ((String) -> Void)?

    private let strengthButton = ChipButton()
    private let cardioButton = ChipButton()
    private let mobilityButton = ChipButton()
    private var selectedButton: ChipButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("workout.start.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "workout.starter"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.Common.cancel,
            style: .plain,
            target: self,
            action: #selector(cancel)
        )
        buildContent()
        select(strengthButton)
    }

    private func buildContent() {
        let icon = UIImageView(image: UIImage(systemName: "figure.strengthtraining.traditional"))
        icon.tintColor = WellnarioPalette.magenta
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 42, weight: .semibold)
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 70).isActive = true

        let heading = UILabel()
        heading.applyWellnarioStyle(.pageTitle, color: WellnarioPalette.textPrimary)
        heading.text = L10n.text("workout.start.heading")
        heading.textAlignment = .center
        heading.numberOfLines = 0

        let body = UILabel()
        body.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        body.text = L10n.text("workout.start.body")
        body.textAlignment = .center
        body.numberOfLines = 0

        let hero = UIStackView(arrangedSubviews: [icon, heading, body], axis: .vertical, spacing: WellnarioSpacing.xSmall)
        contentStack.addArrangedSubview(makeCard(containing: hero))

        contentStack.addArrangedSubview(makeSectionTitle(L10n.text("workout.type")))
        configure(strengthButton, title: L10n.text("workout.strength"), identifier: "workout.type.strength")
        configure(cardioButton, title: L10n.text("workout.cardio"), identifier: "workout.type.cardio")
        configure(mobilityButton, title: L10n.text("workout.mobility"), identifier: "workout.type.mobility")
        let choices = UIStackView(
            arrangedSubviews: [strengthButton, cardioButton, mobilityButton],
            axis: .vertical,
            spacing: WellnarioSpacing.xxSmall
        )
        contentStack.addArrangedSubview(choices)

        let button = PrimaryButton(title: L10n.text("fitness.start_workout"))
        button.accessibilityIdentifier = "workout.confirm_start"
        button.addTarget(self, action: #selector(start), for: .touchUpInside)
        contentStack.addArrangedSubview(button)
    }

    private func configure(_ button: ChipButton, title: String, identifier: String) {
        button.setTitle(title, for: .normal)
        button.contentHorizontalAlignment = .left
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: #selector(typeTapped(_:)), for: .touchUpInside)
    }

    private func select(_ button: ChipButton) {
        strengthButton.isSelected = strengthButton === button
        cardioButton.isSelected = cardioButton === button
        mobilityButton.isSelected = mobilityButton === button
        selectedButton = button
    }

    @objc private func typeTapped(_ sender: ChipButton) {
        UISelectionFeedbackGenerator().selectionChanged()
        select(sender)
    }

    @objc private func start() {
        guard let type = selectedButton?.title(for: .normal) else { return }
        WellnessLocalStore.startWorkout(type: type)
        UIImpactFeedbackGenerator.wellnarioSuccess()
        onStarted?(type)
        dismiss(animated: true)
    }

    @objc private func cancel() { dismiss(animated: true) }
}
