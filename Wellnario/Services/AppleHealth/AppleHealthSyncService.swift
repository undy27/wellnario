@preconcurrency import HealthKit
import UIKit

struct AppleHealthMeasurement: Codable, Equatable, Sendable {
    let value: Double
    let date: Date
    let sourceName: String
}

struct AppleHealthSleepSession: Codable, Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let asleepSeconds: TimeInterval
    let inBedSeconds: TimeInterval
    let awakeSeconds: TimeInterval
    let coreSeconds: TimeInterval
    let deepSeconds: TimeInterval
    let remSeconds: TimeInterval
    let sourceNames: [String]
}

struct AppleHealthSleepDay: Codable, Equatable, Sendable {
    let date: Date
    let hours: Double?
}

enum AppleHealthSleepTrendPeriod: Int, CaseIterable, Sendable {
    case sevenDays
    case thirtyDays
    case sixMonths
    case allTime
}

enum AppleHealthWorkoutKind: String, Codable, Equatable, Sendable {
    case walking
    case running
    case cycling
    case swimming
    case strength
    case yoga
    case highIntensityIntervalTraining
    case other
}

struct AppleHealthWorkout: Codable, Equatable, Sendable {
    let id: UUID
    let kind: AppleHealthWorkoutKind
    let startDate: Date
    let endDate: Date
    let durationSeconds: TimeInterval
    let activeEnergyKilocalories: Double?
    let sourceName: String
}

struct AppleHealthSnapshot: Codable, Equatable, Sendable {
    var lastSyncedAt: Date?
    var latestSleepSession: AppleHealthSleepSession?
    var sleepTrend: [AppleHealthSleepDay]
    var heartRateVariability: AppleHealthMeasurement?
    var restingHeartRate: AppleHealthMeasurement?
    var vo2Max: AppleHealthMeasurement?
    var bloodGlucose: AppleHealthMeasurement?
    var stepsToday: Double?
    var activeEnergyKilocaloriesToday: Double?
    var workoutsThisWeek: [AppleHealthWorkout]

    static let empty = AppleHealthSnapshot(
        lastSyncedAt: nil,
        latestSleepSession: nil,
        sleepTrend: [],
        heartRateVariability: nil,
        restingHeartRate: nil,
        vo2Max: nil,
        bloodGlucose: nil,
        stepsToday: nil,
        activeEnergyKilocaloriesToday: nil,
        workoutsThisWeek: []
    )
}

enum AppleHealthSyncState: Equatable, Sendable {
    case unavailable
    case notConfigured
    case ready
    case syncing
    case failed
}

enum AppleHealthSyncError: Error, Equatable {
    case unavailable
    case authorizationFailed
}

extension Notification.Name {
    static let appleHealthSyncDidChange = Notification.Name("appleHealthSyncDidChange")
}

@MainActor
protocol AppleHealthSyncing: AnyObject {
    var snapshot: AppleHealthSnapshot { get }
    var state: AppleHealthSyncState { get }
    var isConfigured: Bool { get }

    func requestAuthorizationAndSync() async throws
    func sync() async throws
    func syncIfConfigured() async
}

struct AppleHealthSnapshotCache {
    private let defaults: UserDefaults
    private let snapshotKey: String
    private let configuredKey: String

    init(
        defaults: UserDefaults = .standard,
        snapshotKey: String = "appleHealth.snapshot.v1",
        configuredKey: String = "appleHealth.authorizationRequested.v1"
    ) {
        self.defaults = defaults
        self.snapshotKey = snapshotKey
        self.configuredKey = configuredKey
    }

    var isConfigured: Bool {
        get { defaults.bool(forKey: configuredKey) }
        nonmutating set { defaults.set(newValue, forKey: configuredKey) }
    }

    func load() -> AppleHealthSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(AppleHealthSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    func save(_ snapshot: AppleHealthSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }
}

enum AppleHealthSleepAggregator {
    enum SegmentKind: Sendable {
        case inBed
        case awake
        case asleepUnspecified
        case core
        case deep
        case rem

        var isAsleep: Bool {
            switch self {
            case .asleepUnspecified, .core, .deep, .rem: true
            case .inBed, .awake: false
            }
        }
    }

    struct Segment: Sendable {
        let startDate: Date
        let endDate: Date
        let kind: SegmentKind
        let sourceName: String
    }

    static func sessions(from segments: [Segment]) -> [AppleHealthSleepSession] {
        let valid = segments
            .filter { $0.endDate > $0.startDate }
            .sorted { $0.startDate < $1.startDate }
        guard !valid.isEmpty else { return [] }

        var groups: [[Segment]] = []
        var current: [Segment] = []
        var currentEnd = Date.distantPast

        for segment in valid {
            if !current.isEmpty,
               segment.startDate.timeIntervalSince(currentEnd) >= 3 * 60 * 60 {
                groups.append(current)
                current = []
                currentEnd = .distantPast
            }
            current.append(segment)
            currentEnd = max(currentEnd, segment.endDate)
        }
        if !current.isEmpty { groups.append(current) }

        return groups.compactMap(makeSession).sorted { $0.endDate < $1.endDate }
    }

    static func sevenDayTrend(
        sessions: [AppleHealthSleepSession],
        endingAt date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [AppleHealthSleepDay] {
        let today = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return dailyTrend(sessions: sessions, from: start, through: today, calendar: calendar)
    }

    static func allTimeTrend(
        sessions: [AppleHealthSleepSession],
        endingAt date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [AppleHealthSleepDay] {
        guard let earliestSession = sessions.min(by: { $0.endDate < $1.endDate }) else { return [] }
        let start = calendar.startOfDay(for: earliestSession.endDate)
        let today = calendar.startOfDay(for: date)
        return dailyTrend(sessions: sessions, from: start, through: today, calendar: calendar)
    }

    static func trend(
        from history: [AppleHealthSleepDay],
        period: AppleHealthSleepTrendPeriod,
        endingAt date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [AppleHealthSleepDay] {
        let today = calendar.startOfDay(for: date)
        let start: Date
        switch period {
        case .sevenDays:
            start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .thirtyDays:
            start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .sixMonths:
            start = calendar.date(byAdding: .month, value: -6, to: today) ?? today
        case .allTime:
            guard let earliest = history.map(\.date).min() else { return [] }
            start = min(calendar.startOfDay(for: earliest), today)
        }

        var hoursByDay: [Date: Double] = [:]
        for entry in history {
            guard let hours = entry.hours else { continue }
            hoursByDay[calendar.startOfDay(for: entry.date)] = hours
        }
        return daySequence(from: start, through: today, calendar: calendar).map { day in
            AppleHealthSleepDay(date: day, hours: hoursByDay[day])
        }
    }

    private static func dailyTrend(
        sessions: [AppleHealthSleepSession],
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) -> [AppleHealthSleepDay] {
        let days = daySequence(from: start, through: end, calendar: calendar)
        var secondsByDay: [Date: TimeInterval] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.endDate)
            guard day >= start, day <= end else { continue }
            secondsByDay[day, default: 0] += session.asleepSeconds
        }
        return days.map { day in
            let seconds = secondsByDay[day, default: 0]
            return AppleHealthSleepDay(
                date: day,
                hours: seconds > 0 ? seconds / 3_600 : nil
            )
        }
    }

    private static func daySequence(
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) -> [Date] {
        guard start <= end else { return [] }
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        while day <= lastDay {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return days
    }

    private static func makeSession(_ segments: [Segment]) -> AppleHealthSleepSession? {
        guard let startDate = segments.map(\.startDate).min(),
              let endDate = segments.map(\.endDate).max() else {
            return nil
        }

        let asleep = unionDuration(segments.filter { $0.kind.isAsleep })
        guard asleep >= 20 * 60 else { return nil }

        return AppleHealthSleepSession(
            startDate: startDate,
            endDate: endDate,
            asleepSeconds: asleep,
            inBedSeconds: unionDuration(segments),
            awakeSeconds: unionDuration(segments.filter { $0.kind == .awake }),
            coreSeconds: unionDuration(segments.filter { $0.kind == .core }),
            deepSeconds: unionDuration(segments.filter { $0.kind == .deep }),
            remSeconds: unionDuration(segments.filter { $0.kind == .rem }),
            sourceNames: Array(Set(segments.map(\.sourceName))).sorted()
        )
    }

    private static func unionDuration(_ segments: [Segment]) -> TimeInterval {
        let intervals = segments
            .map { ($0.startDate, $0.endDate) }
            .sorted { $0.0 < $1.0 }
        guard var current = intervals.first else { return 0 }
        var total: TimeInterval = 0

        for interval in intervals.dropFirst() {
            if interval.0 <= current.1 {
                current.1 = max(current.1, interval.1)
            } else {
                total += current.1.timeIntervalSince(current.0)
                current = interval
            }
        }
        return total + current.1.timeIntervalSince(current.0)
    }
}

@MainActor
final class AppleHealthSyncService: AppleHealthSyncing {
    private let healthStore: HKHealthStore?
    private var cache: AppleHealthSnapshotCache
    private let calendar: Calendar
    private var observerQueries: [HKObserverQuery] = []
    private var isRunningSync = false

    private(set) var snapshot: AppleHealthSnapshot
    private(set) var state: AppleHealthSyncState

    var isConfigured: Bool { cache.isConfigured }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .autoupdatingCurrent,
        isEnabled: Bool = true
    ) {
        cache = AppleHealthSnapshotCache(defaults: defaults)
        snapshot = cache.load()
        self.calendar = calendar

        guard isEnabled, HKHealthStore.isHealthDataAvailable() else {
            healthStore = nil
            state = .unavailable
            return
        }

        healthStore = HKHealthStore()
        state = cache.isConfigured ? .ready : .notConfigured
        if cache.isConfigured {
            startObservingUpdates()
        }
    }

    func requestAuthorizationAndSync() async throws {
        guard let healthStore else { throw AppleHealthSyncError.unavailable }
        setState(.syncing)

        do {
            let didComplete = try await requestAuthorization(
                healthStore: healthStore,
                readTypes: readTypes
            )
            guard didComplete else { throw AppleHealthSyncError.authorizationFailed }
            cache.isConfigured = true
            try await sync()
            startObservingUpdates()
        } catch {
            setState(.failed)
            throw error
        }
    }

    func syncIfConfigured() async {
        guard isConfigured else { return }
        try? await sync()
    }

    func sync() async throws {
        guard let healthStore else { throw AppleHealthSyncError.unavailable }
        guard !isRunningSync else { return }

        isRunningSync = true
        setState(.syncing)
        defer { isRunningSync = false }

        do {
            let now = Date()
            let sleepSessions = try await fetchSleepSessions(from: healthStore, endingAt: now)
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
                ?? calendar.startOfDay(for: now)
            let todayStart = calendar.startOfDay(for: now)

            let hrv = try await fetchLatestMeasurement(
                from: healthStore,
                identifier: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                since: calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
            )
            let restingHeartRate = try await fetchLatestMeasurement(
                from: healthStore,
                identifier: .restingHeartRate,
                unit: .count().unitDivided(by: .minute()),
                since: calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
            )
            let vo2Max = try await fetchLatestMeasurement(
                from: healthStore,
                identifier: .vo2Max,
                unit: HKUnit(from: "ml/kg*min"),
                since: calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast
            )
            let bloodGlucose = try await fetchLatestMeasurement(
                from: healthStore,
                identifier: .bloodGlucose,
                unit: HKUnit(from: "mg/dL"),
                since: calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast
            )
            let steps = try await fetchCumulativeQuantity(
                from: healthStore,
                identifier: .stepCount,
                unit: .count(),
                start: todayStart,
                end: now
            )
            let activeEnergy = try await fetchCumulativeQuantity(
                from: healthStore,
                identifier: .activeEnergyBurned,
                unit: .kilocalorie(),
                start: todayStart,
                end: now
            )
            let workouts = try await fetchWorkouts(
                from: healthStore,
                start: weekStart,
                end: now
            )

            let updated = AppleHealthSnapshot(
                lastSyncedAt: now,
                latestSleepSession: sleepSessions.last,
                sleepTrend: AppleHealthSleepAggregator.allTimeTrend(
                    sessions: sleepSessions,
                    endingAt: now,
                    calendar: calendar
                ),
                heartRateVariability: hrv,
                restingHeartRate: restingHeartRate,
                vo2Max: vo2Max,
                bloodGlucose: bloodGlucose,
                stepsToday: steps,
                activeEnergyKilocaloriesToday: activeEnergy,
                workoutsThisWeek: workouts
            )
            snapshot = updated
            cache.save(updated)
            setState(.ready)
        } catch {
            setState(.failed)
            throw error
        }
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .vo2Max),
            HKObjectType.quantityType(forIdentifier: .bloodGlucose),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        ].compactMap { $0 }.forEach { types.insert($0) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    private func setState(_ newState: AppleHealthSyncState) {
        state = newState
        NotificationCenter.default.post(name: .appleHealthSyncDidChange, object: self)
    }

    private func requestAuthorization(
        healthStore: HKHealthStore,
        readTypes: Set<HKObjectType>
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    private func fetchSleepSessions(
        from healthStore: HKHealthStore,
        endingAt endDate: Date
    ) async throws -> [AppleHealthSleepSession] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(
            withStart: .distantPast,
            end: endDate,
            options: [.strictEndDate]
        )
        let samples = try await fetchSamples(
            from: healthStore,
            type: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        )
        let segments = samples.compactMap { sample -> AppleHealthSleepAggregator.Segment? in
            guard let sample = sample as? HKCategorySample,
                  let kind = sleepKind(for: sample.value) else {
                return nil
            }
            return AppleHealthSleepAggregator.Segment(
                startDate: sample.startDate,
                endDate: sample.endDate,
                kind: kind,
                sourceName: sample.sourceRevision.source.name
            )
        }
        return AppleHealthSleepAggregator.sessions(from: segments)
    }

    private func sleepKind(for rawValue: Int) -> AppleHealthSleepAggregator.SegmentKind? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: rawValue) else { return nil }
        switch value {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepUnspecified: return .asleepUnspecified
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        case .asleepREM: return .rem
        @unknown default: return nil
        }
    }

    private func fetchLatestMeasurement(
        from healthStore: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        since startDate: Date
    ) async throws -> AppleHealthMeasurement? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: [.strictEndDate]
        )
        let samples = try await fetchSamples(
            from: healthStore,
            type: type,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        )
        guard let sample = samples.first as? HKQuantitySample else { return nil }
        return AppleHealthMeasurement(
            value: sample.quantity.doubleValue(for: unit),
            date: sample.endDate,
            sourceName: sample.sourceRevision.source.name
        )
    }

    private func fetchCumulativeQuantity(
        from healthStore: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate, .strictEndDate]
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum]
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
                }
            }
            healthStore.execute(query)
        }
    }

    private func fetchWorkouts(
        from healthStore: HKHealthStore,
        start: Date,
        end: Date
    ) async throws -> [AppleHealthWorkout] {
        let type = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictEndDate]
        )
        let samples = try await fetchSamples(
            from: healthStore,
            type: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        )
        let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        return samples.compactMap { sample in
            guard let workout = sample as? HKWorkout else { return nil }
            let energy = energyType
                .flatMap { workout.statistics(for: $0) }
                .flatMap { $0.sumQuantity() }
                .map { $0.doubleValue(for: .kilocalorie()) }
            return AppleHealthWorkout(
                id: workout.uuid,
                kind: workoutKind(for: workout.workoutActivityType),
                startDate: workout.startDate,
                endDate: workout.endDate,
                durationSeconds: workout.duration,
                activeEnergyKilocalories: energy,
                sourceName: workout.sourceRevision.source.name
            )
        }
    }

    private func workoutKind(for activity: HKWorkoutActivityType) -> AppleHealthWorkoutKind {
        switch activity {
        case .walking: .walking
        case .running: .running
        case .cycling: .cycling
        case .swimming: .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining: .strength
        case .yoga, .mindAndBody, .flexibility: .yoga
        case .highIntensityIntervalTraining: .highIntensityIntervalTraining
        default: .other
        }
    }

    private func fetchSamples(
        from healthStore: HKHealthStore,
        type: HKSampleType,
        predicate: NSPredicate?,
        limit: Int,
        sortDescriptors: [NSSortDescriptor]?
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: sortDescriptors
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func startObservingUpdates() {
        guard let healthStore, observerQueries.isEmpty else { return }
        let sampleTypes = readTypes.compactMap { $0 as? HKSampleType }
        observerQueries = sampleTypes.map { type in
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                completion()
                Task { @MainActor [weak self] in
                    await self?.syncIfConfigured()
                }
            }
            healthStore.execute(query)
            return query
        }
    }
}
