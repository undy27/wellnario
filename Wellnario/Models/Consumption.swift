import Foundation

public struct ConsumptionActiveSnapshot: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let consumptionID: UUID
    public let activeID: UUID
    public let activeNameKey: String?
    public let activeCustomName: String?
    public let amount: Decimal
    public let unit: DoseUnit

    public init(
        id: UUID,
        consumptionID: UUID,
        activeID: UUID,
        activeNameKey: String?,
        activeCustomName: String?,
        amount: Decimal,
        unit: DoseUnit
    ) {
        self.id = id
        self.consumptionID = consumptionID
        self.activeID = activeID
        self.activeNameKey = activeNameKey
        self.activeCustomName = activeCustomName
        self.amount = amount
        self.unit = unit
    }

    public func localizedActiveName(language: CatalogLanguage) -> String {
        activeCustomName ?? activeNameKey.map { CatalogLocalization.text(for: $0, language: language) } ?? ""
    }
}

public struct Consumption: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let instanceID: UUID
    public let supplementNameSnapshot: String
    public let instanceLabelSnapshot: String
    public let quantity: Decimal
    public let unit: DoseUnit
    /// Absolute instant. SQLite stores it as Unix seconds, which is UTC.
    public let consumedAt: Date
    public let timeZoneID: String
    /// Day as originally experienced by the user, stable across travel/DST.
    public let localDay: LocalDay
    public let notes: String?
    public let activeSnapshots: [ConsumptionActiveSnapshot]
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        instanceID: UUID,
        supplementNameSnapshot: String,
        instanceLabelSnapshot: String,
        quantity: Decimal,
        unit: DoseUnit,
        consumedAt: Date,
        timeZoneID: String,
        localDay: LocalDay,
        notes: String?,
        activeSnapshots: [ConsumptionActiveSnapshot],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.instanceID = instanceID
        self.supplementNameSnapshot = supplementNameSnapshot
        self.instanceLabelSnapshot = instanceLabelSnapshot
        self.quantity = quantity
        self.unit = unit
        self.consumedAt = consumedAt
        self.timeZoneID = timeZoneID
        self.localDay = localDay
        self.notes = notes
        self.activeSnapshots = activeSnapshots
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ConsumptionDraft: Hashable, Sendable {
    public var instanceID: UUID
    public var quantity: Decimal
    public var unit: DoseUnit
    public var consumedAt: Date
    public var timeZoneID: String
    public var notes: String?

    public init(
        instanceID: UUID,
        quantity: Decimal,
        unit: DoseUnit,
        consumedAt: Date = Date(),
        timeZoneID: String = TimeZone.current.identifier,
        notes: String? = nil
    ) {
        self.instanceID = instanceID
        self.quantity = quantity
        self.unit = unit
        self.consumedAt = consumedAt
        self.timeZoneID = timeZoneID
        self.notes = notes
    }
}

public struct DiaryDay: Identifiable, Hashable, Sendable {
    public var id: LocalDay { day }
    public let day: LocalDay
    public let consumptions: [Consumption]

    public init(day: LocalDay, consumptions: [Consumption]) {
        self.day = day
        self.consumptions = consumptions
    }
}

public enum TargetProgressStatus: String, Codable, Hashable, Sendable {
    case noTarget
    case below
    case within
    case above
}

public struct ActiveDailyProgress: Identifiable, Hashable, Sendable {
    public var id: UUID { active.id }
    public let active: Active
    public let consumedAmount: Decimal
    public let unit: DoseUnit
    public let targetLower: Decimal?
    public let targetUpper: Decimal?
    public let status: TargetProgressStatus

    public init(
        active: Active,
        consumedAmount: Decimal,
        unit: DoseUnit,
        targetLower: Decimal?,
        targetUpper: Decimal?,
        status: TargetProgressStatus
    ) {
        self.active = active
        self.consumedAmount = consumedAmount
        self.unit = unit
        self.targetLower = targetLower
        self.targetUpper = targetUpper
        self.status = status
    }
}

public struct DashboardSummary: Hashable, Sendable {
    public let day: LocalDay
    public let supplementCount: Int
    public let instanceCount: Int
    public let consumptionCount: Int
    public let expiringSoonCount: Int
    public let expiredCount: Int
    public let activeProgress: [ActiveDailyProgress]
    public let recentConsumptions: [Consumption]

    public init(
        day: LocalDay,
        supplementCount: Int,
        instanceCount: Int,
        consumptionCount: Int,
        expiringSoonCount: Int,
        expiredCount: Int,
        activeProgress: [ActiveDailyProgress],
        recentConsumptions: [Consumption]
    ) {
        self.day = day
        self.supplementCount = supplementCount
        self.instanceCount = instanceCount
        self.consumptionCount = consumptionCount
        self.expiringSoonCount = expiringSoonCount
        self.expiredCount = expiredCount
        self.activeProgress = activeProgress
        self.recentConsumptions = recentConsumptions
    }
}

public struct DailyConsumptionPoint: Identifiable, Hashable, Sendable {
    public var id: LocalDay { day }
    public let day: LocalDay
    public let amount: Decimal
    public let targetLower: Decimal?
    public let targetUpper: Decimal?
    public let status: TargetProgressStatus

    public init(
        day: LocalDay,
        amount: Decimal,
        targetLower: Decimal?,
        targetUpper: Decimal?,
        status: TargetProgressStatus
    ) {
        self.day = day
        self.amount = amount
        self.targetLower = targetLower
        self.targetUpper = targetUpper
        self.status = status
    }
}

public struct ConsumptionSeries: Hashable, Sendable {
    public let active: Active
    public let from: LocalDay
    public let through: LocalDay
    public let unit: DoseUnit
    public let points: [DailyConsumptionPoint]
    public let total: Decimal
    /// Arithmetic mean over every calendar day, including zero-consumption days.
    public let average: Decimal
    public let daysWithinTarget: Int

    public init(
        active: Active,
        from: LocalDay,
        through: LocalDay,
        unit: DoseUnit,
        points: [DailyConsumptionPoint],
        total: Decimal,
        average: Decimal,
        daysWithinTarget: Int
    ) {
        self.active = active
        self.from = from
        self.through = through
        self.unit = unit
        self.points = points
        self.total = total
        self.average = average
        self.daysWithinTarget = daysWithinTarget
    }
}

public enum DeletionDisposition: String, Codable, Hashable, Sendable {
    case deleted
    case archived
}
