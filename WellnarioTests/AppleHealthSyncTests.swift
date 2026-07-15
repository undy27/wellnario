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
