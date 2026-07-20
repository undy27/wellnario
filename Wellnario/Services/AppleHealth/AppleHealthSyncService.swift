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

struct AppleHealthAutomaticSleepFactors: Codable, Equatable, Sendable {
    let date: Date
    let steps: Double?
    /// Legacy persisted backing value for the binary strength-training factor.
    /// A positive value means that a strength workout was recorded before the
    /// associated sleep session. Retaining the original name keeps cached
    /// snapshots from earlier versions readable.
    let strengthTrainingMinutes: Double?
    let daylightMinutes: Double?
    let earlyDaylightMinutes: Double?
    /// Personal 0–100 physiological StressScore calculated before sleep from
    /// HRV, resting heart rate, respiratory rate, and sleep quality.
    let preSleepStressScore: Double?
    /// Full breakdown retained for the current stress detail screen. It is
    /// optional so snapshots written before the breakdown was introduced
    /// remain readable.
    var preSleepStressDetails: AppleHealthStressCalculationDetails? = nil

    func value(for factorID: String) -> Double? {
        switch factorID {
        case SleepFactorCatalog.automaticStepsID: steps
        case SleepFactorCatalog.automaticStrengthMinutesID:
            strengthTrainingMinutes.map { $0 > 0 ? 1 : 0 }
        case SleepFactorCatalog.automaticDaylightMinutesID: daylightMinutes
        case SleepFactorCatalog.automaticEarlyDaylightMinutesID: earlyDaylightMinutes
        case SleepFactorCatalog.automaticPreSleepStressID: preSleepStressScore
        default: nil
        }
    }
}

struct AppleHealthTimedQuantity: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let value: Double
}

/// A physiological snapshot taken just before a sleep session. Keeping the
/// raw values together makes the StressScore calculation deterministic and
/// independently testable from HealthKit queries.
struct AppleHealthStressObservation: Equatable, Sendable {
    let date: Date
    let heartRateVariability: Double?
    let restingHeartRate: Double?
    let respiratoryRate: Double?
    let sleepQuality: Double?
    let hadActivityInPreviousTwoHours: Bool
}

struct AppleHealthStressMetricDetails: Codable, Equatable, Sendable {
    let value: Double?
    let adjustedValue: Double?
    let baselineMedian: Double?
    let baselineMAD: Double?
    let zScore: Double?
    let contribution: Double?
    let baselineSampleCount: Int
    let weight: Double
}

struct AppleHealthStressCalculationDetails: Codable, Equatable, Sendable {
    let date: Date
    let heartRateVariability: AppleHealthStressMetricDetails
    let restingHeartRate: AppleHealthStressMetricDetails
    let respiratoryRate: AppleHealthStressMetricDetails
    let sleepQuality: AppleHealthStressMetricDetails
    let hadActivityInPreviousTwoHours: Bool
    let compositeIndex: Double?
    let compositeBaselineMedian: Double?
    let compositeBaselineMAD: Double?
    let compositeZScore: Double?
    let score: Double?
}

/// A point on the latest StressScore timeline. Every point is anchored to a
/// real HealthKit measurement time (plus the sync-time estimate), rather than
/// being interpolated at artificial intervals.
struct AppleHealthStressTimelinePoint: Codable, Equatable, Sendable {
    let date: Date
    let score: Double?
}

/// A StressScore evolution over a concrete time interval. It is intentionally
/// separate from daily sleep factors, which retain the pre-sleep score used
/// by sleep analysis.
struct AppleHealthStressTimeline: Codable, Equatable, Sendable {
    let sleepStartDate: Date
    let points: [AppleHealthStressTimelinePoint]
}

/// The data necessary to render a full historical stress day, including the
/// contextual periods that explain the chart's sleep and workout bands.
struct AppleHealthStressDayTimeline: Equatable, Sendable {
    let day: LocalDay
    let timeline: AppleHealthStressTimeline
    let sleepSessions: [AppleHealthSleepSession]
    let workouts: [AppleHealthWorkout]
}

/// Personal StressScore proposed in `doc/propuesta_stress.md`.
///
/// Each biomarker is normalized against its own preceding 28-day history by
/// means of median and MAD. The resulting physiological index is normalized
/// the same way before the logistic 0–100 transformation. We require seven
/// historical daily observations so that a score is not presented from an
/// unstable baseline; no missing biomarker is inferred or substituted.
enum AppleHealthStressScoreCalculator {
    static let baselineDays = 28
    static let minimumHistoricalSamples = 7
    /// Moderate steepening of the final logistic transform. The personal
    /// baseline remains unchanged; deviations from it are simply reflected
    /// more clearly in the visible 0–100 score.
    static let logisticSensitivity = 1.4

    static func scores(
        for observations: [AppleHealthStressObservation],
        calendar: Calendar
    ) -> [Date: Double] {
        details(for: observations, calendar: calendar).compactMapValues(\.score)
    }

    static func details(
        for observations: [AppleHealthStressObservation],
        calendar: Calendar
    ) -> [Date: AppleHealthStressCalculationDetails] {
        let ordered = observations.sorted { $0.date < $1.date }
        var compositeHistory: [(date: Date, value: Double)] = []
        var result: [Date: AppleHealthStressCalculationDetails] = [:]

        for observation in ordered {
            let historical = ordered.filter {
                isInBaselineWindow($0.date, for: observation.date, calendar: calendar)
            }
            let hrvBaseline = historical.compactMap(\.heartRateVariability)
            let restingHeartRateBaseline = historical.compactMap(\.restingHeartRate)
            let respiratoryRateBaseline = historical.compactMap(\.respiratoryRate)
            let sleepQualityBaseline = historical.compactMap(\.sleepQuality)
            let adjustedHRV = observation.hadActivityInPreviousTwoHours
                ? average(hrvBaseline)
                : observation.heartRateVariability
            let hrv = metricDetails(
                value: observation.heartRateVariability,
                adjustedValue: adjustedHRV,
                baseline: hrvBaseline,
                weight: -0.45
            )
            let restingHeartRate = metricDetails(
                value: observation.restingHeartRate,
                baseline: restingHeartRateBaseline,
                weight: 0.30
            )
            let respiratoryRate = metricDetails(
                value: observation.respiratoryRate,
                baseline: respiratoryRateBaseline,
                weight: 0.10
            )
            let sleepQuality = metricDetails(
                value: observation.sleepQuality,
                baseline: sleepQualityBaseline,
                weight: -0.15
            )
            let composite: Double? = if let hrvContribution = hrv.contribution,
                                         let restingContribution = restingHeartRate.contribution,
                                         let respiratoryContribution = respiratoryRate.contribution,
                                         let sleepContribution = sleepQuality.contribution {
                hrvContribution + restingContribution + respiratoryContribution + sleepContribution
            } else {
                nil
            }

            let historicalComposite = compositeHistory
                .filter { isInBaselineWindow($0.date, for: observation.date, calendar: calendar) }
                .map(\.value)
            let compositeStats = robustStatistics(composite, baseline: historicalComposite)
            let score = compositeStats?.zScore.map { normalizedComposite in
                min(max(
                    100 / (1 + exp(-logisticSensitivity * normalizedComposite)),
                    0
                ), 100)
            }
            result[observation.date] = AppleHealthStressCalculationDetails(
                date: observation.date,
                heartRateVariability: hrv,
                restingHeartRate: restingHeartRate,
                respiratoryRate: respiratoryRate,
                sleepQuality: sleepQuality,
                hadActivityInPreviousTwoHours: observation.hadActivityInPreviousTwoHours,
                compositeIndex: composite,
                compositeBaselineMedian: compositeStats?.median,
                compositeBaselineMAD: compositeStats?.mad,
                compositeZScore: compositeStats?.zScore,
                score: score
            )

            if let composite {
                compositeHistory.append((date: observation.date, value: composite))
            }
        }
        return result
    }

    private struct RobustStatistics {
        let median: Double
        let mad: Double
        let zScore: Double?
    }

    private static func metricDetails(
        value: Double?,
        adjustedValue: Double? = nil,
        baseline: [Double],
        weight: Double
    ) -> AppleHealthStressMetricDetails {
        let adjusted = adjustedValue ?? value
        let stats = robustStatistics(adjusted, baseline: baseline)
        return AppleHealthStressMetricDetails(
            value: value,
            adjustedValue: adjusted,
            baselineMedian: stats?.median,
            baselineMAD: stats?.mad,
            zScore: stats?.zScore,
            contribution: stats?.zScore.map { $0 * weight },
            baselineSampleCount: baseline.count,
            weight: weight
        )
    }

    private static func robustStatistics(
        _ value: Double?,
        baseline: [Double]
    ) -> RobustStatistics? {
        guard let value,
              let baselineMedian = median(baseline) else {
            return nil
        }
        let deviations = baseline.map { abs($0 - baselineMedian) }
        guard let mad = median(deviations) else { return nil }
        let scale = 1.4826 * mad
        let zScore: Double?
        if baseline.count < minimumHistoricalSamples {
            zScore = nil
        } else if scale > 0.000_001 {
            zScore = min(max((value - baselineMedian) / scale, -3), 3)
        } else {
            // A zero MAD is common for slowly changing HealthKit metrics
            // (especially respiratory rate and calculated sleep quality).
            // It means "no observed variation", not "no data". Treat a
            // value equal to that stable baseline as neutral; if it differs,
            // use the maximum bounded direction because the robust scale is
            // genuinely zero.
            let difference = value - baselineMedian
            if abs(difference) <= 0.000_001 {
                zScore = 0
            } else {
                zScore = difference > 0 ? 3 : -3
            }
        }
        return RobustStatistics(median: baselineMedian, mad: mad, zScore: zScore)
    }

    static func levelLocalizationKey(for score: Double) -> String {
        switch score {
        case ..<25: return "apple_health.stress.level.very_low"
        case ..<40: return "apple_health.stress.level.low"
        case ..<60: return "apple_health.stress.level.normal"
        case ..<75: return "apple_health.stress.level.elevated"
        case ..<90: return "apple_health.stress.level.high"
        default: return "apple_health.stress.level.very_high"
        }
    }

    private static func compositeIndex(
        for observation: AppleHealthStressObservation,
        in observations: [AppleHealthStressObservation],
        calendar: Calendar
    ) -> Double? {
        let historical = observations.filter {
            isInBaselineWindow($0.date, for: observation.date, calendar: calendar)
        }
        let hrvBaseline = historical.compactMap(\.heartRateVariability)
        let restingHeartRateBaseline = historical.compactMap(\.restingHeartRate)
        let respiratoryRateBaseline = historical.compactMap(\.respiratoryRate)
        let sleepQualityBaseline = historical.compactMap(\.sleepQuality)

        let adjustedHRV: Double?
        if observation.hadActivityInPreviousTwoHours {
            adjustedHRV = average(hrvBaseline)
        } else {
            adjustedHRV = observation.heartRateVariability
        }

        guard let adjustedHRV,
              let restingHeartRate = observation.restingHeartRate,
              let respiratoryRate = observation.respiratoryRate,
              let sleepQuality = observation.sleepQuality,
              let hrvZ = robustZ(adjustedHRV, baseline: hrvBaseline),
              let restingHeartRateZ = robustZ(
                restingHeartRate,
                baseline: restingHeartRateBaseline
              ),
              let respiratoryRateZ = robustZ(
                respiratoryRate,
                baseline: respiratoryRateBaseline
              ),
              let sleepQualityZ = robustZ(
                sleepQuality,
                baseline: sleepQualityBaseline
              ) else {
            return nil
        }

        return -0.45 * hrvZ
            + 0.30 * restingHeartRateZ
            + 0.10 * respiratoryRateZ
            - 0.15 * sleepQualityZ
    }

    private static func isInBaselineWindow(
        _ candidateDate: Date,
        for date: Date,
        calendar: Calendar
    ) -> Bool {
        let currentDay = calendar.startOfDay(for: date)
        let earliestDay = calendar.date(
            byAdding: .day,
            value: -baselineDays,
            to: currentDay
        ) ?? .distantPast
        return candidateDate >= earliestDay && candidateDate < currentDay
    }

    private static func robustZ(_ value: Double, baseline: [Double]) -> Double? {
        guard baseline.count >= minimumHistoricalSamples,
              let baselineMedian = median(baseline) else {
            return nil
        }
        let deviations = baseline.map { abs($0 - baselineMedian) }
        guard let mad = median(deviations) else { return nil }
        let scale = 1.4826 * mad
        if scale > 0.000_001 {
            return min(max((value - baselineMedian) / scale, -3), 3)
        }
        let difference = value - baselineMedian
        if abs(difference) <= 0.000_001 { return 0 }
        return difference > 0 ? 3 : -3
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct AppleHealthAutomaticSleepFactorHistory: Equatable, Sendable {
    let factors: [AppleHealthAutomaticSleepFactors]
    let latestStressTimeline: AppleHealthStressTimeline?
    /// StressScore calculated at the time of the latest sync, using the most
    /// recent HealthKit readings. The pre-sleep score remains separate because
    /// it is used as a sleep factor and has a different reference moment.
    var currentStressDetails: AppleHealthStressCalculationDetails? = nil
}

enum AppleHealthAutomaticSleepFactorBuilder {
    static func build(
        sessions: [AppleHealthSleepSession],
        stepsByDay: [LocalDay: Double],
        workouts: [AppleHealthWorkout],
        daylightByDay: [LocalDay: Double],
        daylightSamples: [AppleHealthTimedQuantity],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity] = [],
        respiratoryRateSamples: [AppleHealthTimedQuantity] = [],
        sleepQualityByDay: [LocalDay: Double] = [:],
        calendar: Calendar
    ) -> [AppleHealthAutomaticSleepFactors] {
        buildHistory(
            sessions: sessions,
            stepsByDay: stepsByDay,
            workouts: workouts,
            daylightByDay: daylightByDay,
            daylightSamples: daylightSamples,
            hrvSamples: hrvSamples,
            restingHeartRateSamples: restingHeartRateSamples,
            respiratoryRateSamples: respiratoryRateSamples,
            sleepQualityByDay: sleepQualityByDay,
            calendar: calendar
        ).factors
    }

    static func buildHistory(
        sessions: [AppleHealthSleepSession],
        stepsByDay: [LocalDay: Double],
        workouts: [AppleHealthWorkout],
        daylightByDay: [LocalDay: Double],
        daylightSamples: [AppleHealthTimedQuantity],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity] = [],
        respiratoryRateSamples: [AppleHealthTimedQuantity] = [],
        sleepQualityByDay: [LocalDay: Double] = [:],
        calendar: Calendar,
        currentDate: Date = Date()
    ) -> AppleHealthAutomaticSleepFactorHistory {
        let orderedSessions = sessions.sorted { $0.endDate < $1.endDate }
        let stressObservations = makeStressObservations(
            sessions: orderedSessions,
            workouts: workouts,
            hrvSamples: hrvSamples,
            restingHeartRateSamples: restingHeartRateSamples,
            respiratoryRateSamples: respiratoryRateSamples,
            sleepQualityByDay: sleepQualityByDay,
            calendar: calendar
        )
        let stressDetails = AppleHealthStressScoreCalculator.details(
            for: stressObservations,
            calendar: calendar
        )
        let stressScores = stressDetails.compactMapValues(\.score)

        let factors = orderedSessions.enumerated().map { index, session in
            let sleepDate = calendar.startOfDay(for: session.endDate)
            let activityDay = LocalDay(containing: session.startDate, in: calendar.timeZone)
            let hasStrengthTraining = workouts.contains {
                    $0.kind == .strength
                        && LocalDay(containing: $0.startDate, in: calendar.timeZone) == activityDay
                        && $0.startDate < session.startDate
                }

            let earlyDaylight: Double?
            if index > 0 {
                let previousWake = orderedSessions[index - 1].endDate
                let earlyWindowEnd = previousWake.addingTimeInterval(2 * 3_600)
                earlyDaylight = summedQuantity(
                    daylightSamples,
                    from: previousWake,
                    through: earlyWindowEnd
                )
            } else {
                earlyDaylight = nil
            }

            return AppleHealthAutomaticSleepFactors(
                date: sleepDate,
                steps: stepsByDay[activityDay],
                strengthTrainingMinutes: hasStrengthTraining ? 1 : 0,
                daylightMinutes: daylightByDay[activityDay],
                earlyDaylightMinutes: earlyDaylight,
                preSleepStressScore: stressScores[session.startDate],
                preSleepStressDetails: stressDetails[session.startDate]
            )
        }
        return AppleHealthAutomaticSleepFactorHistory(
            factors: factors,
            latestStressTimeline: makeLatestStressTimeline(
                sessions: orderedSessions,
                historicalObservations: stressObservations,
                workouts: workouts,
                hrvSamples: hrvSamples,
                restingHeartRateSamples: restingHeartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples,
                sleepQualityByDay: sleepQualityByDay,
                calendar: calendar,
                currentDate: currentDate
            ),
            currentStressDetails: makeCurrentStressDetails(
                at: currentDate,
                historicalObservations: stressObservations,
                sessions: orderedSessions,
                workouts: workouts,
                hrvSamples: hrvSamples,
                restingHeartRateSamples: restingHeartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples,
                sleepQualityByDay: sleepQualityByDay,
                calendar: calendar
            )
        )
    }

    /// Builds a 24-hour stress evolution for a previously selected day. The
    /// normalization baseline still comes from the preceding sleep sessions,
    /// while every displayed point is anchored to a real HealthKit reading.
    static func stressTimeline(
        for period: DateInterval,
        sessions: [AppleHealthSleepSession],
        workouts: [AppleHealthWorkout],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        sleepQualityByDay: [LocalDay: Double],
        calendar: Calendar
    ) -> AppleHealthStressTimeline? {
        guard period.duration > 0 else { return nil }
        let orderedSessions = sessions.sorted { $0.endDate < $1.endDate }
        let observations = makeStressObservations(
            sessions: orderedSessions,
            workouts: workouts,
            hrvSamples: hrvSamples,
            restingHeartRateSamples: restingHeartRateSamples,
            respiratoryRateSamples: respiratoryRateSamples,
            sleepQualityByDay: sleepQualityByDay,
            calendar: calendar
        )
        let measurementDates = Set((
            hrvSamples + restingHeartRateSamples + respiratoryRateSamples
        )
        .map(\.endDate)
        .filter { period.contains($0) || $0 == period.end })
        let dates = Array(measurementDates.union([period.start, period.end])).sorted()
        let points = dates.map { date -> AppleHealthStressTimelinePoint in
            // The interval anchors preserve the true 24-hour scale, but are
            // deliberately not shown as invented physiological readings.
            guard measurementDates.contains(date) else {
                return AppleHealthStressTimelinePoint(date: date, score: nil)
            }
            let latestQuality = orderedSessions.last(where: { $0.endDate <= date }).flatMap {
                sleepQualityByDay[LocalDay(containing: $0.endDate, in: calendar.timeZone)]
            }
            let observation = makeStressObservation(
                at: date,
                sleepQuality: latestQuality,
                workouts: workouts,
                hrvSamples: hrvSamples,
                restingHeartRateSamples: restingHeartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples
            )
            let score = AppleHealthStressScoreCalculator.details(
                for: observations.filter { $0.date < date } + [observation],
                calendar: calendar
            )[date]?.score
            return AppleHealthStressTimelinePoint(date: date, score: score)
        }
        return AppleHealthStressTimeline(sleepStartDate: period.start, points: points)
    }

    private static func makeStressObservations(
        sessions: [AppleHealthSleepSession],
        workouts: [AppleHealthWorkout],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        sleepQualityByDay: [LocalDay: Double],
        calendar: Calendar
    ) -> [AppleHealthStressObservation] {
        sessions.enumerated().map { index, session in
            let previousSleepQuality = index > 0
                ? sleepQualityByDay[LocalDay(
                    containing: sessions[index - 1].endDate,
                    in: calendar.timeZone
                )]
                : nil
            return makeStressObservation(
                at: session.startDate,
                sleepQuality: previousSleepQuality,
                workouts: workouts,
                hrvSamples: hrvSamples,
                restingHeartRateSamples: restingHeartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples
            )
        }
    }

    private static func makeStressObservation(
        at date: Date,
        sleepQuality: Double?,
        workouts: [AppleHealthWorkout],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity]
    ) -> AppleHealthStressObservation {
        AppleHealthStressObservation(
            date: date,
            // HealthKit does not guarantee a reading in the exact pre-bed
            // hour. Use the most recent real physiological measurement, but
            // never one more than 36 hours old.
            heartRateVariability: latestQuantity(
                hrvSamples,
                before: date,
                maximumAge: 36 * 3_600
            ),
            restingHeartRate: latestQuantity(
                restingHeartRateSamples,
                before: date,
                maximumAge: 36 * 3_600
            ),
            respiratoryRate: latestQuantity(
                respiratoryRateSamples,
                before: date,
                maximumAge: 36 * 3_600
            ),
            sleepQuality: sleepQuality,
            hadActivityInPreviousTwoHours: workouts.contains {
                $0.startDate < date
                    && $0.endDate > date.addingTimeInterval(-2 * 3_600)
            }
        )
    }

    private static func makeLatestStressTimeline(
        sessions: [AppleHealthSleepSession],
        historicalObservations: [AppleHealthStressObservation],
        workouts: [AppleHealthWorkout],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        sleepQualityByDay: [LocalDay: Double],
        calendar: Calendar,
        currentDate: Date
    ) -> AppleHealthStressTimeline? {
        guard let latestSession = sessions.last, currentDate >= latestSession.startDate else {
            return nil
        }
        let periodStart = latestSession.startDate.addingTimeInterval(-3_600)
        let measurementDates = Set((
            hrvSamples + restingHeartRateSamples + respiratoryRateSamples
        )
        .map(\.endDate)
        .filter { $0 >= periodStart && $0 <= currentDate })
        let dates = Array(
            measurementDates.union([periodStart, latestSession.startDate, currentDate])
        ).sorted()
        let points = dates.map { date -> AppleHealthStressTimelinePoint in
            guard date != periodStart || measurementDates.contains(date) else {
                // The empty first point keeps the real time scale intact when
                // no reading exists at the start of the requested period.
                return AppleHealthStressTimelinePoint(date: date, score: nil)
            }
            let latestQuality = sessions.last(where: { $0.endDate <= date }).flatMap {
                sleepQualityByDay[LocalDay(containing: $0.endDate, in: calendar.timeZone)]
            }
            let observation = makeStressObservation(
                at: date,
                sleepQuality: latestQuality,
                workouts: workouts,
                hrvSamples: hrvSamples,
                restingHeartRateSamples: restingHeartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples
            )
            let score = AppleHealthStressScoreCalculator.details(
                for: historicalObservations.filter { $0.date < date } + [observation],
                calendar: calendar
            )[date]?.score
            return AppleHealthStressTimelinePoint(date: date, score: score)
        }
        return AppleHealthStressTimeline(
            sleepStartDate: latestSession.startDate,
            points: points
        )
    }

    private static func makeCurrentStressDetails(
        at date: Date,
        historicalObservations: [AppleHealthStressObservation],
        sessions: [AppleHealthSleepSession],
        workouts: [AppleHealthWorkout],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        sleepQualityByDay: [LocalDay: Double],
        calendar: Calendar
    ) -> AppleHealthStressCalculationDetails? {
        let latestSleepQuality = sessions.last.flatMap {
            sleepQualityByDay[LocalDay(containing: $0.endDate, in: calendar.timeZone)]
        }
        let observation = makeStressObservation(
            at: date,
            sleepQuality: latestSleepQuality,
            workouts: workouts,
            hrvSamples: hrvSamples,
            restingHeartRateSamples: restingHeartRateSamples,
            respiratoryRateSamples: respiratoryRateSamples
        )
        return AppleHealthStressScoreCalculator.details(
            for: historicalObservations + [observation],
            calendar: calendar
        )[date]
    }

    private static func summedQuantity(
        _ samples: [AppleHealthTimedQuantity],
        from startDate: Date,
        through endDate: Date
    ) -> Double? {
        var foundSample = false
        let sum = samples.reduce(0.0) { total, sample in
            let overlapStart = max(startDate, sample.startDate)
            let overlapEnd = min(endDate, sample.endDate)
            guard overlapEnd > overlapStart else { return total }
            foundSample = true
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            guard duration > 0 else { return total + sample.value }
            let overlap = overlapEnd.timeIntervalSince(overlapStart)
            return total + sample.value * min(max(overlap / duration, 0), 1)
        }
        return foundSample ? sum : nil
    }

    private static func latestQuantity(
        _ samples: [AppleHealthTimedQuantity],
        before date: Date,
        maximumAge: TimeInterval
    ) -> Double? {
        samples
            .filter {
                $0.endDate <= date
                    && $0.endDate >= date.addingTimeInterval(-maximumAge)
            }
            .max { $0.endDate < $1.endDate }?
            .value
    }
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

enum AppleHealthBiologicalSex: String, Codable, Equatable, Sendable {
    case female
    case male
    case other
    case notSet
}

struct AppleHealthSnapshot: Codable, Equatable, Sendable {
    var lastSyncedAt: Date?
    var dateOfBirthComponents: DateComponents? = nil
    var biologicalSex: AppleHealthBiologicalSex? = nil
    var latestSleepSession: AppleHealthSleepSession?
    var sleepTrend: [AppleHealthSleepDay]
    var heartRateVariability: AppleHealthMeasurement?
    var restingHeartRate: AppleHealthMeasurement?
    /// Average VO₂Max across the three months ending at the latest
    /// successful sync. It is used when no recent lab result is available.
    var vo2Max: AppleHealthMeasurement?
    var bloodGlucose: AppleHealthMeasurement?
    /// Average systolic blood pressure across the six months ending at the
    /// latest successful sync. BioAge uses this representative value.
    var systolicBloodPressureSixMonthAverage: AppleHealthMeasurement? = nil
    var stepsToday: Double?
    var activeEnergyKilocaloriesToday: Double?
    var workoutsThisWeek: [AppleHealthWorkout]
    /// Automatic factor values aligned with the date on which each sleep
    /// session ended. Optional to preserve decoding of pre-feature caches.
    var automaticSleepFactors: [AppleHealthAutomaticSleepFactors]? = nil
    /// Short StressScore evolution before the latest recorded sleep session.
    /// Optional to preserve decoding of snapshots written before this chart.
    var latestPreSleepStressTimeline: AppleHealthStressTimeline? = nil
    /// Most recent StressScore calculation, evaluated at the time the Health
    /// snapshot was synchronized. Optional for backwards-compatible caches.
    var currentStressDetails: AppleHealthStressCalculationDetails? = nil

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
        workoutsThisWeek: [],
        automaticSleepFactors: []
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
    var requiresManualBloodPressureAuthorization: Bool { get }
    var availableSources: [AppleHealthDataSource] { get }
    var disabledSourceSelections: Set<AppleHealthSourceSelection> { get }

    func requestAuthorizationAndSync() async throws
    func sync() async throws
    func syncIfConfigured() async
    func stressTimeline(for day: LocalDay) async -> AppleHealthStressDayTimeline?
    /// Returns true only once when HealthKit reports that a connected app has
    /// a read authorization that still needs the person's decision.
    func consumePendingAuthorizationWarning() async -> Bool
    func setSourceEnabled(
        _ identifier: String,
        for dataKind: AppleHealthDataKind,
        isEnabled: Bool
    )
}

extension AppleHealthSyncing {
    var requiresManualBloodPressureAuthorization: Bool { false }
    func consumePendingAuthorizationWarning() async -> Bool { false }
    func stressTimeline(for day: LocalDay) async -> AppleHealthStressDayTimeline? { nil }
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

/// Pure, potentially expensive calculations that must not run on the main
/// actor while a HealthKit synchronization is in progress.
private enum AppleHealthBackgroundCalculations {
    static func sleepSessions(
        from segments: [AppleHealthSleepAggregator.Segment]
    ) -> [AppleHealthSleepSession] {
        AppleHealthSleepAggregator.sessions(from: segments)
    }

    static func sleepTrend(
        sessions: [AppleHealthSleepSession],
        endingAt endDate: Date,
        calendar: Calendar
    ) -> [AppleHealthSleepDay] {
        AppleHealthSleepAggregator.allTimeTrend(
            sessions: sessions,
            endingAt: endDate,
            calendar: calendar
        )
    }

    static func automaticSleepFactorHistory(
        sessions: [AppleHealthSleepSession],
        stepsByDay: [LocalDay: Double],
        workouts: [AppleHealthWorkout],
        daylightByDay: [LocalDay: Double],
        daylightSamples: [AppleHealthTimedQuantity],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        sleepQualityByDay: [LocalDay: Double],
        calendar: Calendar,
        currentDate: Date
    ) -> AppleHealthAutomaticSleepFactorHistory {
        AppleHealthAutomaticSleepFactorBuilder.buildHistory(
            sessions: sessions,
            stepsByDay: stepsByDay,
            workouts: workouts,
            daylightByDay: daylightByDay,
            daylightSamples: daylightSamples,
            hrvSamples: hrvSamples,
            restingHeartRateSamples: restingHeartRateSamples,
            respiratoryRateSamples: respiratoryRateSamples,
            sleepQualityByDay: sleepQualityByDay,
            calendar: calendar,
            currentDate: currentDate
        )
    }
}

@MainActor
final class AppleHealthSyncService: AppleHealthSyncing {
    private static let bloodPressureAuthorizationReviewedKey =
        "appleHealth.bloodPressureAuthorizationReviewed.v1"
    private static let pendingAuthorizationWarningShownKey =
        "appleHealth.pendingAuthorizationWarningShown.v1"

    private struct SourceQueryFilter {
        let predicate: NSPredicate?
        let excludesAll: Bool
    }

    private struct SourceAccumulator {
        var name: String
        var dataKinds: Set<AppleHealthDataKind>
    }

    private let healthStore: HKHealthStore?
    private let defaults: UserDefaults
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
    var requiresManualBloodPressureAuthorization: Bool {
        Self.requiresManualBloodPressureAuthorization(
            for: ProcessInfo.processInfo.operatingSystemVersion
        )
    }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .autoupdatingCurrent,
        isEnabled: Bool = true
    ) {
        self.defaults = defaults
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
            let wasAlreadyConfigured = cache.isConfigured
            // Existing installations get the recently added daylight type in
            // its own request. Do not include it in the broad legacy request
            // as well: on some HealthKit releases, presenting both requests
            // consecutively can leave the subsequent sync in a failed state.
            let primaryReadTypes = wasAlreadyConfigured
                ? readTypes.subtracting(Self.daylightAuthorizationReadTypes)
                : readTypes
            // Do not gate this call behind getRequestStatusForAuthorization.
            // On some HealthKit versions it may report `.unnecessary` for an
            // already-connected app even after a new read type is added. The
            // actual request is idempotent: HealthKit shows a sheet only when
            // the person still has a decision to make, including for VO₂Max.
            let didComplete = try await requestAuthorization(
                healthStore: healthStore,
                readTypes: primaryReadTypes
            )
            guard didComplete else { throw AppleHealthSyncError.authorizationFailed }

            // `timeInDaylight` was added after Apple Health support had
            // already shipped. Some existing installations do not surface a
            // newly added read type when it is included in a broader request.
            // Ask HealthKit about this type on its own and, only when it still
            // has a pending decision, present its dedicated request. This
            // remains a no-op for people who have already seen the choice.
            if wasAlreadyConfigured,
               (try? await authorizationRequestStatus(
                healthStore: healthStore,
                readTypes: Self.daylightAuthorizationReadTypes
            )) == .shouldRequest {
                _ = try? await requestAuthorization(
                    healthStore: healthStore,
                    readTypes: Self.daylightAuthorizationReadTypes
                )
            }
            hasReviewedBloodPressureAuthorization = true
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

    func stressTimeline(for day: LocalDay) async -> AppleHealthStressDayTimeline? {
        guard let healthStore, isConfigured else { return nil }
        var dateComponents = DateComponents()
        dateComponents.year = day.year
        dateComponents.month = day.month
        dateComponents.day = day.day
        guard let dayStart = calendar.date(from: dateComponents).map(calendar.startOfDay(for:)),
              let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart),
              dayStart < Date() else {
            return nil
        }
        let dayEnd = min(nextDayStart, Date())
        // A StressScore needs two rolling baseline windows. The current
        // observation is compared with the preceding 28 days, but the
        // composite values inside that first window also need their own
        // 28-day history before they can establish a valid composite
        // baseline. Loading only one month therefore left historical charts
        // with no score despite the underlying HealthKit samples existing.
        let stressContextStart = calendar.date(
            byAdding: .day,
            value: -((AppleHealthStressScoreCalculator.baselineDays * 2) + 2),
            to: dayStart
        ) ?? dayStart

        do {
            async let sessionsTask = fetchSleepSessions(
                from: healthStore,
                startingAt: stressContextStart,
                endingAt: dayEnd
            )
            async let workoutsTask = fetchWorkouts(
                from: healthStore,
                start: stressContextStart,
                end: dayEnd
            )
            async let hrvTask = fetchTimedQuantities(
                from: healthStore,
                identifier: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                start: stressContextStart,
                end: dayEnd
            )
            async let restingHeartRateTask = fetchTimedQuantities(
                from: healthStore,
                identifier: .restingHeartRate,
                unit: .count().unitDivided(by: .minute()),
                start: stressContextStart,
                end: dayEnd
            )
            async let respiratoryRateTask = fetchTimedQuantities(
                from: healthStore,
                identifier: .respiratoryRate,
                unit: .count().unitDivided(by: .minute()),
                start: stressContextStart,
                end: dayEnd
            )
            let (sessions, workouts, hrvSamples, restingHeartRateSamples, respiratoryRateSamples) = try await (
                sessionsTask,
                workoutsTask,
                hrvTask,
                restingHeartRateTask,
                respiratoryRateTask
            )
            // The persisted snapshot intentionally stores the raw sleep trend
            // so quality can be recalculated when the user's target or weights
            // change. Historical stress queries must therefore apply the same
            // scoring and manual overrides as a normal synchronization before
            // building their physiological observations. Reading
            // `snapshot.sleepTrend` directly leaves every quality value nil and
            // makes every historical StressScore incomplete.
            let effectiveSleepTrend = SleepManualOverrideStore(defaults: defaults).applying(
                to: snapshot.sleepTrend,
                calendar: calendar
            )
            let sleepQualityByDay = Dictionary(
                uniqueKeysWithValues: effectiveSleepTrend.compactMap { entry in
                    entry.qualityScore.map {
                        (LocalDay(containing: entry.date, in: calendar.timeZone), $0)
                    }
                }
            )
            let period = DateInterval(start: dayStart, end: dayEnd)
            guard let timeline = AppleHealthAutomaticSleepFactorBuilder.stressTimeline(
                for: period,
                sessions: sessions,
                workouts: workouts,
                hrvSamples: hrvSamples,
                restingHeartRateSamples: restingHeartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples,
                sleepQualityByDay: sleepQualityByDay,
                calendar: calendar
            ) else {
                return nil
            }
            let overlappingSessions = sessions.filter {
                $0.startDate < dayEnd && $0.endDate > dayStart
            }
            let overlappingWorkouts = workouts.filter {
                $0.startDate < dayEnd && $0.endDate > dayStart
            }
            return AppleHealthStressDayTimeline(
                day: day,
                timeline: timeline,
                sleepSessions: overlappingSessions,
                workouts: overlappingWorkouts
            )
        } catch {
            return nil
        }
    }

    func consumePendingAuthorizationWarning() async -> Bool {
        guard isConfigured,
              let healthStore,
              !defaults.bool(forKey: Self.pendingAuthorizationWarningShownKey),
              (try? await authorizationRequestStatus(
                healthStore: healthStore,
                readTypes: readTypes
              )) == .shouldRequest else {
            return false
        }
        defaults.set(true, forKey: Self.pendingAuthorizationWarningShownKey)
        return true
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
            // Passive synchronizations never inspect or request newly added
            // permissions. Blood pressure becomes queryable only after the
            // person explicitly reviews authorization from Settings.
            let canQueryBloodPressure = hasReviewedBloodPressureAuthorization
                || requiresManualBloodPressureAuthorization
            try? await updateAvailableSources(
                from: healthStore,
                includingBloodPressure: canQueryBloodPressure
            )
            let sleepSessions = try await fetchSleepSessions(from: healthStore, endingAt: now)
            let currentCalendar = calendar
            let sleepTrend = await Task.detached(priority: .userInitiated) {
                AppleHealthBackgroundCalculations.sleepTrend(
                    sessions: sleepSessions,
                    endingAt: now,
                    calendar: currentCalendar
                )
            }.value
            let effectiveSleepTrend = SleepManualOverrideStore(defaults: defaults).applying(
                to: sleepTrend,
                calendar: calendar
            )
            let sleepQualityByDay = Dictionary(
                uniqueKeysWithValues: effectiveSleepTrend.compactMap { entry in
                    entry.qualityScore.map {
                        (LocalDay(containing: entry.date, in: calendar.timeZone), $0)
                    }
                }
            )
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
                ?? calendar.startOfDay(for: now)
            let todayStart = calendar.startOfDay(for: now)

            // HealthKit executes these independent queries in parallel. Each
            // task yields immediately while HealthKit reads its samples, so
            // neither the queries nor their wait time block touch handling.
            async let hrvTask: AppleHealthMeasurement? = try? await fetchLatestMeasurement(
                from: healthStore,
                identifier: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                since: calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
            )
            async let restingHeartRateTask: AppleHealthMeasurement? = try? await fetchLatestMeasurement(
                from: healthStore,
                identifier: .restingHeartRate,
                unit: .count().unitDivided(by: .minute()),
                since: calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
            )
            async let vo2MaxTask: AppleHealthMeasurement? = try? await fetchAverageMeasurement(
                from: healthStore,
                identifier: .vo2Max,
                unit: HKUnit(from: "ml/kg*min"),
                since: calendar.date(byAdding: .month, value: -3, to: now) ?? .distantPast,
                endingAt: now
            )
            async let bloodGlucoseTask: AppleHealthMeasurement? = try? await fetchLatestMeasurement(
                from: healthStore,
                identifier: .bloodGlucose,
                unit: HKUnit(from: "mg/dL"),
                since: calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast
            )
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)
                ?? .distantPast
            // Blood pressure is an optional BioAge enhancement. A user may
            // legitimately deny it while authorizing all other HealthKit data,
            // so its query must never fail the complete synchronization.
            let retainedSystolicBloodPressure = snapshot.systolicBloodPressureSixMonthAverage
            async let systolicBloodPressureTask: AppleHealthMeasurement? = {
                guard canQueryBloodPressure else {
                    // Keep the last authorized value until the person
                    // explicitly reviews the new permission in Settings.
                    return retainedSystolicBloodPressure
                }
                return try? await fetchAverageMeasurement(
                    from: healthStore,
                    identifier: .bloodPressureSystolic,
                    unit: HKUnit(from: "mmHg"),
                    since: sixMonthsAgo,
                    endingAt: now
                )
            }()
            async let stepsTask: Double? = try? await fetchCumulativeQuantity(
                from: healthStore,
                identifier: .stepCount,
                unit: .count(),
                start: todayStart,
                end: now
            )
            async let activeEnergyTask: Double? = try? await fetchCumulativeQuantity(
                from: healthStore,
                identifier: .activeEnergyBurned,
                unit: .kilocalorie(),
                start: todayStart,
                end: now
            )
            async let workoutsTask: [AppleHealthWorkout] = (try? await fetchWorkouts(
                from: healthStore,
                start: weekStart,
                end: now
            )) ?? []
            async let automaticSleepFactorHistoryTask = fetchAutomaticSleepFactorHistory(
                from: healthStore,
                sessions: sleepSessions,
                sleepQualityByDay: sleepQualityByDay,
                endingAt: now
            )
            let (
                hrv,
                restingHeartRate,
                vo2Max,
                bloodGlucose,
                systolicBloodPressure,
                steps,
                activeEnergy,
                workouts,
                automaticSleepFactorHistory
            ) = await (
                hrvTask,
                restingHeartRateTask,
                vo2MaxTask,
                bloodGlucoseTask,
                systolicBloodPressureTask,
                stepsTask,
                activeEnergyTask,
                workoutsTask,
                automaticSleepFactorHistoryTask
            )

            var updated = AppleHealthSnapshot(
                lastSyncedAt: now,
                latestSleepSession: sleepSessions.last,
                sleepTrend: sleepTrend,
                heartRateVariability: hrv,
                restingHeartRate: restingHeartRate,
                vo2Max: vo2Max,
                bloodGlucose: bloodGlucose,
                systolicBloodPressureSixMonthAverage: systolicBloodPressure,
                stepsToday: steps,
                activeEnergyKilocaloriesToday: activeEnergy,
                workoutsThisWeek: workouts,
                automaticSleepFactors: automaticSleepFactorHistory.factors,
                latestPreSleepStressTimeline: automaticSleepFactorHistory.latestStressTimeline,
                currentStressDetails: automaticSleepFactorHistory.currentStressDetails
            )
            updated.dateOfBirthComponents = try? healthStore.dateOfBirthComponents()
            updated.biologicalSex = readBiologicalSex(from: healthStore)
            snapshot = updated
            cache.save(updated)
            setState(.ready)
        } catch {
            setState(.failed)
            throw error
        }
    }

    static var authorizationReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth),
            HKObjectType.characteristicType(forIdentifier: .biologicalSex),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .respiratoryRate),
            HKObjectType.quantityType(forIdentifier: .vo2Max),
            HKObjectType.quantityType(forIdentifier: .bloodGlucose),
            // HealthKit exposes a single Blood Pressure authorization backed by
            // a correlation containing systolic and diastolic samples.
            HKObjectType.correlationType(forIdentifier: .bloodPressure),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .timeInDaylight)
        ].compactMap { $0 }.forEach { types.insert($0) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    /// Kept separate so previously connected people can explicitly receive
    /// the choice for the daylight-exposure type introduced later.
    static var daylightAuthorizationReadTypes: Set<HKObjectType> {
        guard let daylight = HKObjectType.quantityType(forIdentifier: .timeInDaylight) else {
            return []
        }
        return [daylight]
    }

    private var readTypes: Set<HKObjectType> {
        guard requiresManualBloodPressureAuthorization,
              let bloodPressure = HKObjectType.correlationType(
                forIdentifier: .bloodPressure
              ) else {
            return Self.authorizationReadTypes
        }
        return Self.authorizationReadTypes.subtracting([bloodPressure])
    }

    static func requiresManualBloodPressureAuthorization(
        for version: OperatingSystemVersion
    ) -> Bool {
        version.majorVersion == 26 && version.minorVersion == 5
    }

    private var hasReviewedBloodPressureAuthorization: Bool {
        get {
            defaults.bool(forKey: Self.bloodPressureAuthorizationReviewedKey)
        }
        set {
            defaults.set(
                newValue,
                forKey: Self.bloodPressureAuthorizationReviewedKey
            )
        }
    }

    static var sourceDiscoverySampleTypes: Set<HKSampleType> {
        var types = Set(
            authorizationReadTypes.compactMap { type -> HKSampleType? in
                guard let sampleType = type as? HKSampleType,
                      sampleType.identifier
                        != HKCorrelationTypeIdentifier.bloodPressure.rawValue else {
                    return nil
                }
                return sampleType
            }
        )
        [
            HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
            HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)
        ].compactMap { $0 }.forEach { types.insert($0) }
        return types
    }

    private func readBiologicalSex(from healthStore: HKHealthStore) -> AppleHealthBiologicalSex? {
        guard let biologicalSex = try? healthStore.biologicalSex().biologicalSex else {
            return nil
        }
        switch biologicalSex {
        case .female: return .female
        case .male: return .male
        case .other: return .other
        case .notSet: return .notSet
        @unknown default: return .notSet
        }
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

    private func authorizationRequestStatus(
        healthStore: HKHealthStore,
        readTypes: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(
                toShare: [],
                read: readTypes
            ) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func updateAvailableSources(
        from healthStore: HKHealthStore,
        includingBloodPressure: Bool
    ) async throws {
        let sampleTypes = Self.sourceDiscoverySampleTypes
            .filter { type in
                includingBloodPressure
                    || (
                        type.identifier
                            != HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue
                        && type.identifier
                            != HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue
                    )
            }
            .sorted { $0.identifier < $1.identifier }
        var catalog: [String: Set<HKSource>] = [:]
        var accumulators: [String: SourceAccumulator] = [:]

        for type in sampleTypes {
            // Source discovery is best effort. A denied optional type must not
            // prevent sleep, activity, heart, or workout data from syncing.
            guard let sources = try? await fetchSources(from: healthStore, type: type) else {
                continue
            }
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
             HKQuantityTypeIdentifier.respiratoryRate.rawValue,
             HKQuantityTypeIdentifier.vo2Max.rawValue,
             HKQuantityTypeIdentifier.bloodGlucose.rawValue,
             HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
             HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue,
             HKCorrelationTypeIdentifier.bloodPressure.rawValue:
            .heart
        case HKQuantityTypeIdentifier.stepCount.rawValue,
             HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.timeInDaylight.rawValue:
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
        startingAt startDate: Date = .distantPast,
        endingAt endDate: Date
    ) async throws -> [AppleHealthSleepSession] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let sourceFilter = sourceFilter(for: type)
        guard !sourceFilter.excludesAll else { return [] }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
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
        return await Task.detached(priority: .userInitiated) {
            AppleHealthBackgroundCalculations.sleepSessions(from: segments)
        }.value
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

    private func fetchAverageMeasurement(
        from healthStore: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        since startDate: Date,
        endingAt endDate: Date
    ) async throws -> AppleHealthMeasurement? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let sourceFilter = sourceFilter(for: type)
        guard !sourceFilter.excludesAll else { return nil }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: [.strictStartDate, .strictEndDate]
        )
        let predicate = applyingSourceFilter(sourceFilter, to: datePredicate)
        let average: Double? = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Double?, Error>) in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage]
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(
                        returning: statistics?.averageQuantity()?.doubleValue(for: unit)
                    )
                }
            }
            healthStore.execute(query)
        }
        guard let average else { return nil }
        return AppleHealthMeasurement(
            value: average,
            date: endDate,
            sourceName: "Apple Health"
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

    private func fetchAutomaticSleepFactorHistory(
        from healthStore: HKHealthStore,
        sessions: [AppleHealthSleepSession],
        sleepQualityByDay: [LocalDay: Double],
        endingAt endDate: Date
    ) async -> AppleHealthAutomaticSleepFactorHistory {
        guard let firstSession = sessions.min(by: { $0.startDate < $1.startDate }) else {
            return AppleHealthAutomaticSleepFactorHistory(
                factors: [],
                latestStressTimeline: nil
            )
        }
        let startDate = calendar.startOfDay(for: firstSession.startDate)
        let currentCalendar = calendar
        // These queries read different HealthKit types and are independent.
        // Starting them together both shortens the overall sync and avoids a
        // long sequence of resumptions on the main actor.
        async let stepsTask: [LocalDay: Double] = (try? await fetchDailyCumulativeQuantities(
            from: healthStore,
            identifier: .stepCount,
            unit: .count(),
            start: startDate,
            end: endDate
        )) ?? [:]
        async let daylightTask: [LocalDay: Double] = (try? await fetchDailyCumulativeQuantities(
            from: healthStore,
            identifier: .timeInDaylight,
            unit: .minute(),
            start: startDate,
            end: endDate
        )) ?? [:]
        async let workoutsTask: [AppleHealthWorkout] = (try? await fetchWorkouts(
            from: healthStore,
            start: startDate,
            end: endDate
        )) ?? []
        async let daylightSamplesTask: [AppleHealthTimedQuantity] = (try? await fetchTimedQuantities(
            from: healthStore,
            identifier: .timeInDaylight,
            unit: .minute(),
            start: startDate,
            end: endDate
        )) ?? []
        async let hrvSamplesTask: [AppleHealthTimedQuantity] = (try? await fetchTimedQuantities(
            from: healthStore,
            identifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            start: startDate,
            end: endDate
        )) ?? []
        async let restingHeartRateSamplesTask: [AppleHealthTimedQuantity] = (try? await fetchTimedQuantities(
            from: healthStore,
            identifier: .restingHeartRate,
            unit: .count().unitDivided(by: .minute()),
            start: startDate,
            end: endDate
        )) ?? []
        async let respiratoryRateSamplesTask: [AppleHealthTimedQuantity] = (try? await fetchTimedQuantities(
            from: healthStore,
            identifier: .respiratoryRate,
            unit: .count().unitDivided(by: .minute()),
            start: startDate,
            end: endDate
        )) ?? []
        let (
            steps,
            daylight,
            workouts,
            daylightSamples,
            hrvSamples,
            restingHeartRateSamples,
            respiratoryRateSamples
        ) = await (
            stepsTask,
            daylightTask,
            workoutsTask,
            daylightSamplesTask,
            hrvSamplesTask,
            restingHeartRateSamplesTask,
            respiratoryRateSamplesTask
        )
        return await Task.detached(priority: .userInitiated) {
            AppleHealthBackgroundCalculations.automaticSleepFactorHistory(
                sessions: sessions,
                stepsByDay: steps,
                workouts: workouts,
                daylightByDay: daylight,
                daylightSamples: daylightSamples,
                hrvSamples: hrvSamples,
                restingHeartRateSamples: restingHeartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples,
                sleepQualityByDay: sleepQualityByDay,
                calendar: currentCalendar,
                currentDate: endDate
            )
        }.value
    }

    private func fetchDailyCumulativeQuantities(
        from healthStore: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start startDate: Date,
        end endDate: Date
    ) async throws -> [LocalDay: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return [:]
        }
        let sourceFilter = sourceFilter(for: type)
        guard !sourceFilter.excludesAll else { return [:] }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: [.strictStartDate, .strictEndDate]
        )
        let predicate = applyingSourceFilter(sourceFilter, to: datePredicate)
        let anchorDate = calendar.startOfDay(for: startDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum],
                anchorDate: anchorDate,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { [calendar] _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [:])
                    return
                }
                var values: [LocalDay: Double] = [:]
                collection.enumerateStatistics(from: anchorDate, to: endDate) { statistics, _ in
                    guard let quantity = statistics.sumQuantity() else { return }
                    let day = LocalDay(containing: statistics.startDate, in: calendar.timeZone)
                    values[day] = quantity.doubleValue(for: unit)
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    private func fetchTimedQuantities(
        from healthStore: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start startDate: Date,
        end endDate: Date
    ) async throws -> [AppleHealthTimedQuantity] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            return []
        }
        let sourceFilter = sourceFilter(for: type)
        guard !sourceFilter.excludesAll else { return [] }
        let datePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: [.strictEndDate]
        )
        let predicate = applyingSourceFilter(sourceFilter, to: datePredicate)
        return try await fetchSamples(
            from: healthStore,
            type: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: true
            )]
        ).compactMap { sample in
            guard let quantitySample = sample as? HKQuantitySample else { return nil }
            return AppleHealthTimedQuantity(
                startDate: quantitySample.startDate,
                endDate: quantitySample.endDate,
                value: quantitySample.quantity.doubleValue(for: unit)
            )
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
