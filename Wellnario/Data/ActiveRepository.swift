import Foundation

extension WellnarioRepository {
    public func fetchPresentationTypes() throws -> [PresentationType] {
        try withLock {
            try database.query(
                "SELECT * FROM presentation_types ORDER BY name_key ASC;"
            ).map(mapPresentationType)
        }
    }

    public func fetchActives(includeArchived: Bool) throws -> [Active] {
        try withLock {
            var sql = "SELECT * FROM actives"
            if !includeArchived { sql += " WHERE archived_at IS NULL" }
            sql += " ORDER BY COALESCE(custom_name, name_key) COLLATE NOCASE ASC;"
            return try database.query(sql).map { try mapActive($0) }
        }
    }

    public func active(id: UUID) throws -> Active? {
        try withLock { try loadActive(id: id) }
    }

    public func createActive(_ draft: ActiveDraft) throws -> Active {
        let id = UUID()
        let created = try withLock { () -> Active in
            let values = try validateActiveDraft(draft, excluding: nil)
            let now = Date().timeIntervalSince1970
            try database.execute(
                """
                INSERT INTO actives (
                    id, name_key, custom_name, description_key, custom_description,
                    base_unit, proposed_daily_male, proposed_daily_female, image_key,
                    is_seeded, created_at, updated_at, archived_at
                ) VALUES (?, NULL, ?, NULL, ?, ?, ?, ?, ?, 0, ?, ?, NULL);
                """,
                bindings: [
                    .text(id.uuidString),
                    .text(values.name),
                    binding(values.description),
                    .text(draft.baseUnit.rawValue),
                    try decimalBinding(draft.proposedDailyMale),
                    try decimalBinding(draft.proposedDailyFemale),
                    binding(values.imageKey),
                    .real(now),
                    .real(now)
                ]
            )
            guard let result = try loadActive(id: id) else {
                throw RepositoryError.notFound(entity: "Active", id: id)
            }
            return result
        }
        notify(entity: .active, mutation: .created, id: id)
        return created
    }

    public func updateActive(id: UUID, with draft: ActiveDraft) throws -> Active {
        let updated = try withLock { () -> Active in
            guard let existing = try loadActive(id: id) else {
                throw RepositoryError.notFound(entity: "Active", id: id)
            }
            guard !existing.isSeeded else { throw RepositoryError.readOnlySeed }
            let values = try validateActiveDraft(draft, excluding: id)

            if !existing.baseUnit.isCompatible(with: draft.baseUnit) {
                let references = try activeReferenceCount(id: id)
                guard references == 0 else {
                    throw RepositoryError.validation("The unit family cannot change while the active is in use.")
                }
            }

            try database.execute(
                """
                UPDATE actives
                SET custom_name = ?, custom_description = ?, base_unit = ?,
                    proposed_daily_male = ?, proposed_daily_female = ?, image_key = ?,
                    updated_at = ?
                WHERE id = ?;
                """,
                bindings: [
                    .text(values.name), binding(values.description), .text(draft.baseUnit.rawValue),
                    try decimalBinding(draft.proposedDailyMale),
                    try decimalBinding(draft.proposedDailyFemale),
                    binding(values.imageKey), .real(Date().timeIntervalSince1970),
                    .text(id.uuidString)
                ]
            )
            guard let result = try loadActive(id: id) else {
                throw RepositoryError.notFound(entity: "Active", id: id)
            }
            return result
        }
        notify(entity: .active, mutation: .updated, id: id)
        return updated
    }

    public func deleteActive(id: UUID) throws -> DeletionDisposition {
        let disposition = try withLock { () -> DeletionDisposition in
            guard let existing = try loadActive(id: id) else {
                throw RepositoryError.notFound(entity: "Active", id: id)
            }
            if existing.isArchived { return .archived }

            let hasReferences = try activeReferenceCount(id: id) > 0
            if existing.isSeeded || hasReferences {
                try database.execute(
                    "UPDATE actives SET archived_at = ?, updated_at = ? WHERE id = ?;",
                    bindings: [
                        .real(Date().timeIntervalSince1970), .real(Date().timeIntervalSince1970),
                        .text(id.uuidString)
                    ]
                )
                return .archived
            }
            try database.execute("DELETE FROM actives WHERE id = ?;", bindings: [.text(id.uuidString)])
            return .deleted
        }
        notify(entity: .active, mutation: disposition == .archived ? .archived : .deleted, id: id)
        return disposition
    }

    public func restoreActive(id: UUID) throws -> Active {
        let restored = try withLock { () -> Active in
            guard let existing = try loadActive(id: id) else {
                throw RepositoryError.notFound(entity: "Active", id: id)
            }
            _ = try validateActiveDraft(
                ActiveDraft(
                    name: existing.customName ?? existing.localizedName(language: .english),
                    description: existing.customDescription,
                    baseUnit: existing.baseUnit,
                    proposedDailyMale: existing.proposedDailyMale,
                    proposedDailyFemale: existing.proposedDailyFemale,
                    imageKey: existing.imageKey
                ),
                excluding: id
            )
            try database.execute(
                "UPDATE actives SET archived_at = NULL, updated_at = ? WHERE id = ?;",
                bindings: [.real(Date().timeIntervalSince1970), .text(id.uuidString)]
            )
            guard let result = try loadActive(id: id) else {
                throw RepositoryError.notFound(entity: "Active", id: id)
            }
            return result
        }
        notify(entity: .active, mutation: .restored, id: id)
        return restored
    }

    public func targetHistory(activeID: UUID) throws -> [ActiveTarget] {
        try withLock {
            guard try loadActive(id: activeID) != nil else {
                throw RepositoryError.notFound(entity: "Active", id: activeID)
            }
            return try database.query(
                """
                SELECT id, active_id, lower_amount, upper_amount, unit,
                       effective_from, effective_through, created_at, updated_at
                FROM active_targets
                WHERE user_id = ? AND active_id = ?
                ORDER BY effective_from ASC;
                """,
                bindings: [.text(userID.uuidString), .text(activeID.uuidString)]
            ).map(mapTarget)
        }
    }

    public func setTarget(
        activeID: UUID,
        lowerBound: Decimal,
        upperBound: Decimal,
        effectiveFrom: LocalDay
    ) throws -> ActiveTarget {
        let result = try withLock { () -> ActiveTarget in
            guard let active = try loadActive(id: activeID), !active.isArchived else {
                throw RepositoryError.notFound(entity: "Active", id: activeID)
            }
            try requireNonnegative(lowerBound, field: "Lower target")
            try requireNonnegative(upperBound, field: "Upper target")
            guard lowerBound <= upperBound else {
                throw RepositoryError.validation("The lower target cannot exceed the upper target.")
            }

            return try database.transaction {
                let previousThrough = try effectiveFrom.adding(days: -1)
                try database.execute(
                    """
                    UPDATE active_targets
                    SET effective_through = ?, updated_at = ?
                    WHERE user_id = ? AND active_id = ? AND effective_from < ?
                      AND (effective_through IS NULL OR effective_through >= ?);
                    """,
                    bindings: [
                        .text(previousThrough.iso8601), .real(Date().timeIntervalSince1970),
                        .text(userID.uuidString), .text(activeID.uuidString),
                        .text(effectiveFrom.iso8601), .text(effectiveFrom.iso8601)
                    ]
                )

                let nextRows = try database.query(
                    """
                    SELECT effective_from FROM active_targets
                    WHERE user_id = ? AND active_id = ? AND effective_from > ?
                    ORDER BY effective_from ASC LIMIT 1;
                    """,
                    bindings: [
                        .text(userID.uuidString), .text(activeID.uuidString), .text(effectiveFrom.iso8601)
                    ]
                )
                let effectiveThrough: LocalDay? = try nextRows.first.map {
                    try LocalDay(iso8601: $0.string("effective_from")).adding(days: -1)
                }

                let existingRows = try database.query(
                    """
                    SELECT id FROM active_targets
                    WHERE user_id = ? AND active_id = ? AND effective_from = ? LIMIT 1;
                    """,
                    bindings: [
                        .text(userID.uuidString), .text(activeID.uuidString), .text(effectiveFrom.iso8601)
                    ]
                )
                let targetID = try existingRows.first.map { try uuid($0, "id") } ?? UUID()
                let now = Date().timeIntervalSince1970
                try database.execute(
                    """
                    INSERT INTO active_targets (
                        id, user_id, active_id, lower_amount, upper_amount, unit,
                        effective_from, effective_through, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(user_id, active_id, effective_from) DO UPDATE SET
                        lower_amount = excluded.lower_amount,
                        upper_amount = excluded.upper_amount,
                        unit = excluded.unit,
                        effective_through = excluded.effective_through,
                        updated_at = excluded.updated_at;
                    """,
                    bindings: [
                        .text(targetID.uuidString), .text(userID.uuidString), .text(activeID.uuidString),
                        .text(try DecimalCodec.encode(lowerBound)), .text(try DecimalCodec.encode(upperBound)),
                        .text(active.baseUnit.rawValue), .text(effectiveFrom.iso8601),
                        effectiveThrough.map { .text($0.iso8601) } ?? .null,
                        .real(now), .real(now)
                    ]
                )
                guard let target = try currentTarget(activeID: activeID, on: effectiveFrom) else {
                    throw RepositoryError.notFound(entity: "Target", id: targetID)
                }
                return target
            }
        }
        notify(entity: .target, mutation: .updated, id: result.id)
        return result
    }

    public func clearTarget(activeID: UUID, effectiveFrom: LocalDay) throws {
        try withLock {
            guard try loadActive(id: activeID) != nil else {
                throw RepositoryError.notFound(entity: "Active", id: activeID)
            }
            try database.transaction {
                let previousThrough = try effectiveFrom.adding(days: -1)
                try database.execute(
                    """
                    UPDATE active_targets
                    SET effective_through = ?, updated_at = ?
                    WHERE user_id = ? AND active_id = ? AND effective_from < ?
                      AND (effective_through IS NULL OR effective_through >= ?);
                    """,
                    bindings: [
                        .text(previousThrough.iso8601), .real(Date().timeIntervalSince1970),
                        .text(userID.uuidString), .text(activeID.uuidString),
                        .text(effectiveFrom.iso8601), .text(effectiveFrom.iso8601)
                    ]
                )
                try database.execute(
                    """
                    DELETE FROM active_targets
                    WHERE user_id = ? AND active_id = ? AND effective_from >= ?;
                    """,
                    bindings: [
                        .text(userID.uuidString), .text(activeID.uuidString), .text(effectiveFrom.iso8601)
                    ]
                )
            }
        }
        notify(entity: .target, mutation: .deleted, id: activeID)
    }

    private func validateActiveDraft(
        _ draft: ActiveDraft,
        excluding id: UUID?
    ) throws -> (name: String, description: String?, imageKey: String?) {
        let name = try requiredTrimmed(draft.name, field: "Active name")
        let description = try optionalTrimmed(draft.description, field: "Active description")
        let imageKey = try optionalTrimmed(draft.imageKey, field: "Active image key", maximum: 240)
        if let proposed = draft.proposedDailyMale {
            try requireNonnegative(proposed, field: "Proposed daily amount for men")
        }
        if let proposed = draft.proposedDailyFemale {
            try requireNonnegative(proposed, field: "Proposed daily amount for women")
        }

        let comparableName = normalizedCatalogName(name)
        let rows = try database.query("SELECT id, name_key, custom_name FROM actives;")
        for row in rows {
            let rowID = try uuid(row, "id")
            if rowID == id { continue }
            let candidates: [String]
            if let customName = try row.optionalString("custom_name") {
                candidates = [customName]
            } else if let key = try row.optionalString("name_key") {
                candidates = CatalogLanguage.allCases.map { CatalogLocalization.text(for: key, language: $0) }
            } else {
                candidates = []
            }
            if candidates.contains(where: { normalizedCatalogName($0) == comparableName }) {
                throw RepositoryError.duplicate("An active with this name already exists.")
            }
        }
        return (name, description, imageKey)
    }

    private func normalizedCatalogName(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "es_ES")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func activeReferenceCount(id: UUID) throws -> Int64 {
        try database.scalarInteger(
            """
            SELECT
                (SELECT COUNT(*) FROM supplement_components WHERE active_id = ?) +
                (SELECT COUNT(*) FROM consumption_active_snapshots WHERE active_id = ?) +
                (SELECT COUNT(*) FROM active_targets WHERE active_id = ?) AS count;
            """,
            bindings: [.text(id.uuidString), .text(id.uuidString), .text(id.uuidString)]
        )
    }
}
