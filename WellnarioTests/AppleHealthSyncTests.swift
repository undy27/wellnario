import Foundation
import XCTest
@testable import Wellnario

final class AppleHealthSyncTests: XCTestCase {
    func testSleepAggregationMergesOverlappingSourcesWithoutDoubleCounting() throws {
        let start = try utcDate(2026, 7, 9, hour: 22)
        let segments = [
            segment(start, hours: 1, kind: .core, source: "Apple Watch"),
            segment(start, hours: 1, kind: .asleepUnspecified, source: "iPhone"),
            segment(start.addingTimeInterval(3_600), hours: 1, kind: .deep, source: "Apple Watch"),
            segment(start.addingTimeInterval(7_200), minutes: 10, kind: .awake, source: "Apple Watch"),
            segment(start.addingTimeInterval(7_800), hours: 1, kind: .rem, source: "Apple Watch")
        ]

        let session = try XCTUnwrap(AppleHealthSleepAggregator.sessions(from: segments).first)

        XCTAssertEqual(session.asleepSeconds, 3 * 3_600, accuracy: 0.001)
        XCTAssertEqual(session.deepSeconds, 3_600, accuracy: 0.001)
        XCTAssertEqual(session.remSeconds, 3_600, accuracy: 0.001)
        XCTAssertEqual(session.awakeSeconds, 10 * 60, accuracy: 0.001)
        XCTAssertEqual(session.sourceNames, ["Apple Watch", "iPhone"])
    }

    func testSleepAggregationSeparatesSessionsAfterThreeHourGapAndBuildsSevenDayTrend() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let firstStart = try utcDate(2026, 7, 8, hour: 22)
        let secondStart = try utcDate(2026, 7, 9, hour: 8)
        let segments = [
            segment(firstStart, hours: 7, kind: .asleepUnspecified),
            segment(secondStart, minutes: 30, kind: .asleepUnspecified)
        ]

        let sessions = AppleHealthSleepAggregator.sessions(from: segments)
        let trend = AppleHealthSleepAggregator.sevenDayTrend(
            sessions: sessions,
            endingAt: try utcDate(2026, 7, 10, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(trend.count, 7)
        XCTAssertEqual(try XCTUnwrap(trend[5].hours), 7.5, accuracy: 0.001)
        XCTAssertNil(trend[6].hours)
    }

    func testSnapshotCacheRoundTripsHealthData() throws {
        let suiteName = "AppleHealthSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var cache = AppleHealthSnapshotCache(defaults: defaults)
        let date = try utcDate(2026, 7, 10, hour: 10)
        var snapshot = AppleHealthSnapshot.empty
        snapshot.lastSyncedAt = date
        snapshot.heartRateVariability = AppleHealthMeasurement(
            value: 52,
            date: date,
            sourceName: "Apple Watch"
        )
        snapshot.stepsToday = 8_432

        cache.isConfigured = true
        cache.save(snapshot)

        XCTAssertTrue(cache.isConfigured)
        XCTAssertEqual(cache.load(), snapshot)
    }

    private func segment(
        _ start: Date,
        hours: Double = 0,
        minutes: Double = 0,
        kind: AppleHealthSleepAggregator.SegmentKind,
        source: String = "Test"
    ) -> AppleHealthSleepAggregator.Segment {
        AppleHealthSleepAggregator.Segment(
            startDate: start,
            endDate: start.addingTimeInterval(hours * 3_600 + minutes * 60),
            kind: kind,
            sourceName: source
        )
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, hour: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        return try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        )))
    }
}
