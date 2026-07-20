import UIKit

struct SleepFactorLogEntry: Codable, Hashable, Sendable {
    let date: Date
    let factor: String
    let factorID: String?
    let numericValue: Double?

    init(
        date: Date,
        factor: String,
        factorID: String? = nil,
        numericValue: Double? = nil
    ) {
        self.date = date
        self.factor = factor
        self.factorID = factorID
        self.numericValue = numericValue
    }
}

@MainActor
enum WellnessLocalStore {
    private static let customFactorsKey = "wellnario.sleep.customFactors"
    private static let customFactorDefinitionsKey = "wellnario.sleep.customFactorDefinitions.v2"
    private static let disabledFactorIDsKey = "wellnario.sleep.disabledFactorIDs.v2"
    private static let sleepFactorLogKey = "wellnario.sleep.factorLog"
    private static let lastSleepFactorKey = "wellnario.sleep.lastFactor"
    private static let lastSleepFactorDateKey = "wellnario.sleep.lastFactorDate"
    private static let lastWorkoutTypeKey = "wellnario.fitness.lastWorkoutType"
    private static let lastWorkoutDateKey = "wellnario.fitness.lastWorkoutDate"

    static var customSleepFactors: [String] {
        customSleepFactorDefinitions.map(\.title)
    }

    static var suggestedSleepFactors: [String] {
        SleepFactorCatalog.predefined
            .filter { $0.source == .manual }
            .map(\.title)
    }

    static var customSleepFactorDefinitions: [SleepFactorDefinition] {
        if let data = UserDefaults.standard.data(forKey: customFactorDefinitionsKey),
           let definitions = try? JSONDecoder().decode([SleepFactorDefinition].self, from: data) {
            return definitions.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
        return (UserDefaults.standard.stringArray(forKey: customFactorsKey) ?? []).map {
            SleepFactorDefinition(
                id: legacyCustomFactorID(for: $0),
                category: .custom,
                title: $0,
                valueKind: .discrete,
                source: .manual,
                symbolName: "tag.fill",
                analysisStep: 1,
                analysisStepLabel: ""
            )
        }
    }

    static func allSleepFactorDefinitions(
        repository: WellnarioRepositoryProtocol? = nil
    ) -> [SleepFactorDefinition] {
        SleepFactorCatalog.predefined
            + SleepSupplementFactorCatalog.definitions(repository: repository)
            + customSleepFactorDefinitions
    }

    static func enabledSleepFactorDefinitions(
        repository: WellnarioRepositoryProtocol? = nil
    ) -> [SleepFactorDefinition] {
        let disabledIDs = Set(
            UserDefaults.standard.stringArray(forKey: disabledFactorIDsKey) ?? []
        )
        return allSleepFactorDefinitions(repository: repository).filter { !disabledIDs.contains($0.id) }
    }

    static func isSleepFactorEnabled(
        _ id: String,
        repository: WellnarioRepositoryProtocol? = nil
    ) -> Bool {
        enabledSleepFactorDefinitions(repository: repository).contains { $0.id == id }
    }

    static func setSleepFactor(_ id: String, enabled: Bool) {
        var disabledIDs = Set(
            UserDefaults.standard.stringArray(forKey: disabledFactorIDsKey) ?? []
        )
        if enabled {
            disabledIDs.remove(id)
        } else {
            disabledIDs.insert(id)
        }
        UserDefaults.standard.set(disabledIDs.sorted(), forKey: disabledFactorIDsKey)
    }

    static var sleepFactorLog: [SleepFactorLogEntry] {
        if let data = UserDefaults.standard.data(forKey: sleepFactorLogKey),
           let log = try? JSONDecoder().decode([SleepFactorLogEntry].self, from: data) {
            return log.sorted { $0.date > $1.date }
        }
        guard let lastSleepFactor,
              let date = UserDefaults.standard.object(forKey: lastSleepFactorDateKey) as? Date else {
            return []
        }
        return [SleepFactorLogEntry(date: date, factor: lastSleepFactor)]
    }

    static var lastSleepFactor: String? {
        UserDefaults.standard.string(forKey: lastSleepFactorKey)
    }

    static func addCustomSleepFactor(
        _ name: String,
        valueKind: SleepFactorValueKind = .discrete
    ) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        var definitions = customSleepFactorDefinitions
        guard !allSleepFactorDefinitions().contains(where: {
            $0.title.localizedCaseInsensitiveCompare(normalized) == .orderedSame
        }) else {
            return
        }
        definitions.append(SleepFactorDefinition(
            id: "custom.\(UUID().uuidString.lowercased())",
            category: .custom,
            title: normalized,
            valueKind: valueKind,
            source: .manual,
            symbolName: valueKind == .discrete ? "tag.fill" : "number.circle.fill",
            analysisStep: 1,
            analysisStepLabel: valueKind.unit ?? ""
        ))
        persistCustomDefinitions(definitions)
    }

    static func removeCustomSleepFactor(_ name: String) {
        let definitions = customSleepFactorDefinitions.filter {
            $0.title.localizedCaseInsensitiveCompare(name) != .orderedSame
        }
        persistCustomDefinitions(definitions)
    }

    static func sleepFactorEntry(
        for definition: SleepFactorDefinition,
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SleepFactorLogEntry? {
        sleepFactorLog.first {
            calendar.isDate($0.date, inSameDayAs: date)
                && entry($0, matches: definition)
        }
    }

    static func setSleepFactorValue(
        _ value: Double?,
        for definition: SleepFactorDefinition,
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let startOfDay = calendar.startOfDay(for: date)
        var log = sleepFactorLog.filter {
            !(calendar.isDate($0.date, inSameDayAs: startOfDay)
                && entry($0, matches: definition))
        }
        if definition.valueKind == .discrete {
            if value != nil {
                log.append(SleepFactorLogEntry(
                    date: startOfDay,
                    factor: definition.title,
                    factorID: definition.id
                ))
            }
        } else if let value, value.isFinite {
            log.append(SleepFactorLogEntry(
                date: startOfDay,
                factor: definition.title,
                factorID: definition.id,
                numericValue: value
            ))
        }
        persistSleepFactorLog(log)
        refreshLastSleepFactorCache(log: log, changedDate: startOfDay, calendar: calendar)
    }

    static func factors(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> [String] {
        sleepFactorLog
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .map(\.factor)
    }

    static func setSleepFactors(
        _ factors: [String],
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let normalizedFactors = Array(Set(factors.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        let startOfDay = calendar.startOfDay(for: date)
        var log = sleepFactorLog.filter { !calendar.isDate($0.date, inSameDayAs: startOfDay) }
        log.append(contentsOf: normalizedFactors.map { factor in
            let definition = SleepFactorCatalog.definition(matchingLegacyTitle: factor)
            return SleepFactorLogEntry(
                date: startOfDay,
                factor: factor,
                factorID: definition?.id
            )
        })
        persistSleepFactorLog(log)

        guard calendar.isDateInToday(startOfDay) else { return }
        if let factor = normalizedFactors.last {
            UserDefaults.standard.set(factor, forKey: lastSleepFactorKey)
            UserDefaults.standard.set(Date(), forKey: lastSleepFactorDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastSleepFactorKey)
            UserDefaults.standard.removeObject(forKey: lastSleepFactorDateKey)
        }
    }

    static func logSleepFactor(_ name: String, on date: Date = Date()) {
        var factors = factors(on: date)
        guard !factors.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return
        }
        factors.append(name)
        setSleepFactors(factors, on: date)
        guard Calendar.autoupdatingCurrent.isDateInToday(date) else { return }
        UserDefaults.standard.set(name, forKey: lastSleepFactorKey)
        UserDefaults.standard.set(Date(), forKey: lastSleepFactorDateKey)
    }

    private static func entry(
        _ entry: SleepFactorLogEntry,
        matches definition: SleepFactorDefinition
    ) -> Bool {
        if let factorID = entry.factorID { return factorID == definition.id }
        return entry.factor.localizedCaseInsensitiveCompare(definition.title) == .orderedSame
    }

    private static func persistSleepFactorLog(_ log: [SleepFactorLogEntry]) {
        let sorted = log.sorted { $0.date > $1.date }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        UserDefaults.standard.set(data, forKey: sleepFactorLogKey)
    }

    private static func persistCustomDefinitions(_ definitions: [SleepFactorDefinition]) {
        let sorted = definitions.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        UserDefaults.standard.set(data, forKey: customFactorDefinitionsKey)
        UserDefaults.standard.set(sorted.map(\.title), forKey: customFactorsKey)
    }

    private static func refreshLastSleepFactorCache(
        log: [SleepFactorLogEntry],
        changedDate: Date,
        calendar: Calendar
    ) {
        guard calendar.isDateInToday(changedDate) else { return }
        let todayEntries = log.filter { calendar.isDateInToday($0.date) }
        if let last = todayEntries.last {
            UserDefaults.standard.set(last.factor, forKey: lastSleepFactorKey)
            UserDefaults.standard.set(Date(), forKey: lastSleepFactorDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastSleepFactorKey)
            UserDefaults.standard.removeObject(forKey: lastSleepFactorDateKey)
        }
    }

    private static func legacyCustomFactorID(for name: String) -> String {
        let scalars = name.lowercased().unicodeScalars
            .map { String($0.value, radix: 16) }
            .joined(separator: "-")
        return "custom.legacy.\(scalars)"
    }

    static func startWorkout(type: String) {
        UserDefaults.standard.set(type, forKey: lastWorkoutTypeKey)
        UserDefaults.standard.set(Date(), forKey: lastWorkoutDateKey)
    }
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
