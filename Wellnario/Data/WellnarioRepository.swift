import Foundation

public enum RepositoryError: Error, Equatable, LocalizedError, Sendable {
    case validation(String)
    case notFound(entity: String, id: UUID)
    case duplicate(String)
    case readOnlySeed
    case storage(String)

    public var errorDescription: String? {
        switch self {
        case let .validation(message): return message
        case let .notFound(entity, id): return "\(entity) \(id.uuidString) was not found."
        case let .duplicate(message): return message
        case .readOnlySeed: return "Seeded catalog metadata is read-only. Personal targets can still be edited."
        case let .storage(message): return message
        }
    }
}

public enum RepositoryEntity: String, Sendable {
    case active
    case target
    case supplement
    case instance
    case consumption
}

public enum RepositoryMutation: String, Sendable {
    case created
    case updated
    case deleted
    case archived
    case restored
}

public struct RepositoryChange: Sendable {
    public let entity: RepositoryEntity
    public let mutation: RepositoryMutation
    public let id: UUID

    public init(entity: RepositoryEntity, mutation: RepositoryMutation, id: UUID) {
        self.entity = entity
        self.mutation = mutation
        self.id = id
    }
}

public extension Notification.Name {
    static let wellnarioRepositoryDidChange = Notification.Name("WellnarioRepositoryDidChange")
}

public enum WellnarioRepositoryNotificationKey {
    public static let change = "change"
}

/// Device-local preference used when an active has a single-value target.
/// Explicit target ranges are never expanded because their bounds already
/// express the user's intended tolerance.
struct ActiveTargetMarginPreferences {
    static let defaultPercentage = 10
    static let allowedPercentages = 0...50

    private static let storageKey = "wellnario.actives.targetMarginPercentage"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var percentage: Int {
        guard defaults.object(forKey: Self.storageKey) != nil else {
            return Self.defaultPercentage
        }
        return Self.allowedPercentages.clamped(defaults.integer(forKey: Self.storageKey))
    }

    func setPercentage(_ percentage: Int) {
        defaults.set(Self.allowedPercentages.clamped(percentage), forKey: Self.storageKey)
    }

    func adjustedBounds(lower: Decimal, upper: Decimal) throws -> (lower: Decimal, upper: Decimal) {
        guard lower == upper, percentage > 0 else { return (lower, upper) }
        let lowerFactor = try DecimalMath.divide(Decimal(100 - percentage), 100)
        let upperFactor = try DecimalMath.divide(Decimal(100 + percentage), 100)
        return (
            try DecimalMath.multiply(lower, lowerFactor),
            try DecimalMath.multiply(upper, upperFactor)
        )
    }
}

enum SupplementReminderTemplate: String, CaseIterable, Hashable, Sendable {
    case fasting
    case breakfast
    case lunch
    case dinner
    case bedtime
    case anytime

    var defaultMinutes: Int {
        switch self {
        case .fasting: 7 * 60
        case .breakfast: 9 * 60
        case .lunch: 14 * 60
        case .dinner: 21 * 60
        case .bedtime: 23 * 60
        case .anytime: 12 * 60
        }
    }
}

/// Device-local schedule used by future supplement reminder notifications.
/// Values are stored as minutes from midnight so they remain independent of
/// any particular date or daylight-saving transition.
struct SupplementReminderSchedulePreferences {
    private static let storagePrefix = "wellnario.supplement.reminderSchedule."
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func minutes(for template: SupplementReminderTemplate) -> Int {
        let key = Self.storagePrefix + template.rawValue
        guard defaults.object(forKey: key) != nil else {
            return template.defaultMinutes
        }
        return min(max(defaults.integer(forKey: key), 0), 23 * 60 + 59)
    }

    func date(
        for template: SupplementReminderTemplate,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: Date())
        return calendar.date(
            byAdding: .minute,
            value: minutes(for: template),
            to: startOfDay
        ) ?? startOfDay
    }

    func setTime(
        _ date: Date,
        for template: SupplementReminderTemplate,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return }
        defaults.set((hour * 60) + minute, forKey: Self.storagePrefix + template.rawValue)
    }
}

enum SupplementReminderRecurrence: String, Codable, CaseIterable, Sendable {
    case weekdays
    case everyDays
}

struct SupplementProductReminder: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let supplementID: UUID
    var timeMinutes: Int
    var recurrence: SupplementReminderRecurrence
    /// ISO weekday bit mask (1 = Sunday ... 7 = Saturday).
    var weekdaysMask: Int
    var intervalDays: Int
    var anchorDay: LocalDay

    init(
        id: UUID = UUID(),
        supplementID: UUID,
        timeMinutes: Int = 12 * 60,
        recurrence: SupplementReminderRecurrence = .weekdays,
        weekdaysMask: Int = 127,
        intervalDays: Int = 1,
        anchorDay: LocalDay = LocalDay(containing: Date(), in: .autoupdatingCurrent)
    ) {
        self.id = id
        self.supplementID = supplementID
        self.timeMinutes = min(max(timeMinutes, 0), 1439)
        self.recurrence = recurrence
        self.weekdaysMask = weekdaysMask & 127
        self.intervalDays = max(1, intervalDays)
        self.anchorDay = anchorDay
    }
}

/// A pre-filled schedule shown by the reminder editor. It deliberately has no
/// identity and is never written to the reminder store until the user saves.
struct SupplementReminderSuggestion: Hashable, Sendable {
    let timeMinutes: [Int]
    let recurrence: SupplementReminderRecurrence
    let weekdaysMask: Int
    let intervalDays: Int
}

/// Device-local product reminder configuration. Reminders belong to a product,
/// so all packages of that product share the same schedule.
struct SupplementProductReminderStore {
    private static let storageKey = "wellnario.supplement.productReminders.v1"
    private static let configuredProductsKey = "wellnario.supplement.productReminders.configuredProducts.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func all() -> [SupplementProductReminder] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let values = try? JSONDecoder().decode([SupplementProductReminder].self, from: data) else {
            return []
        }
        return values
    }

    func reminders(for supplementID: UUID) -> [SupplementProductReminder] {
        all().filter { $0.supplementID == supplementID }
    }

    func hasConfiguration(for supplementID: UUID) -> Bool {
        !reminders(for: supplementID).isEmpty || configuredProductIDs.contains(supplementID)
    }

    func hasUserConfiguration(for supplementID: UUID) -> Bool {
        configuredProductIDs.contains(supplementID)
    }

    func set(
        _ reminders: [SupplementProductReminder],
        for supplementID: UUID,
        marksUserConfiguration: Bool = true
    ) {
        let existing = all().filter { $0.supplementID != supplementID }
        let sharedRecurrence = reminders.first?.recurrence ?? .weekdays
        let sharedWeekdaysMask = reminders.first?.weekdaysMask ?? 127
        let sharedIntervalDays = reminders.first?.intervalDays ?? 1
        let sharedAnchorDay = reminders.first?.anchorDay ?? LocalDay(containing: Date(), in: .autoupdatingCurrent)
        let normalized = reminders.prefix(3).map {
            SupplementProductReminder(
                id: $0.id,
                supplementID: supplementID,
                timeMinutes: $0.timeMinutes,
                recurrence: sharedRecurrence,
                weekdaysMask: sharedWeekdaysMask,
                intervalDays: sharedIntervalDays,
                anchorDay: sharedAnchorDay
            )
        }
        guard let data = try? JSONEncoder().encode(existing + normalized) else { return }
        defaults.set(data, forKey: Self.storageKey)
        if marksUserConfiguration {
            var identifiers = configuredProductIDs
            identifiers.insert(supplementID)
            defaults.set(identifiers.map(\.uuidString).sorted(), forKey: Self.configuredProductsKey)
        }
    }

    func remove(for supplementID: UUID) {
        let remaining = all().filter { $0.supplementID != supplementID }
        guard let data = try? JSONEncoder().encode(remaining) else { return }
        defaults.set(data, forKey: Self.storageKey)
        var identifiers = configuredProductIDs
        identifiers.remove(supplementID)
        defaults.set(identifiers.map(\.uuidString).sorted(), forKey: Self.configuredProductsKey)
    }

    /// Removes schedules created by the former automatic-scheduling flow.
    /// User-confirmed schedules are tracked separately and are never removed.
    @discardableResult
    func removeLegacyUnconfirmedSuggestions() -> Int {
        let configured = configuredProductIDs
        let existing = all()
        let retained = existing.filter { configured.contains($0.supplementID) }
        let removedCount = existing.count - retained.count
        guard removedCount > 0,
              let data = try? JSONEncoder().encode(retained) else {
            return 0
        }
        defaults.set(data, forKey: Self.storageKey)
        return removedCount
    }

    private var configuredProductIDs: Set<UUID> {
        Set(
            (defaults.stringArray(forKey: Self.configuredProductsKey) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }
}

/// Produces a non-persistent suggestion for the reminder editor. The target
/// amount controls both the proposed times and, for discrete products, the
/// interval needed to approximate the daily target.
struct SupplementDefaultReminderPlanner {
    private let schedulePreferences: SupplementReminderSchedulePreferences

    init(
        schedulePreferences: SupplementReminderSchedulePreferences = SupplementReminderSchedulePreferences()
    ) {
        self.schedulePreferences = schedulePreferences
    }

    func suggestion(
        for supplement: Supplement,
        in repository: WellnarioRepositoryProtocol
    ) throws -> SupplementReminderSuggestion? {
        let actives = Dictionary(
            uniqueKeysWithValues: try repository.fetchActives(includeArchived: false).map { ($0.id, $0) }
        )
        let components = supplement.components.compactMap { component -> (SupplementComponent, Active)? in
            guard let active = actives[component.activeID] else { return nil }
            return (component, active)
        }
        guard components.contains(where: { $0.1.currentTarget != nil }) else { return nil }

        let timeMinutes = suggestedTemplates(for: components)
            .map { schedulePreferences.minutes(for: $0) }
            .reduce(into: [Int]()) { result, minutes in
                if !result.contains(minutes) { result.append(minutes) }
            }
            .prefix(3)
        guard !timeMinutes.isEmpty else { return nil }

        let intervalDays = suggestedIntervalDays(
            for: supplement,
            components: components,
            remindersPerDoseDay: timeMinutes.count
        )
        return SupplementReminderSuggestion(
            timeMinutes: Array(timeMinutes),
            recurrence: intervalDays > 1 ? .everyDays : .weekdays,
            weekdaysMask: 127,
            intervalDays: intervalDays
        )
    }

    private func suggestedTemplates(
        for components: [(SupplementComponent, Active)]
    ) -> [SupplementReminderTemplate] {
        if let calcium = components.first(where: { slug(for: $0.1) == "calcium" }),
           targetAmount(for: calcium.1, in: .milligram) > 500 {
            return [.breakfast, .dinner]
        }
        if let berberine = components.first(where: { slug(for: $0.1) == "berberine" }) {
            let servings = estimatedServings(component: berberine.0, active: berberine.1)
            if servings >= 3 { return [.breakfast, .lunch, .dinner] }
            if servings == 2 { return [.breakfast, .dinner] }
            return [.breakfast]
        }

        let slugs = Set(components.compactMap { slug(for: $0.1) })
        if slugs.contains("caffeine") { return [.breakfast] }
        if !slugs.isDisjoint(with: ["melatonin", "glycine"]) { return [.bedtime] }
        if !slugs.isDisjoint(with: ["iron", "l_arginine"]) { return [.fasting] }
        if !slugs.isDisjoint(with: ["magnesium", "ashwagandha"]) { return [.bedtime] }
        if !slugs.isDisjoint(with: [
            "vitamin_d", "vitamin_b12", "omega_3", "zinc", "calcium",
            "astaxanthin", "coenzyme_q10", "spermidine", "resveratrol",
            "nicotinamide_riboside", "quercetin", "lutein", "sulforaphane"
        ]) {
            return [.breakfast]
        }
        return [.anytime]
    }

    private func suggestedIntervalDays(
        for supplement: Supplement,
        components: [(SupplementComponent, Active)],
        remindersPerDoseDay: Int
    ) -> Int {
        guard supplement.basisUnit.family == .discrete else { return 1 }
        let dosesPerDay = Decimal(max(1, remindersPerDoseDay))
        return components.reduce(into: 1) { result, item in
            let (component, active) = item
            guard component.amount > 0,
                  let target = active.currentTarget,
                  let dailyTarget = try? target.unit.convert(target.upperBound, to: component.unit),
                  dailyTarget > 0,
                  let amountPerDoseDay = try? DecimalMath.multiply(component.amount, dosesPerDay),
                  let ratio = try? DecimalMath.divide(amountPerDoseDay, dailyTarget) else {
                return
            }
            let ratioValue = NSDecimalNumber(decimal: ratio).doubleValue
            guard ratioValue.isFinite, ratioValue > 1 else { return }
            let interval = Int(ceil(min(ratioValue, 3_650)))
            result = max(result, interval)
        }
    }

    private func slug(for active: Active) -> String? {
        guard let nameKey = active.nameKey,
              nameKey.hasPrefix("active."),
              nameKey.hasSuffix(".name") else { return nil }
        return String(nameKey.dropFirst("active.".count).dropLast(".name".count))
    }

    private func targetAmount(for active: Active, in unit: DoseUnit) -> Decimal {
        guard let target = active.currentTarget,
              let converted = try? target.unit.convert(target.upperBound, to: unit) else { return 0 }
        return converted
    }

    private func estimatedServings(component: SupplementComponent, active: Active) -> Int {
        guard component.amount > 0,
              let target = active.currentTarget,
              let targetAmount = try? target.unit.convert(target.upperBound, to: component.unit),
              let quotient = try? DecimalMath.divide(targetAmount, component.amount) else {
            return 1
        }
        let value = NSDecimalNumber(decimal: quotient).doubleValue
        return min(3, max(1, Int(ceil(value))))
    }
}

private extension ClosedRange where Bound == Int {
    func clamped(_ value: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

public protocol WellnarioRepositoryProtocol: AnyObject {
    var databaseURL: URL { get }
    var userID: UUID { get }

    func fetchPresentationTypes() throws -> [PresentationType]

    func fetchActives(includeArchived: Bool) throws -> [Active]
    func active(id: UUID) throws -> Active?
    func createActive(_ draft: ActiveDraft) throws -> Active
    func updateActive(id: UUID, with draft: ActiveDraft) throws -> Active
    func setActiveFavorite(id: UUID, isFavorite: Bool) throws -> Active
    func deleteActive(id: UUID) throws -> DeletionDisposition
    func restoreActive(id: UUID) throws -> Active
    func targetHistory(activeID: UUID) throws -> [ActiveTarget]
    func setTarget(activeID: UUID, lowerBound: Decimal, upperBound: Decimal, unit: DoseUnit, effectiveFrom: LocalDay) throws -> ActiveTarget
    func clearTarget(activeID: UUID, effectiveFrom: LocalDay) throws

    func fetchSupplements(includeArchived: Bool) throws -> [Supplement]
    func supplement(id: UUID) throws -> Supplement?
    func createSupplement(_ draft: SupplementDraft) throws -> Supplement
    func updateSupplement(id: UUID, with draft: SupplementDraft) throws -> Supplement
    func deleteSupplement(id: UUID) throws -> DeletionDisposition
    func restoreSupplement(id: UUID) throws -> Supplement

    func fetchInstances(supplementID: UUID?, includeArchived: Bool) throws -> [SupplementInstance]
    func instance(id: UUID) throws -> SupplementInstance?
    func createInstance(_ draft: SupplementInstanceDraft) throws -> SupplementInstance
    func updateInstance(id: UUID, with draft: SupplementInstanceDraft) throws -> SupplementInstance
    func deleteInstance(id: UUID) throws -> DeletionDisposition
    func restoreInstance(id: UUID) throws -> SupplementInstance

    func fetchConsumptions(from: LocalDay?, through: LocalDay?, limit: Int?) throws -> [Consumption]
    func consumption(id: UUID) throws -> Consumption?
    func createConsumption(_ draft: ConsumptionDraft) throws -> Consumption
    func createConsumptions(_ drafts: [ConsumptionDraft]) throws -> [Consumption]
    func updateConsumption(id: UUID, with draft: ConsumptionDraft) throws -> Consumption
    func deleteConsumption(id: UUID) throws

    func dashboard(on day: LocalDay, expiringWithinDays: Int) throws -> DashboardSummary
    func diary(from: LocalDay, through: LocalDay) throws -> [DiaryDay]
    func dailyConsumption(activeID: UUID, from: LocalDay, through: LocalDay) throws -> ConsumptionSeries
}

public extension WellnarioRepositoryProtocol {
    func setTarget(
        activeID: UUID,
        lowerBound: Decimal,
        upperBound: Decimal,
        effectiveFrom: LocalDay
    ) throws -> ActiveTarget {
        guard let active = try active(id: activeID) else {
            throw RepositoryError.notFound(entity: "Active", id: activeID)
        }
        return try setTarget(
            activeID: activeID,
            lowerBound: lowerBound,
            upperBound: upperBound,
            unit: active.baseUnit,
            effectiveFrom: effectiveFrom
        )
    }
}

public final class WellnarioRepository: WellnarioRepositoryProtocol, @unchecked Sendable {
    public static let defaultUserID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    public let databaseURL: URL
    public let userID: UUID

    let database: SQLiteDatabase
    let lock = NSRecursiveLock()
    let activeTargetMarginPreferences: ActiveTargetMarginPreferences

    public init(
        databaseURL: URL,
        userID: UUID = WellnarioRepository.defaultUserID,
        preferencesDefaults: UserDefaults = .standard
    ) throws {
        self.databaseURL = databaseURL
        self.userID = userID
        activeTargetMarginPreferences = ActiveTargetMarginPreferences(defaults: preferencesDefaults)
        do {
            let database = try SQLiteDatabase(url: databaseURL)
            try SchemaMigrator.migrate(database)
            try SeedData.apply(to: database, userID: userID)
            self.database = database
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.storage(error.localizedDescription)
        }
    }

    public static func live(fileManager: FileManager = .default) throws -> WellnarioRepository {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleComponent = Bundle.main.bundleIdentifier ?? "com.wellnario.app"
        let directory = applicationSupport.appendingPathComponent(bundleComponent, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appendingPathComponent("Wellnario.sqlite", isDirectory: false)
        return try WellnarioRepository(databaseURL: databaseURL)
    }

    public func dashboard(on date: Date, in timeZone: TimeZone = .current, expiringWithinDays: Int = 30) throws -> DashboardSummary {
        try dashboard(
            on: LocalDay(containing: date, in: timeZone),
            expiringWithinDays: expiringWithinDays
        )
    }

    public func fetchActives() throws -> [Active] {
        try fetchActives(includeArchived: false)
    }

    public func fetchSupplements() throws -> [Supplement] {
        try fetchSupplements(includeArchived: false)
    }

    public func fetchInstances(supplementID: UUID? = nil) throws -> [SupplementInstance] {
        try fetchInstances(supplementID: supplementID, includeArchived: false)
    }

    func withLock<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        do {
            return try body()
        } catch let error as RepositoryError {
            throw error
        } catch let error as DomainValueError {
            throw RepositoryError.validation(error.localizedDescription)
        } catch {
            throw RepositoryError.storage(error.localizedDescription)
        }
    }

    func notify(entity: RepositoryEntity, mutation: RepositoryMutation, id: UUID) {
        let change = RepositoryChange(entity: entity, mutation: mutation, id: id)
        NotificationCenter.default.post(
            name: .wellnarioRepositoryDidChange,
            object: self,
            userInfo: [WellnarioRepositoryNotificationKey.change: change]
        )
    }
}
