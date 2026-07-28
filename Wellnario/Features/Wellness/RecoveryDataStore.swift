import Foundation

@MainActor
final class RecoveryDataStore: Sendable {
    private let database: SQLiteDatabase
    private let userID: UUID

    init(
        databaseURL: URL,
        userID: UUID
    ) throws {
        self.database = try SQLiteDatabase(url: databaseURL)
        self.userID = userID
    }
    
    convenience init() {
        try! self.init(databaseURL: URL(fileURLWithPath: ":memory:"), userID: UUID())
    }

    func saveBaseline(_ baseline: RecoveryBaseline) throws {
        let bindings: [SQLiteBinding] = [
            .text(userID.uuidString),
            .text(baseline.date),
            .real(baseline.hrvMean),
            .real(baseline.hrvStdDev),
            .real(baseline.rhrMean),
            .real(baseline.rhrStdDev),
            .real(baseline.updatedAt.timeIntervalSince1970)
        ]
        try database.execute(
            """
            INSERT INTO recovery_baselines (user_id, date, hrv_mean, hrv_stddev, rhr_mean, rhr_stddev, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, date) DO UPDATE SET
            hrv_mean = excluded.hrv_mean,
            hrv_stddev = excluded.hrv_stddev,
            rhr_mean = excluded.rhr_mean,
            rhr_stddev = excluded.rhr_stddev,
            updated_at = excluded.updated_at;
            """,
            bindings: bindings
        )
    }

    func fetchBaseline(forDate date: String) throws -> RecoveryBaseline? {
        let rows = try database.query(
            """
            SELECT hrv_mean, hrv_stddev, rhr_mean, rhr_stddev, updated_at
            FROM recovery_baselines
            WHERE user_id = ? AND date = ?;
            """,
            bindings: [.text(userID.uuidString), .text(date)]
        )
        guard let row = rows.first else { return nil }
        return try RecoveryBaseline(
            date: date,
            hrvMean: row.double("hrv_mean"),
            hrvStdDev: row.double("hrv_stddev"),
            rhrMean: row.double("rhr_mean"),
            rhrStdDev: row.double("rhr_stddev"),
            updatedAt: Date(timeIntervalSince1970: row.double("updated_at"))
        )
    }

    func saveScore(_ score: RecoveryScore) throws {
        let bindings: [SQLiteBinding] = [
            .text(userID.uuidString),
            .text(score.date),
            .real(score.score),
            score.hrvValue.map { .real($0) } ?? .null,
            score.rhrValue.map { .real($0) } ?? .null,
            score.sleepScore.map { .real($0) } ?? .null,
            score.respiratoryRate.map { .real($0) } ?? .null,
            .real(score.updatedAt.timeIntervalSince1970)
        ]
        try database.execute(
            """
            INSERT INTO recovery_scores (user_id, date, score, hrv_value, rhr_value, sleep_score, respiratory_rate, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, date) DO UPDATE SET
            score = excluded.score,
            hrv_value = excluded.hrv_value,
            rhr_value = excluded.rhr_value,
            sleep_score = excluded.sleep_score,
            respiratory_rate = excluded.respiratory_rate,
            updated_at = excluded.updated_at;
            """,
            bindings: bindings
        )
    }

    func fetchScore(forDate date: String) throws -> RecoveryScore? {
        let rows = try database.query(
            """
            SELECT score, hrv_value, rhr_value, sleep_score, respiratory_rate, updated_at
            FROM recovery_scores
            WHERE user_id = ? AND date = ?;
            """,
            bindings: [.text(userID.uuidString), .text(date)]
        )
        guard let row = rows.first else { return nil }
        return try RecoveryScore(
            date: date,
            score: row.double("score"),
            hrvValue: row.optionalDouble("hrv_value"),
            rhrValue: row.optionalDouble("rhr_value"),
            sleepScore: row.optionalDouble("sleep_score"),
            respiratoryRate: row.optionalDouble("respiratory_rate"),
            updatedAt: Date(timeIntervalSince1970: row.double("updated_at"))
        )
    }
}
