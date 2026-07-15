import Foundation
import UIKit
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
        XCTAssertEqual(session.stageIntervals.map(\.stage), [.core, .deep, .awake, .rem])
        XCTAssertEqual(session.stageIntervals.first?.startDate, start)
        XCTAssertEqual(session.stageIntervals.last?.endDate, start.addingTimeInterval(11_400))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let trend = AppleHealthSleepAggregator.sevenDayTrend(
            sessions: [session],
            endingAt: try utcDate(2026, 7, 10, hour: 12),
            calendar: calendar
        )
        XCTAssertEqual(try XCTUnwrap(trend.last?.lightHours), 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(trend.last?.deepHours), 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(trend.last?.remHours), 1, accuracy: 0.001)
        XCTAssertNil(trend.last?.qualityScore)
    }

    func testLegacySleepSessionCacheDecodesWithoutStageIntervals() throws {
        let start = try utcDate(2026, 7, 9, hour: 22)
        let session = AppleHealthSleepSession(
            startDate: start,
            endDate: start.addingTimeInterval(8 * 3_600),
            asleepSeconds: 7.5 * 3_600,
            inBedSeconds: 8 * 3_600,
            awakeSeconds: 30 * 60,
            coreSeconds: 4.5 * 3_600,
            deepSeconds: 1.5 * 3_600,
            remSeconds: 1.5 * 3_600,
            sourceNames: ["Apple Watch"],
            stageIntervals: [
                AppleHealthSleepStageInterval(
                    startDate: start,
                    endDate: start.addingTimeInterval(3_600),
                    stage: .core
                )
            ]
        )
        let encoded = try JSONEncoder().encode(session)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "stageIntervals")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)

        let decoded = try JSONDecoder().decode(AppleHealthSleepSession.self, from: legacyData)

        XCTAssertEqual(decoded.startDate, session.startDate)
        XCTAssertTrue(decoded.stageIntervals.isEmpty)
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

    func testAllTimeSleepTrendCanBeFilteredByPeriod() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let endingAt = try utcDate(2026, 7, 14, hour: 12)
        let oldSession = AppleHealthSleepSession(
            startDate: try utcDate(2025, 12, 31, hour: 22),
            endDate: try utcDate(2026, 1, 1, hour: 6),
            asleepSeconds: 8 * 3_600,
            inBedSeconds: 8 * 3_600,
            awakeSeconds: 0,
            coreSeconds: 5 * 3_600,
            deepSeconds: 1 * 3_600,
            remSeconds: 2 * 3_600,
            sourceNames: ["Test"]
        )
        let recentSession = AppleHealthSleepSession(
            startDate: try utcDate(2026, 7, 12, hour: 23),
            endDate: try utcDate(2026, 7, 13, hour: 6),
            asleepSeconds: 7 * 3_600,
            inBedSeconds: 7 * 3_600,
            awakeSeconds: 0,
            coreSeconds: 0,
            deepSeconds: 0,
            remSeconds: 0,
            sourceNames: ["Test"]
        )

        let history = AppleHealthSleepAggregator.allTimeTrend(
            sessions: [oldSession, recentSession],
            endingAt: endingAt,
            calendar: calendar
        )
        let sevenDays = AppleHealthSleepAggregator.trend(
            from: history,
            period: .sevenDays,
            endingAt: endingAt,
            calendar: calendar
        )
        let thirtyDays = AppleHealthSleepAggregator.trend(
            from: history,
            period: .thirtyDays,
            endingAt: endingAt,
            calendar: calendar
        )
        let sixMonths = AppleHealthSleepAggregator.trend(
            from: history,
            period: .sixMonths,
            endingAt: endingAt,
            calendar: calendar
        )
        let allTime = AppleHealthSleepAggregator.trend(
            from: history,
            period: .allTime,
            endingAt: endingAt,
            calendar: calendar
        )

        XCTAssertEqual(sevenDays.count, 7)
        XCTAssertEqual(thirtyDays.count, 30)
        XCTAssertEqual(
            sixMonths.first?.date,
            calendar.date(byAdding: .month, value: -6, to: calendar.startOfDay(for: endingAt))
        )
        XCTAssertEqual(try XCTUnwrap(sevenDays[5].hours), 7, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(allTime.first?.hours), 8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(allTime.first?.lightHours), 5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(allTime.first?.deepHours), 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(allTime.first?.remHours), 2, accuracy: 0.001)
        XCTAssertEqual(
            allTime.last?.date,
            calendar.dateInterval(of: .month, for: endingAt)?.start
        )
    }

    func testSixMonthTrendUsesWeeksAfterOneMonthOfDataAndDaysBeforeIt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let endingAt = try utcDate(2026, 7, 14, hour: 12)
        let longHistory = sleepDays(
            from: try XCTUnwrap(calendar.date(byAdding: .day, value: -40, to: endingAt)),
            through: endingAt,
            calendar: calendar
        )
        let shortHistory = sleepDays(
            from: try XCTUnwrap(calendar.date(byAdding: .day, value: -20, to: endingAt)),
            through: endingAt,
            calendar: calendar
        )

        let weekly = AppleHealthSleepAggregator.trendSeries(
            from: longHistory,
            period: .sixMonths,
            endingAt: endingAt,
            calendar: calendar
        )
        let daily = AppleHealthSleepAggregator.trendSeries(
            from: shortHistory,
            period: .sixMonths,
            endingAt: endingAt,
            calendar: calendar
        )

        XCTAssertEqual(weekly.granularity, .week)
        XCTAssertLessThan(weekly.entries.count, 30)
        XCTAssertTrue(weekly.entries.compactMap(\.hours).allSatisfy { $0 == 8 })
        XCTAssertEqual(
            weekly.entries.dropFirst().first?.date,
            calendar.date(byAdding: .weekOfYear, value: 1, to: weekly.entries.first?.date ?? endingAt)
        )
        XCTAssertEqual(daily.granularity, .day)
        XCTAssertGreaterThan(daily.entries.count, 180)
    }

    func testAllTimeTrendUsesMonthsAfterThreeMonthsOfDataAndDaysBeforeIt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let endingAt = try utcDate(2026, 7, 14, hour: 12)
        let longHistory = sleepDays(
            from: try XCTUnwrap(calendar.date(byAdding: .month, value: -4, to: endingAt)),
            through: endingAt,
            calendar: calendar
        )
        let shortHistory = sleepDays(
            from: try XCTUnwrap(calendar.date(byAdding: .month, value: -2, to: endingAt)),
            through: endingAt,
            calendar: calendar
        )

        let monthly = AppleHealthSleepAggregator.trendSeries(
            from: longHistory,
            period: .allTime,
            endingAt: endingAt,
            calendar: calendar
        )
        let daily = AppleHealthSleepAggregator.trendSeries(
            from: shortHistory,
            period: .allTime,
            endingAt: endingAt,
            calendar: calendar
        )

        XCTAssertEqual(monthly.granularity, .month)
        XCTAssertEqual(monthly.entries.count, 5)
        XCTAssertTrue(monthly.entries.compactMap(\.hours).allSatisfy { $0 == 8 })
        XCTAssertEqual(
            monthly.entries.dropFirst().first?.date,
            calendar.date(byAdding: .month, value: 1, to: monthly.entries.first?.date ?? endingAt)
        )
        XCTAssertEqual(daily.granularity, .day)
        XCTAssertGreaterThan(daily.entries.count, 60)
    }

    func testAllTimeTrendUsesYearlyAveragesAfterTwoYearsOfData() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let endingAt = try utcDate(2026, 7, 14, hour: 12)
        let longHistory = sleepDays(
            from: try XCTUnwrap(calendar.date(byAdding: .year, value: -3, to: endingAt)),
            through: endingAt,
            calendar: calendar
        )
        let shorterHistory = sleepDays(
            from: try XCTUnwrap(calendar.date(byAdding: .month, value: -18, to: endingAt)),
            through: endingAt,
            calendar: calendar
        )

        let yearly = AppleHealthSleepAggregator.trendSeries(
            from: longHistory,
            period: .allTime,
            endingAt: endingAt,
            calendar: calendar
        )
        let monthly = AppleHealthSleepAggregator.trendSeries(
            from: shorterHistory,
            period: .allTime,
            endingAt: endingAt,
            calendar: calendar
        )

        XCTAssertEqual(yearly.granularity, .year)
        XCTAssertEqual(yearly.entries.count, 4)
        XCTAssertGreaterThan(yearly.dailyEntries.count, 1_000)
        XCTAssertTrue(yearly.entries.compactMap(\.hours).allSatisfy { $0 == 8 })
        XCTAssertEqual(
            yearly.entries.dropFirst().first?.date,
            calendar.date(byAdding: .year, value: 1, to: yearly.entries.first?.date ?? endingAt)
        )
        XCTAssertEqual(monthly.granularity, .month)
        XCTAssertEqual(monthly.entries.count, 19)
    }

    func testSnapshotCacheRoundTripsHealthData() throws {
        let suiteName = "AppleHealthSyncTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = AppleHealthSnapshotCache(defaults: defaults)
        let date = try utcDate(2026, 7, 10, hour: 10)
        var snapshot = AppleHealthSnapshot.empty
        snapshot.lastSyncedAt = date
        snapshot.heartRateVariability = AppleHealthMeasurement(
            value: 52,
            date: date,
            sourceName: "Apple Watch"
        )
        snapshot.stepsToday = 8_432
        snapshot.sleepTrend = [AppleHealthSleepDay(
            date: date,
            hours: 7.5,
            qualityScore: 86,
            remHours: 1.5,
            deepHours: 1.2,
            lightHours: 4.8
        )]

        cache.isConfigured = true
        cache.save(snapshot)

        XCTAssertTrue(cache.isConfigured)
        XCTAssertEqual(cache.load(), snapshot)
    }

    func testSourcePreferencesPersistCatalogAndDisabledSources() throws {
        let suiteName = "AppleHealthSourcePreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppleHealthSourcePreferences(defaults: defaults)
        let sources = [
            AppleHealthDataSource(
                identifier: "com.apple.health",
                name: "Apple Watch",
                dataKinds: [.sleep, .heart, .activity, .workouts]
            ),
            AppleHealthDataSource(
                identifier: "com.example.ring",
                name: "Old Ring",
                dataKinds: [.sleep, .heart]
            )
        ]

        preferences.saveSources(sources)
        let disabledSelections: Set<AppleHealthSourceSelection> = [
            AppleHealthSourceSelection(sourceIdentifier: "com.example.ring", dataKind: .sleep)
        ]
        preferences.saveDisabledSourceSelections(disabledSelections)

        XCTAssertEqual(preferences.loadSources(), sources)
        XCTAssertEqual(preferences.loadDisabledSourceSelections(), disabledSelections)
    }

    func testSourcePreferencesMigrateLegacyGlobalExclusionsToEveryCategory() throws {
        let suiteName = "AppleHealthLegacySourcePreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["com.example.ring"], forKey: "appleHealth.disabledSources.v1")

        let selections = AppleHealthSourcePreferences(defaults: defaults)
            .loadDisabledSourceSelections()

        XCTAssertEqual(selections.count, AppleHealthDataKind.allCases.count)
        for dataKind in AppleHealthDataKind.allCases {
            XCTAssertTrue(selections.contains(AppleHealthSourceSelection(
                sourceIdentifier: "com.example.ring",
                dataKind: dataKind
            )))
        }
    }

    @MainActor
    func testSourceSelectionPersistsThroughAppleHealthService() async throws {
        let suiteName = "AppleHealthSourceServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AppleHealthSyncService(defaults: defaults, isEnabled: false)

        service.setSourceEnabled("com.example.ring", for: .sleep, isEnabled: false)

        let selection = AppleHealthSourceSelection(
            sourceIdentifier: "com.example.ring",
            dataKind: .sleep
        )
        XCTAssertEqual(service.disabledSourceSelections, [selection])
        let restoredService = AppleHealthSyncService(defaults: defaults, isEnabled: false)
        XCTAssertEqual(restoredService.disabledSourceSelections, [selection])
    }

    @MainActor
    func testAppleHealthSettingsShowsAndUpdatesSourceToggles() async throws {
        let sources = [
            AppleHealthDataSource(
                identifier: "com.apple.health",
                name: "Apple Watch",
                dataKinds: [.sleep, .heart, .activity]
            ),
            AppleHealthDataSource(
                identifier: "com.example.ring",
                name: "Old Ring",
                dataKinds: [.sleep]
            )
        ]
        let service = AppleHealthSyncingStub(
            availableSources: sources,
            disabledSourceSelections: [
                AppleHealthSourceSelection(sourceIdentifier: "com.example.ring", dataKind: .sleep)
            ]
        )
        let controller = IntegrationSetupViewController(
            provider: .appleHealth,
            appleHealthService: service
        )

        controller.loadViewIfNeeded()

        let appleSwitch = try XCTUnwrap(descendant(
            of: UISwitch.self,
            identifier: "settings.integration.apple_health.source.sleep.com.apple.health",
            in: controller.view
        ))
        let ringSwitch = try XCTUnwrap(descendant(
            of: UISwitch.self,
            identifier: "settings.integration.apple_health.source.sleep.com.example.ring",
            in: controller.view
        ))
        let sleepSection = try XCTUnwrap(descendant(
            of: AppleHealthSourceSectionView.self,
            identifier: "settings.integration.apple_health.sources.section.sleep",
            in: controller.view
        ))
        let heartSection = try XCTUnwrap(descendant(
            of: AppleHealthSourceSectionView.self,
            identifier: "settings.integration.apple_health.sources.section.heart",
            in: controller.view
        ))
        let heartHeader = try XCTUnwrap(descendant(
            of: UIButton.self,
            identifier: "settings.integration.apple_health.sources.header.heart",
            in: controller.view
        ))
        XCTAssertTrue(sleepSection.isExpanded)
        XCTAssertFalse(heartSection.isExpanded)
        heartHeader.sendActions(for: .touchUpInside)
        XCTAssertTrue(heartSection.isExpanded)
        XCTAssertTrue(appleSwitch.isOn)
        XCTAssertFalse(ringSwitch.isOn)

        controller.viewDidDisappear(false)
        await Task.yield()
        XCTAssertEqual(service.syncIfConfiguredCallCount, 0)

        ringSwitch.isOn = true
        ringSwitch.sendActions(for: .valueChanged)
        appleSwitch.isOn = false
        appleSwitch.sendActions(for: .valueChanged)

        XCTAssertFalse(service.disabledSourceSelections.contains(AppleHealthSourceSelection(
            sourceIdentifier: "com.example.ring",
            dataKind: .sleep
        )))
        XCTAssertEqual(service.syncIfConfiguredCallCount, 0)

        controller.viewDidDisappear(false)
        await Task.yield()

        XCTAssertEqual(service.syncIfConfiguredCallCount, 1)
        controller.viewDidDisappear(false)
        await Task.yield()
        XCTAssertEqual(service.syncIfConfiguredCallCount, 1)

        ringSwitch.isOn = false
        ringSwitch.sendActions(for: .valueChanged)
        ringSwitch.isOn = true
        ringSwitch.sendActions(for: .valueChanged)
        controller.viewDidDisappear(false)
        await Task.yield()
        XCTAssertEqual(service.syncIfConfiguredCallCount, 1)
    }

    func testTrendMovingAverageSmoothsValuesAndPreservesEmptySeries() throws {
        let values: [Double?] = [6, 9, 3, 12, 5]
        let smoothed = WellnessTrendSmoothing.movingAverage(values, window: 3)

        XCTAssertEqual(try XCTUnwrap(smoothed[0]), 7.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(smoothed[1]), 6, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(smoothed[2]), 8, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(smoothed[4]), 8.5, accuracy: 0.001)
        XCTAssertEqual(
            WellnessTrendSmoothing.movingAverage([nil, nil], window: 7),
            [nil, nil]
        )
        XCTAssertNil(WellnessTrendSmoothing.movingAverage([6, nil, 9], window: 3)[1])
    }

    func testTrendScaleUsesSmoothedSeriesInsteadOfHiddenRawOutlier() throws {
        var values = Array<Double?>(repeating: 8, count: 60)
        values[20] = 18

        let plottedValues = WellnessTrendSmoothing.movingAverage(values, window: 30)
        let bounds = try XCTUnwrap(WellnessTrendScale.bounds(for: plottedValues))

        XCTAssertEqual(values.compactMap { $0 }.max(), 18)
        XCTAssertLessThan(try XCTUnwrap(plottedValues.compactMap { $0 }.max()), 9)
        XCTAssertLessThan(bounds.upper, 9)
    }

    func testLinearTrendUsesDailyPositionsAndIgnoresMissingValues() throws {
        let trend = try XCTUnwrap(WellnessLinearRegression.fit(values: [nil, 1, 2, nil, 4, 5, nil]))

        XCTAssertEqual(trend.startPosition, 1.0 / 6.0, accuracy: 0.001)
        XCTAssertEqual(trend.startValue, 1, accuracy: 0.001)
        XCTAssertEqual(trend.endPosition, 5.0 / 6.0, accuracy: 0.001)
        XCTAssertEqual(trend.endValue, 5, accuracy: 0.001)
    }

    @MainActor
    func testSleepTrendReferenceSelectorDefaultsToTrendAndPersistsSelection() throws {
        let suiteName = "SleepTrendReferenceSelectorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AppleHealthSyncingStub(availableSources: [], disabledSourceSelections: [])
        let initialController = SleepViewController(appleHealthService: service, defaults: defaults)
        initialController.loadViewIfNeeded()

        let initialSelector = try XCTUnwrap(descendant(
            of: UISegmentedControl.self,
            identifier: "sleep.trend.reference.selector",
            in: initialController.view
        ))
        XCTAssertEqual(initialSelector.selectedSegmentIndex, WellnessTrendReferenceLine.linearTrend.rawValue)

        initialSelector.selectedSegmentIndex = WellnessTrendReferenceLine.average.rawValue
        initialSelector.sendActions(for: .valueChanged)

        let restoredController = SleepViewController(appleHealthService: service, defaults: defaults)
        restoredController.loadViewIfNeeded()
        let restoredSelector = try XCTUnwrap(descendant(
            of: UISegmentedControl.self,
            identifier: "sleep.trend.reference.selector",
            in: restoredController.view
        ))
        XCTAssertEqual(restoredSelector.selectedSegmentIndex, WellnessTrendReferenceLine.average.rawValue)
    }

    @MainActor
    func testSleepCardLayoutPersistsVisibilityAndOrder() throws {
        let suiteName = "SleepCardLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = SleepCardLayoutPreferences(defaults: defaults)

        XCTAssertEqual(preferences.orderedCards, [.latestSession, .trend, .factors])
        XCTAssertTrue(SleepCardKind.allCases.allSatisfy(preferences.isVisible))

        preferences.setVisible(false, card: .trend)
        preferences.moveCard(from: 2, to: 0)

        let restored = SleepCardLayoutPreferences(defaults: defaults)
        XCTAssertEqual(restored.orderedCards, [.factors, .latestSession, .trend])
        XCTAssertFalse(restored.isVisible(.trend))
        XCTAssertTrue(restored.isVisible(.latestSession))
        XCTAssertTrue(restored.isVisible(.factors))
    }

    @MainActor
    func testSleepCardEditorMoveUpdatesStoredOrder() throws {
        let suiteName = "SleepCardEditorMoveTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = SleepCardLayoutPreferences(defaults: defaults)
        let controller = SleepCardEditorViewController(preferences: preferences)
        controller.loadViewIfNeeded()

        controller.tableView(
            controller.tableView,
            moveRowAt: IndexPath(row: 0, section: 0),
            to: IndexPath(row: 2, section: 0)
        )

        XCTAssertEqual(preferences.orderedCards, [.trend, .factors, .latestSession])
        XCTAssertTrue(controller.tableView.isEditing)
    }

    @MainActor
    func testSleepViewUsesStoredCardVisibilityAndOrder() throws {
        let suiteName = "SleepCardViewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = SleepCardLayoutPreferences(defaults: defaults)
        preferences.moveCard(from: 2, to: 0)
        preferences.setVisible(false, card: .trend)
        let service = AppleHealthSyncingStub(availableSources: [], disabledSourceSelections: [])
        let controller = SleepViewController(appleHealthService: service, defaults: defaults)

        controller.loadViewIfNeeded()

        XCTAssertEqual(
            controller.contentStack.arrangedSubviews.compactMap(\.accessibilityIdentifier),
            ["sleep.card.section.factors", "sleep.card.section.latestSession"]
        )
        XCTAssertNil(descendant(
            of: PremiumCardView.self,
            identifier: "sleep.trend.card",
            in: controller.view
        ))
    }

    @MainActor
    func testHealthCardLayoutPersistsVisibilityAndOrder() throws {
        let suiteName = "HealthCardLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = HealthCardLayoutPreferences(defaults: defaults)

        preferences.moveCard(from: 2, to: 0)
        preferences.setVisible(false, card: .biologicalAge)

        let restored = HealthCardLayoutPreferences(defaults: defaults)
        XCTAssertEqual(restored.orderedCards, [.medicalReviews, .biologicalAge, .biomarkers])
        XCTAssertFalse(restored.isVisible(.biologicalAge))
        XCTAssertTrue(restored.isVisible(.medicalReviews))
    }

    @MainActor
    func testHealthViewUsesStoredCardVisibilityAndOrder() throws {
        let suiteName = "HealthCardViewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = HealthCardLayoutPreferences(defaults: defaults)
        preferences.moveCard(from: 2, to: 0)
        preferences.setVisible(false, card: .biologicalAge)
        let service = AppleHealthSyncingStub(availableSources: [], disabledSourceSelections: [])
        let controller = HealthViewController(appleHealthService: service, defaults: defaults)

        controller.loadViewIfNeeded()

        XCTAssertEqual(
            controller.contentStack.arrangedSubviews.compactMap(\.accessibilityIdentifier),
            [
                "health.card.section.medicalReviews",
                "health.card.section.biomarkers",
                "health.import_lab"
            ]
        )
    }

    @MainActor
    func testBiologicalAgeTitleIsOutsideItsCard() throws {
        let service = AppleHealthSyncingStub(availableSources: [], disabledSourceSelections: [])
        let controller = HealthViewController(appleHealthService: service)

        controller.loadViewIfNeeded()

        let section = try XCTUnwrap(descendant(
            of: UIStackView.self,
            identifier: "health.card.section.biologicalAge",
            in: controller.view
        ))
        XCTAssertEqual(section.arrangedSubviews.count, 2)
        let titleRow = try XCTUnwrap(section.arrangedSubviews.first as? UIStackView)
        let titleLabel = try XCTUnwrap(titleRow.arrangedSubviews.first as? UILabel)
        let card = try XCTUnwrap(descendant(
            of: PremiumCardView.self,
            identifier: "health.biological_age",
            in: section
        ))

        XCTAssertEqual(titleLabel.text, L10n.text("health.biological_age.estimate"))
        XCTAssertFalse(titleLabel.isDescendant(of: card))
    }

    @MainActor
    func testFitnessCardLayoutPersistsVisibilityAndOrder() throws {
        let suiteName = "FitnessCardLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = FitnessCardLayoutPreferences(defaults: defaults)

        preferences.moveCard(from: 2, to: 0)
        preferences.setVisible(false, card: .weeklyActivity)

        let restored = FitnessCardLayoutPreferences(defaults: defaults)
        XCTAssertEqual(restored.orderedCards, [.recentWorkouts, .weeklySummary, .weeklyActivity])
        XCTAssertFalse(restored.isVisible(.weeklyActivity))
        XCTAssertTrue(restored.isVisible(.recentWorkouts))
    }

    @MainActor
    func testFitnessViewUsesStoredCardVisibilityAndOrder() throws {
        let suiteName = "FitnessCardViewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = FitnessCardLayoutPreferences(defaults: defaults)
        preferences.moveCard(from: 2, to: 0)
        preferences.setVisible(false, card: .weeklyActivity)
        let service = AppleHealthSyncingStub(availableSources: [], disabledSourceSelections: [])
        let controller = FitnessViewController(appleHealthService: service, defaults: defaults)

        controller.loadViewIfNeeded()

        XCTAssertEqual(
            controller.contentStack.arrangedSubviews.compactMap(\.accessibilityIdentifier),
            [
                "fitness.card.section.recentWorkouts",
                "fitness.start",
                "fitness.card.section.weeklySummary"
            ]
        )
    }

    @MainActor
    func testSleepSourceBannerIsHiddenWhenAppleHealthIsNotConfigured() throws {
        let service = AppleHealthSyncingStub(availableSources: [], disabledSourceSelections: [])
        service.isConfigured = false
        service.state = .notConfigured
        let controller = SleepViewController(appleHealthService: service)

        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()

        let banner = try XCTUnwrap(descendant(
            of: FeedbackBannerView.self,
            identifier: "sleep.source.banner",
            in: controller.view
        ))
        XCTAssertTrue(banner.isHidden)
        XCTAssertEqual(controller.scrollView.contentInset.top, 0, accuracy: 0.01)
    }

    @MainActor
    func testSleepSourceBannerStaysOutsideScrollableContentWhenConfigured() throws {
        let service = AppleHealthSyncingStub(availableSources: [], disabledSourceSelections: [])
        service.isConfigured = true
        service.state = .ready
        let controller = SleepViewController(appleHealthService: service)

        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()

        let banner = try XCTUnwrap(descendant(
            of: FeedbackBannerView.self,
            identifier: "sleep.source.banner",
            in: controller.view
        ))
        XCTAssertFalse(banner.isHidden)
        XCTAssertTrue(banner.superview === controller.view)
        XCTAssertFalse(banner.isDescendant(of: controller.scrollView))
        XCTAssertGreaterThan(controller.scrollView.contentInset.top, banner.bounds.height)
        XCTAssertEqual(controller.navigationItem.largeTitleDisplayMode, .never)
        XCTAssertEqual(banner.actionButton.titleLabel?.numberOfLines, 2)
        XCTAssertEqual(
            banner.actionButton.title(for: .normal)?.split(separator: "\n").count,
            2
        )

        let fixedFrame = banner.frame
        let readyHeight = banner.bounds.height
        controller.scrollView.contentOffset.y = 240
        controller.view.layoutIfNeeded()
        XCTAssertEqual(banner.frame, fixedFrame)

        service.state = .syncing
        NotificationCenter.default.post(name: .appleHealthSyncDidChange, object: service)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(banner.bounds.height, readyHeight, accuracy: 0.01)

        var backgroundAlpha: CGFloat = 0
        XCTAssertTrue(banner.backgroundColor?.getRed(
            nil,
            green: nil,
            blue: nil,
            alpha: &backgroundAlpha
        ) == true)
        XCTAssertEqual(backgroundAlpha, 0.45, accuracy: 0.01)
    }

    @MainActor
    func testPremiumCardsDoNotRenderBottomAccent() {
        let card = PremiumCardView(frame: CGRect(x: 0, y: 0, width: 350, height: 180))
        card.layoutIfNeeded()

        let gradientLayers = card.layer.sublayers?.compactMap { $0 as? CAGradientLayer } ?? []
        XCTAssertEqual(gradientLayers.count, 1)
    }

    @MainActor
    func testHealthSourceBannerMatchesFixedSleepBanner() throws {
        let service = AppleHealthSyncingStub(availableSources: [], disabledSourceSelections: [])
        service.isConfigured = true
        service.state = .ready
        let controller = HealthViewController(appleHealthService: service)

        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()

        let banner = try XCTUnwrap(descendant(
            of: FeedbackBannerView.self,
            identifier: "health.source.banner",
            in: controller.view
        ))
        XCTAssertFalse(banner.isHidden)
        XCTAssertTrue(banner.superview === controller.view)
        XCTAssertFalse(banner.isDescendant(of: controller.scrollView))
        XCTAssertEqual(banner.bounds.height, 76, accuracy: 0.01)
        XCTAssertGreaterThan(controller.scrollView.contentInset.top, banner.bounds.height)
        XCTAssertEqual(controller.navigationItem.largeTitleDisplayMode, .never)
        XCTAssertEqual(banner.actionButton.titleLabel?.numberOfLines, 2)
        XCTAssertEqual(
            banner.actionButton.title(for: .normal)?.split(separator: "\n").count,
            2
        )

        let fixedFrame = banner.frame
        controller.scrollView.contentOffset.y = 240
        controller.view.layoutIfNeeded()
        XCTAssertEqual(banner.frame, fixedFrame)

        var backgroundAlpha: CGFloat = 0
        XCTAssertTrue(banner.backgroundColor?.getRed(
            nil,
            green: nil,
            blue: nil,
            alpha: &backgroundAlpha
        ) == true)
        XCTAssertEqual(backgroundAlpha, 0.45, accuracy: 0.01)
    }

    @MainActor
    func testHealthSourceBannerIsHiddenWhenAppleHealthIsNotConfigured() throws {
        let service = AppleHealthSyncingStub(availableSources: [], disabledSourceSelections: [])
        service.isConfigured = false
        service.state = .notConfigured
        let controller = HealthViewController(appleHealthService: service)

        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()

        let banner = try XCTUnwrap(descendant(
            of: FeedbackBannerView.self,
            identifier: "health.source.banner",
            in: controller.view
        ))
        XCTAssertTrue(banner.isHidden)
        XCTAssertEqual(controller.scrollView.contentInset.top, 0, accuracy: 0.01)
    }

    @MainActor
    func testSelectionFieldKeepsRoundedBorderWhileMenuButtonChangesState() throws {
        let field = SelectionFieldView(title: "Periodicidad")
        field.value = "Cada año"
        let configuration = try XCTUnwrap(field.button.configuration)

        XCTAssertEqual(configuration.cornerStyle, .fixed)
        XCTAssertEqual(
            configuration.background.cornerRadius,
            WellnarioRadius.control,
            accuracy: 0.01
        )
        XCTAssertEqual(configuration.background.strokeWidth, 1, accuracy: 0.01)
        XCTAssertTrue(field.button.clipsToBounds)

        field.button.isHighlighted = true
        let highlightedConfiguration = configuration.updated(for: field.button)
        XCTAssertEqual(highlightedConfiguration.cornerStyle, .fixed)
        XCTAssertEqual(
            highlightedConfiguration.background.cornerRadius,
            WellnarioRadius.control,
            accuracy: 0.01
        )
        XCTAssertEqual(highlightedConfiguration.background.strokeWidth, 1, accuracy: 0.01)
    }

    @MainActor
    func testMedicalReviewEditorDismissesKeyboardAndKeepsScheduleReachable() throws {
        let controller = MedicalReviewEditorViewController(review: nil)
        let navigationController = UINavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        controller.loadViewIfNeeded()
        navigationController.view.frame = window.bounds
        navigationController.view.layoutIfNeeded()

        let nameField = try XCTUnwrap(descendant(
            of: UITextField.self,
            identifier: "health.medical_reviews.editor.name",
            in: controller.view
        ))
        let cadenceButton = try XCTUnwrap(descendant(
            of: UIButton.self,
            identifier: "health.medical_reviews.editor.cadence",
            in: controller.view
        ))
        let scrollView = try XCTUnwrap(descendant(
            of: UIScrollView.self,
            identifier: "health.medical_reviews.editor.scroll",
            in: controller.view
        ))

        XCTAssertTrue(nameField.becomeFirstResponder())
        nameField.sendActions(for: .editingDidEndOnExit)
        XCTAssertFalse(nameField.isFirstResponder)

        XCTAssertTrue(nameField.becomeFirstResponder())
        cadenceButton.sendActions(for: .touchDown)
        XCTAssertFalse(nameField.isFirstResponder)

        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(
                    x: 0,
                    y: 500,
                    width: 390,
                    height: 344
                )
            ]
        )
        XCTAssertGreaterThan(scrollView.contentInset.bottom, 0)

        NotificationCenter.default.post(
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        XCTAssertEqual(scrollView.contentInset.bottom, 0, accuracy: 0.01)
    }

    @MainActor
    func testMedicalReviewEditorOffersVaccinesAndSelfTests() throws {
        XCTAssertEqual(
            MedicalReviewKind.allCases,
            [.specialistConsultation, .medicalTest, .vaccination, .selfTest]
        )
        XCTAssertTrue(MedicalReviewKind.allCases.allSatisfy {
            UIImage(systemName: $0.symbolName) != nil
        })

        let controller = MedicalReviewEditorViewController(review: nil)
        controller.loadViewIfNeeded()
        let kindButton = try XCTUnwrap(descendant(
            of: UIButton.self,
            identifier: "health.medical_reviews.editor.kind",
            in: controller.view
        ))
        let menuTitles = kindButton.menu?.children.compactMap { ($0 as? UIAction)?.title }

        XCTAssertEqual(
            menuTitles,
            MedicalReviewKind.allCases.map(\.title)
        )
        XCTAssertTrue(menuTitles?.contains(L10n.text("health.medical_reviews.kind.vaccination")) == true)
        XCTAssertTrue(menuTitles?.contains(L10n.text("health.medical_reviews.kind.self_test")) == true)
    }

    @MainActor
    func testMedicalReviewStorePersistsUpdatesSortsAndDeletesReviews() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MedicalReviewStoreTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Wellnario.sqlite")
        let repository = try WellnarioRepository(databaseURL: databaseURL)
        let store = try MedicalReviewStore(
            databaseURL: databaseURL,
            userID: repository.userID
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let baseline = try utcDate(2026, 1, 15, hour: 0)
        let annual = MedicalReview(
            title: "Dermatología",
            kind: .specialistConsultation,
            intervalMonths: 12,
            lastCompletedAt: baseline
        )
        let quarterly = MedicalReview(
            title: "Analítica general",
            kind: .medicalTest,
            intervalMonths: 3,
            lastCompletedAt: baseline
        )

        store.upsert(annual)
        store.upsert(quarterly)

        XCTAssertEqual(store.reviews.map(\.id), [quarterly.id, annual.id])
        XCTAssertEqual(
            annual.nextDueDate(calendar: calendar),
            try utcDate(2027, 1, 15, hour: 0)
        )

        var edited = quarterly
        edited.title = "Analítica completa"
        edited.intervalMonths = 6
        edited = edited.addingCompletion(
            on: try utcDate(2026, 7, 15, hour: 0),
            notes: "Repetir analítica en seis meses",
            calendar: calendar
        )
        store.upsert(edited)
        XCTAssertEqual(store.reviews.count, 2)
        XCTAssertEqual(store.reviews.first(where: { $0.id == edited.id }), edited)

        let reopened = try MedicalReviewStore(
            databaseURL: databaseURL,
            userID: repository.userID
        )
        let persisted = try XCTUnwrap(reopened.reviews.first(where: { $0.id == edited.id }))
        XCTAssertEqual(persisted.completions.count, 2)
        XCTAssertEqual(
            persisted.completions.map(\.completedAt),
            [
                try utcDate(2026, 7, 15, hour: 0),
                try utcDate(2026, 1, 15, hour: 0)
            ]
        )
        XCTAssertEqual(
            persisted.completions.first?.notes,
            "Repetir analítica en seis meses"
        )

        let notesUpdated = persisted.addingCompletion(
            on: try utcDate(2026, 7, 15, hour: 0),
            notes: "Resultados dentro de rango",
            calendar: calendar
        )
        reopened.upsert(notesUpdated)
        let afterNotesUpdate = try XCTUnwrap(
            reopened.reviews.first(where: { $0.id == edited.id })
        )
        XCTAssertEqual(afterNotesUpdate.completions.count, 2)
        XCTAssertEqual(afterNotesUpdate.completions.first?.notes, "Resultados dentro de rango")

        reopened.upsert(MedicalReview(
            title: "analítica completa",
            kind: .medicalTest,
            intervalMonths: 6,
            lastCompletedAt: try utcDate(2026, 8, 15, hour: 0)
        ))
        let merged = reopened.reviews.filter {
            $0.title.compare("Analítica completa", options: .caseInsensitive) == .orderedSame
        }
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(try XCTUnwrap(merged.first).completions.count, 3)

        reopened.delete(id: annual.id)
        XCTAssertEqual(reopened.reviews.count, 1)
    }

    @MainActor
    func testAllMedicalReviewHistoryCombinesTypesNewestFirstAndOpensFromToolbar() throws {
        let store = MedicalReviewStore()
        let olderDate = try utcDate(2024, 2, 10, hour: 0)
        let middleDate = try utcDate(2025, 5, 20, hour: 0)
        let newestDate = try utcDate(2026, 7, 15, hour: 0)
        let dermatologyID = UUID()
        let bloodworkID = UUID()
        store.upsert(MedicalReview(
            id: dermatologyID,
            title: "Dermatología",
            kind: .specialistConsultation,
            intervalMonths: 12,
            completions: [
                MedicalReviewCompletion(completedAt: olderDate),
                MedicalReviewCompletion(
                    completedAt: newestDate,
                    notes: "Sin lesiones sospechosas"
                )
            ]
        ))
        store.upsert(MedicalReview(
            id: bloodworkID,
            title: "Analítica general",
            kind: .medicalTest,
            intervalMonths: 6,
            completions: [MedicalReviewCompletion(completedAt: middleDate)]
        ))

        XCTAssertEqual(
            store.historyEntries.map(\.completion.completedAt),
            [newestDate, middleDate, olderDate]
        )
        XCTAssertEqual(
            store.historyEntries.map(\.reviewTitle),
            ["Dermatología", "Analítica general", "Dermatología"]
        )

        let controller = MedicalReviewsViewController(store: store)
        let navigationController = UINavigationController(rootViewController: controller)
        controller.loadViewIfNeeded()
        let buttons = try XCTUnwrap(controller.navigationItem.rightBarButtonItems)
        XCTAssertEqual(
            buttons.map(\.accessibilityIdentifier),
            ["health.medical_reviews.add", "health.medical_reviews.all.open"]
        )
        let historyButton = buttons[1]
        XCTAssertTrue(UIApplication.shared.sendAction(
            try XCTUnwrap(historyButton.action),
            to: historyButton.target,
            from: historyButton,
            for: nil
        ))

        let historyController = try XCTUnwrap(
            navigationController.topViewController as? AllMedicalReviewHistoryViewController
        )
        historyController.loadViewIfNeeded()
        XCTAssertEqual(historyController.view.accessibilityIdentifier, "health.medical_reviews.all.root")
        XCTAssertEqual(historyController.tableView.numberOfRows(inSection: 0), 3)
        let firstCell = try XCTUnwrap(historyController.tableView(
            historyController.tableView,
            cellForRowAt: IndexPath(row: 0, section: 0)
        ))
        XCTAssertEqual(
            (firstCell.contentConfiguration as? UIListContentConfiguration)?.text,
            "Dermatología"
        )
        XCTAssertTrue(
            (firstCell.contentConfiguration as? UIListContentConfiguration)?
                .secondaryText?.contains("Sin lesiones sospechosas") == true
        )

        historyController.tableView(
            historyController.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 0)
        )
        let completionEditor = try XCTUnwrap(
            navigationController.topViewController as? MedicalReviewCompletionEditorViewController
        )
        completionEditor.loadViewIfNeeded()
        let completionDate = try XCTUnwrap(descendant(
            of: UIDatePicker.self,
            identifier: "health.medical_reviews.completion.editor.date",
            in: completionEditor.view
        ))
        let editedDate = try XCTUnwrap(Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: -1,
            to: completionDate.date
        ))
        completionDate.date = editedDate
        let completionNotes = try XCTUnwrap(descendant(
            of: UITextView.self,
            identifier: "health.medical_reviews.completion.editor.notes",
            in: completionEditor.view
        ))
        completionNotes.text = "Observación actualizada"
        let completionSave = try XCTUnwrap(completionEditor.navigationItem.rightBarButtonItem)
        XCTAssertTrue(UIApplication.shared.sendAction(
            try XCTUnwrap(completionSave.action),
            to: completionSave.target,
            from: completionSave,
            for: nil
        ))
        let editedCompletion = try XCTUnwrap(
            store.reviews.first(where: { $0.id == dermatologyID })?.completions.first(where: {
                $0.notes == "Observación actualizada"
            })
        )
        XCTAssertTrue(Calendar.autoupdatingCurrent.isDate(
            editedCompletion.completedAt,
            inSameDayAs: editedDate
        ))
    }

    @MainActor
    func testMedicalReviewCompletionDateEditRemovesOldDateAndMergesCollision() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let store = MedicalReviewStore()
        let older = MedicalReviewCompletion(
            completedAt: try utcDate(2025, 1, 10, hour: 0),
            notes: "Primera"
        )
        let newer = MedicalReviewCompletion(
            completedAt: try utcDate(2026, 1, 10, hour: 0),
            notes: "Segunda"
        )
        let review = MedicalReview(
            id: UUID(),
            title: "Oftalmología",
            kind: .specialistConsultation,
            intervalMonths: 12,
            completions: [older, newer]
        )
        store.upsert(review)

        store.updateCompletion(
            reviewID: review.id,
            completionID: older.id,
            completedAt: try utcDate(2027, 1, 10, hour: 0),
            notes: "Fecha corregida"
        )
        var persisted = try XCTUnwrap(store.reviews.first)
        XCTAssertEqual(persisted.completions.count, 2)
        XCTAssertFalse(persisted.completions.contains(where: {
            calendar.isDate($0.completedAt, inSameDayAs: older.completedAt)
        }))
        XCTAssertEqual(persisted.completions.first?.id, older.id)
        XCTAssertEqual(persisted.completions.first?.notes, "Fecha corregida")

        store.updateCompletion(
            reviewID: review.id,
            completionID: older.id,
            completedAt: newer.completedAt,
            notes: "Unificada"
        )
        persisted = try XCTUnwrap(store.reviews.first)
        XCTAssertEqual(persisted.completions.count, 1)
        XCTAssertEqual(persisted.completions.first?.id, older.id)
        XCTAssertEqual(persisted.completions.first?.notes, "Unificada")

        store.deleteCompletion(reviewID: review.id, completionID: older.id)
        XCTAssertTrue(store.reviews.isEmpty)
    }

    @MainActor
    func testMedicalReviewNotesFieldIsCompactAndWrapsPlaceholder() {
        let field = TextAreaFieldView()
        field.minimumHeight = 80
        field.placeholder = L10n.text("health.medical_reviews.notes.placeholder")

        XCTAssertEqual(field.minimumHeight, 80)
        XCTAssertEqual(field.placeholderLabel.numberOfLines, 0)
        XCTAssertEqual(field.placeholderLabel.lineBreakMode, .byWordWrapping)
    }

    @MainActor
    func testMedicalReviewStoreMigratesLegacyDefaultsIntoSQLiteHistory() throws {
        let suiteName = "MedicalReviewLegacyMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = LegacyMedicalReviewFixture(
            id: UUID(),
            title: "Dermatología",
            kind: .specialistConsultation,
            intervalMonths: 12,
            lastCompletedAt: try utcDate(2025, 10, 2, hour: 0)
        )
        defaults.set(
            try JSONEncoder().encode([legacy]),
            forKey: "wellnario.health.medicalReviews"
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MedicalReviewLegacyDB.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Wellnario.sqlite")
        let repository = try WellnarioRepository(databaseURL: databaseURL)
        let store = try MedicalReviewStore(
            databaseURL: databaseURL,
            userID: repository.userID,
            legacyDefaults: defaults
        )

        let migrated = try XCTUnwrap(store.reviews.first)
        XCTAssertEqual(migrated.id, legacy.id)
        XCTAssertEqual(migrated.completions.count, 1)
        XCTAssertEqual(migrated.lastCompletedAt, legacy.lastCompletedAt)
        XCTAssertNil(defaults.data(forKey: "wellnario.health.medicalReviews"))
    }

    @MainActor
    func testMedicalReviewEditorShowsFullHistoryOnlyWhenEditing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var review = MedicalReview(
            title: "Dermatología",
            kind: .specialistConsultation,
            intervalMonths: 12,
            lastCompletedAt: try utcDate(2024, 3, 1, hour: 0),
            notes: "Control anual"
        )
        review = review.addingCompletion(
            on: try utcDate(2025, 3, 1, hour: 0),
            calendar: calendar
        )
        review = review.addingCompletion(
            on: try utcDate(2026, 3, 1, hour: 0),
            calendar: calendar
        )

        let editor = MedicalReviewEditorViewController(review: review)
        let navigationController = UINavigationController(rootViewController: editor)
        editor.loadViewIfNeeded()
        let historyCard = try XCTUnwrap(descendant(
            of: MedicalReviewHistoryCard.self,
            identifier: "health.medical_reviews.history",
            in: editor.view
        ))
        for index in 0..<3 {
            XCTAssertNotNil(descendant(
                of: UIStackView.self,
                identifier: "health.medical_reviews.history.row.\(index)",
                in: historyCard
            ))
        }
        XCTAssertTrue(historyCard.accessibilityValue?.contains("3") == true)
        var requestedDeletion: MedicalReviewCompletion?
        historyCard.onDeleteCompletion = { requestedDeletion = $0 }
        historyCard.requestDeletion(at: 1)
        XCTAssertEqual(requestedDeletion?.id, review.completions[1].id)

        historyCard.selectCompletion(at: 0)
        let completionEditor = try XCTUnwrap(
            navigationController.topViewController as? MedicalReviewCompletionEditorViewController
        )
        completionEditor.loadViewIfNeeded()
        let completionNotes = try XCTUnwrap(descendant(
            of: UITextView.self,
            identifier: "health.medical_reviews.completion.editor.notes",
            in: completionEditor.view
        ))
        completionNotes.text = "Seguimiento editado"
        let completionSave = try XCTUnwrap(completionEditor.navigationItem.rightBarButtonItem)
        XCTAssertTrue(UIApplication.shared.sendAction(
            try XCTUnwrap(completionSave.action),
            to: completionSave.target,
            from: completionSave,
            for: nil
        ))
        XCTAssertTrue(navigationController.topViewController === editor)

        let datePicker = try XCTUnwrap(descendant(
            of: UIDatePicker.self,
            identifier: "health.medical_reviews.editor.last_date",
            in: editor.view
        ))
        datePicker.date = try utcDate(2026, 6, 1, hour: 0)
        datePicker.sendActions(for: .valueChanged)
        let notesField = try XCTUnwrap(descendant(
            of: UITextView.self,
            identifier: "health.medical_reviews.editor.notes",
            in: editor.view
        ))
        XCTAssertTrue(notesField.text.isEmpty)
        notesField.text = "Revisión sin incidencias"
        var savedReview: MedicalReview?
        editor.onSave = { savedReview = $0 }
        let saveItem = try XCTUnwrap(editor.navigationItem.rightBarButtonItem)
        let saveAction = try XCTUnwrap(saveItem.action)
        XCTAssertTrue(UIApplication.shared.sendAction(
            saveAction,
            to: saveItem.target,
            from: saveItem,
            for: nil
        ))
        XCTAssertEqual(savedReview?.completions.count, 4)
        XCTAssertEqual(savedReview?.completions.first?.notes, "Revisión sin incidencias")
        XCTAssertTrue(savedReview?.completions.contains(where: {
            $0.notes == "Seguimiento editado"
        }) == true)
        XCTAssertTrue(Calendar.autoupdatingCurrent.isDate(
            try XCTUnwrap(savedReview?.lastCompletedAt),
            inSameDayAs: datePicker.date
        ))

        let newEditor = MedicalReviewEditorViewController(review: nil)
        newEditor.loadViewIfNeeded()
        XCTAssertNil(descendant(
            of: MedicalReviewHistoryCard.self,
            identifier: "health.medical_reviews.history",
            in: newEditor.view
        ))
    }

    @MainActor
    func testTodayMedicalReviewsPrioritizeLimitAndColorByOverdueRatio() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let referenceDate = try utcDate(2026, 7, 15, hour: 0)
        let reviews = [
            MedicalReview(
                title: "Muy vencida",
                kind: .medicalTest,
                intervalMonths: 4,
                lastCompletedAt: try utcDate(2025, 9, 1, hour: 0)
            ),
            MedicalReview(
                title: "Vencida intermedia",
                kind: .specialistConsultation,
                intervalMonths: 4,
                lastCompletedAt: try utcDate(2026, 1, 1, hour: 0)
            ),
            MedicalReview(
                title: "Vencida reciente",
                kind: .medicalTest,
                intervalMonths: 4,
                lastCompletedAt: try utcDate(2026, 2, 20, hour: 0)
            ),
            MedicalReview(
                title: "Próxima",
                kind: .specialistConsultation,
                intervalMonths: 4,
                lastCompletedAt: try utcDate(2026, 4, 1, hour: 0)
            ),
            MedicalReview(
                title: "Más lejana",
                kind: .medicalTest,
                intervalMonths: 4,
                lastCompletedAt: try utcDate(2026, 5, 1, hour: 0)
            )
        ]

        let entries = MedicalReviewTimeline.entries(
            from: Array(reviews.reversed()),
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(
            entries.map(\.review.title),
            ["Muy vencida", "Vencida intermedia", "Vencida reciente", "Próxima"]
        )
        XCTAssertEqual(
            entries.map(\.urgency),
            [
                .overdueOverThreeQuarters,
                .overdueFromQuarterThroughThreeQuarters,
                .overdueUnderQuarter,
                .upcoming
            ]
        )

        let card = TodayMedicalReviewsSummaryCard()
        card.configure(reviews: reviews, referenceDate: referenceDate, calendar: calendar)
        for (index, urgency) in entries.map(\.urgency).enumerated() {
            let row = try XCTUnwrap(descendant(
                of: TodayMedicalReviewRow.self,
                identifier: "today.summary.reviews.row.\(index)",
                in: card
            ))
            XCTAssertEqual(row.urgency, urgency)
            XCTAssertEqual(
                row.reviewTitleLabel.text,
                [
                    entries[index].review.title,
                    MedicalReviewFormatting.relativeDayStatus(
                        dueDate: entries[index].dueDate,
                        referenceDate: referenceDate,
                        calendar: calendar
                    )
                ].joined(separator: " · ")
            )
            XCTAssertEqual(row.reviewTitleLabel.numberOfLines, 2)
            XCTAssertEqual(row.reviewTitleLabel.lineBreakMode, .byWordWrapping)
            XCTAssertFalse(row.reviewTitleLabel.adjustsFontSizeToFitWidth)
            XCTAssertEqual(
                row.reviewTitleLabel.font.pointSize,
                WellnarioTypography.font(for: .summaryDetail).pointSize,
                accuracy: 0.01
            )
        }
        XCTAssertNil(descendant(
            of: TodayMedicalReviewRow.self,
            identifier: "today.summary.reviews.row.4",
            in: card
        ))
    }

    @MainActor
    func testTodaySummaryCardHeadersShareLayoutTypographyAndRemainPressable() {
        let summaryCard = WellnessSummaryCard()
        summaryCard.configure(
            title: "Resumen",
            symbolName: "heart.fill",
            value: "1",
            detail: "Detalle",
            tone: WellnarioPalette.fuchsia
        )
        let reviewsCard = TodayMedicalReviewsSummaryCard()
        reviewsCard.configure(reviews: [])

        summaryCard.frame = CGRect(x: 0, y: 0, width: 170, height: 130)
        reviewsCard.frame = summaryCard.frame
        summaryCard.layoutIfNeeded()
        reviewsCard.layoutIfNeeded()

        XCTAssertEqual(summaryCard.titleLabel.numberOfLines, 2)
        XCTAssertEqual(reviewsCard.titleLabel.numberOfLines, 2)
        XCTAssertFalse(summaryCard.titleLabel.adjustsFontSizeToFitWidth)
        XCTAssertFalse(reviewsCard.titleLabel.adjustsFontSizeToFitWidth)
        XCTAssertEqual(
            summaryCard.titleLabel.font.pointSize,
            reviewsCard.titleLabel.font.pointSize,
            accuracy: 0.01
        )
        let summarySymbolFrame = summaryCard.symbolContainer.convert(
            summaryCard.symbolContainer.bounds,
            to: summaryCard
        )
        let reviewsSymbolFrame = reviewsCard.symbolContainer.convert(
            reviewsCard.symbolContainer.bounds,
            to: reviewsCard
        )
        XCTAssertEqual(summarySymbolFrame.minX, reviewsSymbolFrame.minX, accuracy: 0.01)
        XCTAssertEqual(summarySymbolFrame.minY, reviewsSymbolFrame.minY, accuracy: 0.01)
        XCTAssertTrue(summaryCard.isPressable)
        XCTAssertTrue(reviewsCard.isPressable)
    }

    @MainActor
    func testMedicalReviewRelativeDayStatusUsesCalendarDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let referenceDate = try utcDate(2026, 7, 15, hour: 22)

        XCTAssertEqual(
            MedicalReviewFormatting.relativeDayStatus(
                dueDate: try utcDate(2026, 7, 18, hour: 1),
                referenceDate: referenceDate,
                calendar: calendar
            ),
            L10n.text("today.reviews.due.remaining.many", 3)
        )
        XCTAssertEqual(
            MedicalReviewFormatting.relativeDayStatus(
                dueDate: try utcDate(2026, 7, 16, hour: 1),
                referenceDate: referenceDate,
                calendar: calendar
            ),
            L10n.text("today.reviews.due.remaining.one")
        )
        XCTAssertEqual(
            MedicalReviewFormatting.relativeDayStatus(
                dueDate: try utcDate(2026, 7, 15, hour: 1),
                referenceDate: referenceDate,
                calendar: calendar
            ),
            L10n.text("today.reviews.due.today")
        )
        XCTAssertEqual(
            MedicalReviewFormatting.relativeDayStatus(
                dueDate: try utcDate(2026, 7, 14, hour: 23),
                referenceDate: referenceDate,
                calendar: calendar
            ),
            L10n.text("today.reviews.due.overdue.one")
        )
        XCTAssertEqual(
            MedicalReviewFormatting.relativeDayStatus(
                dueDate: try utcDate(2026, 7, 10, hour: 23),
                referenceDate: referenceDate,
                calendar: calendar
            ),
            L10n.text("today.reviews.due.overdue.many", 5)
        )
    }

    func testMedicalReviewOverdueThresholdsIncludeQuarterAndThreeQuartersInOrange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let review = MedicalReview(
            title: "Analítica",
            kind: .medicalTest,
            intervalMonths: 4,
            lastCompletedAt: try utcDate(2026, 1, 1, hour: 0)
        )

        XCTAssertEqual(
            MedicalReviewTimeline.urgency(
                for: review,
                referenceDate: try utcDate(2026, 4, 30, hour: 0),
                calendar: calendar
            ),
            .upcoming
        )
        XCTAssertEqual(
            MedicalReviewTimeline.urgency(
                for: review,
                referenceDate: try utcDate(2026, 5, 30, hour: 0),
                calendar: calendar
            ),
            .overdueUnderQuarter
        )
        XCTAssertEqual(
            MedicalReviewTimeline.urgency(
                for: review,
                referenceDate: try utcDate(2026, 5, 31, hour: 0),
                calendar: calendar
            ),
            .overdueFromQuarterThroughThreeQuarters
        )
        XCTAssertEqual(
            MedicalReviewTimeline.urgency(
                for: review,
                referenceDate: try utcDate(2026, 7, 30, hour: 0),
                calendar: calendar
            ),
            .overdueFromQuarterThroughThreeQuarters
        )
        XCTAssertEqual(
            MedicalReviewTimeline.urgency(
                for: review,
                referenceDate: try utcDate(2026, 7, 31, hour: 0),
                calendar: calendar
            ),
            .overdueOverThreeQuarters
        )
    }

    @MainActor
    func testHealthIncludesMedicalReviewsCard() throws {
        let suiteName = "MedicalReviewHealthCardTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = AppleHealthSyncingStub(availableSources: [], disabledSourceSelections: [])
        let controller = HealthViewController(
            appleHealthService: service,
            medicalReviewStore: MedicalReviewStore(defaults: defaults),
            defaults: defaults
        )

        controller.loadViewIfNeeded()

        let button = try XCTUnwrap(descendant(
            of: UIButton.self,
            identifier: "health.medical_reviews.open",
            in: controller.view
        ))
        XCTAssertEqual(button.accessibilityLabel, "Revisiones médicas")
        XCTAssertTrue(button.accessibilityValue?.contains("0") == true)
    }

    @MainActor
    func testFitnessUsesPersistentCompactTitle() {
        let service = AppleHealthSyncingStub(availableSources: [], disabledSourceSelections: [])
        let controller = FitnessViewController(appleHealthService: service)

        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.navigationItem.largeTitleDisplayMode, .never)
    }

    @MainActor
    func testTrendChartRendersReferenceLinesAndYAxisLabels() throws {
        let chart = WellnessTrendChartView(frame: CGRect(x: 0, y: 0, width: 360, height: 190))
        chart.values = [6.5, 7.2, 8.1, 7.4, 6.9, 8.4, 7.8]
        chart.labels = ["L", "M", "X", "J", "V", "S", "D"]
        chart.selectionLabels = ["8 jul", "9 jul", "10 jul", "11 jul", "12 jul", "13 jul", "14 jul"]
        chart.smoothingWindow = 7
        chart.averageTitle = "Media"
        chart.lineColor = WellnarioPalette.violet
        chart.averageColor = WellnarioPalette.cyan
        chart.linearTrend = WellnessLinearTrend(
            startPosition: 0,
            startValue: 6.6,
            endPosition: 1,
            endValue: 8.2
        )
        chart.referenceLine = .linearTrend
        chart.valueFormatter = { String(format: "%.1f h", $0) }
        chart.updateSelection(atX: 220)

        let image = UIGraphicsImageRenderer(bounds: chart.bounds).image { _ in
            chart.drawHierarchy(in: chart.bounds, afterScreenUpdates: true)
        }

        XCTAssertEqual(chart.selectedIndex, 3)
        XCTAssertTrue(chart.averageColor.isEqual(WellnarioPalette.cyan))
        XCTAssertTrue(chart.linearTrendColor.isEqual(WellnarioPalette.success))
        XCTAssertFalse(chart.averageColor.isEqual(chart.lineColor))
        XCTAssertFalse(chart.linearTrendColor.isEqual(chart.lineColor))
        XCTAssertFalse(chart.linearTrendColor.isEqual(chart.averageColor))
        XCTAssertEqual(chart.referenceLine, .linearTrend)
        chart.linearTrend = WellnessLinearTrend(
            startPosition: 0,
            startValue: 8.2,
            endPosition: 1,
            endValue: 6.6
        )
        XCTAssertTrue(chart.linearTrendColor.isEqual(WellnarioPalette.danger))
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1_000)

        chart.referenceLine = .average
        let averageImage = UIGraphicsImageRenderer(bounds: chart.bounds).image { _ in
            chart.drawHierarchy(in: chart.bounds, afterScreenUpdates: true)
        }
        XCTAssertGreaterThan(try XCTUnwrap(averageImage.pngData()).count, 1_000)
        chart.clearSelection()
        XCTAssertNil(chart.selectedIndex)
    }

    @MainActor
    func testSleepStageTimelineRendersNightlyHypnogram() throws {
        let start = try utcDate(2026, 7, 9, hour: 23)
        let intervals = [
            AppleHealthSleepStageInterval(
                startDate: start,
                endDate: start.addingTimeInterval(2 * 3_600),
                stage: .core
            ),
            AppleHealthSleepStageInterval(
                startDate: start.addingTimeInterval(2 * 3_600),
                endDate: start.addingTimeInterval(3 * 3_600),
                stage: .deep
            ),
            AppleHealthSleepStageInterval(
                startDate: start.addingTimeInterval(3 * 3_600),
                endDate: start.addingTimeInterval(3.25 * 3_600),
                stage: .awake
            ),
            AppleHealthSleepStageInterval(
                startDate: start.addingTimeInterval(3.25 * 3_600),
                endDate: start.addingTimeInterval(5 * 3_600),
                stage: .rem
            )
        ]
        let session = AppleHealthSleepSession(
            startDate: start,
            endDate: start.addingTimeInterval(5 * 3_600),
            asleepSeconds: 4.75 * 3_600,
            inBedSeconds: 5 * 3_600,
            awakeSeconds: 0.25 * 3_600,
            coreSeconds: 2 * 3_600,
            deepSeconds: 3_600,
            remSeconds: 1.75 * 3_600,
            sourceNames: ["Apple Watch"],
            stageIntervals: intervals
        )
        let chart = SleepStageTimelineView(frame: CGRect(x: 0, y: 0, width: 360, height: 164))
        chart.configure(session: session)

        let image = UIGraphicsImageRenderer(bounds: chart.bounds).image { _ in
            chart.drawHierarchy(in: chart.bounds, afterScreenUpdates: true)
        }

        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1_000)
        XCTAssertNotNil(chart.accessibilityValue)
        XCTAssertEqual(chart.intrinsicContentSize.height, 164)
    }

    @MainActor
    func testCompactSleepStageDurationFormatting() {
        XCTAssertEqual(AppleHealthUIFormatting.compactDuration(43 * 60), "43m")
        XCTAssertEqual(AppleHealthUIFormatting.compactDuration(60 * 60), "1h")
        XCTAssertEqual(AppleHealthUIFormatting.compactDuration((60 + 43) * 60), "1h 43m")
    }

    @MainActor
    func testNumericDateAndTimeUsesDeviceRegionalOrderAndFourDigitYear() throws {
        let date = try utcDate(2026, 7, 15, hour: 17)

        let dayFirst = WellnarioFormatters.numericDateAndTime(
            date,
            locale: Locale(identifier: "es_ES"),
            timeZoneID: "UTC"
        )
        let monthFirst = WellnarioFormatters.numericDateAndTime(
            date,
            locale: Locale(identifier: "en_US"),
            timeZoneID: "UTC"
        )

        XCTAssertTrue(dayFirst.hasPrefix("15/07/2026"))
        XCTAssertTrue(monthFirst.hasPrefix("07/15/2026"))
    }

    @MainActor
    func testTypographyScalingSupportsBothDirections() {
        let largeTraits = UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge)
        let smallTraits = UITraitCollection(preferredContentSizeCategory: .small)
        let largeFont = WellnarioTypography.font(for: .body, compatibleWith: largeTraits)
        let smallFont = WellnarioTypography.font(for: .body, compatibleWith: smallTraits)

        XCTAssertGreaterThan(largeFont.pointSize, smallFont.pointSize)
    }

    @MainActor
    func testAppearanceDefaultsToDarkAndPersistsSelection() throws {
        let suiteName = "WellnarioAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = WellnarioAppearanceManager(defaults: defaults)
        XCTAssertEqual(manager.mode, .dark)
        XCTAssertEqual(manager.mode.interfaceStyle, .dark)

        manager.setMode(.light)
        XCTAssertEqual(WellnarioAppearanceManager(defaults: defaults).mode, .light)

        manager.setMode(.system)
        XCTAssertEqual(WellnarioAppearanceManager(defaults: defaults).mode, .system)
        XCTAssertEqual(manager.mode.interfaceStyle, .unspecified)
    }

    func testAppDoesNotForceDarkModeInInfoPlist() {
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle"))
    }

    @MainActor
    func testLightPaletteHasLightBackgroundAndDarkReadableText() {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        let lightBackground = WellnarioPalette.background.resolvedColor(with: lightTraits)
        let darkBackground = WellnarioPalette.background.resolvedColor(with: darkTraits)
        let lightText = WellnarioPalette.textPrimary.resolvedColor(with: lightTraits)

        XCTAssertGreaterThan(relativeLuminance(lightBackground), relativeLuminance(darkBackground))
        XCTAssertGreaterThan(relativeLuminance(lightBackground), relativeLuminance(lightText))
    }

    @MainActor
    func testSettingsAppearanceChoiceUpdatesManager() throws {
        let suiteName = "WellnarioSettingsAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = WellnarioAppearanceManager(defaults: defaults)
        let service = AppleHealthSyncingStub(availableSources: [], disabledSourceSelections: [])
        let controller = SettingsViewController(
            appleHealthService: service,
            appearanceManager: manager
        )
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()

        let lightControl = try XCTUnwrap(descendant(
            of: UIControl.self,
            identifier: "settings.appearance.light",
            in: controller.view
        ))
        lightControl.sendActions(for: .touchUpInside)

        XCTAssertEqual(manager.mode, .light)
        XCTAssertTrue(lightControl.isSelected)
    }

    @MainActor
    func testTabSelectionResetsDestinationScrollPosition() {
        let first = ScrollPositionTestViewController()
        let second = ScrollPositionTestViewController()
        let controller = RootTabBarController()
        controller.install(
            viewControllers: [
                WellnarioNavigationController(rootViewController: first),
                WellnarioNavigationController(rootViewController: second)
            ],
            selectedIndex: 0
        )
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()

        second.loadViewIfNeeded()
        second.scrollView.contentOffset.y = 320
        controller.select(index: 1, animated: false)

        XCTAssertEqual(
            second.scrollView.contentOffset.y,
            -second.scrollView.adjustedContentInset.top,
            accuracy: 0.01
        )

        first.scrollView.contentOffset.y = 240
        controller.select(index: 0, animated: false)
        XCTAssertEqual(
            first.scrollView.contentOffset.y,
            -first.scrollView.adjustedContentInset.top,
            accuracy: 0.01
        )

        first.scrollView.contentOffset.y = 180
        controller.select(index: 0, animated: false)
        XCTAssertEqual(
            first.scrollView.contentOffset.y,
            -first.scrollView.adjustedContentInset.top,
            accuracy: 0.01
        )
    }

    @MainActor
    func testTabBarAcceptsAnotherSelectionWhileCrossfadeIsRunning() throws {
        XCTAssertEqual(WellnarioScreenTransition.duration, 0.60, accuracy: 0.001)

        let first = ScrollPositionTestViewController()
        let second = ScrollPositionTestViewController()
        let controller = RootTabBarController()
        controller.install(
            viewControllers: [
                WellnarioNavigationController(rootViewController: first),
                WellnarioNavigationController(rootViewController: second)
            ],
            selectedIndex: 0
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let floatingTabBar = try XCTUnwrap(descendant(
            of: UIView.self,
            identifier: "wellnario.floatingTabBar",
            in: controller.view
        ))

        controller.select(index: 1, animated: true)
        XCTAssertTrue(floatingTabBar.isUserInteractionEnabled)
        XCTAssertEqual(controller.selectedIndex, 1)
        let firstTransitionSnapshot = try XCTUnwrap(descendant(
            of: UIView.self,
            identifier: "wellnario.tabTransition.snapshot",
            in: controller.view
        ))
        XCTAssertTrue(firstTransitionSnapshot.superview === controller.view)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        controller.select(index: 0, animated: true)
        XCTAssertTrue(floatingTabBar.isUserInteractionEnabled)
        XCTAssertEqual(controller.selectedIndex, 0)
        let secondTransitionSnapshot = try XCTUnwrap(descendant(
            of: UIView.self,
            identifier: "wellnario.tabTransition.snapshot",
            in: controller.view
        ))
        XCTAssertTrue(secondTransitionSnapshot.superview === controller.view)
        XCTAssertFalse(secondTransitionSnapshot === firstTransitionSnapshot)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        controller.select(index: 0, animated: false)
        XCTAssertNil(descendant(
            of: UIView.self,
            identifier: "wellnario.tabTransition.snapshot",
            in: controller.view
        ))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    @MainActor
    func testNavigationDestinationResetsScrollPositionBeforeShowing() {
        let destination = ScrollPositionTestViewController()
        let navigationController = WellnarioNavigationController(
            rootViewController: UIViewController()
        )
        destination.loadViewIfNeeded()
        destination.scrollView.contentOffset.y = 280

        navigationController.navigationController(
            navigationController,
            willShow: destination,
            animated: true
        )

        XCTAssertEqual(
            destination.scrollView.contentOffset.y,
            -destination.scrollView.adjustedContentInset.top,
            accuracy: 0.01
        )
    }

    @MainActor
    private func relativeLuminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return (red * 0.2126) + (green * 0.7152) + (blue * 0.0722)
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

    private func sleepDays(
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) -> [AppleHealthSleepDay] {
        var result: [AppleHealthSleepDay] = []
        var day = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        while day <= lastDay {
            result.append(AppleHealthSleepDay(
                date: day,
                hours: 8,
                qualityScore: 85,
                remHours: 2,
                deepHours: 1.5,
                lightHours: 4.5
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
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

    @MainActor
    private func descendant<View: UIView>(
        of type: View.Type,
        identifier: String,
        in root: UIView
    ) -> View? {
        if let view = root as? View, view.accessibilityIdentifier == identifier {
            return view
        }
        for subview in root.subviews {
            if let match = descendant(of: type, identifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }
}

@MainActor
private final class ScrollPositionTestViewController: UIViewController {
    let scrollView = UIScrollView()

    override func loadView() {
        scrollView.contentSize = CGSize(width: 390, height: 2_000)
        view = scrollView
    }
}

private struct LegacyMedicalReviewFixture: Codable {
    let id: UUID
    let title: String
    let kind: MedicalReviewKind
    let intervalMonths: Int
    let lastCompletedAt: Date
}

@MainActor
private final class AppleHealthSyncingStub: AppleHealthSyncing {
    var snapshot = AppleHealthSnapshot.empty
    var state = AppleHealthSyncState.ready
    var isConfigured = true
    var availableSources: [AppleHealthDataSource]
    var disabledSourceSelections: Set<AppleHealthSourceSelection>
    private(set) var syncIfConfiguredCallCount = 0

    init(
        availableSources: [AppleHealthDataSource],
        disabledSourceSelections: Set<AppleHealthSourceSelection>
    ) {
        self.availableSources = availableSources
        self.disabledSourceSelections = disabledSourceSelections
    }

    func requestAuthorizationAndSync() async throws {}
    func sync() async throws {}
    func syncIfConfigured() async { syncIfConfiguredCallCount += 1 }

    func setSourceEnabled(
        _ identifier: String,
        for dataKind: AppleHealthDataKind,
        isEnabled: Bool
    ) {
        let selection = AppleHealthSourceSelection(
            sourceIdentifier: identifier,
            dataKind: dataKind
        )
        if isEnabled {
            disabledSourceSelections.remove(selection)
        } else {
            disabledSourceSelections.insert(selection)
        }
    }
}
