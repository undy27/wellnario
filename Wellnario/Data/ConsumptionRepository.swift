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
                        timezone_id, local_day, notes, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .text(id.uuidString), .text(draft.instanceID.uuidString), .text(userID.uuidString),
                        .text(prepared.supplementName), .text(prepared.instanceLabel),
                        .text(try DecimalCodec.encode(draft.quantity)), .text(draft.unit.rawValue),
                        .real(draft.consumedAt.timeIntervalSince1970), .text(prepared.timeZone.identifier),
                        .text(prepared.localDay.iso8601), binding(prepared.notes), .real(now), .real(now)
                    ]
                )
                try replaceSnapshots(consumptionID: id, snapshots: prepared.snapshots)
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
                try database.execute(
                    """
                    UPDATE consumptions SET
                        instance_id = ?, supplement_name_snapshot = ?, instance_label_snapshot = ?,
                        quantity = ?, unit = ?, consumed_at = ?, timezone_id = ?, local_day = ?,
                        notes = ?, updated_at = ?
                    WHERE id = ? AND user_id = ?;
                    """,
                    bindings: [
                        .text(draft.instanceID.uuidString), .text(supplementName), .text(instanceLabel),
                        .text(try DecimalCodec.encode(draft.quantity)), .text(draft.unit.rawValue),
                        .real(draft.consumedAt.timeIntervalSince1970), .text(timeZone.identifier),
                        .text(localDay.iso8601), binding(notes), .real(Date().timeIntervalSince1970),
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
            guard try loadConsumption(id: id) != nil else {
                throw RepositoryError.notFound(entity: "Consumption", id: id)
            }
            try database.execute(
                "DELETE FROM consumptions WHERE id = ? AND user_id = ?;",
                bindings: [.text(id.uuidString), .text(userID.uuidString)]
            )
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
                total = try DecimalMath.add(total, amount)
                let target = try currentTarget(activeID: activeID, on: day)
                let lower = try target.map { try $0.unit.convert($0.lowerBound, to: active.baseUnit) }
                let upper = try target.map { try $0.unit.convert($0.upperBound, to: active.baseUnit) }
                let progressStatus = status(amount: amount, lower: lower, upper: upper)
                if progressStatus == .within { daysWithinTarget += 1 }
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
            let average = try DecimalMath.divide(total, Decimal(days.count))
            return ConsumptionSeries(
                active: active,
                from: from,
                through: through,
                unit: active.baseUnit,
                points: points,
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
