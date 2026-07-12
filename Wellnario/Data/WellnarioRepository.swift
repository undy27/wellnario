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

public protocol WellnarioRepositoryProtocol: AnyObject {
    var databaseURL: URL { get }
    var userID: UUID { get }

    func fetchPresentationTypes() throws -> [PresentationType]

    func fetchActives(includeArchived: Bool) throws -> [Active]
    func active(id: UUID) throws -> Active?
    func createActive(_ draft: ActiveDraft) throws -> Active
    func updateActive(id: UUID, with draft: ActiveDraft) throws -> Active
    func deleteActive(id: UUID) throws -> DeletionDisposition
    func restoreActive(id: UUID) throws -> Active
    func targetHistory(activeID: UUID) throws -> [ActiveTarget]
    func setTarget(activeID: UUID, lowerBound: Decimal, upperBound: Decimal, effectiveFrom: LocalDay) throws -> ActiveTarget
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
    func updateConsumption(id: UUID, with draft: ConsumptionDraft) throws -> Consumption
    func deleteConsumption(id: UUID) throws

    func dashboard(on day: LocalDay, expiringWithinDays: Int) throws -> DashboardSummary
    func diary(from: LocalDay, through: LocalDay) throws -> [DiaryDay]
    func dailyConsumption(activeID: UUID, from: LocalDay, through: LocalDay) throws -> ConsumptionSeries
}

public final class WellnarioRepository: WellnarioRepositoryProtocol, @unchecked Sendable {
    public static let defaultUserID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    public let databaseURL: URL
    public let userID: UUID

    let database: SQLiteDatabase
    let lock = NSRecursiveLock()

    public init(databaseURL: URL, userID: UUID = WellnarioRepository.defaultUserID) throws {
        self.databaseURL = databaseURL
        self.userID = userID
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
