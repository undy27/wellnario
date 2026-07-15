@preconcurrency import HealthKit
import UIKit

struct AppleHealthMeasurement: Codable, Equatable, Sendable {
    let value: Double
    let date: Date
    let sourceName: String
}

enum AppleHealthSleepStage: String, Codable, Equatable, Sendable {
    case awake
    case rem
    case core
    case deep
    case asleepUnspecified
}

struct AppleHealthSleepStageInterval: Codable, Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let stage: AppleHealthSleepStage
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
    let stageIntervals: [AppleHealthSleepStageInterval]

    init(
        startDate: Date,
        endDate: Date,
        asleepSeconds: TimeInterval,
        inBedSeconds: TimeInterval,
        awakeSeconds: TimeInterval,
        coreSeconds: TimeInterval,
        deepSeconds: TimeInterval,
        remSeconds: TimeInterval,
        sourceNames: [String],
        stageIntervals: [AppleHealthSleepStageInterval] = []
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.asleepSeconds = asleepSeconds
        self.inBedSeconds = inBedSeconds
        self.awakeSeconds = awakeSeconds
        self.coreSeconds = coreSeconds
        self.deepSeconds = deepSeconds
        self.remSeconds = remSeconds
        self.sourceNames = sourceNames
        self.stageIntervals = stageIntervals
    }

    private enum CodingKeys: String, CodingKey {
        case startDate
        case endDate
        case asleepSeconds
        case inBedSeconds
        case awakeSeconds
        case coreSeconds
        case deepSeconds
        case remSeconds
        case sourceNames
        case stageIntervals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        asleepSeconds = try container.decode(TimeInterval.self, forKey: .asleepSeconds)
        inBedSeconds = try container.decode(TimeInterval.self, forKey: .inBedSeconds)
        awakeSeconds = try container.decode(TimeInterval.self, forKey: .awakeSeconds)
        coreSeconds = try container.decode(TimeInterval.self, forKey: .coreSeconds)
        deepSeconds = try container.decode(TimeInterval.self, forKey: .deepSeconds)
        remSeconds = try container.decode(TimeInterval.self, forKey: .remSeconds)
        sourceNames = try container.decode([String].self, forKey: .sourceNames)
        stageIntervals = try container.decodeIfPresent(
            [AppleHealthSleepStageInterval].self,
            forKey: .stageIntervals
        ) ?? []
    }
}

struct AppleHealthSleepDay: Codable, Equatable, Sendable {
    let date: Date
    let hours: Double?
    let qualityScore: Double?
    let remHours: Double?
    let deepHours: Double?
    let lightHours: Double?

    init(
        date: Date,
        hours: Double?,
        qualityScore: Double? = nil,
        remHours: Double? = nil,
        deepHours: Double? = nil,
        lightHours: Double? = nil
    ) {
        self.date = date
        self.hours = hours
        self.qualityScore = qualityScore
        self.remHours = remHours
        self.deepHours = deepHours
        self.lightHours = lightHours
    }
}

enum AppleHealthSleepTrendPeriod: Int, CaseIterable, Sendable {
    case sevenDays
    case thirtyDays
    case sixMonths
    case allTime
}

enum AppleHealthSleepTrendGranularity: Equatable, Sendable {
    case day
    case week
    case month
    case year
}

struct AppleHealthSleepTrendSeries: Equatable, Sendable {
    let entries: [AppleHealthSleepDay]
    let dailyEntries: [AppleHealthSleepDay]
    let granularity: AppleHealthSleepTrendGranularity

    init(
        entries: [AppleHealthSleepDay],
        dailyEntries: [AppleHealthSleepDay]? = nil,
        granularity: AppleHealthSleepTrendGranularity
    ) {
        self.entries = entries
        self.dailyEntries = dailyEntries ?? entries
        self.granularity = granularity
    }
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

enum AppleHealthDataKind: String, Codable, CaseIterable, Equatable, Sendable {
    case sleep
    case heart
    case activity
    case workouts
}

struct AppleHealthDataSource: Codable, Equatable, Identifiable, Sendable {
    let identifier: String
    let name: String
    let dataKinds: [AppleHealthDataKind]

    var id: String { identifier }
}

struct AppleHealthSourceSelection: Codable, Equatable, Hashable, Sendable {
    let sourceIdentifier: String
    let dataKind: AppleHealthDataKind
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
    var availableSources: [AppleHealthDataSource] { get }
    var disabledSourceSelections: Set<AppleHealthSourceSelection> { get }

    func requestAuthorizationAndSync() async throws
    func sync() async throws
    func syncIfConfigured() async
    func setSourceEnabled(
        _ identifier: String,
        for dataKind: AppleHealthDataKind,
        isEnabled: Bool
    )
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

struct AppleHealthSourcePreferences {
    private let defaults: UserDefaults
    private let sourcesKey: String
    private let disabledSelectionsKey: String
    private let legacyDisabledSourcesKey: String

    init(
        defaults: UserDefaults = .standard,
        sourcesKey: String = "appleHealth.sources.v1",
        disabledSelectionsKey: String = "appleHealth.disabledSourceSelections.v2",
        legacyDisabledSourcesKey: String = "appleHealth.disabledSources.v1"
    ) {
        self.defaults = defaults
        self.sourcesKey = sourcesKey
        self.disabledSelectionsKey = disabledSelectionsKey
        self.legacyDisabledSourcesKey = legacyDisabledSourcesKey
    }

    func loadSources() -> [AppleHealthDataSource] {
        guard let data = defaults.data(forKey: sourcesKey),
              let sources = try? JSONDecoder().decode([AppleHealthDataSource].self, from: data) else {
            return []
        }
        return sources
    }

    func saveSources(_ sources: [AppleHealthDataSource]) {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        defaults.set(data, forKey: sourcesKey)
    }

    func loadDisabledSourceSelections() -> Set<AppleHealthSourceSelection> {
        if let data = defaults.data(forKey: disabledSelectionsKey),
           let selections = try? JSONDecoder().decode(Set<AppleHealthSourceSelection>.self, from: data) {
            return selections
        }

        let legacyIdentifiers = Set(defaults.stringArray(forKey: legacyDisabledSourcesKey) ?? [])
        return Set(legacyIdentifiers.flatMap { identifier in
            AppleHealthDataKind.allCases.map {
                AppleHealthSourceSelection(sourceIdentifier: identifier, dataKind: $0)
            }
        })
    }

    func saveDisabledSourceSelections(_ selections: Set<AppleHealthSourceSelection>) {
        guard let data = try? JSONEncoder().encode(selections) else { return }
        defaults.set(data, forKey: disabledSelectionsKey)
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

        var sleepStage: AppleHealthSleepStage? {
            switch self {
            case .inBed: nil
            case .awake: .awake
            case .asleepUnspecified: .asleepUnspecified
            case .core: .core
            case .deep: .deep
            case .rem: .rem
            }
        }

        var timelinePriority: Int {
            switch self {
            case .awake: 3
            case .core, .deep, .rem: 2
            case .asleepUnspecified: 1
            case .inBed: 0
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
        trendSeries(
            from: history,
            period: period,
            endingAt: date,
            calendar: calendar
        ).entries
    }

    static func trendSeries(
        from history: [AppleHealthSleepDay],
        period: AppleHealthSleepTrendPeriod,
        endingAt date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> AppleHealthSleepTrendSeries {
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
            guard let earliest = history.map(\.date).min() else {
                return AppleHealthSleepTrendSeries(entries: [], dailyEntries: [], granularity: .day)
            }
            start = min(calendar.startOfDay(for: earliest), today)
        }

        var entriesByDay: [Date: AppleHealthSleepDay] = [:]
        for entry in history {
            entriesByDay[calendar.startOfDay(for: entry.date)] = entry
        }
        let dailyEntries = daySequence(from: start, through: today, calendar: calendar).map { day in
            guard let entry = entriesByDay[day] else {
                return AppleHealthSleepDay(date: day, hours: nil)
            }
            return AppleHealthSleepDay(
                date: day,
                hours: entry.hours,
                qualityScore: entry.qualityScore,
                remHours: entry.remHours,
                deepHours: entry.deepHours,
                lightHours: entry.lightHours
            )
        }

        switch period {
        case .sevenDays, .thirtyDays:
            return AppleHealthSleepTrendSeries(entries: dailyEntries, granularity: .day)
        case .sixMonths:
            guard hasDataSpan(ofMonths: 1, in: dailyEntries, calendar: calendar) else {
                return AppleHealthSleepTrendSeries(entries: dailyEntries, granularity: .day)
            }
            return AppleHealthSleepTrendSeries(
                entries: aggregate(dailyEntries, by: .weekOfYear, calendar: calendar),
                dailyEntries: dailyEntries,
                granularity: .week
            )
        case .allTime:
            if hasDataSpan(ofMonths: 24, in: dailyEntries, calendar: calendar) {
                return AppleHealthSleepTrendSeries(
                    entries: aggregate(dailyEntries, by: .year, calendar: calendar),
                    dailyEntries: dailyEntries,
                    granularity: .year
                )
            }
            guard hasDataSpan(ofMonths: 3, in: dailyEntries, calendar: calendar) else {
                return AppleHealthSleepTrendSeries(entries: dailyEntries, granularity: .day)
            }
            return AppleHealthSleepTrendSeries(
                entries: aggregate(dailyEntries, by: .month, calendar: calendar),
                dailyEntries: dailyEntries,
                granularity: .month
            )
        }
    }

    private static func hasDataSpan(
        ofMonths months: Int,
        in entries: [AppleHealthSleepDay],
        calendar: Calendar
    ) -> Bool {
        let dates = entries.filter(hasValues).map(\.date)
        guard let first = dates.min(), let last = dates.max(),
              let threshold = calendar.date(byAdding: .month, value: months, to: first) else {
            return false
        }
        return last >= threshold
    }

    private static func aggregate(
        _ entries: [AppleHealthSleepDay],
        by component: Calendar.Component,
        calendar: Calendar
    ) -> [AppleHealthSleepDay] {
        var entriesByBucket: [Date: [AppleHealthSleepDay]] = [:]
        for entry in entries {
            guard let bucket = calendar.dateInterval(of: component, for: entry.date)?.start else { continue }
            entriesByBucket[bucket, default: []].append(entry)
        }

        return entriesByBucket.keys.sorted().map { bucket in
            let bucketEntries = entriesByBucket[bucket, default: []]
            return AppleHealthSleepDay(
                date: bucket,
                hours: average(bucketEntries.map(\.hours)),
                qualityScore: average(bucketEntries.map(\.qualityScore)),
                remHours: average(bucketEntries.map(\.remHours)),
                deepHours: average(bucketEntries.map(\.deepHours)),
                lightHours: average(bucketEntries.map(\.lightHours))
            )
        }
    }

    private static func average(_ values: [Double?]) -> Double? {
        let validValues = values.compactMap { $0 }
        guard !validValues.isEmpty else { return nil }
        return validValues.reduce(0, +) / Double(validValues.count)
    }

    private static func hasValues(_ entry: AppleHealthSleepDay) -> Bool {
        entry.hours != nil
            || entry.qualityScore != nil
            || entry.remHours != nil
            || entry.deepHours != nil
            || entry.lightHours != nil
    }

    private static func dailyTrend(
        sessions: [AppleHealthSleepSession],
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) -> [AppleHealthSleepDay] {
        let days = daySequence(from: start, through: end, calendar: calendar)
        var sessionsByDay: [Date: [AppleHealthSleepSession]] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.endDate)
            guard day >= start, day <= end else { continue }
            sessionsByDay[day, default: []].append(session)
        }
        return days.map { day in
            let dailySessions = sessionsByDay[day, default: []]
            let asleepSeconds = dailySessions.reduce(0) { $0 + $1.asleepSeconds }
            let remSeconds = dailySessions.reduce(0) { $0 + $1.remSeconds }
            let deepSeconds = dailySessions.reduce(0) { $0 + $1.deepSeconds }
            let lightSeconds = dailySessions.reduce(0) { $0 + $1.coreSeconds }
            return AppleHealthSleepDay(
                date: day,
                hours: asleepSeconds > 0 ? asleepSeconds / 3_600 : nil,
                // Apple Health's Sleep Score isn't exposed through the public HealthKit API.
                // Keep this nil until an authorized source supplies a real score.
                qualityScore: nil,
                remHours: remSeconds > 0 ? remSeconds / 3_600 : nil,
                deepHours: deepSeconds > 0 ? deepSeconds / 3_600 : nil,
                lightHours: lightSeconds > 0 ? lightSeconds / 3_600 : nil
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
            sourceNames: Array(Set(segments.map(\.sourceName))).sorted(),
            stageIntervals: stageTimeline(from: segments)
        )
    }

    private static func stageTimeline(from segments: [Segment]) -> [AppleHealthSleepStageInterval] {
        let candidates = segments.filter {
            $0.kind.sleepStage != nil && $0.endDate > $0.startDate
        }
        let boundaries = Array(Set(candidates.flatMap { [$0.startDate, $0.endDate] })).sorted()
        guard boundaries.count > 1 else { return [] }

        var result: [AppleHealthSleepStageInterval] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) where end > start {
            let active = candidates.filter { $0.startDate < end && $0.endDate > start }
            guard let selected = active.sorted(by: stageSegmentSort).first,
                  let stage = selected.kind.sleepStage else {
                continue
            }

            if let previous = result.last,
               previous.stage == stage,
               abs(previous.endDate.timeIntervalSince(start)) < 0.5 {
                result[result.count - 1] = AppleHealthSleepStageInterval(
                    startDate: previous.startDate,
                    endDate: end,
                    stage: stage
                )
            } else {
                result.append(AppleHealthSleepStageInterval(
                    startDate: start,
                    endDate: end,
                    stage: stage
                ))
            }
        }
        return result
    }

    private static func stageSegmentSort(_ lhs: Segment, _ rhs: Segment) -> Bool {
        if lhs.kind.timelinePriority != rhs.kind.timelinePriority {
            return lhs.kind.timelinePriority > rhs.kind.timelinePriority
        }
        let lhsDuration = lhs.endDate.timeIntervalSince(lhs.startDate)
        let rhsDuration = rhs.endDate.timeIntervalSince(rhs.startDate)
        if lhsDuration != rhsDuration {
            return lhsDuration < rhsDuration
        }
        return lhs.sourceName.localizedCaseInsensitiveCompare(rhs.sourceName) == .orderedAscending
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
    private struct SourceQueryFilter {
        let predicate: NSPredicate?
        let excludesAll: Bool
    }

    private struct SourceAccumulator {
        var name: String
        var dataKinds: Set<AppleHealthDataKind>
    }

    private let healthStore: HKHealthStore?
    private var cache: AppleHealthSnapshotCache
    private let sourcePreferences: AppleHealthSourcePreferences
    private let calendar: Calendar
    private var sourcesByTypeIdentifier: [String: Set<HKSource>] = [:]
    private var isRunningSync = false

    private(set) var snapshot: AppleHealthSnapshot
    private(set) var state: AppleHealthSyncState
    private(set) var availableSources: [AppleHealthDataSource]
    private(set) var disabledSourceSelections: Set<AppleHealthSourceSelection>

    var isConfigured: Bool { cache.isConfigured }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .autoupdatingCurrent,
        isEnabled: Bool = true
    ) {
        cache = AppleHealthSnapshotCache(defaults: defaults)
        sourcePreferences = AppleHealthSourcePreferences(defaults: defaults)
        snapshot = cache.load()
        availableSources = sourcePreferences.loadSources()
        disabledSourceSelections = sourcePreferences.loadDisabledSourceSelections()
        self.calendar = calendar

        guard isEnabled, HKHealthStore.isHealthDataAvailable() else {
            healthStore = nil
            state = .unavailable
            return
        }

        healthStore = HKHealthStore()
        state = cache.isConfigured ? .ready : .notConfigured
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
        } catch {
            setState(.failed)
            throw error
        }
    }

    func syncIfConfigured() async {
        guard isConfigured else { return }
        try? await sync()
    }

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
        sourcePreferences.saveDisabledSourceSelections(disabledSourceSelections)
    }

    func sync() async throws {
        guard let healthStore else { throw AppleHealthSyncError.unavailable }
        guard !isRunningSync else { return }

        isRunningSync = true
        setState(.syncing)
        defer { isRunningSync = false }

        do {
            let now = Date()
            try await updateAvailableSources(from: healthStore)
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
        notifyChange()
    }

    private func notifyChange() {
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

    private func updateAvailableSources(from healthStore: HKHealthStore) async throws {
        let sampleTypes = readTypes
            .compactMap { $0 as? HKSampleType }
            .sorted { $0.identifier < $1.identifier }
        var catalog: [String: Set<HKSource>] = [:]
        var accumulators: [String: SourceAccumulator] = [:]

        for type in sampleTypes {
            let sources = try await fetchSources(from: healthStore, type: type)
            catalog[type.identifier] = sources
            guard let dataKind = dataKind(for: type) else { continue }

            for source in sources.sorted(by: sourceSort) {
                let identifier = source.bundleIdentifier
                var accumulator = accumulators[identifier] ?? SourceAccumulator(
                    name: source.name,
                    dataKinds: []
                )
                accumulator.dataKinds.insert(dataKind)
                accumulators[identifier] = accumulator
            }
        }

        sourcesByTypeIdentifier = catalog
        availableSources = accumulators.map { identifier, accumulator in
            AppleHealthDataSource(
                identifier: identifier,
                name: accumulator.name,
                dataKinds: AppleHealthDataKind.allCases.filter(accumulator.dataKinds.contains)
            )
        }.sorted { lhs, rhs in
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return comparison == .orderedSame
                ? lhs.identifier < rhs.identifier
                : comparison == .orderedAscending
        }
        sourcePreferences.saveSources(availableSources)
    }

    private func fetchSources(
        from healthStore: HKHealthStore,
        type: HKSampleType
    ) async throws -> Set<HKSource> {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSourceQuery(sampleType: type, samplePredicate: nil) { _, sources, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: sources ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func dataKind(for type: HKSampleType) -> AppleHealthDataKind? {
        switch type.identifier {
        case HKCategoryTypeIdentifier.sleepAnalysis.rawValue:
            .sleep
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
             HKQuantityTypeIdentifier.restingHeartRate.rawValue,
             HKQuantityTypeIdentifier.vo2Max.rawValue,
             HKQuantityTypeIdentifier.bloodGlucose.rawValue:
            .heart
        case HKQuantityTypeIdentifier.stepCount.rawValue,
             HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            .activity
        case HKObjectType.workoutType().identifier:
            .workouts
        default:
            nil
        }
    }

    private func sourceSort(_ lhs: HKSource, _ rhs: HKSource) -> Bool {
        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        return comparison == .orderedSame
            ? lhs.bundleIdentifier < rhs.bundleIdentifier
            : comparison == .orderedAscending
    }

    private func sourceFilter(for type: HKSampleType) -> SourceQueryFilter {
        guard let dataKind = dataKind(for: type),
              !disabledSourceSelections.isEmpty,
              let knownSources = sourcesByTypeIdentifier[type.identifier],
              !knownSources.isEmpty else {
            return SourceQueryFilter(predicate: nil, excludesAll: false)
        }
        let disabledSources = knownSources.filter {
            disabledSourceSelections.contains(AppleHealthSourceSelection(
                sourceIdentifier: $0.bundleIdentifier,
                dataKind: dataKind
            ))
        }
        guard !disabledSources.isEmpty else {
            return SourceQueryFilter(predicate: nil, excludesAll: false)
        }

        let allowedSources = knownSources.subtracting(disabledSources)
        guard !allowedSources.isEmpty else {
            return SourceQueryFilter(predicate: nil, excludesAll: true)
        }
        return SourceQueryFilter(
            predicate: HKQuery.predicateForObjects(from: allowedSources),
            excludesAll: false
        )
    }

    private func applyingSourceFilter(
        _ sourceFilter: SourceQueryFilter,
        to predicate: NSPredicate
    ) -> NSPredicate {
        guard let sourcePredicate = sourceFilter.predicate else { return predicate }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, sourcePredicate])
    }

    private func fetchSleepSessions(
        from healthStore: HKHealthStore,
        endingAt endDate: Date
    ) async throws -> [AppleHealthSleepSession] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let sourceFilter = sourceFilter(for: type)
        guard !sourceFilter.excludesAll else { return [] }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: .distantPast,
            end: endDate,
            options: [.strictEndDate]
        )
        let predicate = applyingSourceFilter(sourceFilter, to: datePredicate)
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
        let sourceFilter = sourceFilter(for: type)
        guard !sourceFilter.excludesAll else { return nil }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: [.strictEndDate]
        )
        let predicate = applyingSourceFilter(sourceFilter, to: datePredicate)
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
        let sourceFilter = sourceFilter(for: type)
        guard !sourceFilter.excludesAll else { return nil }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate, .strictEndDate]
        )
        let predicate = applyingSourceFilter(sourceFilter, to: datePredicate)
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
        let sourceFilter = sourceFilter(for: type)
        guard !sourceFilter.excludesAll else { return [] }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictEndDate]
        )
        let predicate = applyingSourceFilter(sourceFilter, to: datePredicate)
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

}
