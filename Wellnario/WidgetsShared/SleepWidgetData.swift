import Foundation

enum WellnarioSleepWidgetData {
    static let kind = "WellnarioSleepWidget"
    static let snapshotKey = "wellnario.sleepWidget.snapshot.v1"
    static let appGroupID = WellnarioSupplementWidget.appGroupID
}

struct SleepWidgetSnapshot: Codable, Hashable, Sendable {
    let languageCode: String
    let detail: String
    let qualityScore: Double?
    let qualityText: String
    let durationScore: Double?
    let durationText: String
    let regularityScore: Double?
    let regularityText: String
    let interruptionsScore: Double?
    let interruptionsText: String
    let heartRateDropScore: Double?
    let heartRateDropText: String?
    let sleepStressScore: Double?
    let sleepStressText: String?
    let remDeepSleepScore: Double?
    let remDeepSleepText: String?
    let sleepLatencyScore: Double?
    let sleepLatencyText: String?
    let updatedAt: Date

    init(
        languageCode: String,
        detail: String,
        qualityScore: Double?,
        qualityText: String,
        durationScore: Double?,
        durationText: String,
        regularityScore: Double?,
        regularityText: String,
        interruptionsScore: Double?,
        interruptionsText: String,
        heartRateDropScore: Double? = nil,
        heartRateDropText: String? = nil,
        sleepStressScore: Double? = nil,
        sleepStressText: String? = nil,
        remDeepSleepScore: Double? = nil,
        remDeepSleepText: String? = nil,
        sleepLatencyScore: Double? = nil,
        sleepLatencyText: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.languageCode = languageCode
        self.detail = detail
        self.qualityScore = qualityScore
        self.qualityText = qualityText
        self.durationScore = durationScore
        self.durationText = durationText
        self.regularityScore = regularityScore
        self.regularityText = regularityText
        self.interruptionsScore = interruptionsScore
        self.interruptionsText = interruptionsText
        self.heartRateDropScore = heartRateDropScore
        self.heartRateDropText = heartRateDropText
        self.sleepStressScore = sleepStressScore
        self.sleepStressText = sleepStressText
        self.remDeepSleepScore = remDeepSleepScore
        self.remDeepSleepText = remDeepSleepText
        self.sleepLatencyScore = sleepLatencyScore
        self.sleepLatencyText = sleepLatencyText
        self.updatedAt = updatedAt
    }

    static let placeholder = SleepWidgetSnapshot(
        languageCode: "es",
        detail: "Sin datos",
        qualityScore: nil,
        qualityText: "—",
        durationScore: nil,
        durationText: "—",
        regularityScore: nil,
        regularityText: "—",
        interruptionsScore: nil,
        interruptionsText: "—"
    )
}

struct SleepWidgetDataStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: WellnarioSleepWidgetData.appGroupID)) {
        self.defaults = defaults ?? .standard
    }

    func snapshot() -> SleepWidgetSnapshot? {
        guard let data = defaults.data(forKey: WellnarioSleepWidgetData.snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(SleepWidgetSnapshot.self, from: data)
    }

    func save(_ snapshot: SleepWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: WellnarioSleepWidgetData.snapshotKey)
    }
}
