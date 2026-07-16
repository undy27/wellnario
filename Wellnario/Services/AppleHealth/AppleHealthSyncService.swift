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
    /// Start of the main sleep session ending on this day. It is retained so
    /// Wellnario can assess bedtime regularity without querying HealthKit again.
    let sleepStartDate: Date?
    /// Awake time explicitly reported inside the sleep sessions for this day.
    let awakeHours: Double?
    /// Total scored sleep period (asleep plus explicitly awake time).
    let sleepPeriodHours: Double?

    init(
        date: Date,
        hours: Double?,
        qualityScore: Double? = nil,
        remHours: Double? = nil,
        deepHours: Double? = nil,
        lightHours: Double? = nil,
        sleepStartDate: Date? = nil,
        awakeHours: Double? = nil,
        sleepPeriodHours: Double? = nil
    ) {
        self.date = date
        self.hours = hours
        self.qualityScore = qualityScore
        self.remHours = remHours
        self.deepHours = deepHours
        self.lightHours = lightHours
        self.sleepStartDate = sleepStartDate
        self.awakeHours = awakeHours
        self.sleepPeriodHours = sleepPeriodHours
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
    var dateOfBirthComponents: DateComponents? = nil
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
    static let sleepManualOverridesDidChange = Notification.Name(
        "wellnarioSleepManualOverridesDidChange"
    )
    static let sleepQualityPreferencesDidChange = Notification.Name(
        "wellnarioSleepQualityPreferencesDidChange"
    )
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

struct SleepDurationRecommendation: Equatable, Sendable {
    enum AgeGroup: String, CaseIterable, Sendable {
        case newborn
        case infant
        case toddler
        case preschool
        case schoolAge
        case teenager
        case youngAdult
        case adult
        case olderAdult
    }

    let ageGroup: AgeGroup
    let minimumHours: Double
    let maximumHours: Double

    var targetHours: Double { (minimumHours + maximumHours) / 2 }

    static let all: [SleepDurationRecommendation] = [
        .init(ageGroup: .newborn, minimumHours: 14, maximumHours: 17),
        .init(ageGroup: .infant, minimumHours: 12, maximumHours: 15),
        .init(ageGroup: .toddler, minimumHours: 11, maximumHours: 14),
        .init(ageGroup: .preschool, minimumHours: 10, maximumHours: 13),
        .init(ageGroup: .schoolAge, minimumHours: 9, maximumHours: 11),
        .init(ageGroup: .teenager, minimumHours: 8, maximumHours: 10),
        .init(ageGroup: .youngAdult, minimumHours: 7, maximumHours: 9),
        .init(ageGroup: .adult, minimumHours: 7, maximumHours: 9),
        .init(ageGroup: .olderAdult, minimumHours: 7, maximumHours: 8)
    ]

    static let adultDefault = all.first { $0.ageGroup == .adult }!

    static func recommendation(ageInMonths: Int?) -> SleepDurationRecommendation {
        guard let ageInMonths, ageInMonths >= 0 else { return adultDefault }
        let ageGroup: AgeGroup
        switch ageInMonths {
        case 0..<4: ageGroup = .newborn
        case 4..<12: ageGroup = .infant
        case 12..<36: ageGroup = .toddler
        case 36..<72: ageGroup = .preschool
        case 72..<168: ageGroup = .schoolAge
        case 168..<216: ageGroup = .teenager
        case 216..<312: ageGroup = .youngAdult
        case 312..<780: ageGroup = .adult
        default: ageGroup = .olderAdult
        }
        return all.first { $0.ageGroup == ageGroup } ?? adultDefault
    }

    static func ageInMonths(
        from components: DateComponents?,
        at date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int? {
        guard let components,
              let birthDate = calendar.date(from: components),
              birthDate <= date else { return nil }
        return calendar.dateComponents([.month], from: birthDate, to: date).month
    }
}

struct SleepQualityWeights: Equatable, Sendable {
    let duration: Int
    let regularity: Int
    let interruptions: Int

    static let `default` = SleepQualityWeights(
        duration: 70,
        regularity: 10,
        interruptions: 20
    )

    var isValid: Bool {
        duration >= 0
            && regularity >= 0
            && interruptions >= 0
            && duration + regularity + interruptions == 100
    }
}

struct SleepQualityConfiguration: Equatable, Sendable {
    let targetHours: Double
    let weights: SleepQualityWeights
}

struct SleepQualityPreferences {
    static let targetRange = (1.0 / 60.0)...24.0

    private let defaults: UserDefaults
    private let durationWeightKey = "wellnario.sleep.quality.durationWeight.v1"
    private let regularityWeightKey = "wellnario.sleep.quality.regularityWeight.v1"
    private let interruptionWeightKey = "wellnario.sleep.quality.interruptionWeight.v1"
    private let customTargetKey = "wellnario.sleep.quality.customTargetHours.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var weights: SleepQualityWeights {
        let requiredKeys = [durationWeightKey, regularityWeightKey, interruptionWeightKey]
        guard requiredKeys.allSatisfy({ defaults.object(forKey: $0) != nil }) else {
            return .default
        }
        let stored = SleepQualityWeights(
            duration: defaults.integer(forKey: durationWeightKey),
            regularity: defaults.integer(forKey: regularityWeightKey),
            interruptions: defaults.integer(forKey: interruptionWeightKey)
        )
        return stored.isValid ? stored : .default
    }

    var customTargetHours: Double? {
        guard let value = defaults.object(forKey: customTargetKey) as? NSNumber else { return nil }
        let hours = value.doubleValue
        return Self.targetRange.contains(hours) ? hours : nil
    }

    func recommendation(
        dateOfBirthComponents: DateComponents?,
        at date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> SleepDurationRecommendation {
        SleepDurationRecommendation.recommendation(
            ageInMonths: SleepDurationRecommendation.ageInMonths(
                from: dateOfBirthComponents,
                at: date,
                calendar: calendar
            )
        )
    }

    func configuration(
        dateOfBirthComponents: DateComponents? = nil,
        at date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> SleepQualityConfiguration {
        let recommended = recommendation(
            dateOfBirthComponents: dateOfBirthComponents,
            at: date,
            calendar: calendar
        )
        return SleepQualityConfiguration(
            targetHours: customTargetHours ?? recommended.targetHours,
            weights: weights
        )
    }

    @discardableResult
    func setWeights(_ weights: SleepQualityWeights) -> Bool {
        guard weights.isValid else { return false }
        defaults.set(weights.duration, forKey: durationWeightKey)
        defaults.set(weights.regularity, forKey: regularityWeightKey)
        defaults.set(weights.interruptions, forKey: interruptionWeightKey)
        notifyChange()
        return true
    }

    @discardableResult
    func setCustomTargetHours(_ hours: Double) -> Bool {
        guard hours.isFinite, Self.targetRange.contains(hours) else { return false }
        defaults.set(hours, forKey: customTargetKey)
        notifyChange()
        return true
    }

    func useRecommendedTarget() {
        guard defaults.object(forKey: customTargetKey) != nil else { return }
        defaults.removeObject(forKey: customTargetKey)
        notifyChange()
    }

    func reset(notify: Bool = true) {
        [
            durationWeightKey,
            regularityWeightKey,
            interruptionWeightKey,
            customTargetKey
        ].forEach(defaults.removeObject(forKey:))
        if notify { notifyChange() }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .sleepQualityPreferencesDidChange, object: nil)
    }
}

struct SleepQualityBreakdown: Equatable, Sendable {
    let durationScore: Double
    let regularityScore: Double
    let interruptionScore: Double
    let compliantDays: Int
    let awakePercentage: Double
    let totalScore: Double
}

enum SleepQualityCalculator {
    static let regularityWindowDays = 7
    static let bedtimeToleranceMinutes = 60.0
    static let zeroInterruptionScoreAtPercentage = 15.0

    static func applying(
        to history: [AppleHealthSleepDay],
        configuration: SleepQualityConfiguration,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [AppleHealthSleepDay] {
        let sorted = history.sorted { $0.date < $1.date }
        let startsByDay = sleepStartsByDay(in: sorted, calendar: calendar)
        return sorted.map { entry in
            guard let breakdown = breakdown(
                for: entry,
                configuration: configuration,
                calendar: calendar,
                startsByDay: startsByDay
            ) else { return entry }
            return AppleHealthSleepDay(
                date: entry.date,
                hours: entry.hours,
                qualityScore: breakdown.totalScore,
                remHours: entry.remHours,
                deepHours: entry.deepHours,
                lightHours: entry.lightHours,
                sleepStartDate: entry.sleepStartDate,
                awakeHours: entry.awakeHours,
                sleepPeriodHours: entry.sleepPeriodHours
            )
        }
    }

    static func breakdown(
        for entry: AppleHealthSleepDay,
        in history: [AppleHealthSleepDay],
        configuration: SleepQualityConfiguration,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SleepQualityBreakdown? {
        breakdown(
            for: entry,
            configuration: configuration,
            calendar: calendar,
            startsByDay: sleepStartsByDay(in: history, calendar: calendar)
        )
    }

    private static func breakdown(
        for entry: AppleHealthSleepDay,
        configuration: SleepQualityConfiguration,
        calendar: Calendar,
        startsByDay: [Date: Date]
    ) -> SleepQualityBreakdown? {
        guard let hours = entry.hours, hours >= 0, configuration.targetHours > 0 else { return nil }

        let durationScore = min(max(hours / configuration.targetHours, 0), 1) * 100
        let awakePercentage: Double
        let interruptionScore: Double
        if let reportedAwakeHours = entry.awakeHours {
            let awakeHours = max(reportedAwakeHours, 0)
            let periodHours = max(entry.sleepPeriodHours ?? (hours + awakeHours), 0)
            awakePercentage = periodHours > 0 ? min(awakeHours / periodHours * 100, 100) : 0
            interruptionScore = max(
                0,
                1 - awakePercentage / zeroInterruptionScoreAtPercentage
            ) * 100
        } else {
            // Missing interruption data is unknown, not equivalent to zero awakenings.
            awakePercentage = 0
            interruptionScore = 0
        }
        let compliantDays = regularityComplianceDays(
            endingOn: entry.date,
            startsByDay: startsByDay,
            calendar: calendar
        )
        let regularityScore = Double(compliantDays) / Double(regularityWindowDays) * 100
        let weights = configuration.weights
        let total = (
            durationScore * Double(weights.duration)
                + regularityScore * Double(weights.regularity)
                + interruptionScore * Double(weights.interruptions)
        ) / 100

        return SleepQualityBreakdown(
            durationScore: durationScore,
            regularityScore: regularityScore,
            interruptionScore: interruptionScore,
            compliantDays: compliantDays,
            awakePercentage: awakePercentage,
            totalScore: min(max(total, 0), 100)
        )
    }

    private static func regularityComplianceDays(
        endingOn endDate: Date,
        startsByDay: [Date: Date],
        calendar: Calendar
    ) -> Int {
        let endDay = calendar.startOfDay(for: endDate)
        let starts = (0..<regularityWindowDays).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else {
                return nil
            }
            return startsByDay[day]
        }
        let minutes = starts.map { start -> Double in
            let components = calendar.dateComponents([.hour, .minute, .second], from: start)
            return Double(components.hour ?? 0) * 60
                + Double(components.minute ?? 0)
                + Double(components.second ?? 0) / 60
        }
        guard let mean = circularMeanMinutes(minutes) else { return 0 }
        return minutes.filter {
            circularDistanceMinutes($0, mean) <= bedtimeToleranceMinutes
        }.count
    }

    private static func sleepStartsByDay(
        in history: [AppleHealthSleepDay],
        calendar: Calendar
    ) -> [Date: Date] {
        var result: [Date: Date] = [:]
        for entry in history {
            guard let start = entry.sleepStartDate else { continue }
            result[calendar.startOfDay(for: entry.date)] = start
        }
        return result
    }

    private static func circularMeanMinutes(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let fullDay = 24.0 * 60.0
        let angles = values.map { $0 / fullDay * 2 * Double.pi }
        let sine = angles.map(sin).reduce(0, +) / Double(angles.count)
        let cosine = angles.map(cos).reduce(0, +) / Double(angles.count)
        guard abs(sine) > 0.000_001 || abs(cosine) > 0.000_001 else { return nil }
        var angle = atan2(sine, cosine)
        if angle < 0 { angle += 2 * Double.pi }
        return angle / (2 * Double.pi) * fullDay
    }

    private static func circularDistanceMinutes(_ lhs: Double, _ rhs: Double) -> Double {
        let fullDay = 24.0 * 60.0
        let direct = abs(lhs - rhs).truncatingRemainder(dividingBy: fullDay)
        return min(direct, fullDay - direct)
    }
}

/// A device-local correction applied only while Wellnario presents sleep data.
/// It is deliberately stored outside the Apple Health snapshot so a later sync
/// cannot remove it, and it is never written back to HealthKit.
struct SleepManualOverride: Codable, Equatable, Sendable {
    let day: LocalDay
    let qualityScore: Double?
    let durationHours: Double?
    let updatedAt: Date
}

struct SleepManualOverrideStore {
    static let qualityRange = 0.0...100.0
    static let durationRange = (1.0 / 60.0)...24.0

    private let defaults: UserDefaults
    private let storageKey: String
    let qualityPreferences: SleepQualityPreferences

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "wellnario.sleep.manualOverrides.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        qualityPreferences = SleepQualityPreferences(defaults: defaults)
    }

    var overrides: [SleepManualOverride] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SleepManualOverride].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.day < $1.day }
    }

    func override(for day: LocalDay) -> SleepManualOverride? {
        overrides.first { $0.day == day }
    }

    func override(
        for date: Date,
        timeZone: TimeZone = .current
    ) -> SleepManualOverride? {
        override(for: LocalDay(containing: date, in: timeZone))
    }

    @discardableResult
    func save(
        day: LocalDay,
        qualityScore: Double?,
        durationHours: Double?,
        updatedAt: Date = Date()
    ) -> Bool {
        guard qualityScore != nil || durationHours != nil,
              qualityScore.map({ $0.isFinite && Self.qualityRange.contains($0) }) ?? true,
              durationHours.map({ $0.isFinite && Self.durationRange.contains($0) }) ?? true else {
            return false
        }

        var stored = overrides.filter { $0.day != day }
        stored.append(SleepManualOverride(
            day: day,
            qualityScore: qualityScore,
            durationHours: durationHours,
            updatedAt: updatedAt
        ))
        persist(stored)
        NotificationCenter.default.post(name: .sleepManualOverridesDidChange, object: nil)
        return true
    }

    func remove(day: LocalDay) {
        let currentOverrides = overrides
        let stored = currentOverrides.filter { $0.day != day }
        guard stored.count != currentOverrides.count else { return }
        persist(stored)
        NotificationCenter.default.post(name: .sleepManualOverridesDidChange, object: nil)
    }

    func removeAll(notify: Bool = true) {
        defaults.removeObject(forKey: storageKey)
        if notify {
            NotificationCenter.default.post(name: .sleepManualOverridesDidChange, object: nil)
        }
    }

    func applying(
        to history: [AppleHealthSleepDay],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [AppleHealthSleepDay] {
        resolve(
            history: history,
            configuration: qualityPreferences.configuration(calendar: calendar),
            calendar: calendar
        )
    }

    func applying(
        to snapshot: AppleHealthSnapshot,
        calendar: Calendar = .autoupdatingCurrent
    ) -> AppleHealthSnapshot {
        var effective = snapshot
        let configuration = qualityPreferences.configuration(
            dateOfBirthComponents: snapshot.dateOfBirthComponents,
            calendar: calendar
        )
        effective.sleepTrend = resolve(
            history: snapshot.sleepTrend,
            configuration: configuration,
            calendar: calendar
        )

        if let session = snapshot.latestSleepSession,
           let manualOverride = override(
               for: session.endDate,
               timeZone: calendar.timeZone
           ),
           let durationHours = manualOverride.durationHours {
            effective.latestSleepSession = AppleHealthSleepSession(
                startDate: session.startDate,
                endDate: session.endDate,
                asleepSeconds: durationHours * 3_600,
                inBedSeconds: session.inBedSeconds,
                awakeSeconds: session.awakeSeconds,
                coreSeconds: session.coreSeconds,
                deepSeconds: session.deepSeconds,
                remSeconds: session.remSeconds,
                sourceNames: session.sourceNames,
                stageIntervals: session.stageIntervals
            )
        }
        return effective
    }

    private func resolve(
        history: [AppleHealthSleepDay],
        configuration: SleepQualityConfiguration,
        calendar: Calendar
    ) -> [AppleHealthSleepDay] {
        var overridesByDay: [LocalDay: SleepManualOverride] = [:]
        for manualOverride in overrides {
            overridesByDay[manualOverride.day] = manualOverride
        }
        var entriesByDay: [LocalDay: AppleHealthSleepDay] = [:]
        for entry in history {
            entriesByDay[LocalDay(containing: entry.date, in: calendar.timeZone)] = entry
        }

        for manualOverride in overridesByDay.values {
            let existing = entriesByDay[manualOverride.day]
            guard let date = try? manualOverride.day.startDate(in: calendar.timeZone) else { continue }
            entriesByDay[manualOverride.day] = AppleHealthSleepDay(
                date: existing?.date ?? date,
                hours: manualOverride.durationHours ?? existing?.hours,
                qualityScore: existing?.qualityScore,
                remHours: existing?.remHours,
                deepHours: existing?.deepHours,
                lightHours: existing?.lightHours,
                sleepStartDate: existing?.sleepStartDate,
                awakeHours: existing?.awakeHours,
                sleepPeriodHours: existing?.sleepPeriodHours
            )
        }

        let scored = SleepQualityCalculator.applying(
            to: entriesByDay.values.sorted { $0.date < $1.date },
            configuration: configuration,
            calendar: calendar
        )
        return scored.map { entry in
            let day = LocalDay(containing: entry.date, in: calendar.timeZone)
            guard let manualQuality = overridesByDay[day]?.qualityScore else { return entry }
            return AppleHealthSleepDay(
                date: entry.date,
                hours: entry.hours,
                qualityScore: manualQuality,
                remHours: entry.remHours,
                deepHours: entry.deepHours,
                lightHours: entry.lightHours,
                sleepStartDate: entry.sleepStartDate,
                awakeHours: entry.awakeHours,
                sleepPeriodHours: entry.sleepPeriodHours
            )
        }
    }

    private func persist(_ overrides: [SleepManualOverride]) {
        guard let data = try? JSONEncoder().encode(overrides.sorted(by: { $0.day < $1.day })) else {
            return
        }
        defaults.set(data, forKey: storageKey)
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
                lightHours: entry.lightHours,
                sleepStartDate: entry.sleepStartDate,
                awakeHours: entry.awakeHours,
                sleepPeriodHours: entry.sleepPeriodHours
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
                lightHours: average(bucketEntries.map(\.lightHours)),
                sleepStartDate: nil,
                awakeHours: average(bucketEntries.map(\.awakeHours)),
                sleepPeriodHours: average(bucketEntries.map(\.sleepPeriodHours))
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
            let awakeSeconds = dailySessions.reduce(0) {
                $0 + interruptionAwakeSeconds(in: $1)
            }
            let remSeconds = dailySessions.reduce(0) { $0 + $1.remSeconds }
            let deepSeconds = dailySessions.reduce(0) { $0 + $1.deepSeconds }
            let lightSeconds = dailySessions.reduce(0) { $0 + $1.coreSeconds }
            let mainSession = dailySessions.max { lhs, rhs in
                if lhs.asleepSeconds != rhs.asleepSeconds {
                    return lhs.asleepSeconds < rhs.asleepSeconds
                }
                return lhs.endDate < rhs.endDate
            }
            return AppleHealthSleepDay(
                date: day,
                hours: asleepSeconds > 0 ? asleepSeconds / 3_600 : nil,
                // Wellnario computes this later using the current target and weights.
                qualityScore: nil,
                remHours: remSeconds > 0 ? remSeconds / 3_600 : nil,
                deepHours: deepSeconds > 0 ? deepSeconds / 3_600 : nil,
                lightHours: lightSeconds > 0 ? lightSeconds / 3_600 : nil,
                sleepStartDate: mainSession.map(sleepStartDate),
                awakeHours: dailySessions.isEmpty ? nil : awakeSeconds / 3_600,
                sleepPeriodHours: dailySessions.isEmpty
                    ? nil
                    : (asleepSeconds + awakeSeconds) / 3_600
            )
        }
    }

    private static func interruptionAwakeSeconds(
        in session: AppleHealthSleepSession
    ) -> TimeInterval {
        let asleepIntervals = session.stageIntervals.filter { $0.stage != .awake }
        guard let firstAsleep = asleepIntervals.map(\.startDate).min(),
              let lastAsleep = asleepIntervals.map(\.endDate).max() else {
            return session.awakeSeconds
        }
        return session.stageIntervals
            .filter { $0.stage == .awake }
            .reduce(0) { total, interval in
                let start = max(interval.startDate, firstAsleep)
                let end = min(interval.endDate, lastAsleep)
                return total + max(end.timeIntervalSince(start), 0)
            }
    }

    private static func sleepStartDate(in session: AppleHealthSleepSession) -> Date {
        session.stageIntervals
            .filter { $0.stage != .awake }
            .map(\.startDate)
            .min() ?? session.startDate
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

            var updated = AppleHealthSnapshot(
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
            updated.dateOfBirthComponents = try? healthStore.dateOfBirthComponents()
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
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth),
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
