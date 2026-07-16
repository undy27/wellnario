import Foundation

extension WellnarioRepository {
    var today: LocalDay { LocalDay(containing: Date(), in: .current) }

    func uuid(_ row: SQLiteRow, _ column: String) throws -> UUID {
        let value = try row.string(column)
        guard let id = UUID(uuidString: value) else {
            throw RepositoryError.storage("Invalid UUID in \(column): \(value)")
        }
        return id
    }

    func unit(_ row: SQLiteRow, _ column: String) throws -> DoseUnit {
        let value = try row.string(column)
        guard let unit = DoseUnit(rawValue: value) else {
            throw RepositoryError.storage("Invalid dose unit in \(column): \(value)")
        }
        return unit
    }

    func decimal(_ row: SQLiteRow, _ column: String) throws -> Decimal {
        try DecimalCodec.decode(row.string(column))
    }

    func optionalDecimal(_ row: SQLiteRow, _ column: String) throws -> Decimal? {
        guard let value = try row.optionalString(column) else { return nil }
        return try DecimalCodec.decode(value)
    }

    func date(_ row: SQLiteRow, _ column: String) throws -> Date {
        Date(timeIntervalSince1970: try row.double(column))
    }

    func optionalDate(_ row: SQLiteRow, _ column: String) throws -> Date? {
        try row.optionalDouble(column).map(Date.init(timeIntervalSince1970:))
    }

    func localDay(_ row: SQLiteRow, _ column: String) throws -> LocalDay {
        try LocalDay(iso8601: row.string(column))
    }

    func optionalLocalDay(_ row: SQLiteRow, _ column: String) throws -> LocalDay? {
        guard let value = try row.optionalString(column) else { return nil }
        return try LocalDay(iso8601: value)
    }

    func requiredTrimmed(_ value: String, field: String, maximum: Int = 120) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw RepositoryError.validation("\(field) is required.") }
        guard result.count <= maximum else {
            throw RepositoryError.validation("\(field) must contain at most \(maximum) characters.")
        }
        return result
    }

    func optionalTrimmed(_ value: String?, field: String, maximum: Int = 4_000) throws -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.count <= maximum else {
            throw RepositoryError.validation("\(field) must contain at most \(maximum) characters.")
        }
        return result.isEmpty ? nil : result
    }

    func requirePositive(_ value: Decimal, field: String) throws {
        guard DecimalCodec.isFinite(value), value > 0 else {
            throw RepositoryError.validation("\(field) must be greater than zero.")
        }
    }

    func requireNonnegative(_ value: Decimal, field: String) throws {
        guard DecimalCodec.isFinite(value), value >= 0 else {
            throw RepositoryError.validation("\(field) cannot be negative.")
        }
    }

    func binding(_ value: String?) -> SQLiteBinding {
        value.map(SQLiteBinding.text) ?? .null
    }

    func decimalBinding(_ value: Decimal?) throws -> SQLiteBinding {
        guard let value else { return .null }
        return .text(try DecimalCodec.encode(value))
    }

    func mapTarget(_ row: SQLiteRow) throws -> ActiveTarget {
        ActiveTarget(
            id: try uuid(row, "id"),
            activeID: try uuid(row, "active_id"),
            lowerBound: try decimal(row, "lower_amount"),
            upperBound: try decimal(row, "upper_amount"),
            unit: try unit(row, "unit"),
            effectiveFrom: try localDay(row, "effective_from"),
            effectiveThrough: try optionalLocalDay(row, "effective_through"),
            createdAt: try date(row, "created_at"),
            updatedAt: try date(row, "updated_at")
        )
    }

    func currentTarget(activeID: UUID, on day: LocalDay) throws -> ActiveTarget? {
        let rows = try database.query(
            """
            SELECT id, active_id, lower_amount, upper_amount, unit,
                   effective_from, effective_through, created_at, updated_at
            FROM active_targets
            WHERE user_id = ? AND active_id = ?
              AND effective_from <= ?
              AND (effective_through IS NULL OR effective_through >= ?)
            ORDER BY effective_from DESC
            LIMIT 1;
            """,
            bindings: [
                .text(userID.uuidString), .text(activeID.uuidString),
                .text(day.iso8601), .text(day.iso8601)
            ]
        )
        return try rows.first.map(mapTarget)
    }

    func mapActive(_ row: SQLiteRow, targetDay: LocalDay? = nil) throws -> Active {
        let id = try uuid(row, "id")
        return Active(
            id: id,
            nameKey: try row.optionalString("name_key"),
            customName: try row.optionalString("custom_name"),
            descriptionKey: try row.optionalString("description_key"),
            customDescription: try row.optionalString("custom_description"),
            baseUnit: try unit(row, "base_unit"),
            proposedDailyMale: try optionalDecimal(row, "proposed_daily_male"),
            proposedDailyFemale: try optionalDecimal(row, "proposed_daily_female"),
            imageKey: try row.optionalString("image_key"),
            categories: try activeCategories(activeID: id),
            isFavorite: try isActiveFavorite(activeID: id),
            isSeeded: try row.integer("is_seeded") != 0,
            currentTarget: try currentTarget(activeID: id, on: targetDay ?? today),
            createdAt: try date(row, "created_at"),
            updatedAt: try date(row, "updated_at"),
            archivedAt: try optionalDate(row, "archived_at")
        )
    }

    func isActiveFavorite(activeID: UUID) throws -> Bool {
        try database.scalarInteger(
            "SELECT COUNT(*) AS count FROM active_favorites WHERE user_id = ? AND active_id = ?;",
            bindings: [.text(userID.uuidString), .text(activeID.uuidString)]
        ) > 0
    }

    func activeCategories(activeID: UUID) throws -> [ActiveCategory] {
        let rows = try database.query(
            "SELECT category FROM active_category_assignments WHERE active_id = ?;",
            bindings: [.text(activeID.uuidString)]
        )
        let stored = try Set(rows.map { row -> ActiveCategory in
            let rawValue = try row.string("category")
            guard let category = ActiveCategory(rawValue: rawValue) else {
                throw RepositoryError.storage("Invalid active category: \(rawValue)")
            }
            return category
        })
        return ActiveCategory.allCases.filter(stored.contains)
    }

    func loadActive(id: UUID, targetDay: LocalDay? = nil) throws -> Active? {
        let rows = try database.query(
            "SELECT * FROM actives WHERE id = ? LIMIT 1;",
            bindings: [.text(id.uuidString)]
        )
        return try rows.first.map { try mapActive($0, targetDay: targetDay) }
    }

    func mapIllustration(_ row: SQLiteRow) throws -> PresentationIllustration {
        PresentationIllustration(
            id: try uuid(row, "id"),
            presentationTypeID: try uuid(row, "presentation_type_id"),
            variantKey: try row.string("variant_key"),
            assetKey: try row.string("asset_key"),
            displayOrder: Int(try row.integer("display_order"))
        )
    }

    func illustrations(presentationTypeID: UUID) throws -> [PresentationIllustration] {
        try database.query(
            """
            SELECT * FROM presentation_illustrations
            WHERE presentation_type_id = ?
            ORDER BY display_order ASC, id ASC;
            """,
            bindings: [.text(presentationTypeID.uuidString)]
        ).map(mapIllustration)
    }

    func mapPresentationType(_ row: SQLiteRow) throws -> PresentationType {
        let id = try uuid(row, "id")
        return PresentationType(
            id: id,
            nameKey: try row.string("name_key"),
            defaultUnit: try unit(row, "default_unit"),
            illustrations: try illustrations(presentationTypeID: id),
            isSeeded: try row.integer("is_seeded") != 0,
            createdAt: try date(row, "created_at"),
            updatedAt: try date(row, "updated_at")
        )
    }

    func mapComponent(_ row: SQLiteRow) throws -> SupplementComponent {
        SupplementComponent(
            id: try uuid(row, "id"),
            supplementID: try uuid(row, "supplement_id"),
            activeID: try uuid(row, "active_id"),
            amount: try decimal(row, "amount"),
            unit: try unit(row, "unit"),
            displayOrder: Int(try row.integer("display_order"))
        )
    }

    func components(supplementID: UUID) throws -> [SupplementComponent] {
        try database.query(
            """
            SELECT * FROM supplement_components
            WHERE supplement_id = ?
            ORDER BY display_order ASC, id ASC;
            """,
            bindings: [.text(supplementID.uuidString)]
        ).map(mapComponent)
    }

    func mapSupplement(_ row: SQLiteRow) throws -> Supplement {
        let id = try uuid(row, "id")
        return Supplement(
            id: id,
            name: try row.string("name"),
            brand: try row.string("brand"),
            details: try row.optionalString("details"),
            category: try row.optionalString("category"),
            price: try optionalDecimal(row, "price_amount"),
            currencyCode: try row.optionalString("currency_code"),
            imageReference: try row.optionalString("image_reference"),
            presentationTypeID: try uuid(row, "presentation_type_id"),
            basisQuantity: try decimal(row, "basis_quantity"),
            basisUnit: try unit(row, "basis_unit"),
            components: try components(supplementID: id),
            createdAt: try date(row, "created_at"),
            updatedAt: try date(row, "updated_at"),
            archivedAt: try optionalDate(row, "archived_at")
        )
    }

    func loadSupplement(id: UUID) throws -> Supplement? {
        let rows = try database.query(
            "SELECT * FROM supplements WHERE id = ? AND user_id = ? LIMIT 1;",
            bindings: [.text(id.uuidString), .text(userID.uuidString)]
        )
        return try rows.first.map(mapSupplement)
    }

    func mapInstance(_ row: SQLiteRow) throws -> SupplementInstance {
        SupplementInstance(
            id: try uuid(row, "id"),
            supplementID: try uuid(row, "supplement_id"),
            label: try row.string("label"),
            expirationDay: try optionalLocalDay(row, "expiration_day"),
            notes: try row.optionalString("notes"),
            totalQuantity: try optionalDecimal(row, "total_quantity"),
            totalUnit: try row.optionalString("total_unit").map { rawValue in
                guard let unit = DoseUnit(rawValue: rawValue) else {
                    throw RepositoryError.storage("Invalid dose unit in total_unit: \(rawValue)")
                }
                return unit
            },
            createdAt: try date(row, "created_at"),
            updatedAt: try date(row, "updated_at"),
            archivedAt: try optionalDate(row, "archived_at")
        )
    }

    func loadInstance(id: UUID) throws -> SupplementInstance? {
        let rows = try database.query(
            "SELECT * FROM supplement_instances WHERE id = ? AND user_id = ? LIMIT 1;",
            bindings: [.text(id.uuidString), .text(userID.uuidString)]
        )
        return try rows.first.map(mapInstance)
    }

    func mapSnapshot(_ row: SQLiteRow) throws -> ConsumptionActiveSnapshot {
        ConsumptionActiveSnapshot(
            id: try uuid(row, "id"),
            consumptionID: try uuid(row, "consumption_id"),
            activeID: try uuid(row, "active_id"),
            activeNameKey: try row.optionalString("active_name_key_snapshot"),
            activeCustomName: try row.optionalString("active_custom_name_snapshot"),
            amount: try decimal(row, "amount"),
            unit: try unit(row, "unit")
        )
    }

    func snapshots(consumptionID: UUID) throws -> [ConsumptionActiveSnapshot] {
        try database.query(
            """
            SELECT * FROM consumption_active_snapshots
            WHERE consumption_id = ?
            ORDER BY id ASC;
            """,
            bindings: [.text(consumptionID.uuidString)]
        ).map(mapSnapshot)
    }

    func mapConsumption(_ row: SQLiteRow) throws -> Consumption {
        let id = try uuid(row, "id")
        return Consumption(
            id: id,
            instanceID: try uuid(row, "instance_id"),
            supplementNameSnapshot: try row.string("supplement_name_snapshot"),
            instanceLabelSnapshot: try row.string("instance_label_snapshot"),
            quantity: try decimal(row, "quantity"),
            unit: try unit(row, "unit"),
            consumedAt: try date(row, "consumed_at"),
            timeZoneID: try row.string("timezone_id"),
            localDay: try localDay(row, "local_day"),
            notes: try row.optionalString("notes"),
            activeSnapshots: try snapshots(consumptionID: id),
            createdAt: try date(row, "created_at"),
            updatedAt: try date(row, "updated_at")
        )
    }

    func loadConsumption(id: UUID) throws -> Consumption? {
        let rows = try database.query(
            "SELECT * FROM consumptions WHERE id = ? AND user_id = ? LIMIT 1;",
            bindings: [.text(id.uuidString), .text(userID.uuidString)]
        )
        return try rows.first.map(mapConsumption)
    }

    func status(amount: Decimal, lower: Decimal?, upper: Decimal?) -> TargetProgressStatus {
        guard let lower, let upper else { return .noTarget }
        if amount < lower { return .below }
        if amount > upper { return .above }
        return .within
    }
}
