import Darwin
import Foundation

enum SleepFactorCategory: String, CaseIterable, Codable, Sendable {
    case automatic
    case vitalState
    case lifestyle
    case medication
    case nutrition
    case sleep
    case wellbeing
    case custom

    @MainActor
    var title: String {
        L10n.text("sleep.factors.category.\(rawValue)")
    }
}

enum SleepFactorValueKind: Codable, Hashable, Sendable {
    case discrete
    case numeric(unit: String)

    var unit: String? {
        guard case let .numeric(unit) = self else { return nil }
        return unit
    }
}

enum SleepFactorSource: String, Codable, Sendable {
    case automatic
    case manual
}

struct SleepFactorDefinition: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let category: SleepFactorCategory
    let title: String
    let valueKind: SleepFactorValueKind
    let source: SleepFactorSource
    let symbolName: String
    /// Change in X represented by one unit in the explanatory result.
    let analysisStep: Double
    /// Human-readable unit corresponding to `analysisStep`.
    let analysisStepLabel: String

    var isNumeric: Bool {
        if case .numeric = valueKind { return true }
        return false
    }

    /// Built-in numeric factors are quantities or bounded ratings, so a
    /// negative axis would only be a visual padding artefact. Custom factors
    /// deliberately have no bound because a person may define a value such as
    /// temperature that can legitimately be negative.
    var chartMinimumValue: Double? {
        guard isNumeric else { return nil }
        switch source {
        case .automatic:
            return 0
        case .manual:
            switch id {
            case "vital.pain", "vital.mood", "lifestyle.screenMinutes",
                 "nutrition.caffeine", "sleep.napMinutes", "wellbeing.stress",
                 "wellbeing.meditationMinutes":
                return 0
            default:
                return nil
            }
        }
    }

    var chartMaximumValue: Double? {
        guard isNumeric else { return nil }
        switch id {
        case SleepFactorCatalog.automaticPreSleepStressID:
            return 100
        case "vital.pain", "vital.mood", "wellbeing.stress":
            return 10
        default:
            return nil
        }
    }
}

@MainActor
enum SleepFactorCatalog {
    nonisolated static let automaticStepsID = "automatic.steps"
    nonisolated static let automaticStrengthMinutesID = "automatic.strengthMinutes"
    nonisolated static let automaticDaylightMinutesID = "automatic.daylightMinutes"
    nonisolated static let automaticEarlyDaylightMinutesID = "automatic.earlyDaylightMinutes"
    nonisolated static let automaticPreSleepStressID = "automatic.preSleepStress"

    static var predefined: [SleepFactorDefinition] {
        [
            numeric(
                id: automaticStepsID,
                category: .automatic,
                titleKey: "sleep.factor.automatic.steps",
                unitKey: "sleep.factor.unit.steps",
                symbol: "figure.walk",
                source: .automatic,
                analysisStep: 1_000,
                analysisStepLabelKey: "sleep.factor.analysis_unit.thousand_steps"
            ),
            discrete(
                id: automaticStrengthMinutesID,
                category: .automatic,
                titleKey: "sleep.factor.automatic.strength",
                symbol: "figure.strengthtraining.traditional",
                source: .automatic
            ),
            numeric(
                id: automaticDaylightMinutesID,
                category: .automatic,
                titleKey: "sleep.factor.automatic.daylight",
                unitKey: "sleep.factor.unit.minutes",
                symbol: "sun.max.fill",
                source: .automatic,
                analysisStep: 60,
                analysisStepLabelKey: "sleep.factor.analysis_unit.hour"
            ),
            numeric(
                id: automaticEarlyDaylightMinutesID,
                category: .automatic,
                titleKey: "sleep.factor.automatic.early_daylight",
                unitKey: "sleep.factor.unit.minutes",
                symbol: "sunrise.fill",
                source: .automatic,
                analysisStep: 60,
                analysisStepLabelKey: "sleep.factor.analysis_unit.hour"
            ),
            numeric(
                id: automaticPreSleepStressID,
                category: .automatic,
                titleKey: "sleep.factor.automatic.pre_sleep_stress",
                unitKey: "sleep.factor.unit.percent",
                symbol: "waveform.path.ecg",
                source: .automatic,
                analysisStep: 10,
                analysisStepLabelKey: "sleep.factor.analysis_unit.ten_stress_points"
            ),
            discrete(
                id: "vital.illness",
                category: .vitalState,
                titleKey: "sleep.factor.vital.illness",
                symbol: "thermometer.medium"
            ),
            numeric(
                id: "vital.pain",
                category: .vitalState,
                titleKey: "sleep.factor.vital.pain",
                unitKey: "sleep.factor.unit.zero_to_ten",
                symbol: "bolt.heart.fill",
                analysisStepLabelKey: "sleep.factor.analysis_unit.point"
            ),
            numeric(
                id: "vital.mood",
                category: .vitalState,
                titleKey: "sleep.factor.vital.mood",
                unitKey: "sleep.factor.unit.zero_to_ten",
                symbol: "face.smiling",
                analysisStepLabelKey: "sleep.factor.analysis_unit.point"
            ),
            discrete(
                id: "lifestyle.alcohol",
                category: .lifestyle,
                titleKey: "sleep.factor.alcohol",
                symbol: "wineglass.fill"
            ),
            discrete(
                id: "lifestyle.lateTraining",
                category: .lifestyle,
                titleKey: "sleep.factor.late_training",
                symbol: "figure.run"
            ),
            numeric(
                id: "lifestyle.screenMinutes",
                category: .lifestyle,
                titleKey: "sleep.factor.screen_time",
                unitKey: "sleep.factor.unit.minutes",
                symbol: "iphone",
                analysisStepLabelKey: "sleep.factor.analysis_unit.minute"
            ),
            discrete(
                id: "medication.sleepMedication",
                category: .medication,
                titleKey: "sleep.factor.medication.sleep",
                symbol: "pills.fill"
            ),
            discrete(
                id: "medication.change",
                category: .medication,
                titleKey: "sleep.factor.medication.change",
                symbol: "cross.case.fill"
            ),
            discrete(
                id: "nutrition.heavyDinner",
                category: .nutrition,
                titleKey: "sleep.factor.heavy_dinner",
                symbol: "fork.knife"
            ),
            numeric(
                id: "nutrition.caffeine",
                category: .nutrition,
                titleKey: "sleep.factor.nutrition.caffeine",
                unitKey: "sleep.factor.unit.milligrams",
                symbol: "cup.and.saucer.fill",
                analysisStep: 10,
                analysisStepLabelKey: "sleep.factor.analysis_unit.ten_milligrams"
            ),
            discrete(
                id: "nutrition.lateDinner",
                category: .nutrition,
                titleKey: "sleep.factor.nutrition.late_dinner",
                symbol: "clock.badge.exclamationmark"
            ),
            numeric(
                id: "sleep.napMinutes",
                category: .sleep,
                titleKey: "sleep.factor.nap",
                unitKey: "sleep.factor.unit.minutes",
                symbol: "bed.double.fill",
                analysisStepLabelKey: "sleep.factor.analysis_unit.minute"
            ),
            discrete(
                id: "sleep.lateBedtime",
                category: .sleep,
                titleKey: "sleep.factor.sleep.late_bedtime",
                symbol: "moon.zzz.fill"
            ),
            discrete(
                id: "sleep.noise",
                category: .sleep,
                titleKey: "sleep.factor.sleep.noise",
                symbol: "speaker.wave.3.fill"
            ),
            numeric(
                id: "wellbeing.stress",
                category: .wellbeing,
                titleKey: "sleep.factor.stress",
                unitKey: "sleep.factor.unit.zero_to_ten",
                symbol: "brain.head.profile",
                analysisStepLabelKey: "sleep.factor.analysis_unit.point"
            ),
            numeric(
                id: "wellbeing.meditationMinutes",
                category: .wellbeing,
                titleKey: "sleep.factor.wellbeing.meditation",
                unitKey: "sleep.factor.unit.minutes",
                symbol: "figure.mind.and.body",
                analysisStepLabelKey: "sleep.factor.analysis_unit.minute"
            ),
            discrete(
                id: "wellbeing.relaxation",
                category: .wellbeing,
                titleKey: "sleep.factor.wellbeing.relaxation",
                symbol: "leaf.fill"
            )
        ]
    }

    static func definition(
        id: String,
        customDefinitions: [SleepFactorDefinition] = WellnessLocalStore.customSleepFactorDefinitions
    ) -> SleepFactorDefinition? {
        (predefined + customDefinitions).first { $0.id == id }
    }

    static func definition(
        matchingLegacyTitle title: String,
        customDefinitions: [SleepFactorDefinition] = WellnessLocalStore.customSleepFactorDefinitions
    ) -> SleepFactorDefinition? {
        (predefined + customDefinitions).first {
            $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame
        }
    }

    private static func discrete(
        id: String,
        category: SleepFactorCategory,
        titleKey: String,
        symbol: String,
        source: SleepFactorSource = .manual
    ) -> SleepFactorDefinition {
        SleepFactorDefinition(
            id: id,
            category: category,
            title: L10n.text(titleKey),
            valueKind: .discrete,
            source: source,
            symbolName: symbol,
            analysisStep: 1,
            analysisStepLabel: ""
        )
    }

    private static func numeric(
        id: String,
        category: SleepFactorCategory,
        titleKey: String,
        unitKey: String,
        symbol: String,
        source: SleepFactorSource = .manual,
        analysisStep: Double = 1,
        analysisStepLabelKey: String
    ) -> SleepFactorDefinition {
        SleepFactorDefinition(
            id: id,
            category: category,
            title: L10n.text(titleKey),
            valueKind: .numeric(unit: L10n.text(unitKey)),
            source: source,
            symbolName: symbol,
            analysisStep: analysisStep,
            analysisStepLabel: L10n.text(analysisStepLabelKey)
        )
    }
}

enum SleepFactorOutcome: Int, CaseIterable, Sendable {
    case quality
    case duration

    @MainActor
    var title: String {
        switch self {
        case .quality: L10n.text("sleep.trend.metric.quality")
        case .duration: L10n.text("sleep.trend.metric.duration")
        }
    }
}

struct SleepFactorDataPoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

enum SleepFactorRegressionKind: Equatable, Sendable {
    case linear
    case quadratic
}

struct SleepFactorNumericImpact: Equatable, Sendable {
    let model: SleepFactorRegressionKind
    let intercept: Double
    let linearCoefficient: Double
    let quadraticCoefficient: Double
    let effectPercentPerStep: Double
    let confidence: Double
    let sampleCount: Int
    let points: [SleepFactorDataPoint]
    let optimumX: Double?

    func predictedValue(at x: Double) -> Double {
        intercept + linearCoefficient * x + quadraticCoefficient * x * x
    }
}

struct SleepFactorDiscreteImpact: Equatable, Sendable {
    let effectPercent: Double
    let confidence: Double
    let presentSampleCount: Int
    let absentSampleCount: Int
    let presentMean: Double
    let absentMean: Double
}

enum SleepFactorImpact: Equatable, Sendable {
    case numeric(SleepFactorNumericImpact)
    case discrete(SleepFactorDiscreteImpact)
    case insufficient(
        sampleCount: Int,
        presentSampleCount: Int? = nil,
        absentSampleCount: Int? = nil
    )
}

enum SleepFactorStatistics {
    /// With fewer than seven nights in either group, a comparison can look
    /// convincing by chance even though it is not useful for sleep decisions.
    static let minimumDiscreteGroupSamples = 7

    static func analyzeNumeric(
        _ points: [SleepFactorDataPoint],
        analysisStep: Double
    ) -> SleepFactorImpact {
        let samples = points.filter { $0.x.isFinite && $0.y.isFinite }
        guard samples.count >= 4,
              Set(samples.map(\.x)).count >= 3,
              let linear = linearFit(samples) else {
            return .insufficient(sampleCount: samples.count)
        }

        let quadratic = samples.count >= 6 ? quadraticFit(samples) : nil
        let chosenQuadratic = quadratic.flatMap { fit -> RegressionFit? in
            fit.aicc + 2 < linear.aicc ? fit : nil
        }
        let fit = chosenQuadratic ?? linear
        let meanX = samples.map(\.x).reduce(0, +) / Double(samples.count)
        let meanY = samples.map(\.y).reduce(0, +) / Double(samples.count)
        let derivative = fit.linear + (2 * fit.quadratic * meanX)
        let effect = meanY == 0 ? 0 : (derivative * analysisStep / abs(meanY)) * 100
        let confidence = modelConfidence(rSquared: fit.rSquared, sampleCount: samples.count)
        let range = (samples.map(\.x).min() ?? 0)...(samples.map(\.x).max() ?? 0)
        let optimum: Double?
        if fit.kind == .quadratic, abs(fit.quadratic) > .ulpOfOne {
            let candidate = -fit.linear / (2 * fit.quadratic)
            optimum = range.contains(candidate) ? candidate : nil
        } else {
            optimum = nil
        }
        return .numeric(SleepFactorNumericImpact(
            model: fit.kind,
            intercept: fit.intercept,
            linearCoefficient: fit.linear,
            quadraticCoefficient: fit.quadratic,
            effectPercentPerStep: effect,
            confidence: confidence,
            sampleCount: samples.count,
            points: samples.sorted { $0.x < $1.x },
            optimumX: optimum
        ))
    }

    static func analyzeDiscrete(
        presentValues: [Double],
        absentValues: [Double]
    ) -> SleepFactorImpact {
        let present = presentValues.filter(\.isFinite)
        let absent = absentValues.filter(\.isFinite)
        guard present.count >= minimumDiscreteGroupSamples,
              absent.count >= minimumDiscreteGroupSamples else {
            return .insufficient(
                sampleCount: present.count + absent.count,
                presentSampleCount: present.count,
                absentSampleCount: absent.count
            )
        }
        let presentMean = mean(present)
        let absentMean = mean(absent)
        let effect = absentMean == 0 ? 0 : ((presentMean - absentMean) / abs(absentMean)) * 100
        let variancePresent = sampleVariance(present, mean: presentMean)
        let varianceAbsent = sampleVariance(absent, mean: absentMean)
        let standardError = sqrt(
            variancePresent / Double(present.count)
                + varianceAbsent / Double(absent.count)
        )
        let z = standardError > .ulpOfOne
            ? abs(presentMean - absentMean) / standardError
            : (presentMean == absentMean ? 0 : 8)
        return .discrete(SleepFactorDiscreteImpact(
            effectPercent: effect,
            confidence: min(max(erf(z / sqrt(2)), 0), 0.999),
            presentSampleCount: present.count,
            absentSampleCount: absent.count,
            presentMean: presentMean,
            absentMean: absentMean
        ))
    }

    private struct RegressionFit {
        let kind: SleepFactorRegressionKind
        let intercept: Double
        let linear: Double
        let quadratic: Double
        let rSquared: Double
        let aicc: Double
    }

    private static func linearFit(_ points: [SleepFactorDataPoint]) -> RegressionFit? {
        let count = Double(points.count)
        let meanX = points.map(\.x).reduce(0, +) / count
        let meanY = points.map(\.y).reduce(0, +) / count
        let denominator = points.reduce(0) { $0 + pow($1.x - meanX, 2) }
        guard denominator > .ulpOfOne else { return nil }
        let slope = points.reduce(0) {
            $0 + ($1.x - meanX) * ($1.y - meanY)
        } / denominator
        let intercept = meanY - slope * meanX
        return regressionFit(
            kind: .linear,
            intercept: intercept,
            linear: slope,
            quadratic: 0,
            points: points,
            parameterCount: 2
        )
    }

    private static func quadraticFit(_ points: [SleepFactorDataPoint]) -> RegressionFit? {
        let n = Double(points.count)
        let sx = points.reduce(0) { $0 + $1.x }
        let sx2 = points.reduce(0) { $0 + pow($1.x, 2) }
        let sx3 = points.reduce(0) { $0 + pow($1.x, 3) }
        let sx4 = points.reduce(0) { $0 + pow($1.x, 4) }
        let sy = points.reduce(0) { $0 + $1.y }
        let sxy = points.reduce(0) { $0 + $1.x * $1.y }
        let sx2y = points.reduce(0) { $0 + pow($1.x, 2) * $1.y }
        guard let coefficients = solve3x3(
            matrix: [
                [n, sx, sx2],
                [sx, sx2, sx3],
                [sx2, sx3, sx4]
            ],
            values: [sy, sxy, sx2y]
        ) else {
            return nil
        }
        return regressionFit(
            kind: .quadratic,
            intercept: coefficients[0],
            linear: coefficients[1],
            quadratic: coefficients[2],
            points: points,
            parameterCount: 3
        )
    }

    private static func regressionFit(
        kind: SleepFactorRegressionKind,
        intercept: Double,
        linear: Double,
        quadratic: Double,
        points: [SleepFactorDataPoint],
        parameterCount: Int
    ) -> RegressionFit {
        let meanY = mean(points.map(\.y))
        let total = points.reduce(0) { $0 + pow($1.y - meanY, 2) }
        let residual = points.reduce(0) { partial, point in
            let predicted = intercept + linear * point.x + quadratic * point.x * point.x
            return partial + pow(point.y - predicted, 2)
        }
        let rSquared = total > .ulpOfOne ? max(0, min(1, 1 - residual / total)) : 0
        let n = Double(points.count)
        let k = Double(parameterCount)
        let baseAIC = n * log(max(residual / n, 1e-12)) + 2 * k
        let correction = n > k + 1 ? (2 * k * (k + 1)) / (n - k - 1) : .infinity
        return RegressionFit(
            kind: kind,
            intercept: intercept,
            linear: linear,
            quadratic: quadratic,
            rSquared: rSquared,
            aicc: baseAIC + correction
        )
    }

    private static func solve3x3(matrix: [[Double]], values: [Double]) -> [Double]? {
        var augmented = zip(matrix, values).map { $0 + [$1] }
        for pivot in 0..<3 {
            guard let bestRow = (pivot..<3).max(by: {
                abs(augmented[$0][pivot]) < abs(augmented[$1][pivot])
            }), abs(augmented[bestRow][pivot]) > 1e-10 else {
                return nil
            }
            if bestRow != pivot { augmented.swapAt(bestRow, pivot) }
            let divisor = augmented[pivot][pivot]
            for column in pivot..<4 { augmented[pivot][column] /= divisor }
            for row in 0..<3 where row != pivot {
                let multiplier = augmented[row][pivot]
                for column in pivot..<4 {
                    augmented[row][column] -= multiplier * augmented[pivot][column]
                }
            }
        }
        return augmented.map { $0[3] }
    }

    private static func modelConfidence(rSquared: Double, sampleCount: Int) -> Double {
        guard rSquared > 0, sampleCount > 3 else { return 0 }
        let z = sqrt(
            rSquared * Double(sampleCount - 2) / max(1 - rSquared, 1e-9)
        )
        return min(max(erf(z / sqrt(2)), 0), 0.999)
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    private static func sampleVariance(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        return values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
    }
}
