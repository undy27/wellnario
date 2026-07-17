import Foundation

extension WellnarioRepository {
    public func fetchConsumptions(
        from: LocalDay? = nil,
        through: LocalDay? = nil,
        limit: Int? = nil
    ) throws -> [Consumption] {
        try withLock {
            if let from, let through, from > through {
                throw RepositoryError.validation("The start day must not be after the end day.")
            }
            if let limit, !(1...10_000).contains(limit) {
                throw RepositoryError.validation("The consumption limit must be between 1 and 10,000.")
            }

            var sql = "SELECT * FROM consumptions WHERE user_id = ?"
            var bindings: [SQLiteBinding] = [.text(userID.uuidString)]
            if let from {
                sql += " AND local_day >= ?"
                bindings.append(.text(from.iso8601))
            }
            if let through {
                sql += " AND local_day <= ?"
                bindings.append(.text(through.iso8601))
            }
            sql += " ORDER BY consumed_at DESC, id DESC"
            if let limit {
                sql += " LIMIT ?"
                bindings.append(.integer(Int64(limit)))
            }
            sql += ";"
            return try database.query(sql, bindings: bindings).map(mapConsumption)
        }
    }

    public func consumption(id: UUID) throws -> Consumption? {
        try withLock { try loadConsumption(id: id) }
    }

    public func createConsumption(_ draft: ConsumptionDraft) throws -> Consumption {
        let id = UUID()
        let created = try withLock { () -> Consumption in
            let prepared = try prepareConsumption(draft, allowArchivedInstance: false)
            let now = Date().timeIntervalSince1970
            try database.transaction {
                try database.execute(
                    """
                    INSERT INTO consumptions (
                        id, instance_id, user_id, supplement_name_snapshot,
                        instance_label_snapshot, quantity, unit, consumed_at,
                        timezone_id, local_day, notes, inventory_applied, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .text(id.uuidString), .text(draft.instanceID.uuidString), .text(userID.uuidString),
                        .text(prepared.supplementName), .text(prepared.instanceLabel),
                        .text(try DecimalCodec.encode(draft.quantity)), .text(draft.unit.rawValue),
                        .real(draft.consumedAt.timeIntervalSince1970), .text(prepared.timeZone.identifier),
                        .text(prepared.localDay.iso8601), binding(prepared.notes), .integer(0),
                        .real(now), .real(now)
                    ]
                )
                try replaceSnapshots(consumptionID: id, snapshots: prepared.snapshots)
                let inventoryApplied = try applyInventoryConsumption(
                    instanceID: draft.instanceID,
                    quantity: draft.quantity,
                    unit: draft.unit
                )
                if inventoryApplied {
                    try setInventoryApplied(true, to: id)
                }
            }
            guard let result = try loadConsumption(id: id) else {
                throw RepositoryError.notFound(entity: "Consumption", id: id)
            }
            return result
        }
        notify(entity: .consumption, mutation: .created, id: id)
        return created
    }

    public func updateConsumption(id: UUID, with draft: ConsumptionDraft) throws -> Consumption {
        let updated = try withLock { () -> Consumption in
            guard let existing = try loadConsumption(id: id) else {
                throw RepositoryError.notFound(entity: "Consumption", id: id)
            }
            let hadInventoryApplied = try inventoryWasApplied(to: id)
            try requirePositive(draft.quantity, field: "Consumed quantity")
            guard let timeZone = TimeZone(identifier: draft.timeZoneID) else {
                throw RepositoryError.validation("The selected time zone is invalid.")
            }
            let notes = try optionalTrimmed(draft.notes, field: "Consumption notes")
            let localDay = LocalDay(containing: draft.consumedAt, in: timeZone)

            let snapshots: [PreparedSnapshot]
            let supplementName: String
            let instanceLabel: String
            if existing.instanceID == draft.instanceID {
                guard draft.unit.isCompatible(with: existing.unit) else {
                    throw RepositoryError.validation(
                        "The unit of a historical consumption cannot change to an incompatible unit."
                    )
                }
                let comparableNewQuantity = try draft.unit.convert(draft.quantity, to: existing.unit)
                let scale = try DecimalMath.divide(comparableNewQuantity, existing.quantity)
                snapshots = try existing.activeSnapshots.map {
                    PreparedSnapshot(
                        activeID: $0.activeID,
                        activeNameKey: $0.activeNameKey,
                        activeCustomName: $0.activeCustomName,
                        amount: try DecimalMath.multiply($0.amount, scale),
                        unit: $0.unit
                    )
                }
                supplementName = existing.supplementNameSnapshot
                instanceLabel = existing.instanceLabelSnapshot
            } else {
                let prepared = try prepareConsumption(draft, allowArchivedInstance: false)
                snapshots = prepared.snapshots
                supplementName = prepared.supplementName
                instanceLabel = prepared.instanceLabel
            }

            try database.transaction {
                if hadInventoryApplied {
                    try restoreInventoryConsumption(
                        instanceID: existing.instanceID,
                        quantity: existing.quantity,
                        unit: existing.unit
                    )
                }
                let inventoryApplied = try applyInventoryConsumption(
                    instanceID: draft.instanceID,
                    quantity: draft.quantity,
                    unit: draft.unit
                )
                try database.execute(
                    """
                    UPDATE consumptions SET
                        instance_id = ?, supplement_name_snapshot = ?, instance_label_snapshot = ?,
                        quantity = ?, unit = ?, consumed_at = ?, timezone_id = ?, local_day = ?,
                        notes = ?, inventory_applied = ?, updated_at = ?
                    WHERE id = ? AND user_id = ?;
                    """,
                    bindings: [
                        .text(draft.instanceID.uuidString), .text(supplementName), .text(instanceLabel),
                        .text(try DecimalCodec.encode(draft.quantity)), .text(draft.unit.rawValue),
                        .real(draft.consumedAt.timeIntervalSince1970), .text(timeZone.identifier),
                        .text(localDay.iso8601), binding(notes), .integer(inventoryApplied ? 1 : 0),
                        .real(Date().timeIntervalSince1970),
                        .text(id.uuidString), .text(userID.uuidString)
                    ]
                )
                try replaceSnapshots(consumptionID: id, snapshots: snapshots)
            }
            guard let result = try loadConsumption(id: id) else {
                throw RepositoryError.notFound(entity: "Consumption", id: id)
            }
            return result
        }
        notify(entity: .consumption, mutation: .updated, id: id)
        return updated
    }

    public func deleteConsumption(id: UUID) throws {
        try withLock {
            guard let existing = try loadConsumption(id: id) else {
                throw RepositoryError.notFound(entity: "Consumption", id: id)
            }
            let hadInventoryApplied = try inventoryWasApplied(to: id)
            try database.transaction {
                if hadInventoryApplied {
                    try restoreInventoryConsumption(
                        instanceID: existing.instanceID,
                        quantity: existing.quantity,
                        unit: existing.unit
                    )
                }
                try database.execute(
                    "DELETE FROM consumptions WHERE id = ? AND user_id = ?;",
                    bindings: [.text(id.uuidString), .text(userID.uuidString)]
                )
            }
        }
        notify(entity: .consumption, mutation: .deleted, id: id)
    }

    public func diary(from: LocalDay, through: LocalDay) throws -> [DiaryDay] {
        try withLock {
            guard from <= through else {
                throw RepositoryError.validation("The start day must not be after the end day.")
            }
            let consumptions = try fetchConsumptions(from: from, through: through, limit: nil)
            let grouped = Dictionary(grouping: consumptions, by: \.localDay)
            return grouped.keys.sorted(by: >).map { day in
                DiaryDay(
                    day: day,
                    consumptions: grouped[day, default: []].sorted {
                        if $0.consumedAt == $1.consumedAt { return $0.id.uuidString > $1.id.uuidString }
                        return $0.consumedAt > $1.consumedAt
                    }
                )
            }
        }
    }

    public func dailyConsumption(
        activeID: UUID,
        from: LocalDay,
        through: LocalDay
    ) throws -> ConsumptionSeries {
        try withLock {
            guard from <= through else {
                throw RepositoryError.validation("The start day must not be after the end day.")
            }
            guard let active = try loadActive(id: activeID) else {
                throw RepositoryError.notFound(entity: "Active", id: activeID)
            }
            let days = try inclusiveDays(from: from, through: through)
            let firstRecordedDay = try database.query(
                """
                SELECT MIN(c.local_day) AS first_recorded_day
                FROM consumption_active_snapshots s
                JOIN consumptions c ON c.id = s.consumption_id
                WHERE c.user_id = ? AND s.active_id = ?;
                """,
                bindings: [.text(userID.uuidString), .text(activeID.uuidString)]
            ).first.map { try optionalLocalDay($0, "first_recorded_day") } ?? nil
            let rows = try database.query(
                """
                SELECT c.local_day, s.amount, s.unit
                FROM consumption_active_snapshots s
                JOIN consumptions c ON c.id = s.consumption_id
                WHERE c.user_id = ? AND s.active_id = ?
                  AND c.local_day >= ? AND c.local_day <= ?
                ORDER BY c.local_day ASC;
                """,
                bindings: [
                    .text(userID.uuidString), .text(activeID.uuidString),
                    .text(from.iso8601), .text(through.iso8601)
                ]
            )

            var totals: [LocalDay: Decimal] = [:]
            for row in rows {
                let day = try localDay(row, "local_day")
                let sourceUnit = try unit(row, "unit")
                let normalized = try sourceUnit.convert(try decimal(row, "amount"), to: active.baseUnit)
                totals[day] = try DecimalMath.add(totals[day] ?? 0, normalized)
            }

            var points: [DailyConsumptionPoint] = []
            var total: Decimal = 0
            var daysWithinTarget = 0
            for day in days {
                let amount = totals[day] ?? 0
                let isRecordedPeriod = firstRecordedDay.map { day >= $0 } ?? false
                if isRecordedPeriod {
                    total = try DecimalMath.add(total, amount)
                }
                let target = try currentTarget(activeID: activeID, on: day)
                let targetBounds: (lower: Decimal, upper: Decimal)? = try target.map { target in
                    let lower = try target.unit.convert(target.lowerBound, to: active.baseUnit)
                    let upper = try target.unit.convert(target.upperBound, to: active.baseUnit)
                    return try activeTargetMarginPreferences.adjustedBounds(lower: lower, upper: upper)
                }
                let lower = targetBounds?.lower
                let upper = targetBounds?.upper
                let progressStatus = status(amount: amount, lower: lower, upper: upper)
                if isRecordedPeriod, progressStatus == .within { daysWithinTarget += 1 }
                points.append(
                    DailyConsumptionPoint(
                        day: day,
                        amount: amount,
                        targetLower: lower,
                        targetUpper: upper,
                        status: progressStatus
                    )
                )
            }
            let recordedDayCount = firstRecordedDay.map { firstDay in
                days.lazy.filter { $0 >= firstDay }.count
            } ?? 0
            let average = recordedDayCount > 0
                ? try DecimalMath.divide(total, Decimal(recordedDayCount))
                : 0
            return ConsumptionSeries(
                active: active,
                from: from,
                through: through,
                unit: active.baseUnit,
                points: points,
                firstRecordedDay: firstRecordedDay,
                total: total,
                average: average,
                daysWithinTarget: daysWithinTarget
            )
        }
    }

    public func dashboard(
        on day: LocalDay,
        expiringWithinDays: Int = 30
    ) throws -> DashboardSummary {
        try withLock {
            guard expiringWithinDays >= 0 else {
                throw RepositoryError.validation("The expiration window cannot be negative.")
            }
            let expirationLimit = try day.adding(days: expiringWithinDays)
            let supplements = Int(try database.scalarInteger(
                "SELECT COUNT(*) AS count FROM supplements WHERE user_id = ? AND archived_at IS NULL;",
                bindings: [.text(userID.uuidString)]
            ))
            let instances = Int(try database.scalarInteger(
                "SELECT COUNT(*) AS count FROM supplement_instances WHERE user_id = ? AND archived_at IS NULL;",
                bindings: [.text(userID.uuidString)]
            ))
            let expired = Int(try database.scalarInteger(
                """
                SELECT COUNT(*) AS count FROM supplement_instances
                WHERE user_id = ? AND archived_at IS NULL
                  AND expiration_day IS NOT NULL AND expiration_day < ?;
                """,
                bindings: [.text(userID.uuidString), .text(day.iso8601)]
            ))
            let expiring = Int(try database.scalarInteger(
                """
                SELECT COUNT(*) AS count FROM supplement_instances
                WHERE user_id = ? AND archived_at IS NULL
                  AND expiration_day >= ? AND expiration_day <= ?;
                """,
                bindings: [
                    .text(userID.uuidString), .text(day.iso8601), .text(expirationLimit.iso8601)
                ]
            ))
            let recent = try fetchConsumptions(from: day, through: day, limit: nil)

            let consumedIDRows = try database.query(
                """
                SELECT DISTINCT s.active_id
                FROM consumption_active_snapshots s
                JOIN consumptions c ON c.id = s.consumption_id
                WHERE c.user_id = ? AND c.local_day = ?;
                """,
                bindings: [.text(userID.uuidString), .text(day.iso8601)]
            )
            let consumedIDs = Set(try consumedIDRows.map { try uuid($0, "active_id") })
            let activeRows = try database.query(
                "SELECT * FROM actives WHERE archived_at IS NULL ORDER BY COALESCE(custom_name, name_key) ASC;"
            )
            let actives = try activeRows.map { try mapActive($0, targetDay: day) }
                .filter { $0.currentTarget != nil || consumedIDs.contains($0.id) }
            let progress = try actives.map { active -> ActiveDailyProgress in
                let series = try dailyConsumption(activeID: active.id, from: day, through: day)
                let point = series.points[0]
                return ActiveDailyProgress(
                    active: active,
                    consumedAmount: point.amount,
                    unit: active.baseUnit,
                    targetLower: point.targetLower,
                    targetUpper: point.targetUpper,
                    status: point.status
                )
            }
            return DashboardSummary(
                day: day,
                supplementCount: supplements,
                instanceCount: instances,
                consumptionCount: recent.count,
                expiringSoonCount: expiring,
                expiredCount: expired,
                activeProgress: progress,
                recentConsumptions: recent
            )
        }
    }

    private struct PreparedSnapshot {
        let activeID: UUID
        let activeNameKey: String?
        let activeCustomName: String?
        let amount: Decimal
        let unit: DoseUnit
    }

    private struct PreparedConsumption {
        let supplementName: String
        let instanceLabel: String
        let timeZone: TimeZone
        let localDay: LocalDay
        let notes: String?
        let snapshots: [PreparedSnapshot]
    }

    private func prepareConsumption(
        _ draft: ConsumptionDraft,
        allowArchivedInstance: Bool
    ) throws -> PreparedConsumption {
        try requirePositive(draft.quantity, field: "Consumed quantity")
        guard let timeZone = TimeZone(identifier: draft.timeZoneID) else {
            throw RepositoryError.validation("The selected time zone is invalid.")
        }
        guard let instance = try loadInstance(id: draft.instanceID),
              allowArchivedInstance || !instance.isArchived else {
            throw RepositoryError.notFound(entity: "Instance", id: draft.instanceID)
        }
        guard let supplement = try loadSupplement(id: instance.supplementID),
              allowArchivedInstance || !supplement.isArchived else {
            throw RepositoryError.notFound(entity: "Supplement", id: instance.supplementID)
        }
        guard draft.unit.isCompatible(with: supplement.basisUnit) else {
            throw RepositoryError.validation(
                "\(draft.unit.rawValue) is incompatible with the supplement serving unit \(supplement.basisUnit.rawValue)."
            )
        }
        let normalizedQuantity = try draft.unit.convert(draft.quantity, to: supplement.basisUnit)
        let fraction = try DecimalMath.divide(normalizedQuantity, supplement.basisQuantity)
        let snapshots = try supplement.components.map { component -> PreparedSnapshot in
            guard let active = try loadActive(id: component.activeID) else {
                throw RepositoryError.notFound(entity: "Active", id: component.activeID)
            }
            let componentAmount = try component.unit.convert(component.amount, to: active.baseUnit)
            return PreparedSnapshot(
                activeID: active.id,
                activeNameKey: active.nameKey,
                activeCustomName: active.customName,
                amount: try DecimalMath.multiply(componentAmount, fraction),
                unit: active.baseUnit
            )
        }
        return PreparedConsumption(
            supplementName: supplement.name,
            instanceLabel: instance.label,
            timeZone: timeZone,
            localDay: LocalDay(containing: draft.consumedAt, in: timeZone),
            notes: try optionalTrimmed(draft.notes, field: "Consumption notes"),
            snapshots: snapshots
        )
    }

    private func replaceSnapshots(
        consumptionID: UUID,
        snapshots: [PreparedSnapshot]
    ) throws {
        try database.execute(
            "DELETE FROM consumption_active_snapshots WHERE consumption_id = ?;",
            bindings: [.text(consumptionID.uuidString)]
        )
        for snapshot in snapshots {
            try database.execute(
                """
                INSERT INTO consumption_active_snapshots (
                    id, consumption_id, active_id, active_name_key_snapshot,
                    active_custom_name_snapshot, amount, unit
                ) VALUES (?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .text(UUID().uuidString), .text(consumptionID.uuidString),
                    .text(snapshot.activeID.uuidString), binding(snapshot.activeNameKey),
                    binding(snapshot.activeCustomName), .text(try DecimalCodec.encode(snapshot.amount)),
                    .text(snapshot.unit.rawValue)
                ]
            )
        }
    }

    private func applyInventoryConsumption(
        instanceID: UUID,
        quantity: Decimal,
        unit: DoseUnit
    ) throws -> Bool {
        try adjustRemainingInventory(
            instanceID: instanceID,
            quantity: quantity,
            unit: unit,
            restoring: false
        )
    }

    private func inventoryWasApplied(to consumptionID: UUID) throws -> Bool {
        let rows = try database.query(
            """
            SELECT inventory_applied
            FROM consumptions
            WHERE id = ? AND user_id = ?;
            """,
            bindings: [.text(consumptionID.uuidString), .text(userID.uuidString)]
        )
        guard let row = rows.first else {
            throw RepositoryError.notFound(entity: "Consumption", id: consumptionID)
        }
        return try row.integer("inventory_applied") != 0
    }

    private func setInventoryApplied(_ applied: Bool, to consumptionID: UUID) throws {
        try database.execute(
            """
            UPDATE consumptions
            SET inventory_applied = ?
            WHERE id = ? AND user_id = ?;
            """,
            bindings: [
                .integer(applied ? 1 : 0),
                .text(consumptionID.uuidString),
                .text(userID.uuidString)
            ]
        )
    }

    private func restoreInventoryConsumption(
        instanceID: UUID,
        quantity: Decimal,
        unit: DoseUnit
    ) throws {
        _ = try adjustRemainingInventory(
            instanceID: instanceID,
            quantity: quantity,
            unit: unit,
            restoring: true
        )
    }

    /// Keeps the intake history and the editable amount remaining in a package
    /// in sync. Instances without a configured amount remain valid and simply
    /// opt out of automatic inventory tracking.
    private func adjustRemainingInventory(
        instanceID: UUID,
        quantity: Decimal,
        unit: DoseUnit,
        restoring: Bool
    ) throws -> Bool {
        guard let instance = try loadInstance(id: instanceID) else {
            throw RepositoryError.notFound(entity: "Instance", id: instanceID)
        }
        guard let remainingQuantity = instance.totalQuantity,
              let remainingUnit = instance.totalUnit else {
            return false
        }
        guard unit.isCompatible(with: remainingUnit) else {
            throw RepositoryError.validation(
                "The intake unit is incompatible with the inventory unit."
            )
        }

        let normalizedQuantity = try unit.convert(quantity, to: remainingUnit)
        let adjustedQuantity: Decimal
        if restoring {
            adjustedQuantity = try DecimalMath.add(remainingQuantity, normalizedQuantity)
        } else {
            let negativeQuantity = try DecimalMath.multiply(normalizedQuantity, -1)
            let difference = try DecimalMath.add(remainingQuantity, negativeQuantity)
            adjustedQuantity = max(0, difference)
        }

        try database.execute(
            """
            UPDATE supplement_instances
            SET total_quantity = ?, updated_at = ?
            WHERE id = ? AND user_id = ?;
            """,
            bindings: [
                .text(try DecimalCodec.encode(adjustedQuantity)),
                .real(Date().timeIntervalSince1970),
                .text(instanceID.uuidString),
                .text(userID.uuidString)
            ]
        )
        return true
    }

    private func inclusiveDays(from: LocalDay, through: LocalDay) throws -> [LocalDay] {
        var result: [LocalDay] = []
        var cursor = from
        while cursor <= through {
            result.append(cursor)
            guard result.count <= 50_000 else {
                throw RepositoryError.validation("The requested date range is too large.")
            }
            if cursor == through { break }
            cursor = try cursor.adding(days: 1)
        }
        return result
    }
}

@MainActor
struct InventoryReconciliationService {
    let repository: WellnarioRepositoryProtocol

    @discardableResult
    func reconcile(
        instanceID: UUID,
        actualQuantity: Decimal,
        correctionNote: String? = nil,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> InventoryReconciliationResult {
        guard actualQuantity >= 0 else {
            throw RepositoryError.validation(L10n.text("settings.advanced.deviations.error.nonnegative"))
        }
        guard let instance = try repository.instance(id: instanceID),
              !instance.isArchived else {
            throw RepositoryError.notFound(entity: "Instance", id: instanceID)
        }
        guard let currentQuantity = instance.totalQuantity,
              let inventoryUnit = instance.totalUnit else {
            throw RepositoryError.validation(L10n.text("settings.advanced.deviations.error.untracked"))
        }
        if inventoryUnit.family == .discrete,
           (!actualQuantity.isWholeNumber || !currentQuantity.isWholeNumber) {
            throw RepositoryError.validation(L10n.text("settings.advanced.deviations.error.discrete"))
        }

        let difference = actualQuantity - currentQuantity
        guard difference != 0 else {
            return InventoryReconciliationResult(
                previousQuantity: currentQuantity,
                correctedQuantity: actualQuantity,
                unit: inventoryUnit,
                direction: .unchanged,
                adjustedConsumptionCount: 0
            )
        }

        let consumptions = try repository
            .fetchConsumptions(from: nil, through: nil, limit: nil)
            .filter { $0.instanceID == instanceID && $0.consumedAt <= now }
            .sorted { $0.consumedAt < $1.consumedAt }
        guard let firstConsumption = consumptions.first else {
            throw RepositoryError.validation(L10n.text("settings.advanced.deviations.error.no_history"))
        }

        let adjustedCount: Int
        let direction: InventoryReconciliationResult.Direction
        if difference > 0 {
            adjustedCount = try removeLoggedConsumption(
                difference,
                from: consumptions,
                inventoryUnit: inventoryUnit,
                firstDate: firstConsumption.consumedAt,
                through: now
            )
            direction = .removedConsumption
        } else {
            adjustedCount = try addMissingConsumption(
                -difference,
                to: instance,
                inventoryUnit: inventoryUnit,
                firstDay: firstConsumption.localDay,
                through: now,
                timeZone: timeZone,
                note: correctionNote
            )
            direction = .addedConsumption
        }

        _ = try repository.updateInstance(
            id: instance.id,
            with: SupplementInstanceDraft(
                supplementID: instance.supplementID,
                label: instance.label,
                expirationDay: instance.expirationDay,
                notes: instance.notes,
                totalQuantity: actualQuantity,
                totalUnit: inventoryUnit
            )
        )
        return InventoryReconciliationResult(
            previousQuantity: currentQuantity,
            correctedQuantity: actualQuantity,
            unit: inventoryUnit,
            direction: direction,
            adjustedConsumptionCount: adjustedCount
        )
    }

    private func addMissingConsumption(
        _ amount: Decimal,
        to instance: SupplementInstance,
        inventoryUnit: DoseUnit,
        firstDay: LocalDay,
        through now: Date,
        timeZone: TimeZone,
        note: String?
    ) throws -> Int {
        let today = LocalDay(containing: now, in: timeZone)
        let days = try inclusiveDays(from: firstDay, through: today)
        let allocations: [(day: LocalDay, amount: Decimal)]
        if inventoryUnit.family == .discrete {
            guard amount.isWholeNumber else {
                throw RepositoryError.validation(L10n.text("settings.advanced.deviations.error.discrete"))
            }
            allocations = discreteAllocations(amount: amount, across: days)
        } else {
            allocations = try continuousAllocations(amount: amount, across: days)
        }

        for allocation in allocations where allocation.amount > 0 {
            let consumedAt = try correctionDate(
                on: allocation.day,
                today: today,
                now: now,
                timeZone: timeZone
            )
            _ = try repository.createConsumption(ConsumptionDraft(
                instanceID: instance.id,
                quantity: allocation.amount,
                unit: inventoryUnit,
                consumedAt: consumedAt,
                timeZoneID: timeZone.identifier,
                notes: note
            ))
        }
        return allocations.count
    }

    private func removeLoggedConsumption(
        _ amount: Decimal,
        from consumptions: [Consumption],
        inventoryUnit: DoseUnit,
        firstDate: Date,
        through now: Date
    ) throws -> Int {
        var remainingByID: [UUID: Decimal] = [:]
        for consumption in consumptions {
            remainingByID[consumption.id] = try consumption.unit.convert(
                consumption.quantity,
                to: inventoryUnit
            )
        }
        let available = remainingByID.values.reduce(Decimal.zero, +)
        guard amount <= available else {
            throw RepositoryError.validation(L10n.text("settings.advanced.deviations.error.exceeds_history"))
        }

        if inventoryUnit.family == .discrete {
            guard amount.isWholeNumber,
                  remainingByID.values.allSatisfy(\.isWholeNumber) else {
                throw RepositoryError.validation(L10n.text("settings.advanced.deviations.error.discrete"))
            }
            try applyDiscreteReduction(
                amount,
                consumptions: consumptions,
                remainingByID: &remainingByID,
                firstDate: firstDate,
                through: now
            )
        } else {
            try applyContinuousReduction(
                amount,
                consumptions: consumptions,
                remainingByID: &remainingByID
            )
        }

        var adjustedCount = 0
        for consumption in consumptions {
            guard let remaining = remainingByID[consumption.id] else { continue }
            let original = try consumption.unit.convert(consumption.quantity, to: inventoryUnit)
            guard remaining != original else { continue }
            adjustedCount += 1
            if remaining == 0 {
                try repository.deleteConsumption(id: consumption.id)
            } else {
                let newQuantity = try inventoryUnit.convert(remaining, to: consumption.unit)
                _ = try repository.updateConsumption(
                    id: consumption.id,
                    with: ConsumptionDraft(
                        instanceID: consumption.instanceID,
                        quantity: newQuantity,
                        unit: consumption.unit,
                        consumedAt: consumption.consumedAt,
                        timeZoneID: consumption.timeZoneID,
                        notes: consumption.notes
                    )
                )
            }
        }
        return adjustedCount
    }

    private func applyContinuousReduction(
        _ amount: Decimal,
        consumptions: [Consumption],
        remainingByID: inout [UUID: Decimal]
    ) throws {
        let grouped = Dictionary(grouping: consumptions, by: \.localDay)
        var dailyCapacity = grouped.mapValues { entries in
            entries.reduce(Decimal.zero) { $0 + (remainingByID[$1.id] ?? 0) }
        }
        var dailyReduction = Dictionary(uniqueKeysWithValues: grouped.keys.map { ($0, Decimal.zero) })
        var pending = amount
        var activeDays = Set(dailyCapacity.filter { $0.value > 0 }.keys)

        while pending > 0, !activeDays.isEmpty {
            let share = try DecimalMath.divide(pending, Decimal(activeDays.count))
            var applied: Decimal = 0
            for day in activeDays {
                let capacity = dailyCapacity[day] ?? 0
                let reduction = min(share, capacity)
                dailyReduction[day, default: 0] += reduction
                dailyCapacity[day] = capacity - reduction
                applied += reduction
            }
            guard applied > 0 else { break }
            pending -= applied
            activeDays = Set(dailyCapacity.filter { $0.value > 0 }.keys)
        }
        guard pending == 0 else {
            throw RepositoryError.validation(L10n.text("settings.advanced.deviations.error.exceeds_history"))
        }

        for (day, entries) in grouped {
            var reduction = dailyReduction[day] ?? 0
            guard reduction > 0 else { continue }
            let total = entries.reduce(Decimal.zero) { $0 + (remainingByID[$1.id] ?? 0) }
            for (offset, consumption) in entries.enumerated() {
                let available = remainingByID[consumption.id] ?? 0
                let portion: Decimal
                if offset == entries.count - 1 {
                    portion = min(reduction, available)
                } else {
                    portion = min(
                        try DecimalMath.multiply(
                            dailyReduction[day] ?? 0,
                            try DecimalMath.divide(available, total)
                        ),
                        available
                    )
                }
                remainingByID[consumption.id] = available - portion
                reduction -= portion
            }
        }
    }

    private func applyDiscreteReduction(
        _ amount: Decimal,
        consumptions: [Consumption],
        remainingByID: inout [UUID: Decimal],
        firstDate: Date,
        through now: Date
    ) throws {
        let units = NSDecimalNumber(decimal: amount).intValue
        guard units > 0 else { return }
        let interval = max(0, now.timeIntervalSince(firstDate))
        for index in 0..<units {
            let fraction = (Double(index) + 0.5) / Double(units)
            let target = firstDate.addingTimeInterval(interval * fraction)
            guard let candidate = (consumptions
                .filter { (remainingByID[$0.id] ?? 0) >= 1 }
                .min(by: {
                    abs($0.consumedAt.timeIntervalSince(target))
                        < abs($1.consumedAt.timeIntervalSince(target))
                })) else {
                throw RepositoryError.validation(L10n.text("settings.advanced.deviations.error.exceeds_history"))
            }
            remainingByID[candidate.id, default: 0] -= 1
        }
    }

    private func continuousAllocations(
        amount: Decimal,
        across days: [LocalDay]
    ) throws -> [(day: LocalDay, amount: Decimal)] {
        guard !days.isEmpty else { return [] }
        let share = try DecimalMath.divide(amount, Decimal(days.count))
        var allocated: Decimal = 0
        return days.enumerated().map { offset, day in
            let value = offset == days.count - 1 ? amount - allocated : share
            allocated += value
            return (day, value)
        }
    }

    private func discreteAllocations(
        amount: Decimal,
        across days: [LocalDay]
    ) -> [(day: LocalDay, amount: Decimal)] {
        guard !days.isEmpty else { return [] }
        let units = NSDecimalNumber(decimal: amount).intValue
        guard units > 0 else { return [] }
        let eventCount = min(units, days.count)
        let base = units / eventCount
        let remainder = units % eventCount
        return (0..<eventCount).map { index in
            let dayIndex: Int
            if eventCount == 1 {
                dayIndex = days.count - 1
            } else {
                dayIndex = Int(
                    (Double(index) * Double(days.count - 1) / Double(eventCount - 1)).rounded()
                )
            }
            return (days[dayIndex], Decimal(base + (index < remainder ? 1 : 0)))
        }
    }

    private func inclusiveDays(from: LocalDay, through: LocalDay) throws -> [LocalDay] {
        guard from <= through else { return [through] }
        var days: [LocalDay] = []
        var cursor = from
        while cursor <= through {
            days.append(cursor)
            if cursor == through { break }
            cursor = try cursor.adding(days: 1)
        }
        return days
    }

    private func correctionDate(
        on day: LocalDay,
        today: LocalDay,
        now: Date,
        timeZone: TimeZone
    ) throws -> Date {
        let midday = try day.startDate(in: timeZone).addingTimeInterval(12 * 60 * 60)
        return day == today ? min(midday, now) : midday
    }
}

private extension Decimal {
    var isWholeNumber: Bool {
        var value = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded == self
    }
}
