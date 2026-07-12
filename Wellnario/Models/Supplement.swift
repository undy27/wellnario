import Foundation

public struct PresentationIllustration: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let presentationTypeID: UUID
    public let variantKey: String
    public let assetKey: String
    public let displayOrder: Int

    public init(
        id: UUID,
        presentationTypeID: UUID,
        variantKey: String,
        assetKey: String,
        displayOrder: Int
    ) {
        self.id = id
        self.presentationTypeID = presentationTypeID
        self.variantKey = variantKey
        self.assetKey = assetKey
        self.displayOrder = displayOrder
    }
}

public struct PresentationType: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let nameKey: String
    public let defaultUnit: DoseUnit
    public let illustrations: [PresentationIllustration]
    public let isSeeded: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        nameKey: String,
        defaultUnit: DoseUnit,
        illustrations: [PresentationIllustration],
        isSeeded: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.nameKey = nameKey
        self.defaultUnit = defaultUnit
        self.illustrations = illustrations
        self.isSeeded = isSeeded
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func localizedName(language: CatalogLanguage) -> String {
        CatalogLocalization.text(for: nameKey, language: language)
    }
}

public struct SupplementComponent: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let supplementID: UUID
    public let activeID: UUID
    /// Amount of active contained in the supplement's shared basis quantity.
    public let amount: Decimal
    public let unit: DoseUnit
    public let displayOrder: Int

    public init(
        id: UUID,
        supplementID: UUID,
        activeID: UUID,
        amount: Decimal,
        unit: DoseUnit,
        displayOrder: Int
    ) {
        self.id = id
        self.supplementID = supplementID
        self.activeID = activeID
        self.amount = amount
        self.unit = unit
        self.displayOrder = displayOrder
    }
}

public struct SupplementComponentDraft: Hashable, Sendable {
    public var activeID: UUID
    public var amount: Decimal
    public var unit: DoseUnit

    public init(activeID: UUID, amount: Decimal, unit: DoseUnit) {
        self.activeID = activeID
        self.amount = amount
        self.unit = unit
    }
}

public struct Supplement: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let brand: String
    public let details: String?
    public let category: String?
    public let price: Decimal?
    public let currencyCode: String?
    public let imageReference: String?
    public let presentationTypeID: UUID
    /// Label serving, e.g. 2 capsules or 5 ml.
    public let basisQuantity: Decimal
    public let basisUnit: DoseUnit
    public let components: [SupplementComponent]
    public let createdAt: Date
    public let updatedAt: Date
    public let archivedAt: Date?

    public init(
        id: UUID,
        name: String,
        brand: String,
        details: String?,
        category: String?,
        price: Decimal?,
        currencyCode: String?,
        imageReference: String?,
        presentationTypeID: UUID,
        basisQuantity: Decimal,
        basisUnit: DoseUnit,
        components: [SupplementComponent],
        createdAt: Date,
        updatedAt: Date,
        archivedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.details = details
        self.category = category
        self.price = price
        self.currencyCode = currencyCode
        self.imageReference = imageReference
        self.presentationTypeID = presentationTypeID
        self.basisQuantity = basisQuantity
        self.basisUnit = basisUnit
        self.components = components
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
}

public struct SupplementDraft: Hashable, Sendable {
    public var name: String
    public var brand: String
    public var details: String?
    public var category: String?
    public var price: Decimal?
    public var currencyCode: String?
    public var imageReference: String?
    public var presentationTypeID: UUID
    public var basisQuantity: Decimal
    public var basisUnit: DoseUnit
    public var components: [SupplementComponentDraft]

    public init(
        name: String,
        brand: String,
        details: String? = nil,
        category: String? = nil,
        price: Decimal? = nil,
        currencyCode: String? = nil,
        imageReference: String? = nil,
        presentationTypeID: UUID,
        basisQuantity: Decimal,
        basisUnit: DoseUnit,
        components: [SupplementComponentDraft]
    ) {
        self.name = name
        self.brand = brand
        self.details = details
        self.category = category
        self.price = price
        self.currencyCode = currencyCode
        self.imageReference = imageReference
        self.presentationTypeID = presentationTypeID
        self.basisQuantity = basisQuantity
        self.basisUnit = basisUnit
        self.components = components
    }
}

public struct SupplementInstance: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let supplementID: UUID
    public let label: String
    public let expirationDay: LocalDay?
    public let notes: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let archivedAt: Date?

    public init(
        id: UUID,
        supplementID: UUID,
        label: String,
        expirationDay: LocalDay?,
        notes: String?,
        createdAt: Date,
        updatedAt: Date,
        archivedAt: Date?
    ) {
        self.id = id
        self.supplementID = supplementID
        self.label = label
        self.expirationDay = expirationDay
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
}

public struct SupplementInstanceDraft: Hashable, Sendable {
    public var supplementID: UUID
    public var label: String?
    public var expirationDay: LocalDay?
    public var notes: String?

    public init(
        supplementID: UUID,
        label: String? = nil,
        expirationDay: LocalDay? = nil,
        notes: String? = nil
    ) {
        self.supplementID = supplementID
        self.label = label
        self.expirationDay = expirationDay
        self.notes = notes
    }
}
