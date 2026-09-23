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
    /// Time between the beginning of the matching HealthKit `inBed` interval
    /// and the first asleep sample. It is unavailable when no reliable
    /// `inBed` interval contains the sleep onset.
    let sleepLatencySeconds: TimeInterval?
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
        sleepLatencySeconds: TimeInterval? = nil,
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
        self.sleepLatencySeconds = sleepLatencySeconds
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
        case sleepLatencySeconds
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
        sleepLatencySeconds = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .sleepLatencySeconds
        )
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
    /// Awake time explicitly reported anywhere within the sleep sessions for
    /// this day, including the beginning and end of each displayed session.
    let awakeHours: Double?
    /// Combined start-to-end duration of the displayed sleep sessions for this
    /// day. It is the denominator used with `awakeHours` for interruptions.
    let sleepPeriodHours: Double?
    /// Percentage decrease from the initial sleeping heart rate to the
    /// stable low heart rate reached later in the same main sleep session.
    let heartRateDropPercentage: Double?
    /// Mean 0–100 physiological StressScore estimated at evenly distributed
    /// points of the main sleep session. It remains optional when HealthKit
    /// does not provide enough data to produce a reliable estimate.
    let averageSleepStressScore: Double?
    /// Minutes from the start of the matching HealthKit `inBed` interval to
    /// the first asleep sample of the main sleep session.
    let sleepLatencyMinutes: Double?

    init(
        date: Date,
        hours: Double?,
        qualityScore: Double? = nil,
        remHours: Double? = nil,
        deepHours: Double? = nil,
        lightHours: Double? = nil,
        sleepStartDate: Date? = nil,
        awakeHours: Double? = nil,
        sleepPeriodHours: Double? = nil,
        heartRateDropPercentage: Double? = nil,
        averageSleepStressScore: Double? = nil,
        sleepLatencyMinutes: Double? = nil
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
        self.heartRateDropPercentage = heartRateDropPercentage
        self.averageSleepStressScore = averageSleepStressScore
        self.sleepLatencyMinutes = sleepLatencyMinutes
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
    /// Start date of the source session. It identifies the main session when
    /// multiple sessions finish on the same sleep day.
    var sleepSessionStartDate: Date? = nil
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
    /// Mean StressScore measured during this sleep session. This is separate
    /// from the pre-sleep score because it participates in sleep quality.
    var averageSleepStressScore: Double? = nil
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
    /// A recent ordinary heart-rate sample. This is kept separate from
    /// HealthKit's daily resting-heart-rate value so each signal can be
    /// normalized against a baseline made from the same kind of measurement.
    var heartRate: Double? = nil
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
    /// `true` when `restingHeartRate` contains the detail generated from
    /// ordinary heart-rate samples rather than HealthKit's daily RHR.
    var usesInstantaneousHeartRate: Bool? = nil
    /// Sleep observations already combine phase-matched standardized
    /// biomarkers, so they use the nocturnal calibration directly instead of
    /// normalizing that composite a second time.
    var usesSleepCalibration: Bool? = nil
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

    /// The value users currently see at the right edge of the chart. Keeping
    /// this selection in the model prevents summary labels from accidentally
    /// showing the separate, unsmoothed calculation detail.
    var latestScoredPoint: AppleHealthStressTimelinePoint? {
        points.last { $0.score != nil }
    }
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
    /// A phase-matched, physiologically typical sleep observation represents
    /// relaxation rather than medium daytime stress.
    static let sleepNeutralScore = 20.0
    private static let sleepLogisticIntercept = log(
        sleepNeutralScore / (100 - sleepNeutralScore)
    )

    static func scores(
        for observations: [AppleHealthStressObservation],
        calendar: Calendar
    ) -> [Date: Double] {
        details(for: observations, calendar: calendar).compactMapValues(\.score)
    }

    static func detail(
        for observation: AppleHealthStressObservation,
        historicalObservations: [AppleHealthStressObservation],
        historicalComposites: [(date: Date, value: Double)],
        calendar: Calendar
    ) -> AppleHealthStressCalculationDetails {
        let start = calendar.date(byAdding: .day, value: -baselineDays, to: observation.date) ?? .distantPast
        let historical = historicalObservations.filter {
            $0.date >= start && $0.date < observation.date
        }
        let hrvBaseline = historical.compactMap(\.heartRateVariability)
        let restingHeartRateBaseline = historical.compactMap(\.restingHeartRate)
        let heartRateBaseline = historical.compactMap(\.heartRate)
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
        let usesInstantaneousHeartRate = observation.heartRate != nil
        let heartRate = metricDetails(
            value: usesInstantaneousHeartRate
                ? observation.heartRate
                : observation.restingHeartRate,
            baseline: usesInstantaneousHeartRate
                ? heartRateBaseline
                : restingHeartRateBaseline,
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
                                     let heartRateContribution = heartRate.contribution {
            hrvContribution
                + heartRateContribution
                + (respiratoryRate.contribution ?? 0)
                + (sleepQuality.contribution ?? 0)
        } else {
            nil
        }

        let historicalComposite = historicalComposites
            .filter { $0.date >= start && $0.date < observation.date }
            .map(\.value)
        let compositeStats = robustStatistics(composite, baseline: historicalComposite)
        let score = compositeStats?.zScore.map { logisticScore($0) }
        return AppleHealthStressCalculationDetails(
            date: observation.date,
            heartRateVariability: hrv,
            restingHeartRate: heartRate,
            respiratoryRate: respiratoryRate,
            sleepQuality: sleepQuality,
            hadActivityInPreviousTwoHours: observation.hadActivityInPreviousTwoHours,
            compositeIndex: composite,
            compositeBaselineMedian: compositeStats?.median,
            compositeBaselineMAD: compositeStats?.mad,
            compositeZScore: compositeStats?.zScore,
            score: score,
            usesInstantaneousHeartRate: usesInstantaneousHeartRate
        )
    }

    /// A nocturnal composite is already a weighted combination of
    /// phase-matched biomarker z-scores. Applying another robust z-score makes
    /// tiny night-to-night differences look like large absolute activation.
    /// The contextual intercept maps an ordinary sleeping state to 20/100.
    static func calibratedForSleep(
        _ details: AppleHealthStressCalculationDetails
    ) -> AppleHealthStressCalculationDetails {
        let score = details.compositeIndex.map {
            logisticScore($0, intercept: sleepLogisticIntercept)
        }
        return AppleHealthStressCalculationDetails(
            date: details.date,
            heartRateVariability: details.heartRateVariability,
            restingHeartRate: details.restingHeartRate,
            respiratoryRate: details.respiratoryRate,
            sleepQuality: details.sleepQuality,
            hadActivityInPreviousTwoHours: details.hadActivityInPreviousTwoHours,
            compositeIndex: details.compositeIndex,
            compositeBaselineMedian: details.compositeBaselineMedian,
            compositeBaselineMAD: details.compositeBaselineMAD,
            compositeZScore: details.compositeZScore,
            score: score,
            usesInstantaneousHeartRate: details.usesInstantaneousHeartRate,
            usesSleepCalibration: true
        )
    }

    static func details(
        for observations: [AppleHealthStressObservation],
        calendar: Calendar
    ) -> [Date: AppleHealthStressCalculationDetails] {
        let ordered = observations.sorted { $0.date < $1.date }
        var compositeHistory: [(date: Date, value: Double)] = []
        var result: [Date: AppleHealthStressCalculationDetails] = [:]

        for observation in ordered {
            let historical = ordered.filter { $0.date < observation.date }
            let historicalComposites = compositeHistory.filter { $0.date < observation.date }
            let detailResult = detail(
                for: observation,
                historicalObservations: historical,
                historicalComposites: historicalComposites,
                calendar: calendar
            )
            result[observation.date] = detailResult

            if let composite = detailResult.compositeIndex {
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
            let difference = value - baselineMedian
            if abs(difference) <= 0.000_001 {
                zScore = 0
            } else {
                // A zero MAD provides no defensible scale for a non-zero
                // difference. Saturating to ±3 would turn even a one-unit
                // change into the maximum possible deviation.
                zScore = nil
            }
        }
        return RobustStatistics(median: baselineMedian, mad: mad, zScore: zScore)
    }

    private static func logisticScore(
        _ input: Double,
        intercept: Double = 0
    ) -> Double {
        min(max(
            100 / (1 + exp(-(intercept + logisticSensitivity * input))),
            0
        ), 100)
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
    private static let dailyMetricMaximumAge: TimeInterval = 36 * 3_600
    private static let realtimeHRVMaximumAge: TimeInterval = 12 * 3_600
    private static let heartRateMaximumAge: TimeInterval = 30 * 60

    static func build(
        sessions: [AppleHealthSleepSession],
        stepsByDay: [LocalDay: Double],
        workouts: [AppleHealthWorkout],
        daylightByDay: [LocalDay: Double],
        daylightSamples: [AppleHealthTimedQuantity],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity] = [],
        heartRateSamples: [AppleHealthTimedQuantity] = [],
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
            heartRateSamples: heartRateSamples,
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
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        heartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        sleepQualityByDay: [LocalDay: Double],
        calendar: Calendar,
        currentDate: Date = Date()
    ) -> AppleHealthAutomaticSleepFactorHistory {
        let orderedSessions = sessions.sorted { $0.endDate < $1.endDate }
        let stressObservations = makeStressObservations(
            sessions: orderedSessions,
            workouts: workouts,
            hrvSamples: hrvSamples,
            restingHeartRateSamples: restingHeartRateSamples,
            heartRateSamples: heartRateSamples,
            respiratoryRateSamples: respiratoryRateSamples,
            sleepQualityByDay: sleepQualityByDay,
            calendar: calendar
        )
        let stressDetails = AppleHealthStressScoreCalculator.details(
            for: stressObservations,
            calendar: calendar
        )
        let stressScores = stressDetails.compactMapValues(\.score)
        let averageSleepStressBySession = averageSleepStressScores(
            for: orderedSessions,
            workouts: workouts,
            hrvSamples: hrvSamples,
            restingHeartRateSamples: restingHeartRateSamples,
            heartRateSamples: heartRateSamples,
            respiratoryRateSamples: respiratoryRateSamples,
            sleepQualityByDay: sleepQualityByDay,
            calendar: calendar
        )

        let factors = orderedSessions.enumerated().map { index, session in
            let sleepDate = calendar.startOfDay(for: session.endDate)
            let activityDay = LocalDay(containing: session.startDate, in: calendar.timeZone)
            let previousWake = index > 0 ? orderedSessions[index - 1].endDate : nil
            let hasStrengthTraining = workouts.contains {
                    $0.kind == .strength
                        && LocalDay(containing: $0.startDate, in: calendar.timeZone) == activityDay
                        && $0.startDate < session.startDate
                }

            // Daylight after waking and total daylight must refer to the same
            // calendar day. Using the sleep start date breaks that relationship
            // for nights that begin after midnight.
            let daylightDay = previousWake.map {
                LocalDay(containing: $0, in: calendar.timeZone)
            } ?? activityDay
            let daylightMinutes = daylightByDay[daylightDay]
            let earlyDaylight: Double?
            if let previousWake {
                let earlyWindowEnd = previousWake.addingTimeInterval(2 * 3_600)
                let daylightInEarlyWindow = summedQuantity(
                    daylightSamples,
                    from: previousWake,
                    through: earlyWindowEnd
                )
                // The two-hour window is part of the daily total. In case
                // HealthKit's aggregate and individual samples disagree, keep
                // the presentation internally consistent.
                if let daylightInEarlyWindow, let daylightMinutes {
                    earlyDaylight = min(daylightInEarlyWindow, daylightMinutes)
                } else {
                    earlyDaylight = daylightInEarlyWindow
                }
            } else {
                earlyDaylight = nil
            }

            return AppleHealthAutomaticSleepFactors(
                date: sleepDate,
                sleepSessionStartDate: session.startDate,
                steps: stepsByDay[activityDay],
                strengthTrainingMinutes: hasStrengthTraining ? 1 : 0,
                daylightMinutes: daylightMinutes,
                earlyDaylightMinutes: earlyDaylight,
                preSleepStressScore: stressScores[session.startDate],
                averageSleepStressScore: averageSleepStressBySession[session.startDate],
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
                heartRateSamples: heartRateSamples,
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
                heartRateSamples: heartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples,
                sleepQualityByDay: sleepQualityByDay,
                calendar: calendar
            )
        )
    }

    /// Samples four equally spaced portions of each qualifying sleep session.
    /// For every portion, the score is calibrated against the same relative
    /// sleep phase in earlier sessions, then the valid estimates are averaged.
    /// This keeps the mean representative of the whole night without turning
    /// a synchronization into one full stress-timeline calculation per sample.
    private static func averageSleepStressScores(
        for sessions: [AppleHealthSleepSession],
        workouts: [AppleHealthWorkout],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        heartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        sleepQualityByDay: [LocalDay: Double],
        calendar: Calendar
    ) -> [Date: Double] {
        let minimumComparableSleepDuration: TimeInterval = 2 * 3_600
        let qualifyingSessions = sessions.filter {
            $0.endDate.timeIntervalSince($0.startDate) >= minimumComparableSleepDuration
        }
        let sampleProgresses = [0.125, 0.375, 0.625, 0.875]
        var scoresBySession: [Date: [Double]] = [:]

        for progress in sampleProgresses {
            let observations = qualifyingSessions.map { session -> AppleHealthStressObservation in
                let duration = session.endDate.timeIntervalSince(session.startDate)
                let date = session.startDate.addingTimeInterval(duration * progress)
                return makeStressObservation(
                    at: date,
                    sleepQuality: sleepQualityByDay[
                        LocalDay(containing: session.endDate, in: calendar.timeZone)
                    ],
                    workouts: workouts,
                    hrvSamples: hrvSamples,
                    restingHeartRateSamples: restingHeartRateSamples,
                    heartRateSamples: heartRateSamples,
                    respiratoryRateSamples: respiratoryRateSamples,
                    usesRealtimeInputs: true
                )
            }
            let details = AppleHealthStressScoreCalculator.details(
                for: observations,
                calendar: calendar
            )
            for (session, observation) in zip(qualifyingSessions, observations) {
                guard let detail = details[observation.date],
                      let score = AppleHealthStressScoreCalculator
                          .calibratedForSleep(detail).score,
                      score.isFinite else {
                    continue
                }
                scoresBySession[session.startDate, default: []].append(
                    min(max(score, 0), 100)
                )
            }
        }

        return scoresBySession.compactMapValues { scores in
            guard !scores.isEmpty else { return nil }
            return scores.reduce(0, +) / Double(scores.count)
        }
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
        heartRateSamples: [AppleHealthTimedQuantity],
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
            heartRateSamples: heartRateSamples,
            respiratoryRateSamples: respiratoryRateSamples,
            sleepQualityByDay: sleepQualityByDay,
            calendar: calendar
        )
        let sampledHeartRates = sampleTimedQuantities(heartRateSamples, interval: 10 * 60)
        let measurementDates = Set((
            hrvSamples + restingHeartRateSamples + sampledHeartRates + respiratoryRateSamples
        )
        .map(\.endDate)
        .filter { $0 >= period.start && $0 <= period.end })
        let initialDates = Array(measurementDates.union([period.start])).sorted()
        var datesWithGaps = initialDates
        let wearDates = heartRateSamples.map(\.endDate).filter { $0 >= period.start && $0 <= period.end }.sorted()
        for i in wearDates.indices.dropFirst() {
            let previous = wearDates[i - 1]
            let current = wearDates[i]
            if current.timeIntervalSince(previous) > 4 * 3600 {
                datesWithGaps.append(previous.addingTimeInterval(current.timeIntervalSince(previous) / 2))
            }
        }
        if let firstWear = wearDates.first, firstWear.timeIntervalSince(period.start) > 4 * 3600 {
            datesWithGaps.append(period.start.addingTimeInterval(firstWear.timeIntervalSince(period.start) / 2))
        }
        if let lastWear = wearDates.last, period.end.timeIntervalSince(lastWear) > 4 * 3600 {
            datesWithGaps.append(lastWear.addingTimeInterval(period.end.timeIntervalSince(lastWear) / 2))
        }
        if wearDates.isEmpty {
            datesWithGaps.append(period.start.addingTimeInterval(period.end.timeIntervalSince(period.start) / 2))
        }
        let dates = Array(Set(datesWithGaps)).sorted()
        let precalculatedHistoricalDetails = AppleHealthStressScoreCalculator.details(
            for: observations,
            calendar: calendar
        )
        let precalculatedComposites = precalculatedHistoricalDetails.compactMap { key, value in
            value.compositeIndex.map { (date: key, value: $0) }
        }.sorted { $0.date < $1.date }

        let points = dates.map { date -> AppleHealthStressTimelinePoint in
            guard measurementDates.contains(date) else {
                return AppleHealthStressTimelinePoint(date: date, score: nil)
            }
            let detail = makeTimelineStressDetail(
                at: date,
                sessions: orderedSessions,
                historicalObservations: observations,
                historicalComposites: precalculatedComposites,
                workouts: workouts,
                hrvSamples: hrvSamples,
                restingHeartRateSamples: restingHeartRateSamples,
                heartRateSamples: heartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples,
                sleepQualityByDay: sleepQualityByDay,
                calendar: calendar
            )
            return AppleHealthStressTimelinePoint(date: date, score: detail.score)
        }
        return AppleHealthStressTimeline(sleepStartDate: period.start, points: smoothTimelinePoints(points))
    }

    private static func makeStressObservations(
        sessions: [AppleHealthSleepSession],
        workouts: [AppleHealthWorkout],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        heartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        sleepQualityByDay: [LocalDay: Double],
        calendar: Calendar
    ) -> [AppleHealthStressObservation] {
        return sessions.enumerated().map { index, session in
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
                heartRateSamples: heartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples,
                usesRealtimeInputs: false
            )
        }
    }

    private static func makeStressObservation(
        at date: Date,
        sleepQuality: Double?,
        workouts: [AppleHealthWorkout],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        heartRateSamples: [AppleHealthTimedQuantity] = [],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        usesRealtimeInputs: Bool = false
    ) -> AppleHealthStressObservation {
        AppleHealthStressObservation(
            date: date,
            // HealthKit does not guarantee an HRV reading in the exact
            // pre-bed hour. The admissible age depends on whether this is a
            // daily retrospective or a real-time calculation.
            heartRateVariability: latestQuantity(
                hrvSamples,
                before: date,
                maximumAge: usesRealtimeInputs
                    ? realtimeHRVMaximumAge
                    : dailyMetricMaximumAge
            ),
            restingHeartRate: latestQuantity(
                restingHeartRateSamples,
                before: date,
                maximumAge: dailyMetricMaximumAge
            ),
            heartRate: latestQuantity(
                heartRateSamples,
                before: date,
                maximumAge: heartRateMaximumAge
            ),
            respiratoryRate: latestQuantity(
                respiratoryRateSamples,
                before: date,
                maximumAge: dailyMetricMaximumAge
            ),
            sleepQuality: sleepQuality,
            hadActivityInPreviousTwoHours: workouts.contains {
                $0.startDate < date
                    && $0.endDate > date.addingTimeInterval(-2 * 3_600)
            }
        )
    }

    private static func sampleTimedQuantities(
        _ samples: [AppleHealthTimedQuantity],
        interval: TimeInterval
    ) -> [AppleHealthTimedQuantity] {
        let sorted = samples.sorted { $0.endDate < $1.endDate }
        var result: [AppleHealthTimedQuantity] = []
        var lastDate: Date? = nil
        for s in sorted {
            if let last = lastDate {
                if s.endDate.timeIntervalSince(last) >= interval {
                    result.append(s)
                    lastDate = s.endDate
                }
            } else {
                result.append(s)
                lastDate = s.endDate
            }
        }
        return result
    }

    private static func smoothTimelinePoints(_ points: [AppleHealthStressTimelinePoint]) -> [AppleHealthStressTimelinePoint] {
        guard points.count > 2 else { return points }
        var smoothed: [AppleHealthStressTimelinePoint] = []
        for i in 0..<points.count {
            let p = points[i]
            guard let currentScore = p.score else {
                smoothed.append(p)
                continue
            }
            var windowScores: [Double] = [currentScore]
            if i > 0, let prev = points[i - 1].score {
                windowScores.append(prev)
            }
            if i < points.count - 1, let next = points[i + 1].score {
                windowScores.append(next)
            }
            let avg = windowScores.reduce(0, +) / Double(windowScores.count)
            smoothed.append(AppleHealthStressTimelinePoint(date: p.date, score: avg))
        }
        return smoothed
    }

    private static func makeLatestStressTimeline(
        sessions: [AppleHealthSleepSession],
        historicalObservations: [AppleHealthStressObservation],
        workouts: [AppleHealthWorkout],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        heartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        sleepQualityByDay: [LocalDay: Double],
        calendar: Calendar,
        currentDate: Date
    ) -> AppleHealthStressTimeline? {
        guard let latestSession = sessions.last, currentDate >= latestSession.startDate else {
            return nil
        }
        let periodStart = latestSession.startDate.addingTimeInterval(-3_600)
        let sampledHeartRates = sampleTimedQuantities(heartRateSamples, interval: 10 * 60)
        let measurementDates = Set((
            hrvSamples + restingHeartRateSamples + sampledHeartRates + respiratoryRateSamples
        )
        .map(\.endDate)
        .filter { $0 >= periodStart && $0 <= currentDate }
        + [currentDate])
        let initialDates = Array(
            measurementDates.union([periodStart, latestSession.startDate, currentDate])
        ).sorted()
        var datesWithGaps = initialDates
        let wearDates = heartRateSamples.map(\.endDate).filter { $0 >= periodStart && $0 <= currentDate }.sorted()
        for i in wearDates.indices.dropFirst() {
            let previous = wearDates[i - 1]
            let current = wearDates[i]
            if current.timeIntervalSince(previous) > 4 * 3600 {
                datesWithGaps.append(previous.addingTimeInterval(current.timeIntervalSince(previous) / 2))
            }
        }
        if let firstWear = wearDates.first, firstWear.timeIntervalSince(periodStart) > 4 * 3600 {
            datesWithGaps.append(periodStart.addingTimeInterval(firstWear.timeIntervalSince(periodStart) / 2))
        }
        if let lastWear = wearDates.last, currentDate.timeIntervalSince(lastWear) > 4 * 3600 {
            datesWithGaps.append(lastWear.addingTimeInterval(currentDate.timeIntervalSince(lastWear) / 2))
        }
        if wearDates.isEmpty {
            datesWithGaps.append(periodStart.addingTimeInterval(currentDate.timeIntervalSince(periodStart) / 2))
        }
        let dates = Array(Set(datesWithGaps)).sorted()
        let precalculatedHistoricalDetails = AppleHealthStressScoreCalculator.details(
            for: historicalObservations,
            calendar: calendar
        )
        let precalculatedComposites = precalculatedHistoricalDetails.compactMap { key, value in
            value.compositeIndex.map { (date: key, value: $0) }
        }.sorted { $0.date < $1.date }

        let points = dates.map { date -> AppleHealthStressTimelinePoint in
            guard measurementDates.contains(date) else {
                // The empty points and gap markers keep the real time scale intact
                // and break the lines when there's no continuous data.
                return AppleHealthStressTimelinePoint(date: date, score: nil)
            }
            let detail = makeTimelineStressDetail(
                at: date,
                sessions: sessions,
                historicalObservations: historicalObservations,
                historicalComposites: precalculatedComposites,
                workouts: workouts,
                hrvSamples: hrvSamples,
                restingHeartRateSamples: restingHeartRateSamples,
                heartRateSamples: heartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples,
                sleepQualityByDay: sleepQualityByDay,
                calendar: calendar
            )
            return AppleHealthStressTimelinePoint(date: date, score: detail.score)
        }
        return AppleHealthStressTimeline(
            sleepStartDate: latestSession.startDate,
            points: smoothTimelinePoints(points)
        )
    }

    /// Uses sleep observations only when the requested point falls inside a
    /// sleep session. A point halfway through the current night is compared
    /// with points halfway through previous nights, instead of with the
    /// pre-bed physiological baseline used by the sleep-factor model.
    private static func makeTimelineStressDetail(
        at date: Date,
        sessions: [AppleHealthSleepSession],
        historicalObservations: [AppleHealthStressObservation],
        historicalComposites: [(date: Date, value: Double)],
        workouts: [AppleHealthWorkout],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        heartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        sleepQualityByDay: [LocalDay: Double],
        calendar: Calendar
    ) -> AppleHealthStressCalculationDetails {
        if let sleepSession = sessions.last(where: {
            $0.startDate <= date && date <= $0.endDate
        }),
           let sleepDetail = makeSleepStressDetail(
            at: date,
            in: sleepSession,
            sessions: sessions,
            workouts: workouts,
            hrvSamples: hrvSamples,
            restingHeartRateSamples: restingHeartRateSamples,
            heartRateSamples: heartRateSamples,
            respiratoryRateSamples: respiratoryRateSamples,
            sleepQualityByDay: sleepQualityByDay,
            calendar: calendar
           ) {
            return sleepDetail
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
            heartRateSamples: heartRateSamples,
            respiratoryRateSamples: respiratoryRateSamples,
            usesRealtimeInputs: true
        )
        return AppleHealthStressScoreCalculator.detail(
            for: observation,
            historicalObservations: historicalObservations.filter { $0.date < date },
            historicalComposites: historicalComposites.filter { $0.date < date },
            calendar: calendar
        )
    }

    private static func makeSleepStressDetail(
        at date: Date,
        in sleepSession: AppleHealthSleepSession,
        sessions: [AppleHealthSleepSession],
        workouts: [AppleHealthWorkout],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        heartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        sleepQualityByDay: [LocalDay: Double],
        calendar: Calendar
    ) -> AppleHealthStressCalculationDetails? {
        let targetDuration = sleepSession.endDate.timeIntervalSince(sleepSession.startDate)
        guard targetDuration > 0 else { return nil }
        let sleepProgress = min(max(
            date.timeIntervalSince(sleepSession.startDate) / targetDuration,
            0
        ), 1)
        let minimumComparableSleepDuration: TimeInterval = 2 * 3_600
        let historicalSessions = sessions
            .filter {
                $0.endDate <= sleepSession.startDate
                    && $0.asleepSeconds >= minimumComparableSleepDuration
            }
            .sorted { $0.endDate < $1.endDate }

        let historicalSleepObservations = historicalSessions.map { session in
            let duration = max(session.endDate.timeIntervalSince(session.startDate), 0)
            let referenceDate = session.startDate.addingTimeInterval(duration * sleepProgress)
            return makeStressObservation(
                at: referenceDate,
                sleepQuality: sleepQualityByDay[
                    LocalDay(containing: session.endDate, in: calendar.timeZone)
                ],
                workouts: workouts,
                hrvSamples: hrvSamples,
                restingHeartRateSamples: restingHeartRateSamples,
                heartRateSamples: heartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples,
                usesRealtimeInputs: true
            )
        }
        let currentObservation = makeStressObservation(
            at: date,
            sleepQuality: sleepQualityByDay[
                LocalDay(containing: sleepSession.endDate, in: calendar.timeZone)
            ],
            workouts: workouts,
            hrvSamples: hrvSamples,
            restingHeartRateSamples: restingHeartRateSamples,
            heartRateSamples: heartRateSamples,
            respiratoryRateSamples: respiratoryRateSamples,
            usesRealtimeInputs: true
        )
        guard let relativeDetails = AppleHealthStressScoreCalculator.details(
            for: historicalSleepObservations + [currentObservation],
            calendar: calendar
        )[date] else {
            return nil
        }
        return AppleHealthStressScoreCalculator.calibratedForSleep(relativeDetails)
    }

    private static func makeCurrentStressDetails(
        at date: Date,
        historicalObservations: [AppleHealthStressObservation],
        sessions: [AppleHealthSleepSession],
        workouts: [AppleHealthWorkout],
        hrvSamples: [AppleHealthTimedQuantity],
        restingHeartRateSamples: [AppleHealthTimedQuantity],
        heartRateSamples: [AppleHealthTimedQuantity],
        respiratoryRateSamples: [AppleHealthTimedQuantity],
        sleepQualityByDay: [LocalDay: Double],
        calendar: Calendar
    ) -> AppleHealthStressCalculationDetails? {
        let historicalDetails = AppleHealthStressScoreCalculator.details(
            for: historicalObservations,
            calendar: calendar
        )
        let historicalComposites = historicalDetails.compactMap { key, value in
            value.compositeIndex.map { (date: key, value: $0) }
        }.sorted { $0.date < $1.date }
        return makeTimelineStressDetail(
            at: date,
            sessions: sessions,
            historicalObservations: historicalObservations,
            historicalComposites: historicalComposites,
            workouts: workouts,
            hrvSamples: hrvSamples,
            restingHeartRateSamples: restingHeartRateSamples,
            heartRateSamples: heartRateSamples,
            respiratoryRateSamples: respiratoryRateSamples,
            sleepQualityByDay: sleepQualityByDay,
            calendar: calendar
        )
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
        var low = 0
        var high = samples.count - 1
        var resultIndex: Int? = nil
        
        while low <= high {
            let mid = low + (high - low) / 2
            if samples[mid].startDate <= date {
                resultIndex = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        
        guard let idx = resultIndex else { return nil }
        
        var i = idx
        var bestSample: AppleHealthTimedQuantity? = nil
        while i >= 0 {
            let sample = samples[i]
            if sample.endDate <= date {
                // Since there might be slight overlaps, we check up to 5 elements backwards
                // to find the absolute max endDate just to be completely safe and match previous behavior.
                if bestSample == nil || sample.endDate > bestSample!.endDate {
                    bestSample = sample
                }
            }
            // If we've gone backwards and the end date is way too old, no need to keep checking
            if let best = bestSample, date.timeIntervalSince(best.endDate) <= maximumAge {
                if idx - i > 5 { break }
            } else if date.timeIntervalSince(sample.endDate) > maximumAge + 3600 {
                break
            }
            i -= 1
        }
        
        guard let latest = bestSample, date.timeIntervalSince(latest.endDate) <= maximumAge else {
            return nil
        }
        return latest.value
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
    /// Bundle identifier shared by revisions of the same producer. Older
    /// preferences used this value directly as the source identifier.
    var sourceBundleIdentifier: String? = nil

    var id: String { identifier }
}

enum AppleHealthSourceIdentity {
    private static let separator = "::"

    static func identifier(bundleIdentifier: String, name: String) -> String {
        "\(bundleIdentifier)\(separator)\(name)"
    }

    static func identifier(for source: HKSource) -> String {
        identifier(bundleIdentifier: source.bundleIdentifier, name: source.name)
    }
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

struct FitnessMaximumHeartRateEstimate: Equatable, Sendable {
    let value: Int
    let usesFullProfile: Bool
}

enum FitnessMaximumHeartRateEstimator {
    static func estimate(
        snapshot: AppleHealthSnapshot,
        restingHeartRate: Double?,
        referenceDate: Date = Date()
    ) -> FitnessMaximumHeartRateEstimate {
        let calendar = Calendar.autoupdatingCurrent
        let age: Int?
        if let components = snapshot.dateOfBirthComponents,
           let birthDate = calendar.date(from: components),
           let years = calendar.dateComponents([.year], from: birthDate, to: referenceDate).year,
           (12...110).contains(years) {
            age = years
        } else {
            age = nil
        }
        let sex = snapshot.biologicalSex
        let hasSex = sex == .female || sex == .male
        let validRestingHeartRate = restingHeartRate.flatMap { value in
            (35...100).contains(value) ? value : nil
        }

        let ageBasedMaximum: Double
        if let age {
            switch sex {
            case .some(.male):
                ageBasedMaximum = 211 - (0.64 * Double(age))
            case .some(.female):
                ageBasedMaximum = 206 - (0.88 * Double(age))
            default:
                ageBasedMaximum = 208 - (0.7 * Double(age))
            }
        } else {
            ageBasedMaximum = 185
        }

        // Heart-rate maximum is driven mainly by age. The resting-rate adjustment
        // is deliberately small, so it personalizes the estimate without turning
        // it into a clinical measurement.
        let restingRateAdjustment = validRestingHeartRate.map { (65 - $0) * 0.2 } ?? 0
        let value = Int((ageBasedMaximum + restingRateAdjustment).rounded())
        return FitnessMaximumHeartRateEstimate(
            value: min(max(value, FitnessMaximumHeartRatePreferences.supportedRange.lowerBound), FitnessMaximumHeartRatePreferences.supportedRange.upperBound),
            usesFullProfile: age != nil && hasSex && validRestingHeartRate != nil
        )
    }
}

struct FitnessMaximumHeartRatePreferences {
    static let supportedRange = 120...230

    private let defaults: UserDefaults
    private let manualMaximumKey: String

    init(
        defaults: UserDefaults = .standard,
        manualMaximumKey: String = "wellnario.fitness.manualMaximumHeartRate.v1"
    ) {
        self.defaults = defaults
        self.manualMaximumKey = manualMaximumKey
    }

    var manualMaximumHeartRate: Int? {
        guard defaults.object(forKey: manualMaximumKey) != nil else { return nil }
        let value = defaults.integer(forKey: manualMaximumKey)
        return Self.supportedRange.contains(value) ? value : nil
    }

    func setManualMaximumHeartRate(_ value: Int) {
        guard Self.supportedRange.contains(value) else { return }
        defaults.set(value, forKey: manualMaximumKey)
    }

    func resetToAutomaticEstimate() {
        defaults.removeObject(forKey: manualMaximumKey)
    }
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
    /// Version of the logic used to calculate the sleep factors. Used to
    /// invalidate the cache and force a recalculation when metrics change.
    var automaticSleepFactorsVersion: Int? = nil
    /// Version of the nocturnal heart-rate-drop algorithm used by the cached
    /// values and processed-day ledger.
    var heartRateDropCalculationVersion: Int? = nil
    /// Days for which HealthKit heart-rate data has already been inspected,
    /// including days where there were not enough samples to calculate a drop.
    var heartRateDropProcessedDays: [LocalDay]? = nil
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
        automaticSleepFactors: [],
        automaticSleepFactorsVersion: nil,
        latestPreSleepStressTimeline: nil,
        currentStressDetails: nil
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
    func heartRateSamples(from startDate: Date, through endDate: Date) async -> [AppleHealthTimedQuantity]
    func restingHeartRateSamples(from startDate: Date, through endDate: Date) async -> [AppleHealthTimedQuantity]
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
    func heartRateSamples(from startDate: Date, through endDate: Date) async -> [AppleHealthTimedQuantity] { [] }
    func restingHeartRateSamples(from startDate: Date, through endDate: Date) async -> [AppleHealthTimedQuantity] { [] }
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

    /// Expands the old bundle-wide exclusions into the source identities now
    /// shown by the app. This keeps an existing "Oura only" choice intact when
    /// older Apple Watch or iPhone sources become visible again.
    func migratingLegacyDisabledSourceSelections(
        _ selections: Set<AppleHealthSourceSelection>,
        to sources: [AppleHealthDataSource]
    ) -> Set<AppleHealthSourceSelection> {
        var migrated = selections
        for selection in selections {
            let matches = sources.filter {
                $0.sourceBundleIdentifier == selection.sourceIdentifier
                    && $0.dataKinds.contains(selection.dataKind)
            }
            guard !matches.isEmpty else { continue }
            migrated.remove(selection)
            migrated.formUnion(matches.map {
                AppleHealthSourceSelection(
                    sourceIdentifier: $0.identifier,
                    dataKind: selection.dataKind
                )
            })
        }
        return migrated
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
    let heartRateDrop: Int
    let sleepStress: Int
    let remDeepSleep: Int
    let sleepLatency: Int

    init(
        duration: Int,
        regularity: Int,
        interruptions: Int,
        heartRateDrop: Int = 0,
        sleepStress: Int = 0,
        remDeepSleep: Int = 0,
        sleepLatency: Int = 0
    ) {
        self.duration = duration
        self.regularity = regularity
        self.interruptions = interruptions
        self.heartRateDrop = heartRateDrop
        self.sleepStress = sleepStress
        self.remDeepSleep = remDeepSleep
        self.sleepLatency = sleepLatency
    }

    static let `default` = SleepQualityWeights(
        duration: 46,
        regularity: 6,
        interruptions: 14,
        heartRateDrop: 7,
        sleepStress: 8,
        remDeepSleep: 9,
        sleepLatency: 10
    )

    var isValid: Bool {
        duration >= 0
            && regularity >= 0
            && interruptions >= 0
            && heartRateDrop >= 0
            && sleepStress >= 0
            && remDeepSleep >= 0
            && sleepLatency >= 0
            && duration + regularity + interruptions + heartRateDrop
                + sleepStress + remDeepSleep + sleepLatency == 100
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
    private let heartRateDropWeightKey = "wellnario.sleep.quality.heartRateDropWeight.v1"
    private let sleepStressWeightKey = "wellnario.sleep.quality.sleepStressWeight.v1"
    private let remDeepSleepWeightKey = "wellnario.sleep.quality.remDeepSleepWeight.v1"
    private let sleepLatencyWeightKey = "wellnario.sleep.quality.sleepLatencyWeight.v1"
    private let customTargetKey = "wellnario.sleep.quality.customTargetHours.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var weights: SleepQualityWeights {
        let baseWeightKeys = [durationWeightKey, regularityWeightKey, interruptionWeightKey]
        guard baseWeightKeys.allSatisfy({ defaults.object(forKey: $0) != nil }) else {
            return .default
        }
        if defaults.object(forKey: heartRateDropWeightKey) == nil {
            let legacyDuration = defaults.integer(forKey: durationWeightKey)
            let legacyRegularity = defaults.integer(forKey: regularityWeightKey)
            let legacyInterruptions = defaults.integer(forKey: interruptionWeightKey)
            guard legacyDuration >= 0,
                  legacyRegularity >= 0,
                  legacyInterruptions >= 0,
                  legacyDuration + legacyRegularity + legacyInterruptions == 100 else {
                return .default
            }
            let duration = Int((Double(legacyDuration) * 0.6).rounded())
            let regularity = Int((Double(legacyRegularity) * 0.6).rounded())
            return SleepQualityWeights(
                duration: duration,
                regularity: regularity,
                interruptions: 60 - duration - regularity,
                heartRateDrop: 10,
                sleepStress: 10,
                remDeepSleep: 10,
                sleepLatency: 10
            )
        }
        if defaults.object(forKey: sleepStressWeightKey) == nil {
            let previous = SleepQualityWeights(
                duration: defaults.integer(forKey: durationWeightKey),
                regularity: defaults.integer(forKey: regularityWeightKey),
                interruptions: defaults.integer(forKey: interruptionWeightKey),
                heartRateDrop: defaults.integer(forKey: heartRateDropWeightKey)
            )
            guard previous.duration >= 0,
                  previous.regularity >= 0,
                  previous.interruptions >= 0,
                  previous.heartRateDrop >= 0,
                  previous.duration + previous.regularity
                    + previous.interruptions + previous.heartRateDrop == 100 else {
                return .default
            }
            let duration = Int((Double(previous.duration) * 0.7).rounded())
            let regularity = Int((Double(previous.regularity) * 0.7).rounded())
            let heartRateDrop = Int((Double(previous.heartRateDrop) * 0.7).rounded())
            return SleepQualityWeights(
                duration: duration,
                regularity: regularity,
                interruptions: 70 - duration - regularity - heartRateDrop,
                heartRateDrop: heartRateDrop,
                sleepStress: 10,
                remDeepSleep: 10,
                sleepLatency: 10
            )
        }
        if defaults.object(forKey: remDeepSleepWeightKey) == nil {
            let previous = SleepQualityWeights(
                duration: defaults.integer(forKey: durationWeightKey),
                regularity: defaults.integer(forKey: regularityWeightKey),
                interruptions: defaults.integer(forKey: interruptionWeightKey),
                heartRateDrop: defaults.integer(forKey: heartRateDropWeightKey),
                sleepStress: defaults.integer(forKey: sleepStressWeightKey)
            )
            guard previous.isValid else { return .default }
            let duration = Int((Double(previous.duration) * 0.8).rounded())
            let regularity = Int((Double(previous.regularity) * 0.8).rounded())
            let heartRateDrop = Int((Double(previous.heartRateDrop) * 0.8).rounded())
            let sleepStress = Int((Double(previous.sleepStress) * 0.8).rounded())
            return SleepQualityWeights(
                duration: duration,
                regularity: regularity,
                interruptions: 80 - duration - regularity - heartRateDrop - sleepStress,
                heartRateDrop: heartRateDrop,
                sleepStress: sleepStress,
                remDeepSleep: 10,
                sleepLatency: 10
            )
        }
        if defaults.object(forKey: sleepLatencyWeightKey) == nil {
            let previous = SleepQualityWeights(
                duration: defaults.integer(forKey: durationWeightKey),
                regularity: defaults.integer(forKey: regularityWeightKey),
                interruptions: defaults.integer(forKey: interruptionWeightKey),
                heartRateDrop: defaults.integer(forKey: heartRateDropWeightKey),
                sleepStress: defaults.integer(forKey: sleepStressWeightKey),
                remDeepSleep: defaults.integer(forKey: remDeepSleepWeightKey)
            )
            guard previous.isValid else { return .default }
            let duration = Int((Double(previous.duration) * 0.9).rounded())
            let regularity = Int((Double(previous.regularity) * 0.9).rounded())
            let heartRateDrop = Int((Double(previous.heartRateDrop) * 0.9).rounded())
            let sleepStress = Int((Double(previous.sleepStress) * 0.9).rounded())
            let remDeepSleep = Int((Double(previous.remDeepSleep) * 0.9).rounded())
            return SleepQualityWeights(
                duration: duration,
                regularity: regularity,
                interruptions: 90 - duration - regularity - heartRateDrop
                    - sleepStress - remDeepSleep,
                heartRateDrop: heartRateDrop,
                sleepStress: sleepStress,
                remDeepSleep: remDeepSleep,
                sleepLatency: 10
            )
        }
        let stored = SleepQualityWeights(
            duration: defaults.integer(forKey: durationWeightKey),
            regularity: defaults.integer(forKey: regularityWeightKey),
            interruptions: defaults.integer(forKey: interruptionWeightKey),
            heartRateDrop: defaults.integer(forKey: heartRateDropWeightKey),
            sleepStress: defaults.integer(forKey: sleepStressWeightKey),
            remDeepSleep: defaults.integer(forKey: remDeepSleepWeightKey),
            sleepLatency: defaults.integer(forKey: sleepLatencyWeightKey)
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
        defaults.set(weights.heartRateDrop, forKey: heartRateDropWeightKey)
        defaults.set(weights.sleepStress, forKey: sleepStressWeightKey)
        defaults.set(weights.remDeepSleep, forKey: remDeepSleepWeightKey)
        defaults.set(weights.sleepLatency, forKey: sleepLatencyWeightKey)
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
            heartRateDropWeightKey,
            sleepStressWeightKey,
            remDeepSleepWeightKey,
            sleepLatencyWeightKey,
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
    let heartRateDropScore: Double?
    var sleepStressScore: Double? = nil
    var remDeepSleepScore: Double? = nil
    var sleepLatencyScore: Double? = nil
    /// Number of available nights in the seven-day window that are within
    /// the maximum-score regularity band (±30 minutes from the circular mean).
    let compliantDays: Int
    let awakePercentage: Double
    let heartRateDropPercentage: Double?
    var averageSleepStressScore: Double? = nil
    var remDeepSleepPercentage: Double? = nil
    var sleepLatencyMinutes: Double? = nil
    let effectiveWeightTotal: Int
    let totalScore: Double
}

enum SleepQualityCalculator {
    static let regularityWindowDays = 7
    static let fullRegularityScoreWithinMinutes = 30.0
    static let zeroRegularityScoreAtMinutes = 4 * 60.0
    static let zeroInterruptionScoreAtPercentage = 15.0
    static let fullHeartRateDropScoreAtPercentage = 25.0
    /// The sleep-calibrated StressScore maps an ordinary nocturnal observation
    /// to 20/100. An average of 50/100 already represents sustained elevated
    /// activation, so values at or above it receive no quality points.
    static let zeroSleepStressQualityAtAverageScore = 50.0
    static let fullRemDeepSleepScoreRange = 35.0...45.0
    static let minimumClassifiedSleepCoverage = 0.8
    static let fullSleepLatencyScoreRangeMinutes = 5.0...20.0
    static let zeroLongSleepLatencyScoreAtMinutes = 60.0

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
                sleepPeriodHours: entry.sleepPeriodHours,
                heartRateDropPercentage: entry.heartRateDropPercentage,
                averageSleepStressScore: entry.averageSleepStressScore,
                sleepLatencyMinutes: entry.sleepLatencyMinutes
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
        let regularity = regularity(
            endingOn: entry.date,
            startsByDay: startsByDay,
            calendar: calendar
        )
        let compliantDays = regularity.fullScoreDays
        let regularityScore = regularity.score
        let weights = configuration.weights
        let heartRateDropPercentage = entry.heartRateDropPercentage.flatMap {
            $0.isFinite && $0 >= 0 ? $0 : nil
        }
        let heartRateDropScore = heartRateDropPercentage.map {
            min($0 / fullHeartRateDropScoreAtPercentage, 1) * 100
        }
        let averageSleepStressScore = entry.averageSleepStressScore.flatMap {
            $0.isFinite ? min(max($0, 0), 100) : nil
        }
        let sleepStressScore = averageSleepStressScore.map {
            max(0, 1 - $0 / zeroSleepStressQualityAtAverageScore) * 100
        }
        let remDeepSleepPercentage = remDeepSleepPercentage(for: entry)
        let remDeepSleepScore = remDeepSleepPercentage.map { percentage in
            if percentage < fullRemDeepSleepScoreRange.lowerBound {
                return percentage / fullRemDeepSleepScoreRange.lowerBound * 100
            }
            if percentage <= fullRemDeepSleepScoreRange.upperBound {
                return 100
            }
            return max(
                0,
                (100 - percentage)
                    / (100 - fullRemDeepSleepScoreRange.upperBound) * 100
            )
        }
        let sleepLatencyMinutes = entry.sleepLatencyMinutes.flatMap {
            $0.isFinite && $0 >= 0 ? $0 : nil
        }
        let sleepLatencyScore = sleepLatencyMinutes.map { minutes in
            if minutes < fullSleepLatencyScoreRangeMinutes.lowerBound {
                return minutes / fullSleepLatencyScoreRangeMinutes.lowerBound * 100
            }
            if minutes <= fullSleepLatencyScoreRangeMinutes.upperBound {
                return 100
            }
            return max(
                0,
                (zeroLongSleepLatencyScoreAtMinutes - minutes)
                    / (zeroLongSleepLatencyScoreAtMinutes
                        - fullSleepLatencyScoreRangeMinutes.upperBound) * 100
            )
        }
        let unavailableWeight =
            (heartRateDropScore == nil ? weights.heartRateDrop : 0)
            + (sleepStressScore == nil ? weights.sleepStress : 0)
            + (remDeepSleepScore == nil ? weights.remDeepSleep : 0)
            + (sleepLatencyScore == nil ? weights.sleepLatency : 0)
        let effectiveWeightTotal = 100 - unavailableWeight
        let weightedTotal = (
            durationScore * Double(weights.duration)
                + regularityScore * Double(weights.regularity)
                + interruptionScore * Double(weights.interruptions)
                + (heartRateDropScore ?? 0) * Double(weights.heartRateDrop)
                + (sleepStressScore ?? 0) * Double(weights.sleepStress)
                + (remDeepSleepScore ?? 0) * Double(weights.remDeepSleep)
                + (sleepLatencyScore ?? 0) * Double(weights.sleepLatency)
        )
        let total = effectiveWeightTotal > 0
            ? weightedTotal / Double(effectiveWeightTotal)
            : 0

        return SleepQualityBreakdown(
            durationScore: durationScore,
            regularityScore: regularityScore,
            interruptionScore: interruptionScore,
            heartRateDropScore: heartRateDropScore,
            sleepStressScore: sleepStressScore,
            remDeepSleepScore: remDeepSleepScore,
            sleepLatencyScore: sleepLatencyScore,
            compliantDays: compliantDays,
            awakePercentage: awakePercentage,
            heartRateDropPercentage: heartRateDropPercentage,
            averageSleepStressScore: averageSleepStressScore,
            remDeepSleepPercentage: remDeepSleepPercentage,
            sleepLatencyMinutes: sleepLatencyMinutes,
            effectiveWeightTotal: effectiveWeightTotal,
            totalScore: min(max(total, 0), 100)
        )
    }

    private static func remDeepSleepPercentage(
        for entry: AppleHealthSleepDay
    ) -> Double? {
        guard let totalSleepHours = entry.hours,
              totalSleepHours.isFinite,
              totalSleepHours > 0 else {
            return nil
        }
        let stages = [entry.remHours, entry.deepHours, entry.lightHours]
        guard stages.contains(where: { $0 != nil }) else { return nil }
        let values = stages.map { value -> Double in
            guard let value, value.isFinite else { return 0 }
            return max(value, 0)
        }
        let classifiedHours = values.reduce(0, +)
        guard classifiedHours > 0,
              classifiedHours / totalSleepHours >= minimumClassifiedSleepCoverage else {
            return nil
        }
        return min(max((values[0] + values[1]) / classifiedHours * 100, 0), 100)
    }

    private static func regularity(
        endingOn endDate: Date,
        startsByDay: [Date: Date],
        calendar: Calendar
    ) -> (score: Double, fullScoreDays: Int) {
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
        guard let currentStart = startsByDay[endDay],
              let mean = circularMeanMinutes(minutes) else {
            return (0, 0)
        }
        let currentComponents = calendar.dateComponents(
            [.hour, .minute, .second],
            from: currentStart
        )
        let currentMinutes = Double(currentComponents.hour ?? 0) * 60
            + Double(currentComponents.minute ?? 0)
            + Double(currentComponents.second ?? 0) / 60
        let distances = minutes.map { circularDistanceMinutes($0, mean) }
        let fullScoreDays = distances.filter {
            $0 <= fullRegularityScoreWithinMinutes
        }.count
        return (
            regularityScore(forDeviationInMinutes: circularDistanceMinutes(currentMinutes, mean)),
            fullScoreDays
        )
    }

    private static func regularityScore(
        forDeviationInMinutes deviation: Double
    ) -> Double {
        guard deviation.isFinite else { return 0 }
        if deviation <= fullRegularityScoreWithinMinutes { return 100 }
        if deviation >= zeroRegularityScoreAtMinutes { return 0 }
        let span = zeroRegularityScoreAtMinutes - fullRegularityScoreWithinMinutes
        return (zeroRegularityScoreAtMinutes - deviation) / span * 100
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

enum SleepHeartRateDropCalculator {
    static let initialWindow: TimeInterval = 60 * 60
    static let minimumInitialSamples = 2
    static let minimumLaterSamples = 4
    private static let validHeartRateRange = 25.0...220.0

    static func percentage(
        for session: AppleHealthSleepSession,
        heartRateSamples: [AppleHealthTimedQuantity]
    ) -> Double? {
        let (sleepStart, sleepEnd) = sleepBounds(for: session)
        guard sleepEnd.timeIntervalSince(sleepStart) > initialWindow else { return nil }

        let initialEnd = sleepStart.addingTimeInterval(initialWindow)
        let initialValues = values(
            in: heartRateSamples,
            from: sleepStart,
            through: initialEnd
        )
        let laterValues = values(
            in: heartRateSamples,
            from: initialEnd,
            through: sleepEnd,
            includingStart: false
        )
        guard initialValues.count >= minimumInitialSamples,
              laterValues.count >= minimumLaterSamples,
              let initialMedian = median(initialValues),
              let stableLow = percentile(laterValues, fraction: 0.2),
              initialMedian > 0 else {
            return nil
        }
        return min(max((initialMedian - stableLow) / initialMedian * 100, 0), 100)
    }

    /// Calculates a collection of sessions without scanning the complete
    /// HealthKit history once for every night.
    static func percentages(
        for sessions: [AppleHealthSleepSession],
        heartRateSamples: [AppleHealthTimedQuantity]
    ) -> [Date: Double] {
        guard !sessions.isEmpty, !heartRateSamples.isEmpty else { return [:] }
        let sortedSamples = heartRateSamples.sorted { $0.endDate < $1.endDate }
        var result: [Date: Double] = [:]

        for session in sessions {
            let (sleepStart, sleepEnd) = sleepBounds(for: session)
            let lowerIndex = lowerBound(in: sortedSamples, for: sleepStart)
            let upperIndex = upperBound(in: sortedSamples, for: sleepEnd)
            guard lowerIndex < upperIndex,
                  let drop = percentage(
                    for: session,
                    heartRateSamples: Array(sortedSamples[lowerIndex..<upperIndex])
                  ) else {
                continue
            }
            result[session.startDate] = drop
        }
        return result
    }

    private static func sleepBounds(
        for session: AppleHealthSleepSession
    ) -> (start: Date, end: Date) {
        let asleepIntervals = session.stageIntervals.filter { $0.stage != .awake }
        return (
            asleepIntervals.map(\.startDate).min() ?? session.startDate,
            asleepIntervals.map(\.endDate).max() ?? session.endDate
        )
    }

    private static func lowerBound(
        in samples: [AppleHealthTimedQuantity],
        for date: Date
    ) -> Int {
        var lower = 0
        var upper = samples.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if samples[middle].endDate < date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func upperBound(
        in samples: [AppleHealthTimedQuantity],
        for date: Date
    ) -> Int {
        var lower = 0
        var upper = samples.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if samples[middle].endDate <= date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private static func values(
        in samples: [AppleHealthTimedQuantity],
        from startDate: Date,
        through endDate: Date,
        includingStart: Bool = true
    ) -> [Double] {
        samples.compactMap { sample in
            let startsInsideWindow = includingStart
                ? sample.endDate >= startDate
                : sample.endDate > startDate
            guard startsInsideWindow,
                  sample.endDate <= endDate,
                  sample.value.isFinite,
                  validHeartRateRange.contains(sample.value) else {
                return nil
            }
            return sample.value
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        percentile(values, fraction: 0.5)
    }

    private static func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let position = min(max(fraction, 0), 1) * Double(sorted.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        guard lowerIndex != upperIndex else { return sorted[lowerIndex] }
        let interpolation = position - Double(lowerIndex)
        return sorted[lowerIndex]
            + (sorted[upperIndex] - sorted[lowerIndex]) * interpolation
    }
}

/// A device-local correction applied only while Wellnario presents sleep data.
/// It is deliberately stored outside the Health snapshot so a later sync
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
                sleepLatencySeconds: session.sleepLatencySeconds,
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
                sleepPeriodHours: existing?.sleepPeriodHours,
                heartRateDropPercentage: existing?.heartRateDropPercentage,
                averageSleepStressScore: existing?.averageSleepStressScore,
                sleepLatencyMinutes: existing?.sleepLatencyMinutes
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
                sleepPeriodHours: entry.sleepPeriodHours,
                heartRateDropPercentage: entry.heartRateDropPercentage,
                averageSleepStressScore: entry.averageSleepStressScore,
                sleepLatencyMinutes: entry.sleepLatencyMinutes
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
        heartRateSamples: [AppleHealthTimedQuantity] = [],
        endingAt date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [AppleHealthSleepDay] {
        let today = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return dailyTrend(
            sessions: sessions,
            heartRateSamples: heartRateSamples,
            from: start,
            through: today,
            calendar: calendar
        )
    }

    static func allTimeTrend(
        sessions: [AppleHealthSleepSession],
        heartRateSamples: [AppleHealthTimedQuantity] = [],
        endingAt date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [AppleHealthSleepDay] {
        guard let earliestSession = sessions.min(by: { $0.endDate < $1.endDate }) else { return [] }
        let start = calendar.startOfDay(for: earliestSession.endDate)
        let today = calendar.startOfDay(for: date)
        return dailyTrend(
            sessions: sessions,
            heartRateSamples: heartRateSamples,
            from: start,
            through: today,
            calendar: calendar
        )
    }

    static func preservingCachedHeartRateDrops(
        in updated: [AppleHealthSleepDay],
        from cached: [AppleHealthSleepDay],
        calendar: Calendar
    ) -> [AppleHealthSleepDay] {
        let cachedByDay = Dictionary(
            cached.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { _, newest in newest }
        )
        return updated.map { entry in
            guard entry.heartRateDropPercentage == nil,
                  let cachedEntry = cachedByDay[calendar.startOfDay(for: entry.date)],
                  let cachedDrop = cachedEntry.heartRateDropPercentage else {
                return entry
            }
            return AppleHealthSleepDay(
                date: entry.date,
                hours: entry.hours,
                qualityScore: entry.qualityScore,
                remHours: entry.remHours,
                deepHours: entry.deepHours,
                lightHours: entry.lightHours,
                sleepStartDate: entry.sleepStartDate,
                awakeHours: entry.awakeHours,
                sleepPeriodHours: entry.sleepPeriodHours,
                heartRateDropPercentage: cachedDrop,
                averageSleepStressScore: entry.averageSleepStressScore,
                sleepLatencyMinutes: entry.sleepLatencyMinutes
            )
        }
    }

    static func applyingAverageSleepStress(
        from factors: [AppleHealthAutomaticSleepFactors],
        sessions: [AppleHealthSleepSession],
        to trend: [AppleHealthSleepDay],
        calendar: Calendar
    ) -> [AppleHealthSleepDay] {
        let scoresBySessionStart = Dictionary(
            factors.compactMap { factor -> (Date, Double)? in
                guard let startDate = factor.sleepSessionStartDate,
                      let score = factor.averageSleepStressScore,
                      score.isFinite else {
                    return nil
                }
                return (startDate, min(max(score, 0), 100))
            },
            uniquingKeysWith: { _, newest in newest }
        )
        let sessionsByDay = Dictionary(
            grouping: sessions,
            by: { calendar.startOfDay(for: $0.endDate) }
        )
        return trend.map { entry in
            let day = calendar.startOfDay(for: entry.date)
            guard let mainSession = sessionsByDay[day]?.max(by: { lhs, rhs in
                if lhs.asleepSeconds != rhs.asleepSeconds {
                    return lhs.asleepSeconds < rhs.asleepSeconds
                }
                return lhs.endDate < rhs.endDate
            }) else {
                return entry
            }
            return AppleHealthSleepDay(
                date: entry.date,
                hours: entry.hours,
                qualityScore: entry.qualityScore,
                remHours: entry.remHours,
                deepHours: entry.deepHours,
                lightHours: entry.lightHours,
                sleepStartDate: entry.sleepStartDate,
                awakeHours: entry.awakeHours,
                sleepPeriodHours: entry.sleepPeriodHours,
                heartRateDropPercentage: entry.heartRateDropPercentage,
                averageSleepStressScore: scoresBySessionStart[mainSession.startDate],
                sleepLatencyMinutes: entry.sleepLatencyMinutes
            )
        }
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

        let dailyEntries = trendDailyEntries(
            from: history,
            startingAt: start,
            through: today,
            calendar: calendar
        )

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

    static func trendSeries(
        from history: [AppleHealthSleepDay],
        dateRange: ClosedRange<Date>,
        calendar: Calendar = .autoupdatingCurrent
    ) -> AppleHealthSleepTrendSeries {
        let start = calendar.startOfDay(for: dateRange.lowerBound)
        let end = calendar.startOfDay(for: dateRange.upperBound)
        guard start <= end else {
            return AppleHealthSleepTrendSeries(entries: [], dailyEntries: [], granularity: .day)
        }

        let dailyEntries = trendDailyEntries(
            from: history,
            startingAt: start,
            through: end,
            calendar: calendar
        )
        let dayCount = max(
            (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1,
            1
        )
        let component: Calendar.Component?
        let granularity: AppleHealthSleepTrendGranularity
        switch dayCount {
        case ...31:
            component = nil
            granularity = .day
        case ...183:
            component = .weekOfYear
            granularity = .week
        case ...731:
            component = .month
            granularity = .month
        default:
            component = .year
            granularity = .year
        }

        guard let component else {
            return AppleHealthSleepTrendSeries(entries: dailyEntries, granularity: granularity)
        }
        return AppleHealthSleepTrendSeries(
            entries: aggregate(dailyEntries, by: component, calendar: calendar),
            dailyEntries: dailyEntries,
            granularity: granularity
        )
    }

    private static func trendDailyEntries(
        from history: [AppleHealthSleepDay],
        startingAt start: Date,
        through end: Date,
        calendar: Calendar
    ) -> [AppleHealthSleepDay] {
        var entriesByDay: [Date: AppleHealthSleepDay] = [:]
        for entry in history {
            entriesByDay[calendar.startOfDay(for: entry.date)] = entry
        }
        return daySequence(from: start, through: end, calendar: calendar).map { day in
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
                sleepPeriodHours: entry.sleepPeriodHours,
                heartRateDropPercentage: entry.heartRateDropPercentage,
                averageSleepStressScore: entry.averageSleepStressScore,
                sleepLatencyMinutes: entry.sleepLatencyMinutes
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
                sleepPeriodHours: average(bucketEntries.map(\.sleepPeriodHours)),
                heartRateDropPercentage: average(
                    bucketEntries.map(\.heartRateDropPercentage)
                ),
                averageSleepStressScore: average(
                    bucketEntries.map(\.averageSleepStressScore)
                ),
                sleepLatencyMinutes: average(bucketEntries.map(\.sleepLatencyMinutes))
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
            || entry.heartRateDropPercentage != nil
            || entry.averageSleepStressScore != nil
    }

    private static func dailyTrend(
        sessions: [AppleHealthSleepSession],
        heartRateSamples: [AppleHealthTimedQuantity],
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
        let heartRateDrops = SleepHeartRateDropCalculator.percentages(
            for: sessions,
            heartRateSamples: heartRateSamples
        )
        return days.map { day in
            let dailySessions = sessionsByDay[day, default: []]
            let asleepSeconds = dailySessions.reduce(0) { $0 + $1.asleepSeconds }
            // The interruption percentage must describe the same interval
            // displayed to the person as their sleep session. Do not discard
            // awake stages at either end: HealthKit has explicitly recorded
            // them as part of that session and the UI includes them in its
            // start-to-end range.
            let awakeSeconds = dailySessions.reduce(0) { $0 + $1.awakeSeconds }
            let sessionSpanSeconds = dailySessions.reduce(0) { total, session in
                total + max(session.endDate.timeIntervalSince(session.startDate), 0)
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
                    : sessionSpanSeconds / 3_600,
                heartRateDropPercentage: mainSession.flatMap {
                    heartRateDrops[$0.startDate]
                },
                sleepLatencyMinutes: mainSession?.sleepLatencySeconds.map { $0 / 60 }
            )
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

        let asleepSegments = segments.filter { $0.kind.isAsleep }
        let asleep = unionDuration(asleepSegments)
        guard asleep >= 20 * 60 else { return nil }

        let sleepLatencySeconds = sleepLatencySeconds(
            asleepSegments: asleepSegments,
            inBedSegments: segments.filter { $0.kind == .inBed }
        )

        return AppleHealthSleepSession(
            startDate: startDate,
            endDate: endDate,
            asleepSeconds: asleep,
            inBedSeconds: unionDuration(segments),
            awakeSeconds: unionDuration(segments.filter { $0.kind == .awake }),
            coreSeconds: unionDuration(segments.filter { $0.kind == .core }),
            deepSeconds: unionDuration(segments.filter { $0.kind == .deep }),
            remSeconds: unionDuration(segments.filter { $0.kind == .rem }),
            sleepLatencySeconds: sleepLatencySeconds,
            sourceNames: Array(Set(segments.map(\.sourceName))).sorted(),
            stageIntervals: stageTimeline(from: segments)
        )
    }

    private static func sleepLatencySeconds(
        asleepSegments: [Segment],
        inBedSegments: [Segment]
    ) -> TimeInterval? {
        guard let firstAsleepStart = asleepSegments.map(\.startDate).min() else {
            return nil
        }
        let onsetSources = Set(
            asleepSegments
                .filter { $0.startDate == firstAsleepStart }
                .map(\.sourceName)
        )
        let containing = inBedSegments.filter {
            $0.startDate <= firstAsleepStart && $0.endDate >= firstAsleepStart
        }
        let preferred = containing.filter { onsetSources.contains($0.sourceName) }
        // HealthKit can expose both the complete in-bed interval and a nested
        // interval from the same source. The complete interval is the one that
        // represents when the user went to bed; choosing the nested interval
        // would artificially shorten latency. If the onset source has no in-bed
        // data, retain the conservative fallback to the latest foreign-source
        // interval so a broad phone schedule is not mixed with wearable stages.
        let inBed = preferred.min(by: { $0.startDate < $1.startDate })
            ?? containing.max(by: { $0.startDate < $1.startDate })
        guard let inBed else {
            return nil
        }
        return max(firstAsleepStart.timeIntervalSince(inBed.startDate), 0)
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

enum AppleHealthSessionQuantitySelector {
    static func latestSamples(
        from samples: [AppleHealthTimedQuantity],
        for sessions: [AppleHealthSleepSession]
    ) -> [AppleHealthTimedQuantity] {
        let orderedSamples = samples.sorted {
            if $0.endDate != $1.endDate {
                return $0.endDate < $1.endDate
            }
            return $0.startDate < $1.startDate
        }
        return sessions.compactMap { session in
            orderedSamples.last {
                $0.startDate >= session.startDate
                    && $0.endDate <= session.endDate
            }
        }.sorted { $0.startDate < $1.startDate }
    }
}

enum AppleHealthHeartRateDropBackfill {
    static func sessionDays(
        in sessions: [AppleHealthSleepSession],
        calendar: Calendar
    ) -> Set<LocalDay> {
        Set(sessions.map {
            LocalDay(containing: $0.endDate, in: calendar.timeZone)
        })
    }

    static func nextBatch(
        from sessions: [AppleHealthSleepSession],
        excluding processedDays: Set<LocalDay>,
        daySpan: Int,
        calendar: Calendar
    ) -> [AppleHealthSleepSession] {
        guard daySpan > 0 else { return [] }
        let pending = sessions.filter {
            !processedDays.contains(
                LocalDay(containing: $0.endDate, in: calendar.timeZone)
            )
        }
        guard let newestEnd = pending.map(\.endDate).max(),
              let windowStart = calendar.date(
                byAdding: .day,
                value: -(daySpan - 1),
                to: newestEnd
              ) else {
            return []
        }
        return pending
            .filter { $0.endDate >= windowStart && $0.endDate <= newestEnd }
            .sorted { $0.startDate < $1.startDate }
    }

    static func applying(
        heartRateSamples: [AppleHealthTimedQuantity],
        for sessions: [AppleHealthSleepSession],
        to trend: [AppleHealthSleepDay],
        calendar: Calendar
    ) -> [AppleHealthSleepDay] {
        let sessionsByDay = Dictionary(
            grouping: sessions,
            by: { LocalDay(containing: $0.endDate, in: calendar.timeZone) }
        )
        let drops = SleepHeartRateDropCalculator.percentages(
            for: sessions,
            heartRateSamples: heartRateSamples
        )
        return trend.map { entry in
            let day = LocalDay(containing: entry.date, in: calendar.timeZone)
            guard let dailySessions = sessionsByDay[day],
                  let mainSession = dailySessions.max(by: { lhs, rhs in
                      if lhs.asleepSeconds != rhs.asleepSeconds {
                          return lhs.asleepSeconds < rhs.asleepSeconds
                      }
                      return lhs.endDate < rhs.endDate
                  }) else {
                return entry
            }
            return AppleHealthSleepDay(
                date: entry.date,
                hours: entry.hours,
                qualityScore: entry.qualityScore,
                remHours: entry.remHours,
                deepHours: entry.deepHours,
                lightHours: entry.lightHours,
                sleepStartDate: entry.sleepStartDate,
                awakeHours: entry.awakeHours,
                sleepPeriodHours: entry.sleepPeriodHours,
                heartRateDropPercentage: drops[mainSession.startDate],
                averageSleepStressScore: entry.averageSleepStressScore,
                sleepLatencyMinutes: entry.sleepLatencyMinutes
            )
        }
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
        heartRateSamples: [AppleHealthTimedQuantity],
        endingAt endDate: Date,
        calendar: Calendar
    ) -> [AppleHealthSleepDay] {
        AppleHealthSleepAggregator.allTimeTrend(
            sessions: sessions,
            heartRateSamples: heartRateSamples,
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
        heartRateSamples: [AppleHealthTimedQuantity],
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
            heartRateSamples: heartRateSamples,
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
    // The automatic factors use sleep quality as an input. Bump this when a
    // quality component changes so their cached historical values are rebuilt.
    private static let currentAutomaticSleepFactorsVersion = 11
    private static let currentHeartRateDropCalculationVersion = 1
    private static let historicalHeartRateBackfillDaySpan = 30

    private struct SourceQueryFilter {
        let predicate: NSPredicate?
        let excludesAll: Bool
    }

    private struct SourceAccumulator {
        var name: String
        var bundleIdentifier: String
        var dataKinds: Set<AppleHealthDataKind>
    }

    private let healthStore: HKHealthStore?
    private let defaults: UserDefaults
    private var cache: AppleHealthSnapshotCache
    private let sourcePreferences: AppleHealthSourcePreferences
    private let calendar: Calendar
    private var sourcesByTypeIdentifier: [String: Set<HKSource>] = [:]
    private var isRunningSync = false
    private var heartRateDropBackfillTask: Task<Void, Never>?
    private var heartRateDropBackfillGeneration = 0

    private(set) var snapshot: AppleHealthSnapshot
    private(set) var state: AppleHealthSyncState
    private(set) var availableSources: [AppleHealthDataSource]
    private(set) var disabledSourceSelections: Set<AppleHealthSourceSelection>

    var recoveryEngine: RecoveryEngine?

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
                ? readTypes.subtracting(Self.recentlyAddedAuthorizationReadTypes)
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

            // `timeInDaylight` was added after Health support had
            // already shipped. Some existing installations do not surface a
            // newly added read type when it is included in a broader request.
            // Ask HealthKit about this type on its own and, only when it still
            // has a pending decision, present its dedicated request. This
            // remains a no-op for people who have already seen the choice.
            if wasAlreadyConfigured,
               (try? await authorizationRequestStatus(
                healthStore: healthStore,
                readTypes: Self.recentlyAddedAuthorizationReadTypes
            )) == .shouldRequest {
                _ = try? await requestAuthorization(
                    healthStore: healthStore,
                    readTypes: Self.recentlyAddedAuthorizationReadTypes
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
            async let heartRateTask = fetchTimedQuantities(
                from: healthStore,
                identifier: .heartRate,
                unit: .count().unitDivided(by: .minute()),
                // The target day's FC must be normalized against FC—not RHR—
                // from the same two rolling baseline windows as the other
                // stress inputs. Limiting this query to 48 hours leaves fewer
                // than the seven historical FC observations required.
                start: stressContextStart,
                end: dayEnd
            )
            let sessions = try await sessionsTask

            async let respiratoryRateTask = fetchLatestQuantitiesForSessions(
                from: healthStore,
                identifier: .respiratoryRate,
                unit: .count().unitDivided(by: .minute()),
                sessions: sessions
            )

            let workouts = try await workoutsTask
            let hrvSamples = try await hrvTask
            let restingHeartRateSamples = try await restingHeartRateTask
            let heartRateSamples = try await heartRateTask
            let respiratoryRateSamples = try await respiratoryRateTask
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
                heartRateSamples: heartRateSamples,
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

    func heartRateSamples(from startDate: Date, through endDate: Date) async -> [AppleHealthTimedQuantity] {
        guard let healthStore, isConfigured, startDate < endDate else { return [] }
        return (try? await fetchTimedQuantities(
            from: healthStore,
            identifier: .heartRate,
            unit: .count().unitDivided(by: .minute()),
            start: startDate,
            end: endDate
        )) ?? []
    }

    func restingHeartRateSamples(
        from startDate: Date,
        through endDate: Date
    ) async -> [AppleHealthTimedQuantity] {
        guard let healthStore, isConfigured, startDate < endDate else { return [] }
        return (try? await fetchTimedQuantities(
            from: healthStore,
            identifier: .restingHeartRate,
            unit: .count().unitDivided(by: .minute()),
            start: startDate,
            end: endDate
        )) ?? []
    }

    func consumePendingAuthorizationWarning() async -> Bool {
        guard isConfigured, let healthStore else { return false }

        // If there are recently added types that still need authorization, we MUST
        // present the request natively at least once, otherwise they won't even
        // appear in iOS Settings for the user to enable.
        if (try? await authorizationRequestStatus(
            healthStore: healthStore,
            readTypes: Self.recentlyAddedAuthorizationReadTypes
        )) == .shouldRequest {
            _ = try? await requestAuthorization(
                healthStore: healthStore,
                readTypes: Self.recentlyAddedAuthorizationReadTypes
            )
            // We just showed the native modal, so no need for the banner right now.
            // Reset the flag so if they dismissed it without deciding, we can show the banner next time.
            defaults.set(false, forKey: Self.pendingAuthorizationWarningShownKey)
            return false
        }

        guard !defaults.bool(forKey: Self.pendingAuthorizationWarningShownKey),
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

        cancelHeartRateDropBackfill()
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
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)
                ?? .distantPast
            let recentHeartRateStart = calendar.date(
                byAdding: .day,
                value: -35,
                to: now
            ) ?? now.addingTimeInterval(-(35 * 24 * 3_600))
            let heartRateHistoryStart = max(
                sleepSessions.map(\.startDate).min() ?? recentHeartRateStart,
                recentHeartRateStart
            )
            async let recentSleepDataTask: (
                heartRateSamples: [AppleHealthTimedQuantity],
                trend: [AppleHealthSleepDay]
            ) = {
                let heartRateSamples = (try? await fetchTimedQuantities(
                    from: healthStore,
                    identifier: .heartRate,
                    unit: .count().unitDivided(by: .minute()),
                    start: heartRateHistoryStart,
                    end: now
                )) ?? []
                let trend = await Task.detached(priority: .userInitiated) {
                    AppleHealthBackgroundCalculations.sleepTrend(
                        sessions: sleepSessions,
                        heartRateSamples: heartRateSamples,
                        endingAt: now,
                        calendar: currentCalendar
                    )
                }.value
                return (heartRateSamples, trend)
            }()
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
                ?? calendar.startOfDay(for: now)
            let todayStart = calendar.startOfDay(for: now)

            // HealthKit executes these independent queries in parallel. Each
            // task yields immediately while HealthKit reads its samples, so
            // neither the queries nor their wait time block touch handling.
            async let hrvTask: AppleHealthMeasurement? = {
                let s = Date()
                let res = try? await fetchLatestMeasurement(from: healthStore, identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), since: calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast)
                print("🕒 sync: hrvTask took \(Date().timeIntervalSince(s))s")
                return res
            }()
            async let restingHeartRateTask: AppleHealthMeasurement? = {
                let s = Date()
                let res = try? await fetchLatestMeasurement(from: healthStore, identifier: .restingHeartRate, unit: .count().unitDivided(by: .minute()), since: calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast)
                print("🕒 sync: restingHeartRateTask took \(Date().timeIntervalSince(s))s")
                return res
            }()
            async let vo2MaxTask: AppleHealthMeasurement? = {
                let s = Date()
                let res = try? await fetchAverageMeasurement(from: healthStore, identifier: .vo2Max, unit: HKUnit(from: "ml/kg*min"), since: calendar.date(byAdding: .month, value: -3, to: now) ?? .distantPast, endingAt: now)
                print("🕒 sync: vo2MaxTask took \(Date().timeIntervalSince(s))s")
                return res
            }()
            async let bloodGlucoseTask: AppleHealthMeasurement? = {
                let s = Date()
                let res = try? await fetchLatestMeasurement(from: healthStore, identifier: .bloodGlucose, unit: HKUnit(from: "mg/dL"), since: calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast)
                print("🕒 sync: bloodGlucoseTask took \(Date().timeIntervalSince(s))s")
                return res
            }()
            let retainedSystolicBloodPressure = snapshot.systolicBloodPressureSixMonthAverage
            async let systolicBloodPressureTask: AppleHealthMeasurement? = {
                let s = Date()
                guard canQueryBloodPressure else { return retainedSystolicBloodPressure }
                let res = try? await fetchAverageMeasurement(from: healthStore, identifier: .bloodPressureSystolic, unit: HKUnit(from: "mmHg"), since: sixMonthsAgo, endingAt: now)
                print("🕒 sync: systolicBloodPressureTask took \(Date().timeIntervalSince(s))s")
                return res
            }()
            async let stepsTask: Double? = {
                let s = Date()
                let res = try? await fetchCumulativeQuantity(from: healthStore, identifier: .stepCount, unit: .count(), start: todayStart, end: now)
                print("🕒 sync: stepsTask took \(Date().timeIntervalSince(s))s")
                return res
            }()
            async let activeEnergyTask: Double? = {
                let s = Date()
                let res = try? await fetchCumulativeQuantity(from: healthStore, identifier: .activeEnergyBurned, unit: .kilocalorie(), start: todayStart, end: now)
                print("🕒 sync: activeEnergyTask took \(Date().timeIntervalSince(s))s")
                return res
            }()
            async let workoutsTask: [AppleHealthWorkout] = {
                let s = Date()
                let res = (try? await fetchWorkouts(from: healthStore, start: weekStart, end: now)) ?? []
                print("🕒 sync: workoutsTask took \(Date().timeIntervalSince(s))s")
                return res
            }()
            let recentSleepData = await recentSleepDataTask
            let sleepHeartRateSamples = recentSleepData.heartRateSamples
            let canReuseCachedHeartRateDrops =
                snapshot.heartRateDropCalculationVersion
                    == Self.currentHeartRateDropCalculationVersion
            let sleepTrend = AppleHealthSleepAggregator.preservingCachedHeartRateDrops(
                in: recentSleepData.trend,
                from: canReuseCachedHeartRateDrops ? snapshot.sleepTrend : [],
                calendar: calendar
            )
            let previouslyProcessedHeartRateDropDays = canReuseCachedHeartRateDrops
                ? Set(snapshot.heartRateDropProcessedDays ?? [])
                : []
            let recentlyProcessedHeartRateDropDays =
                AppleHealthHeartRateDropBackfill.sessionDays(
                    in: sleepSessions.filter {
                        $0.startDate >= heartRateHistoryStart
                    },
                    calendar: calendar
                )
            let processedHeartRateDropDays =
                previouslyProcessedHeartRateDropDays
                    .union(recentlyProcessedHeartRateDropDays)
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
            let cachedFactors = snapshot.automaticSleepFactorsVersion == Self.currentAutomaticSleepFactorsVersion
                ? (snapshot.automaticSleepFactors ?? [])
                : []
            async let automaticSleepFactorHistoryTask = {
                let s = Date()
                let res = await fetchAutomaticSleepFactorHistory(
                    from: healthStore,
                    sessions: sleepSessions,
                    sleepQualityByDay: sleepQualityByDay,
                    heartRateSamples: sleepHeartRateSamples,
                    cachedFactors: cachedFactors,
                    cacheVersion: snapshot.automaticSleepFactorsVersion,
                    endingAt: now
                )
                print("🕒 sync: automaticSleepFactorHistoryTask took \(Date().timeIntervalSince(s))s")
                return res
            }()
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
            let sleepTrendWithAverageStress =
                AppleHealthSleepAggregator.applyingAverageSleepStress(
                    from: automaticSleepFactorHistory.factors,
                    sessions: sleepSessions,
                    to: sleepTrend,
                    calendar: calendar
                )

            var updated = AppleHealthSnapshot(
                lastSyncedAt: now,
                latestSleepSession: sleepSessions.last,
                sleepTrend: sleepTrendWithAverageStress,
                heartRateVariability: hrv,
                restingHeartRate: restingHeartRate,
                vo2Max: vo2Max,
                bloodGlucose: bloodGlucose,
                systolicBloodPressureSixMonthAverage: systolicBloodPressure,
                stepsToday: steps,
                activeEnergyKilocaloriesToday: activeEnergy,
                workoutsThisWeek: workouts,
                automaticSleepFactors: automaticSleepFactorHistory.factors,
                automaticSleepFactorsVersion: Self.currentAutomaticSleepFactorsVersion,
                heartRateDropCalculationVersion:
                    Self.currentHeartRateDropCalculationVersion,
                heartRateDropProcessedDays:
                    processedHeartRateDropDays.sorted(),
                latestPreSleepStressTimeline: automaticSleepFactorHistory.latestStressTimeline,
                currentStressDetails: automaticSleepFactorHistory.currentStressDetails
            )
            updated.dateOfBirthComponents = try? healthStore.dateOfBirthComponents()
            updated.biologicalSex = readBiologicalSex(from: healthStore)
            snapshot = updated
            cache.save(updated)
            
        if let recoveryEngine {
            try? await recoveryEngine.sync(
                sleepTrend: snapshot.sleepTrend,
                healthStore: healthStore,
                calendar: calendar,
                now: now
            )
        }

        setState(.ready)
        scheduleHeartRateDropBackfill(
            from: sleepSessions,
            healthStore: healthStore
        )
        } catch {
            setState(.failed)
            throw error
        }
    }

    private func cancelHeartRateDropBackfill() {
        heartRateDropBackfillGeneration += 1
        heartRateDropBackfillTask?.cancel()
        heartRateDropBackfillTask = nil
    }

    private func scheduleHeartRateDropBackfill(
        from sessions: [AppleHealthSleepSession],
        healthStore: HKHealthStore
    ) {
        guard !sessions.isEmpty else { return }
        cancelHeartRateDropBackfill()
        let generation = heartRateDropBackfillGeneration
        heartRateDropBackfillTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.backfillHistoricalHeartRateDrops(
                from: sessions,
                healthStore: healthStore,
                generation: generation
            )
        }
    }

    private func backfillHistoricalHeartRateDrops(
        from sessions: [AppleHealthSleepSession],
        healthStore: HKHealthStore,
        generation: Int
    ) async {
        while !Task.isCancelled,
              generation == heartRateDropBackfillGeneration {
            let processedDays =
                snapshot.heartRateDropCalculationVersion
                    == Self.currentHeartRateDropCalculationVersion
                ? Set(snapshot.heartRateDropProcessedDays ?? [])
                : []
            let batch = AppleHealthHeartRateDropBackfill.nextBatch(
                from: sessions,
                excluding: processedDays,
                daySpan: Self.historicalHeartRateBackfillDaySpan,
                calendar: calendar
            )
            guard let batchStart = batch.map(\.startDate).min(),
                  let batchEnd = batch.map(\.endDate).max() else {
                break
            }

            let samples: [AppleHealthTimedQuantity]
            do {
                samples = try await fetchTimedQuantities(
                    from: healthStore,
                    identifier: .heartRate,
                    unit: .count().unitDivided(by: .minute()),
                    start: batchStart,
                    end: batchEnd
                )
            } catch {
                break
            }
            guard !Task.isCancelled,
                  generation == heartRateDropBackfillGeneration else {
                break
            }

            let currentTrend = snapshot.sleepTrend
            let currentCalendar = calendar
            let updatedTrend = await Task.detached(priority: .utility) {
                AppleHealthHeartRateDropBackfill.applying(
                    heartRateSamples: samples,
                    for: batch,
                    to: currentTrend,
                    calendar: currentCalendar
                )
            }.value
            guard !Task.isCancelled,
                  generation == heartRateDropBackfillGeneration else {
                break
            }

            let batchDays = AppleHealthHeartRateDropBackfill.sessionDays(
                in: batch,
                calendar: calendar
            )
            var updated = snapshot
            updated.sleepTrend = updatedTrend
            updated.heartRateDropCalculationVersion =
                Self.currentHeartRateDropCalculationVersion
            updated.heartRateDropProcessedDays =
                processedDays.union(batchDays).sorted()
            snapshot = updated
            cache.save(updated)
            notifyChange()
            await Task.yield()
        }

        if generation == heartRateDropBackfillGeneration {
            heartRateDropBackfillTask = nil
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
            HKObjectType.quantityType(forIdentifier: .heartRate),
            HKObjectType.quantityType(forIdentifier: .respiratoryRate),
            HKObjectType.quantityType(forIdentifier: .vo2Max),
            HKObjectType.quantityType(forIdentifier: .bloodGlucose),
            // Authorize the constituent quantities, not the correlation itself.
            // HealthKit rejects blood-pressure correlations in authorization
            // requests with an Objective-C exception (including on iOS 27).
            HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
            HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .timeInDaylight)
        ].compactMap { $0 }.forEach { types.insert($0) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    /// Kept separate so previously connected people can explicitly receive
    /// the choice for types introduced later.
    static var recentlyAddedAuthorizationReadTypes: Set<HKObjectType> {
        [
            HKObjectType.quantityType(forIdentifier: .timeInDaylight),
            HKObjectType.quantityType(forIdentifier: .heartRate)
        ].compactMap { $0 }.reduce(into: Set<HKObjectType>()) { $0.insert($1) }
    }

    private var readTypes: Set<HKObjectType> {
        Self.authorizationReadTypes(for: ProcessInfo.processInfo.operatingSystemVersion)
    }

    static func authorizationReadTypes(for version: OperatingSystemVersion) -> Set<HKObjectType> {
        guard requiresManualBloodPressureAuthorization(for: version) else {
            return authorizationReadTypes
        }
        // Preserve the manual-authorization workaround for iOS 26.5.
        let bloodPressureTypes: Set<HKObjectType> = Set([
            HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
            HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)
        ].compactMap { $0 })
        return authorizationReadTypes.subtracting(bloodPressureTypes)
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
            
        let now = Date()
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)
        let recentPredicate = HKQuery.predicateForSamples(
            withStart: sixMonthsAgo,
            end: nil,
            options: .strictStartDate
        )
        var catalog: [String: Set<HKSource>] = [:]
        var accumulators: [String: SourceAccumulator] = [:]

        for type in sampleTypes {
            // Sleep is queried from the beginning of HealthKit history. Using
            // the recent six-month window here hid older watches and phones,
            // then made the all-time sleep query fall back to no source filter.
            let predicate = dataKind(for: type) == .sleep ? nil : recentPredicate
            guard let sources = try? await fetchSources(from: healthStore, type: type, predicate: predicate) else {
                continue
            }
            catalog[type.identifier] = sources
            guard let dataKind = dataKind(for: type) else { continue }

            for source in sources.sorted(by: sourceSort) {
                let identifier = AppleHealthSourceIdentity.identifier(for: source)
                var accumulator = accumulators[identifier] ?? SourceAccumulator(
                    name: source.name,
                    bundleIdentifier: source.bundleIdentifier,
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
                dataKinds: AppleHealthDataKind.allCases.filter(accumulator.dataKinds.contains),
                sourceBundleIdentifier: accumulator.bundleIdentifier
            )
        }.sorted { lhs, rhs in
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            return comparison == .orderedSame
                ? lhs.identifier < rhs.identifier
                : comparison == .orderedAscending
        }
        let migratedSelections = sourcePreferences.migratingLegacyDisabledSourceSelections(
            disabledSourceSelections,
            to: availableSources
        )
        if migratedSelections != disabledSourceSelections {
            disabledSourceSelections = migratedSelections
            sourcePreferences.saveDisabledSourceSelections(migratedSelections)
        }
        sourcePreferences.saveSources(availableSources)
    }

    private func fetchSources(
        from healthStore: HKHealthStore,
        type: HKSampleType,
        predicate: NSPredicate? = nil
    ) async throws -> Set<HKSource> {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSourceQuery(sampleType: type, samplePredicate: predicate) { _, sources, error in
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
            let identifiers = [
                AppleHealthSourceIdentity.identifier(for: $0),
                $0.bundleIdentifier
            ]
            return identifiers.contains { identifier in
                disabledSourceSelections.contains(AppleHealthSourceSelection(
                    sourceIdentifier: identifier,
                    dataKind: dataKind
                ))
            }
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
            sourceName: L10n.text("apple_health.source_name")
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
        heartRateSamples: [AppleHealthTimedQuantity],
        cachedFactors: [AppleHealthAutomaticSleepFactors],
        cacheVersion: Int?,
        endingAt endDate: Date
    ) async -> AppleHealthAutomaticSleepFactorHistory {
        guard let firstSession = sessions.min(by: { $0.startDate < $1.startDate }) else {
            return AppleHealthAutomaticSleepFactorHistory(
                factors: [],
                latestStressTimeline: nil
            )
        }
        let firstSessionDate = calendar.startOfDay(for: firstSession.startDate)
        
        let isIncremental = cacheVersion == Self.currentAutomaticSleepFactorsVersion && !cachedFactors.isEmpty
        // Incremental fetch looks back 35 days (30 days for rolling baseline + 5 extra days buffer).
        // Full recalculation limits to 6 months to avoid OOM and speed issues.
        let fetchWindow: TimeInterval = isIncremental ? -(35 * 24 * 3600) : -(6 * 30 * 24 * 3600)
        let startDate = max(firstSessionDate, endDate.addingTimeInterval(fetchWindow))
        let currentCalendar = calendar
        
        let sessionsToProcess = sessions.filter { $0.endDate >= startDate }

        let p_start = Date()
        
        async let stepsTask: [LocalDay: Double] = {
            let s = Date()
            let res = (try? await fetchDailyCumulativeQuantities(from: healthStore, identifier: .stepCount, unit: .count(), start: startDate, end: endDate)) ?? [:]
            print("🕒 stepsTask took \(Date().timeIntervalSince(s))s")
            return res
        }()
        async let daylightTask: [LocalDay: Double] = {
            let s = Date()
            let res = (try? await fetchDailyCumulativeQuantities(from: healthStore, identifier: .timeInDaylight, unit: .minute(), start: startDate, end: endDate)) ?? [:]
            print("🕒 daylightTask took \(Date().timeIntervalSince(s))s")
            return res
        }()
        async let workoutsTask: [AppleHealthWorkout] = {
            let s = Date()
            let res = (try? await fetchWorkouts(from: healthStore, start: startDate, end: endDate)) ?? []
            print("🕒 workoutsTask took \(Date().timeIntervalSince(s))s")
            return res
        }()
        async let daylightSamplesTask: [AppleHealthTimedQuantity] = {
            let s = Date()
            let res = (try? await fetchTimedQuantities(from: healthStore, identifier: .timeInDaylight, unit: .minute(), start: startDate, end: endDate)) ?? []
            print("🕒 daylightSamplesTask took \(Date().timeIntervalSince(s))s")
            return res
        }()
        async let hrvSamplesTask: [AppleHealthTimedQuantity] = {
            let s = Date()
            let res = (try? await fetchTimedQuantities(from: healthStore, identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: startDate, end: endDate)) ?? []
            print("🕒 hrvSamplesTask took \(Date().timeIntervalSince(s))s")
            return res
        }()
        async let restingHeartRateSamplesTask: [AppleHealthTimedQuantity] = {
            let s = Date()
            let res = (try? await fetchTimedQuantities(from: healthStore, identifier: .restingHeartRate, unit: .count().unitDivided(by: .minute()), start: startDate, end: endDate)) ?? []
            print("🕒 restingHeartRateSamplesTask took \(Date().timeIntervalSince(s))s")
            return res
        }()
        async let respiratoryRateSamplesTask: [AppleHealthTimedQuantity] = {
            let s = Date()
            let res = (try? await fetchLatestQuantitiesForSessions(from: healthStore, identifier: .respiratoryRate, unit: .count().unitDivided(by: .minute()), sessions: sessionsToProcess)) ?? []
            print("🕒 respiratoryRateSamplesTask took \(Date().timeIntervalSince(s))s")
            return res
        }()
        async let automaticHeartRateSamplesTask: [AppleHealthTimedQuantity] = {
            if isIncremental {
                return heartRateSamples
            }
            let s = Date()
            let res = (try? await fetchTimedQuantities(
                from: healthStore,
                identifier: .heartRate,
                unit: .count().unitDivided(by: .minute()),
                start: startDate,
                end: endDate
            )) ?? []
            print("🕒 automaticHeartRateSamplesTask took \(Date().timeIntervalSince(s))s")
            return res
        }()
        let (
            steps,
            daylight,
            workouts,
            daylightSamples,
            hrvSamples,
            restingHeartRateSamples,
            respiratoryRateSamples,
            automaticHeartRateSamples
        ) = await (
            stepsTask,
            daylightTask,
            workoutsTask,
            daylightSamplesTask,
            hrvSamplesTask,
            restingHeartRateSamplesTask,
            respiratoryRateSamplesTask,
            automaticHeartRateSamplesTask
        )
        print("🕒 fetchAutomaticSleepFactorHistory total data fetch took \(Date().timeIntervalSince(p_start))s")
        let newHistory = await Task.detached(priority: .userInitiated) {
            AppleHealthBackgroundCalculations.automaticSleepFactorHistory(
                sessions: sessionsToProcess,
                stepsByDay: steps,
                workouts: workouts,
                daylightByDay: daylight,
                daylightSamples: daylightSamples,
                hrvSamples: hrvSamples,
                restingHeartRateSamples: restingHeartRateSamples,
                heartRateSamples: automaticHeartRateSamples,
                respiratoryRateSamples: respiratoryRateSamples,
                sleepQualityByDay: sleepQualityByDay,
                calendar: currentCalendar,
                currentDate: endDate
            )
        }.value

        let thresholdDate = endDate.addingTimeInterval(-(7 * 24 * 3600))
        let retainedFactors = cachedFactors.filter { $0.date < thresholdDate }
        let processedFactors = newHistory.factors
        let validProcessedFactors = isIncremental ? processedFactors.filter { $0.date >= thresholdDate } : processedFactors

        return AppleHealthAutomaticSleepFactorHistory(
            factors: retainedFactors + validProcessedFactors,
            latestStressTimeline: newHistory.latestStressTimeline,
            currentStressDetails: newHistory.currentStressDetails
        )
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

    private func fetchDailyAverageQuantities(
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
            options: [.strictStartDate, .strictEndDate]
        )
        let predicate = applyingSourceFilter(sourceFilter, to: datePredicate)
        let anchorDate = calendar.startOfDay(for: startDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage],
                anchorDate: anchorDate,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }
                var samples: [AppleHealthTimedQuantity] = []
                collection.enumerateStatistics(from: anchorDate, to: endDate) { statistics, _ in
                    guard let quantity = statistics.averageQuantity() else { return }
                    // Mark the reading as "available" at noon of the day it belongs to,
                    // so latestQuantity(before:) finds it reliably for sleep sessions
                    let date = statistics.startDate.addingTimeInterval(12 * 3600)
                    samples.append(AppleHealthTimedQuantity(
                        startDate: date,
                        endDate: date,
                        value: quantity.doubleValue(for: unit)
                    ))
                }
                continuation.resume(returning: samples)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLatestQuantitiesForSessions(
        from healthStore: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        sessions: [AppleHealthSleepSession]
    ) async throws -> [AppleHealthTimedQuantity] {
        guard let firstStart = sessions.map(\.startDate).min(),
              let lastEnd = sessions.map(\.endDate).max() else {
            return []
        }
        let samples = try await fetchTimedQuantities(
            from: healthStore,
            identifier: identifier,
            unit: unit,
            start: firstStart,
            end: lastEnd
        )
        return AppleHealthSessionQuantitySelector.latestSamples(
            from: samples,
            for: sessions
        )
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
