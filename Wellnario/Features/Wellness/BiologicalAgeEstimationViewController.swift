import UIKit

enum BiologicalAgeMarker: String, CaseIterable, Hashable, Sendable {
    case albumin
    case creatinine
    case glucose
    case cReactiveProtein
    case lymphocytePercentage
    case meanCorpuscularVolume
    case redCellDistributionWidth
    case alkalinePhosphatase
    case whiteBloodCellCount
    case forcedExpiratoryVolume
    case systolicBloodPressure
    case totalCholesterol
    case glycatedHemoglobin
    case bloodUreaNitrogen

    static let phenoAgeMarkers: Set<Self> = [
        .albumin,
        .creatinine,
        .glucose,
        .cReactiveProtein,
        .lymphocytePercentage,
        .meanCorpuscularVolume,
        .redCellDistributionWidth,
        .alkalinePhosphatase,
        .whiteBloodCellCount
    ]

    static let bioAgeMarkers: Set<Self> = [
        .forcedExpiratoryVolume,
        .systolicBloodPressure,
        .totalCholesterol,
        .glycatedHemoglobin,
        .albumin,
        .creatinine,
        .cReactiveProtein,
        .alkalinePhosphatase,
        .bloodUreaNitrogen
    ]

    @MainActor
    var title: String {
        L10n.text("health.biological_age.marker.\(rawValue)")
    }

    var canonicalUnit: String {
        switch self {
        case .albumin: "g/dL"
        case .creatinine: "mg/dL"
        case .glucose: "mg/dL"
        case .cReactiveProtein: "mg/dL"
        case .lymphocytePercentage: "%"
        case .meanCorpuscularVolume: "fL"
        case .redCellDistributionWidth: "%"
        case .alkalinePhosphatase: "U/L"
        case .whiteBloodCellCount: "10³/µL"
        case .forcedExpiratoryVolume: "mL"
        case .systolicBloodPressure: "mmHg"
        case .totalCholesterol: "mg/dL"
        case .glycatedHemoglobin: "%"
        case .bloodUreaNitrogen: "mg/dL"
        }
    }

    fileprivate var seededNameKey: String? {
        switch self {
        case .albumin: "health.biomarker.catalog.albumin"
        case .creatinine: "health.biomarker.catalog.creatinine"
        case .glucose: "health.biomarker.catalog.glucose_blood"
        case .cReactiveProtein: "health.biomarker.catalog.crp"
        case .lymphocytePercentage: "health.biomarker.catalog.lymphocyte_percentage"
        case .meanCorpuscularVolume: "health.biomarker.catalog.mcv"
        case .redCellDistributionWidth: "health.biomarker.catalog.rdw"
        case .alkalinePhosphatase: "health.biomarker.catalog.alkaline_phosphatase"
        case .whiteBloodCellCount: "health.biomarker.catalog.leukocytes_blood"
        case .forcedExpiratoryVolume: "health.biomarker.catalog.fev1"
        case .systolicBloodPressure: "health.biomarker.catalog.systolic_blood_pressure"
        case .totalCholesterol: "health.biomarker.catalog.cholesterol"
        case .glycatedHemoglobin: "health.biomarker.catalog.glycated_hemoglobin"
        case .bloodUreaNitrogen: "health.biomarker.catalog.bun"
        }
    }

    fileprivate var aliases: [String] {
        switch self {
        case .albumin:
            ["albumina", "albumin"]
        case .creatinine:
            ["creatinina", "creatinine"]
        case .glucose:
            ["glucosa", "glucose"]
        case .cReactiveProtein:
            ["proteina c reactiva", "pcr", "c reactive protein", "crp"]
        case .lymphocytePercentage:
            ["linfocitos", "porcentaje de linfocitos", "lymphocytes", "lymphocyte percentage"]
        case .meanCorpuscularVolume:
            ["vcm", "volumen corpuscular medio", "mcv", "mean corpuscular volume"]
        case .redCellDistributionWidth:
            ["rdw", "ade", "amplitud de distribucion eritrocitaria", "red cell distribution width"]
        case .alkalinePhosphatase:
            ["fosfatasa alcalina", "alkaline phosphatase", "alp"]
        case .whiteBloodCellCount:
            ["leucocitos", "recuento leucocitario", "white blood cells", "wbc"]
        case .forcedExpiratoryVolume:
            ["vef1", "fev1", "volumen espiratorio forzado", "forced expiratory volume"]
        case .systolicBloodPressure:
            ["presion arterial sistolica", "tension arterial sistolica", "systolic blood pressure", "sbp"]
        case .totalCholesterol:
            ["colesterol total", "colesterol", "total cholesterol", "cholesterol"]
        case .glycatedHemoglobin:
            ["hemoglobina glicosilada", "hba1c", "glycated hemoglobin"]
        case .bloodUreaNitrogen:
            ["nitrogeno ureico", "bun", "blood urea nitrogen"]
        }
    }
}

struct BiologicalAgeEstimate: Equatable, Sendable {
    let phenoAge: Double?
    let bioAge: Double?
}

enum BiologicalAgeValueSource: Equatable, Sendable {
    case analysis(date: Date, isOlderThanTwoYears: Bool)
    case appleHealthSystolicAverage(asOf: Date)
    case populationAverage

    var analysisDate: Date? {
        guard case let .analysis(date, _) = self else { return nil }
        return date
    }

    var isEditable: Bool {
        switch self {
        case let .analysis(_, isOlderThanTwoYears): isOlderThanTwoYears
        case .appleHealthSystolicAverage: false
        case .populationAverage: true
        }
    }
}

struct BiologicalAgeResolvedValue: Equatable, Sendable {
    let marker: BiologicalAgeMarker
    var value: Double
    let populationAverage: Double
    let source: BiologicalAgeValueSource
    var isCreatinineAdjusted: Bool
    var wasManuallyReviewed: Bool = false
}

struct BiologicalAgeProfile: Equatable, Sendable {
    let chronologicalAge: Int?
    let biologicalSex: AppleHealthBiologicalSex?
    let values: [BiologicalAgeMarker: BiologicalAgeResolvedValue]
    let estimate: BiologicalAgeEstimate

    var weightedEstimate: BiologicalAgeWeightedEstimate {
        let phenoCoverage = freshAnalysisCoverage(
            for: BiologicalAgeMarker.phenoAgeMarkers
        )
        let bioCoverage = freshAnalysisCoverage(
            for: BiologicalAgeMarker.bioAgeMarkers
        )

        let age: Double?
        switch (estimate.phenoAge, estimate.bioAge) {
        case let (phenoAge?, bioAge?):
            let totalWeight = phenoCoverage + bioCoverage
            if totalWeight > 0 {
                age = (
                    phenoAge * phenoCoverage
                    + bioAge * bioCoverage
                ) / totalWeight
            } else {
                age = (phenoAge + bioAge) / 2
            }
        case let (phenoAge?, nil):
            age = phenoAge
        case let (nil, bioAge?):
            age = bioAge
        case (nil, nil):
            age = nil
        }

        return BiologicalAgeWeightedEstimate(
            age: age,
            phenoAgeFreshAnalysisCoverage: phenoCoverage,
            bioAgeFreshAnalysisCoverage: bioCoverage
        )
    }

    private func freshAnalysisCoverage(
        for markers: Set<BiologicalAgeMarker>
    ) -> Double {
        guard !markers.isEmpty else { return 0 }
        let freshCount = markers.reduce(into: 0) { count, marker in
            guard let value = values[marker],
                  case .analysis(_, isOlderThanTwoYears: false) = value.source else {
                return
            }
            count += 1
        }
        return Double(freshCount) / Double(markers.count)
    }
}

struct BiologicalAgeWeightedEstimate: Equatable, Sendable {
    let age: Double?
    let phenoAgeFreshAnalysisCoverage: Double
    let bioAgeFreshAnalysisCoverage: Double
}

enum BiologicalAgeCalculator {
    private struct Regression {
        let intercept: Double
        let slope: Double
        let residualDeviation: Double
    }

    static func phenoAge(
        chronologicalAge: Double,
        values: [BiologicalAgeMarker: Double]
    ) -> Double? {
        guard let albumin = values[.albumin],
              let creatinine = values[.creatinine],
              let glucose = values[.glucose],
              let crp = values[.cReactiveProtein],
              let lymphocytes = values[.lymphocytePercentage],
              let mcv = values[.meanCorpuscularVolume],
              let rdw = values[.redCellDistributionWidth],
              let alkalinePhosphatase = values[.alkalinePhosphatase],
              let whiteBloodCells = values[.whiteBloodCellCount],
              crp >= 0 else {
            return nil
        }

        let linearPredictor =
            -19.90667
            - 0.03359355 * (albumin * 10)
            + 0.009506491 * (creatinine * 88.4017)
            + 0.1953192 * (glucose * 0.0555)
            + 0.09536762 * log(1 + crp)
            - 0.01199984 * lymphocytes
            + 0.02676401 * mcv
            + 0.3306156 * rdw
            + 0.001868778 * alkalinePhosphatase
            + 0.05542406 * whiteBloodCells
            + 0.08035356 * chronologicalAge

        let mortalityRisk = 1 - exp((-1.51714 * exp(linearPredictor)) / 0.007692696)
        let boundedRisk = min(max(mortalityRisk, Double.leastNonzeroMagnitude), 1 - 1e-12)
        let transformedRisk = -0.0055305 * log(1 - boundedRisk)
        guard transformedRisk > 0 else { return nil }
        return log(transformedRisk) / 0.090165 + 141.50225
    }

    static func bioAge(
        chronologicalAge: Double,
        sex: AppleHealthBiologicalSex,
        values: [BiologicalAgeMarker: Double]
    ) -> Double? {
        guard let parameters = bioAgeParameters(for: sex) else { return nil }
        let regressions = parameters.regressions
        guard regressions.keys.allSatisfy({ values[$0] != nil }) else { return nil }

        var numerator = 0.0
        var denominator = 0.0
        for (marker, regression) in regressions {
            guard var value = values[marker] else { return nil }
            if marker == .cReactiveProtein {
                guard value >= 0 else { return nil }
                value = log(1 + value)
            }
            let variance = regression.residualDeviation * regression.residualDeviation
            numerator += (value - regression.intercept) * regression.slope / variance
            denominator += pow(regression.slope / regression.residualDeviation, 2)
        }

        return (numerator + chronologicalAge / parameters.biologicalAgeVariance)
            / (denominator + 1 / parameters.biologicalAgeVariance)
    }

    static func populationAverage(
        for marker: BiologicalAgeMarker,
        age: Double,
        sex: AppleHealthBiologicalSex
    ) -> Double? {
        guard sex == .female || sex == .male else { return nil }
        let pair: (intercept: Double, slope: Double)
        switch (sex, marker) {
        case (.male, .albumin): pair = (4.6035635625344, -0.0075322054560026)
        case (.male, .creatinine): pair = (0.808360959843825, 0.00322705176807644)
        case (.male, .glucose): pair = (82.3748561103877, 0.361449217357743)
        case (.male, .cReactiveProtein): pair = (0.171833062042172, 0.00428067458706998)
        case (.male, .lymphocytePercentage): pair = (36.6740842265735, -0.0895995811474931)
        case (.male, .meanCorpuscularVolume): pair = (87.7123274843186, 0.0479840899464439)
        case (.male, .redCellDistributionWidth): pair = (12.3132390619981, 0.0168221486417584)
        case (.male, .alkalinePhosphatase): pair = (82.3456475331894, 0.118293276907739)
        case (.male, .whiteBloodCellCount): pair = (6.92759576926947, 0.00443680765986976)
        case (.female, .albumin): pair = (4.10879220584658, -0.00146598422136805)
        case (.female, .creatinine): pair = (0.581956410233673, 0.00343084878335352)
        case (.female, .glucose): pair = (75.6427132381184, 0.45648566510593)
        case (.female, .cReactiveProtein): pair = (0.405548709414768, 0.00177259024625752)
        case (.female, .lymphocytePercentage): pair = (34.7512139577364, -0.028272700490517)
        case (.female, .meanCorpuscularVolume): pair = (86.7289643649125, 0.0447411855328097)
        case (.female, .redCellDistributionWidth): pair = (12.8537166644568, 0.00746928119181165)
        case (.female, .alkalinePhosphatase): pair = (63.3173481595909, 0.45555176869775)
        case (.female, .whiteBloodCellCount): pair = (7.67495301518379, -0.009180897857832)
        default:
            guard let regression = bioAgeParameters(for: sex)?.regressions[marker] else {
                return nil
            }
            pair = (regression.intercept, regression.slope)
        }
        return max(0.001, pair.intercept + pair.slope * age)
    }

    private static func bioAgeParameters(
        for sex: AppleHealthBiologicalSex
    ) -> (biologicalAgeVariance: Double, regressions: [BiologicalAgeMarker: Regression])? {
        switch sex {
        case .male:
            return (
                802.3076,
                [
                    .forcedExpiratoryVolume: .init(intercept: 5306.505957531714, slope: -38.79587622479422, residualDeviation: 675.293422085246),
                    .systolicBloodPressure: .init(intercept: 101.089652036507, slope: 0.55738260440710, residualDeviation: 15.879224698559),
                    .totalCholesterol: .init(intercept: 190.325788860880, slope: 0.38494211703774, residualDeviation: 40.855239843759),
                    .glycatedHemoglobin: .init(intercept: 4.731511105862, slope: 0.01732942292290, residualDeviation: 0.921120203244),
                    .albumin: .init(intercept: 4.577019066155, slope: -0.00725205979230, residualDeviation: 0.343255342199),
                    .creatinine: .init(intercept: 0.788608163293, slope: 0.00337259360810, residualDeviation: 0.205489712632),
                    .cReactiveProtein: .init(intercept: 0.154975131951, slope: 0.00278167930826, residualDeviation: 0.219097750220),
                    .alkalinePhosphatase: .init(intercept: 76.037061005160, slope: 0.22289070270808, residualDeviation: 25.494586472040),
                    .bloodUreaNitrogen: .init(intercept: 10.107635605091, slope: 0.10113295950921, residualDeviation: 4.827920343371)
                ]
            )
        case .female:
            return (
                576.5413,
                [
                    .forcedExpiratoryVolume: .init(intercept: 3927.674198851609, slope: -29.89563038717856, residualDeviation: 485.290614394642),
                    .systolicBloodPressure: .init(intercept: 85.511380909615, slope: 0.79615504192375, residualDeviation: 16.847323122060),
                    .totalCholesterol: .init(intercept: 146.349524338774, slope: 1.31479151585702, residualDeviation: 41.231072544253),
                    .glycatedHemoglobin: .init(intercept: 4.449792928335, slope: 0.02295361690261, residualDeviation: 1.011862650312),
                    .albumin: .init(intercept: 4.157074783338, slope: -0.00218719680304, residualDeviation: 0.342769220139),
                    .creatinine: .init(intercept: 0.584474180669, slope: 0.00325438285236, residualDeviation: 0.165232287780),
                    .cReactiveProtein: .init(intercept: 0.303289326927, slope: 0.00117759956019, residualDeviation: 0.279985823701),
                    .alkalinePhosphatase: .init(intercept: 54.958375866792, slope: 0.62992731342012, residualDeviation: 27.885066405307),
                    .bloodUreaNitrogen: .init(intercept: 6.193569618961, slope: 0.14484356956869, residualDeviation: 4.235136640928)
                ]
            )
        case .other, .notSet:
            return nil
        }
    }
}

@MainActor
final class BiologicalAgePreferences {
    private struct ManualValue: Codable {
        let value: Double
        let analysisDate: Date?
    }

    private let defaults: UserDefaults
    private let valuesKey = "wellnario.biologicalAge.manualValues.v2"
    private let creatinineAdjustmentKey = "wellnario.biologicalAge.creatinineAdjustment.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var creatineOrStrengthTraining: Bool {
        get { defaults.bool(forKey: creatinineAdjustmentKey) }
        set { defaults.set(newValue, forKey: creatinineAdjustmentKey) }
    }

    func manualValue(
        for marker: BiologicalAgeMarker,
        source: BiologicalAgeValueSource
    ) -> Double? {
        guard let stored = storedValues[marker.rawValue] else { return nil }
        switch source {
        case .populationAverage:
            return stored.analysisDate == nil ? stored.value : nil
        case let .analysis(date, _):
            guard let storedDate = stored.analysisDate,
                  abs(storedDate.timeIntervalSince(date)) < 1 else { return nil }
            return stored.value
        case .appleHealthSystolicAverage:
            return nil
        }
    }

    func setManualValues(
        _ values: [BiologicalAgeMarker: (value: Double, source: BiologicalAgeValueSource)]
    ) {
        var stored = storedValues
        for (marker, entry) in values {
            stored[marker.rawValue] = ManualValue(
                value: entry.value,
                analysisDate: entry.source.analysisDate
            )
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: valuesKey)
    }

    private var storedValues: [String: ManualValue] {
        guard let data = defaults.data(forKey: valuesKey),
              let stored = try? JSONDecoder().decode([String: ManualValue].self, from: data) else {
            return [:]
        }
        return stored
    }
}

@MainActor
enum BiologicalAgeProfileResolver {
    private struct LatestResult {
        let value: Double
        let date: Date
    }

    static func resolve(
        store: HealthDataStore,
        snapshot: AppleHealthSnapshot,
        preferences: BiologicalAgePreferences,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> BiologicalAgeProfile {
        let age = chronologicalAge(
            from: snapshot.dateOfBirthComponents,
            on: now,
            calendar: calendar
        )
        guard let age,
              let sex = snapshot.biologicalSex,
              sex == .female || sex == .male else {
            return BiologicalAgeProfile(
                chronologicalAge: age,
                biologicalSex: snapshot.biologicalSex,
                values: [:],
                estimate: BiologicalAgeEstimate(phenoAge: nil, bioAge: nil)
            )
        }

        let latestResults = latestResults(in: store)
        let cutoff = calendar.date(byAdding: .year, value: -2, to: now) ?? .distantPast
        var resolved: [BiologicalAgeMarker: BiologicalAgeResolvedValue] = [:]

        for marker in BiologicalAgeMarker.allCases {
            guard let average = BiologicalAgeCalculator.populationAverage(
                for: marker,
                age: Double(age),
                sex: sex
            ) else { continue }
            if marker == .systolicBloodPressure,
               let systolicAverage = snapshot.systolicBloodPressureSixMonthAverage,
               systolicAverage.value.isFinite,
               systolicAverage.value >= 0 {
                resolved[marker] = BiologicalAgeResolvedValue(
                    marker: marker,
                    value: systolicAverage.value,
                    populationAverage: average,
                    source: .appleHealthSystolicAverage(asOf: systolicAverage.date),
                    isCreatinineAdjusted: false
                )
            } else if let latest = latestResults[marker] {
                let isOld = latest.date < cutoff
                let source = BiologicalAgeValueSource.analysis(
                    date: latest.date,
                    isOlderThanTwoYears: isOld
                )
                let manualValue = isOld
                    ? preferences.manualValue(for: marker, source: source)
                    : nil
                resolved[marker] = BiologicalAgeResolvedValue(
                    marker: marker,
                    value: manualValue ?? latest.value,
                    populationAverage: average,
                    source: source,
                    isCreatinineAdjusted: false,
                    wasManuallyReviewed: manualValue != nil
                )
            } else {
                let source = BiologicalAgeValueSource.populationAverage
                let manualValue = preferences.manualValue(for: marker, source: source)
                resolved[marker] = BiologicalAgeResolvedValue(
                    marker: marker,
                    value: manualValue ?? average,
                    populationAverage: average,
                    source: source,
                    isCreatinineAdjusted: false,
                    wasManuallyReviewed: manualValue != nil
                )
            }
        }

        if preferences.creatineOrStrengthTraining,
           var creatinine = resolved[.creatinine],
           creatinine.source.analysisDate != nil {
            creatinine.value = (creatinine.value + creatinine.populationAverage) / 2
            creatinine.isCreatinineAdjusted = true
            resolved[.creatinine] = creatinine
        }

        let values = resolved.mapValues(\.value)
        return BiologicalAgeProfile(
            chronologicalAge: age,
            biologicalSex: sex,
            values: resolved,
            estimate: BiologicalAgeEstimate(
                phenoAge: BiologicalAgeCalculator.phenoAge(
                    chronologicalAge: Double(age),
                    values: values
                ),
                bioAge: BiologicalAgeCalculator.bioAge(
                    chronologicalAge: Double(age),
                    sex: sex,
                    values: values
                )
            )
        )
    }

    private static func chronologicalAge(
        from components: DateComponents?,
        on date: Date,
        calendar: Calendar
    ) -> Int? {
        guard let components,
              let birthDate = calendar.date(from: components),
              birthDate <= date else { return nil }
        return calendar.dateComponents([.year], from: birthDate, to: date).year
    }

    private static func latestResults(
        in store: HealthDataStore
    ) -> [BiologicalAgeMarker: LatestResult] {
        let biomarkers = Dictionary(
            uniqueKeysWithValues: store.biomarkers(includeArchived: true).map { ($0.id, $0) }
        )
        var latest: [BiologicalAgeMarker: LatestResult] = [:]
        for analysis in store.analyses() {
            for result in analysis.results {
                guard let biomarker = biomarkers[result.biomarkerID],
                      let marker = marker(for: biomarker),
                      let converted = canonicalValue(result, for: marker),
                      converted.isFinite,
                      converted >= 0 else { continue }
                if latest[marker].map({ $0.date >= analysis.collectedAt }) == true {
                    continue
                }
                latest[marker] = LatestResult(value: converted, date: analysis.collectedAt)
            }
        }
        return latest
    }

    private static func marker(for biomarker: HealthBiomarker) -> BiologicalAgeMarker? {
        if let nameKey = biomarker.nameKey,
           let exact = BiologicalAgeMarker.allCases.first(where: { $0.seededNameKey == nameKey }) {
            return exact
        }
        let name = normalized(biomarker.customName ?? biomarker.name)
        return BiologicalAgeMarker.allCases.first { marker in
            marker.aliases.contains { alias in
                let candidate = normalized(alias)
                return name == candidate || name.hasPrefix("\(candidate) ")
            }
        }
    }

    private static func canonicalValue(
        _ result: LabResult,
        for marker: BiologicalAgeMarker
    ) -> Double? {
        let value = NSDecimalNumber(decimal: result.value).doubleValue
        let unit = normalizedUnit(result.unit)
        switch marker {
        case .albumin where unit == "g/l":
            return value / 10
        case .creatinine where unit == "umol/l":
            return value / 88.4017
        case .glucose where unit == "mmol/l":
            return value / 0.0555
        case .cReactiveProtein where unit == "mg/l":
            return value / 10
        case .totalCholesterol where unit == "mmol/l":
            return value * 38.67
        case .glycatedHemoglobin where unit == "mmol/mol":
            return (value + 23.5) / 10.93
        case .alkalinePhosphatase where unit == "ukat/l":
            return value * 60
        case .forcedExpiratoryVolume where unit == "l":
            return value * 1_000
        case .bloodUreaNitrogen where unit == "mmol/l":
            return value * 2.801
        default:
            return value
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedUnit(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "µ", with: "u")
            .replacingOccurrences(of: "μ", with: "u")
            .replacingOccurrences(of: " ", with: "")
    }
}

@MainActor
final class BiologicalAgeEstimationViewController: WellnessScrollViewController {
    private let store: HealthDataStore
    private let appleHealthService: AppleHealthSyncing
    private let preferences: BiologicalAgePreferences
    private var profile: BiologicalAgeProfile?
    private var editableFields: [BiologicalAgeMarker: FormFieldView] = [:]
    private let creatinineSwitch = UISwitch()
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    init(
        store: HealthDataStore,
        appleHealthService: AppleHealthSyncing,
        preferences: BiologicalAgePreferences
    ) {
        self.store = store
        self.appleHealthService = appleHealthService
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("health.biological_age.screen.title")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.backButtonDisplayMode = .minimal
        view.accessibilityIdentifier = "health.biological_age.estimation"
        scrollView.keyboardDismissMode = .interactive
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.Common.save,
            style: .done,
            target: self,
            action: #selector(saveAndRecalculate)
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardHidden(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        rebuildContent()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if isViewLoaded { rebuildContent() }
    }

    private func rebuildContent() {
        view.endEditing(true)
        editableFields.removeAll()
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        profile = BiologicalAgeProfileResolver.resolve(
            store: store,
            snapshot: appleHealthService.snapshot,
            preferences: preferences
        )
        guard let profile else { return }

        contentStack.addArrangedSubview(makeProfileCard(profile))
        contentStack.addArrangedSubview(makeEstimateCard(profile))
        contentStack.addArrangedSubview(makeCreatinineCard(profile))
        contentStack.addArrangedSubview(makeValuesCard(profile))
        contentStack.addArrangedSubview(makeMethodCard(profile))

        let button = PrimaryButton(
            title: L10n.text("health.biological_age.save_recalculate"),
            style: .primary
        )
        button.accessibilityIdentifier = "health.biological_age.save"
        button.addTarget(self, action: #selector(saveAndRecalculate), for: .touchUpInside)
        contentStack.addArrangedSubview(button)
    }

    private func makeProfileCard(_ profile: BiologicalAgeProfile) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = WellnarioSpacing.small
        stack.addArrangedSubview(cardTitle(L10n.text("health.biological_age.profile.title")))
        stack.addArrangedSubview(
            valueRow(
                title: L10n.text("health.biological_age.chronological"),
                value: profile.chronologicalAge.map {
                    L10n.text("health.biological_age.age_value", $0)
                } ?? L10n.text("health.biological_age.unavailable")
            )
        )
        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(
            valueRow(
                title: L10n.text("health.biological_age.sex_at_birth"),
                value: sexTitle(profile.biologicalSex)
            )
        )
        return makeCard(containing: stack, identifier: "health.biological_age.profile")
    }

    private func makeEstimateCard(_ profile: BiologicalAgeProfile) -> UIView {
        let pheno = metricView(
            title: "PhenoAge",
            value: profile.estimate.phenoAge
        )
        let bio = metricView(
            title: "BioAge",
            value: profile.estimate.bioAge
        )
        let metrics = UIStackView(
            arrangedSubviews: [pheno, bio],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            distribution: .fillEqually
        )
        let stack = UIStackView(
            arrangedSubviews: [
                cardTitle(L10n.text("health.biological_age.results.title")),
                metrics,
                explanatoryLabel(profileMessage(profile))
            ],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        return makeCard(containing: stack, identifier: "health.biological_age.results")
    }

    private func makeCreatinineCard(_ profile: BiologicalAgeProfile) -> UIView {
        let title = cardTitle(L10n.text("health.biological_age.creatinine.title"))
        let question = explanatoryLabel(
            L10n.text("health.biological_age.creatinine.question")
        )
        creatinineSwitch.isOn = preferences.creatineOrStrengthTraining
        creatinineSwitch.onTintColor = WellnarioPalette.fuchsia
        creatinineSwitch.accessibilityIdentifier = "health.biological_age.creatinine.toggle"
        let switchRow = UIStackView(
            arrangedSubviews: [
                valueLabel(L10n.text("health.biological_age.creatinine.answer")),
                UIView(),
                creatinineSwitch
            ],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .center
        )
        let hasCreatinineAnalysis = profile.values[.creatinine]?.source.analysisDate != nil
        let helperKey = hasCreatinineAnalysis
            ? "health.biological_age.creatinine.help"
            : "health.biological_age.creatinine.no_analysis"
        let stack = UIStackView(
            arrangedSubviews: [title, question, switchRow, captionLabel(L10n.text(helperKey))],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        return makeCard(containing: stack, identifier: "health.biological_age.creatinine")
    }

    private func makeValuesCard(_ profile: BiologicalAgeProfile) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = WellnarioSpacing.small
        stack.addArrangedSubview(cardTitle(L10n.text("health.biological_age.values.title")))
        stack.addArrangedSubview(
            explanatoryLabel(L10n.text("health.biological_age.values.intro"))
        )

        let editable = BiologicalAgeMarker.allCases.compactMap { marker -> BiologicalAgeResolvedValue? in
            guard let value = profile.values[marker], value.source.isEditable else { return nil }
            return value
        }
        if editable.isEmpty {
            stack.addArrangedSubview(captionLabel(L10n.text("health.biological_age.values.current")))
        } else {
            for (index, value) in editable.enumerated() {
                if index > 0 { stack.addArrangedSubview(divider()) }
                let field = FormFieldView()
                field.configure(
                    title: "\(value.marker.title) (\(value.marker.canonicalUnit))",
                    placeholder: decimalText(value.populationAverage),
                    text: decimalText(unadjustedDisplayValue(value)),
                    keyboardType: .decimalPad
                )
                field.helperText = sourceDescription(value.source)
                field.accessibilityIdentifier = "health.biological_age.value.\(value.marker.rawValue)"
                field.textField.inputAccessoryView = keyboardToolbar()
                editableFields[value.marker] = field
                stack.addArrangedSubview(field)
            }
        }
        return makeCard(containing: stack, identifier: "health.biological_age.values")
    }

    private func makeMethodCard(_ profile: BiologicalAgeProfile) -> UIView {
        var text = L10n.text("health.biological_age.method.description")
        if let age = profile.chronologicalAge, !(30...75).contains(age) {
            text += "\n\n" + L10n.text("health.biological_age.method.age_warning")
        }
        let stack = UIStackView(
            arrangedSubviews: [
                cardTitle(L10n.text("health.biological_age.method.title")),
                explanatoryLabel(text)
            ],
            axis: .vertical,
            spacing: WellnarioSpacing.small
        )
        return makeCard(containing: stack, identifier: "health.biological_age.method")
    }

    @objc private func saveAndRecalculate() {
        view.endEditing(true)
        var stored: [
            BiologicalAgeMarker: (value: Double, source: BiologicalAgeValueSource)
        ] = [:]
        for (marker, field) in editableFields {
            guard let text = field.textField.text,
                  let value = parsedNumber(text),
                  value >= 0 else {
                field.setError(L10n.text("health.biological_age.value.invalid"))
                let feedback = UINotificationFeedbackGenerator()
                feedback.prepare()
                feedback.notificationOccurred(.error)
                return
            }
            guard let source = profile?.values[marker]?.source else { continue }
            stored[marker] = (value, source)
            field.setError(nil)
        }
        preferences.setManualValues(stored)
        preferences.creatineOrStrengthTraining = creatinineSwitch.isOn
        UIImpactFeedbackGenerator.wellnarioSuccess()
        closeAfterSaving()
    }

    private func closeAfterSaving() {
        guard let navigationController,
              navigationController.topViewController === self,
              navigationController.viewControllers.count > 1 else {
            dismiss(animated: true)
            return
        }
        navigationController.popViewController(animated: true)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard let frame = notification.userInfo?[
            UIResponder.keyboardFrameEndUserInfoKey
        ] as? CGRect else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        scrollView.contentInset.bottom = overlap + WellnarioSpacing.small
        scrollView.verticalScrollIndicatorInsets.bottom = scrollView.contentInset.bottom
    }

    @objc private func keyboardHidden(_ notification: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    private func metricView(title: String, value: Double?) -> UIView {
        let titleLabel = UILabel()
        titleLabel.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        titleLabel.text = title
        titleLabel.textAlignment = .center

        let metric = UILabel()
        metric.applyWellnarioStyle(.metric, color: WellnarioPalette.fuchsia)
        metric.text = value.map { L10n.text("health.biological_age.estimate_value", Int($0.rounded())) }
            ?? "—"
        metric.textAlignment = .center
        metric.adjustsFontSizeToFitWidth = true
        metric.minimumScaleFactor = 0.75

        let container = UIView()
        container.backgroundColor = WellnarioPalette.surfaceElevated
        container.applyContinuousCorners(WellnarioRadius.control)
        let stack = UIStackView(
            arrangedSubviews: [titleLabel, metric],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall,
            alignment: .fill
        )
        container.addForAutoLayout(stack)
        stack.pinEdges(to: container, insets: .all(WellnarioSpacing.xSmall))
        return container
    }

    private func valueRow(title: String, value: String) -> UIView {
        let name = valueLabel(title)
        let content = valueLabel(value)
        content.textColor = WellnarioPalette.textPrimary
        content.textAlignment = .right
        content.setContentCompressionResistancePriority(.required, for: .horizontal)
        return UIStackView(
            arrangedSubviews: [name, UIView(), content],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .firstBaseline
        )
    }

    private func cardTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    private func valueLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.body, color: WellnarioPalette.textSecondary)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    private func explanatoryLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    private func captionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        label.text = text
        label.numberOfLines = 0
        return label
    }

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = WellnarioPalette.hairline
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func keyboardToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(
                title: L10n.Common.done,
                style: .done,
                target: self,
                action: #selector(dismissKeyboard)
            )
        ]
        return toolbar
    }

    private func sexTitle(_ sex: AppleHealthBiologicalSex?) -> String {
        switch sex {
        case .female: L10n.text("health.biological_age.sex.female")
        case .male: L10n.text("health.biological_age.sex.male")
        case .other: L10n.text("health.biological_age.sex.other")
        case .notSet, nil: L10n.text("health.biological_age.unavailable")
        }
    }

    private func profileMessage(_ profile: BiologicalAgeProfile) -> String {
        if profile.chronologicalAge == nil {
            return L10n.text("health.biological_age.missing_birth_date")
        }
        guard profile.biologicalSex == .female || profile.biologicalSex == .male else {
            return L10n.text("health.biological_age.missing_sex")
        }
        return L10n.text("health.biological_age.results.description")
    }

    private func sourceDescription(_ source: BiologicalAgeValueSource) -> String {
        switch source {
        case let .analysis(date, _):
            return L10n.text(
                "health.biological_age.value.old_analysis",
                date.formatted(date: .numeric, time: .omitted)
            )
        case .appleHealthSystolicAverage:
            return L10n.text("health.biological_age.value.apple_health_systolic_average")
        case .populationAverage:
            return L10n.text("health.biological_age.value.population_average")
        }
    }

    private func unadjustedDisplayValue(_ value: BiologicalAgeResolvedValue) -> Double {
        guard value.isCreatinineAdjusted else { return value.value }
        return (value.value * 2) - value.populationAverage
    }

    private func decimalText(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private func parsedNumber(_ text: String) -> Double? {
        if let number = numberFormatter.number(from: text) {
            return number.doubleValue
        }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }
}

@MainActor
final class BiologicalAgeAuditViewController: WellnessScrollViewController {
    private let profile: BiologicalAgeProfile
    private let referenceDate: Date
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = LocalizationManager.shared.locale
        return formatter
    }()
    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = LocalizationManager.shared.locale
        return formatter
    }()
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    init(profile: BiologicalAgeProfile, referenceDate: Date = Date()) {
        self.profile = profile
        self.referenceDate = referenceDate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.text("health.biological_age.audit.title")
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "health.biological_age.audit"
        buildContent()
    }

    private func buildContent() {
        contentStack.addArrangedSubview(makeIntro())
        contentStack.addArrangedSubview(makeAlgorithmCard(
            title: "PhenoAge",
            markers: BiologicalAgeMarker.phenoAgeMarkers,
            estimate: profile.estimate.phenoAge,
            identifier: "health.biological_age.audit.phenoAge"
        ))
        contentStack.addArrangedSubview(makeAlgorithmCard(
            title: "BioAge",
            markers: BiologicalAgeMarker.bioAgeMarkers,
            estimate: profile.estimate.bioAge,
            identifier: "health.biological_age.audit.bioAge"
        ))
    }

    private func makeIntro() -> UIView {
        let label = UILabel()
        label.applyWellnarioStyle(.secondary, color: WellnarioPalette.textSecondary)
        label.text = L10n.text("health.biological_age.audit.description")
        label.numberOfLines = 0
        return label
    }

    private func makeAlgorithmCard(
        title: String,
        markers: Set<BiologicalAgeMarker>,
        estimate: Double?,
        identifier: String
    ) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = WellnarioSpacing.small
        stack.addArrangedSubview(sectionTitle(title))
        stack.addArrangedSubview(estimateLabel(estimate))

        let orderedMarkers = BiologicalAgeMarker.allCases.filter(markers.contains)
        for (index, marker) in orderedMarkers.enumerated() {
            if index > 0 { stack.addArrangedSubview(divider()) }
            stack.addArrangedSubview(makeParameterRow(marker))
        }
        return makeCard(containing: stack, identifier: identifier)
    }

    private func makeParameterRow(_ marker: BiologicalAgeMarker) -> UIView {
        let title = UILabel()
        title.applyWellnarioStyle(.secondary, color: WellnarioPalette.textPrimary)
        title.text = "\(marker.title) (\(marker.canonicalUnit))"
        title.numberOfLines = 0

        let value = UILabel()
        value.applyWellnarioStyle(.body, color: WellnarioPalette.textPrimary)
        value.textAlignment = .right
        value.numberOfLines = 0
        value.text = profile.values[marker].map {
            "\(decimalText($0.value)) \($0.marker.canonicalUnit)"
        } ?? L10n.text("health.biological_age.audit.missing")
        value.setContentCompressionResistancePriority(.required, for: .horizontal)

        let valueRow = UIStackView(
            arrangedSubviews: [title, UIView(), value],
            axis: .horizontal,
            spacing: WellnarioSpacing.small,
            alignment: .firstBaseline
        )

        let source = UILabel()
        source.applyWellnarioStyle(.caption, color: WellnarioPalette.textSecondary)
        source.text = profile.values[marker].map(sourceText) ?? L10n.text(
            "health.biological_age.audit.missing"
        )
        source.numberOfLines = 0

        let age = UILabel()
        age.applyWellnarioStyle(.caption, color: WellnarioPalette.textTertiary)
        age.text = profile.values[marker].flatMap(ageText)
        age.numberOfLines = 0
        age.isHidden = age.text == nil

        let row = UIStackView(
            arrangedSubviews: [valueRow, source, age],
            axis: .vertical,
            spacing: WellnarioSpacing.xxxSmall
        )
        row.accessibilityIdentifier = "health.biological_age.audit.parameter.\(marker.rawValue)"
        return row
    }

    private func sourceText(_ value: BiologicalAgeResolvedValue) -> String {
        let base: String
        switch value.source {
        case .analysis:
            base = L10n.text("health.biological_age.audit.source.analysis")
        case .appleHealthSystolicAverage:
            base = L10n.text("health.biological_age.audit.source.apple_health")
        case .populationAverage:
            base = L10n.text("health.biological_age.audit.source.population")
        }
        var details = [base]
        if value.wasManuallyReviewed {
            details.append(L10n.text("health.biological_age.audit.source.reviewed"))
        }
        if value.isCreatinineAdjusted {
            details.append(L10n.text("health.biological_age.audit.source.adjusted"))
        }
        return details.joined(separator: " · ")
    }

    private func ageText(_ value: BiologicalAgeResolvedValue) -> String? {
        let date: Date?
        switch value.source {
        case let .analysis(analysisDate, _): date = analysisDate
        case let .appleHealthSystolicAverage(asOf): date = asOf
        case .populationAverage: date = nil
        }
        guard let date else {
            return L10n.text("health.biological_age.audit.age.not_applicable")
        }
        return L10n.text(
            "health.biological_age.audit.age.date",
            dateFormatter.string(from: date),
            relativeFormatter.localizedString(for: date, relativeTo: referenceDate)
        )
    }

    private func estimateLabel(_ estimate: Double?) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.caption, color: WellnarioPalette.fuchsia)
        label.text = estimate.map {
            L10n.text("health.biological_age.audit.estimate", Int($0.rounded()))
        } ?? L10n.text("health.biological_age.audit.missing")
        return label
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.applyWellnarioStyle(.sectionTitle, color: WellnarioPalette.textPrimary)
        label.text = text
        return label
    }

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = WellnarioPalette.hairline
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func decimalText(_ value: Double) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
