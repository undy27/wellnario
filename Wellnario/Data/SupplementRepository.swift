import Foundation

extension WellnarioRepository {
    public func fetchSupplements(includeArchived: Bool) throws -> [Supplement] {
        try withLock {
            var sql = "SELECT * FROM supplements WHERE user_id = ?"
            if !includeArchived { sql += " AND archived_at IS NULL" }
            sql += " ORDER BY name COLLATE NOCASE ASC, brand COLLATE NOCASE ASC;"
            return try database.query(sql, bindings: [.text(userID.uuidString)]).map(mapSupplement)
        }
    }

    public func supplement(id: UUID) throws -> Supplement? {
        try withLock { try loadSupplement(id: id) }
    }

    public func createSupplement(_ draft: SupplementDraft) throws -> Supplement {
        let id = UUID()
        let created = try withLock { () -> Supplement in
            let values = try validateSupplementDraft(draft, allowingArchivedActiveIDs: [])
            let now = Date().timeIntervalSince1970
            try database.transaction {
                try database.execute(
                    """
                    INSERT INTO supplements (
                        id, user_id, name, brand, details, category, price_amount,
                        currency_code, image_reference, presentation_type_id,
                        basis_quantity, basis_unit, created_at, updated_at, archived_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL);
                    """,
                    bindings: [
                        .text(id.uuidString), .text(userID.uuidString), .text(values.name), .text(values.brand),
                        binding(values.details), binding(values.category), try decimalBinding(values.price),
                        binding(values.currencyCode), binding(values.imageReference),
                        .text(draft.presentationTypeID.uuidString),
                        .text(try DecimalCodec.encode(draft.basisQuantity)), .text(draft.basisUnit.rawValue),
                        .real(now), .real(now)
                    ]
                )
                try replaceComponents(supplementID: id, drafts: draft.components)
            }
            guard let result = try loadSupplement(id: id) else {
                throw RepositoryError.notFound(entity: "Supplement", id: id)
            }
            return result
        }
        notify(entity: .supplement, mutation: .created, id: id)
        return created
    }

    public func updateSupplement(id: UUID, with draft: SupplementDraft) throws -> Supplement {
        let updated = try withLock { () -> Supplement in
            guard let existing = try loadSupplement(id: id) else {
                throw RepositoryError.notFound(entity: "Supplement", id: id)
            }
            guard !existing.isArchived else {
                throw RepositoryError.validation("Restore the supplement before editing it.")
            }
            let values = try validateSupplementDraft(
                draft,
                allowingArchivedActiveIDs: Set(existing.components.map(\.activeID))
            )
            try database.transaction {
                try database.execute(
                    """
                    UPDATE supplements SET
                        name = ?, brand = ?, details = ?, category = ?, price_amount = ?,
                        currency_code = ?, image_reference = ?, presentation_type_id = ?,
                        basis_quantity = ?, basis_unit = ?, updated_at = ?
                    WHERE id = ? AND user_id = ?;
                    """,
                    bindings: [
                        .text(values.name), .text(values.brand), binding(values.details), binding(values.category),
                        try decimalBinding(values.price), binding(values.currencyCode), binding(values.imageReference),
                        .text(draft.presentationTypeID.uuidString),
                        .text(try DecimalCodec.encode(draft.basisQuantity)), .text(draft.basisUnit.rawValue),
                        .real(Date().timeIntervalSince1970), .text(id.uuidString), .text(userID.uuidString)
                    ]
                )
                try replaceComponents(supplementID: id, drafts: draft.components)
            }
            guard let result = try loadSupplement(id: id) else {
                throw RepositoryError.notFound(entity: "Supplement", id: id)
            }
            return result
        }
        notify(entity: .supplement, mutation: .updated, id: id)
        return updated
    }

    public func deleteSupplement(id: UUID) throws -> DeletionDisposition {
        let disposition = try withLock { () -> DeletionDisposition in
            guard let existing = try loadSupplement(id: id) else {
                throw RepositoryError.notFound(entity: "Supplement", id: id)
            }
            if existing.isArchived { return .archived }
            let historyCount = try database.scalarInteger(
                """
                SELECT COUNT(*) AS count
                FROM consumptions c
                JOIN supplement_instances i ON i.id = c.instance_id
                WHERE i.supplement_id = ?;
                """,
                bindings: [.text(id.uuidString)]
            )
            if historyCount > 0 {
                let now = Date().timeIntervalSince1970
                try database.transaction {
                    try database.execute(
                        "UPDATE supplements SET archived_at = ?, updated_at = ? WHERE id = ?;",
                        bindings: [.real(now), .real(now), .text(id.uuidString)]
                    )
                    try database.execute(
                        """
                        UPDATE supplement_instances SET archived_at = ?, updated_at = ?
                        WHERE supplement_id = ? AND archived_at IS NULL;
                        """,
                        bindings: [.real(now), .real(now), .text(id.uuidString)]
                    )
                }
                return .archived
            }
            try database.execute("DELETE FROM supplements WHERE id = ?;", bindings: [.text(id.uuidString)])
            return .deleted
        }
        notify(entity: .supplement, mutation: disposition == .archived ? .archived : .deleted, id: id)
        return disposition
    }

    public func restoreSupplement(id: UUID) throws -> Supplement {
        let restored = try withLock { () -> Supplement in
            guard let existing = try loadSupplement(id: id) else {
                throw RepositoryError.notFound(entity: "Supplement", id: id)
            }
            guard let archivedAt = existing.archivedAt else { return existing }
            let now = Date().timeIntervalSince1970
            try database.transaction {
                try database.execute(
                    "UPDATE supplements SET archived_at = NULL, updated_at = ? WHERE id = ?;",
                    bindings: [.real(now), .text(id.uuidString)]
                )
                try database.execute(
                    """
                    UPDATE supplement_instances SET archived_at = NULL, updated_at = ?
                    WHERE supplement_id = ? AND archived_at = ?;
                    """,
                    bindings: [
                        .real(now), .text(id.uuidString), .real(archivedAt.timeIntervalSince1970)
                    ]
                )
            }
            guard let result = try loadSupplement(id: id) else {
                throw RepositoryError.notFound(entity: "Supplement", id: id)
            }
            return result
        }
        notify(entity: .supplement, mutation: .restored, id: id)
        return restored
    }

    public func fetchInstances(supplementID: UUID?, includeArchived: Bool) throws -> [SupplementInstance] {
        try withLock {
            var sql = "SELECT * FROM supplement_instances WHERE user_id = ?"
            var bindings: [SQLiteBinding] = [.text(userID.uuidString)]
            if let supplementID {
                sql += " AND supplement_id = ?"
                bindings.append(.text(supplementID.uuidString))
            }
            if !includeArchived { sql += " AND archived_at IS NULL" }
            sql += " ORDER BY expiration_day IS NULL ASC, expiration_day ASC, label COLLATE NOCASE ASC;"
            return try database.query(sql, bindings: bindings).map(mapInstance)
        }
    }

    public func instance(id: UUID) throws -> SupplementInstance? {
        try withLock { try loadInstance(id: id) }
    }

    public func createInstance(_ draft: SupplementInstanceDraft) throws -> SupplementInstance {
        let id = UUID()
        let created = try withLock { () -> SupplementInstance in
            guard let supplement = try loadSupplement(id: draft.supplementID), !supplement.isArchived else {
                throw RepositoryError.notFound(entity: "Supplement", id: draft.supplementID)
            }
            let label = try instanceLabel(draft.label)
            let notes = try optionalTrimmed(draft.notes, field: "Instance notes")
            let initialQuantity = draft.initialQuantity ?? draft.totalQuantity
            let initialUnit = draft.initialUnit ?? draft.totalUnit
            try validateInstanceAmounts(
                remainingQuantity: draft.totalQuantity,
                remainingUnit: draft.totalUnit,
                initialQuantity: initialQuantity,
                initialUnit: initialUnit
            )
            let now = Date().timeIntervalSince1970
            try database.execute(
                """
                INSERT INTO supplement_instances (
                    id, supplement_id, user_id, label, expiration_day, notes, total_quantity, total_unit,
                    initial_quantity, initial_unit, created_at, updated_at, archived_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL);
                """,
                bindings: [
                    .text(id.uuidString), .text(draft.supplementID.uuidString), .text(userID.uuidString),
                    .text(label), draft.expirationDay.map { .text($0.iso8601) } ?? .null,
                    binding(notes), try decimalBinding(draft.totalQuantity), binding(draft.totalUnit?.rawValue),
                    try decimalBinding(initialQuantity), binding(initialUnit?.rawValue),
                    .real(now), .real(now)
                ]
            )
            guard let result = try loadInstance(id: id) else {
                throw RepositoryError.notFound(entity: "Instance", id: id)
            }
            return result
        }
        notify(entity: .instance, mutation: .created, id: id)
        return created
    }

    public func updateInstance(id: UUID, with draft: SupplementInstanceDraft) throws -> SupplementInstance {
        let updated = try withLock { () -> SupplementInstance in
            guard let existing = try loadInstance(id: id) else {
                throw RepositoryError.notFound(entity: "Instance", id: id)
            }
            guard !existing.isArchived else {
                throw RepositoryError.validation("Restore the instance before editing it.")
            }
            guard let supplement = try loadSupplement(id: draft.supplementID), !supplement.isArchived else {
                throw RepositoryError.notFound(entity: "Supplement", id: draft.supplementID)
            }
            if existing.supplementID != draft.supplementID {
                let historyCount = try database.scalarInteger(
                    "SELECT COUNT(*) AS count FROM consumptions WHERE instance_id = ?;",
                    bindings: [.text(id.uuidString)]
                )
                guard historyCount == 0 else {
                    throw RepositoryError.validation("An instance with consumption history cannot change product.")
                }
            }
            let label = try instanceLabel(draft.label)
            let notes = try optionalTrimmed(draft.notes, field: "Instance notes")
            // The initial content is a historical reference set when the package is
            // created. Editing the remaining content must never redefine it.
            let initialQuantity = existing.initialQuantity
            let initialUnit = existing.initialUnit
            try validateInstanceAmounts(
                remainingQuantity: draft.totalQuantity,
                remainingUnit: draft.totalUnit,
                initialQuantity: initialQuantity,
                initialUnit: initialUnit
            )
            try database.execute(
                """
                UPDATE supplement_instances SET supplement_id = ?, label = ?, expiration_day = ?,
                    notes = ?, total_quantity = ?, total_unit = ?, initial_quantity = ?, initial_unit = ?, updated_at = ?
                WHERE id = ? AND user_id = ?;
                """,
                bindings: [
                    .text(draft.supplementID.uuidString), .text(label),
                    draft.expirationDay.map { .text($0.iso8601) } ?? .null,
                    binding(notes), try decimalBinding(draft.totalQuantity), binding(draft.totalUnit?.rawValue),
                    try decimalBinding(initialQuantity), binding(initialUnit?.rawValue),
                    .real(Date().timeIntervalSince1970),
                    .text(id.uuidString), .text(userID.uuidString)
                ]
            )
            guard let result = try loadInstance(id: id) else {
                throw RepositoryError.notFound(entity: "Instance", id: id)
            }
            return result
        }
        notify(entity: .instance, mutation: .updated, id: id)
        return updated
    }

    public func deleteInstance(id: UUID) throws -> DeletionDisposition {
        let disposition = try withLock { () -> DeletionDisposition in
            guard let existing = try loadInstance(id: id) else {
                throw RepositoryError.notFound(entity: "Instance", id: id)
            }
            if existing.isArchived { return .archived }
            let historyCount = try database.scalarInteger(
                "SELECT COUNT(*) AS count FROM consumptions WHERE instance_id = ?;",
                bindings: [.text(id.uuidString)]
            )
            if historyCount > 0 {
                let now = Date().timeIntervalSince1970
                try database.execute(
                    "UPDATE supplement_instances SET archived_at = ?, updated_at = ? WHERE id = ?;",
                    bindings: [.real(now), .real(now), .text(id.uuidString)]
                )
                return .archived
            }
            try database.execute(
                "DELETE FROM supplement_instances WHERE id = ?;",
                bindings: [.text(id.uuidString)]
            )
            return .deleted
        }
        notify(entity: .instance, mutation: disposition == .archived ? .archived : .deleted, id: id)
        return disposition
    }

    public func restoreInstance(id: UUID) throws -> SupplementInstance {
        let restored = try withLock { () -> SupplementInstance in
            guard let existing = try loadInstance(id: id) else {
                throw RepositoryError.notFound(entity: "Instance", id: id)
            }
            guard let supplement = try loadSupplement(id: existing.supplementID), !supplement.isArchived else {
                throw RepositoryError.validation("Restore the supplement before restoring this instance.")
            }
            try database.execute(
                "UPDATE supplement_instances SET archived_at = NULL, updated_at = ? WHERE id = ?;",
                bindings: [.real(Date().timeIntervalSince1970), .text(id.uuidString)]
            )
            guard let result = try loadInstance(id: id) else {
                throw RepositoryError.notFound(entity: "Instance", id: id)
            }
            return result
        }
        notify(entity: .instance, mutation: .restored, id: id)
        return restored
    }

    private struct ValidatedSupplementDraft {
        let name: String
        let brand: String
        let details: String?
        let category: String?
        let price: Decimal?
        let currencyCode: String?
        let imageReference: String?
    }

    private func validateSupplementDraft(
        _ draft: SupplementDraft,
        allowingArchivedActiveIDs: Set<UUID>
    ) throws -> ValidatedSupplementDraft {
        let name = try requiredTrimmed(draft.name, field: "Supplement name")
        let brand = try optionalTrimmed(draft.brand, field: "Brand", maximum: 120) ?? ""
        let details = try optionalTrimmed(draft.details, field: "Supplement description")
        let category = try optionalTrimmed(draft.category, field: "Category", maximum: 120)
        let imageReference = try optionalTrimmed(draft.imageReference, field: "Image reference", maximum: 1_024)
        try requirePositive(draft.basisQuantity, field: "Serving quantity")

        guard try database.scalarInteger(
            "SELECT COUNT(*) AS count FROM presentation_types WHERE id = ?;",
            bindings: [.text(draft.presentationTypeID.uuidString)]
        ) == 1 else {
            throw RepositoryError.notFound(entity: "Presentation type", id: draft.presentationTypeID)
        }
        guard !draft.components.isEmpty else {
            throw RepositoryError.validation("Add at least one monitored active.")
        }
        guard Set(draft.components.map(\.activeID)).count == draft.components.count else {
            throw RepositoryError.validation("Each active can appear only once in a supplement.")
        }
        for component in draft.components {
            try requirePositive(component.amount, field: "Active amount")
            guard let active = try loadActive(id: component.activeID),
                  !active.isArchived || allowingArchivedActiveIDs.contains(component.activeID) else {
                throw RepositoryError.notFound(entity: "Active", id: component.activeID)
            }
            guard component.unit.isCompatible(with: active.baseUnit) else {
                throw RepositoryError.validation(
                    "\(component.unit.rawValue) is incompatible with \(active.baseUnit.rawValue)."
                )
            }
        }

        var currencyCode: String?
        if let price = draft.price {
            try requireNonnegative(price, field: "Price")
            let code = try requiredTrimmed(draft.currencyCode ?? "", field: "Currency code", maximum: 3).uppercased()
            let allowed = CharacterSet.uppercaseLetters
            guard code.count == 3, code.unicodeScalars.allSatisfy(allowed.contains) else {
                throw RepositoryError.validation("Currency must be a three-letter ISO code.")
            }
            currencyCode = code
        } else {
            currencyCode = nil
        }
        return ValidatedSupplementDraft(
            name: name,
            brand: brand,
            details: details,
            category: category,
            price: draft.price,
            currencyCode: currencyCode,
            imageReference: imageReference
        )
    }

    private func replaceComponents(
        supplementID: UUID,
        drafts: [SupplementComponentDraft]
    ) throws {
        try database.execute(
            "DELETE FROM supplement_components WHERE supplement_id = ?;",
            bindings: [.text(supplementID.uuidString)]
        )
        for (index, component) in drafts.enumerated() {
            try database.execute(
                """
                INSERT INTO supplement_components (
                    id, supplement_id, active_id, amount, unit, display_order
                ) VALUES (?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(UUID().uuidString), .text(supplementID.uuidString),
                    .text(component.activeID.uuidString), .text(try DecimalCodec.encode(component.amount)),
                    .text(component.unit.rawValue), .integer(Int64(index))
                ]
            )
        }
    }

    private func instanceLabel(_ proposed: String?) throws -> String {
        try optionalTrimmed(proposed, field: "Instance label", maximum: 120) ?? ""
    }

    private func validateInstanceAmounts(
        remainingQuantity: Decimal?,
        remainingUnit: DoseUnit?,
        initialQuantity: Decimal?,
        initialUnit: DoseUnit?
    ) throws {
        guard (remainingQuantity == nil) == (remainingUnit == nil),
              (initialQuantity == nil) == (initialUnit == nil) else {
            throw RepositoryError.validation("Package content requires both an amount and a unit.")
        }
        if let remainingQuantity {
            try requireNonnegative(remainingQuantity, field: "Remaining package content")
        }
        if let initialQuantity {
            try requireNonnegative(initialQuantity, field: "Initial package content")
        }
        if let remainingUnit, let initialUnit, !remainingUnit.isCompatible(with: initialUnit) {
            throw RepositoryError.validation("Initial and remaining package content must use compatible units.")
        }
    }
}
