import Foundation

struct RecoveryBaseline: Equatable, Sendable {
    var date: String // e.g. "2023-10-01"
    var hrvMean: Double
    var hrvStdDev: Double
    var rhrMean: Double
    var rhrStdDev: Double
    var updatedAt: Date
    
    init(date: String, hrvMean: Double, hrvStdDev: Double, rhrMean: Double, rhrStdDev: Double, updatedAt: Date = Date()) {
        self.date = date
        self.hrvMean = hrvMean
        self.hrvStdDev = hrvStdDev
        self.rhrMean = rhrMean
        self.rhrStdDev = rhrStdDev
        self.updatedAt = updatedAt
    }
}

struct RecoveryScore: Equatable, Sendable {
    var date: String // e.g. "2023-10-01"
    var score: Double // 0-100
    var hrvValue: Double?
    var rhrValue: Double?
    var sleepScore: Double?
    var respiratoryRate: Double?
    var updatedAt: Date
    
    init(date: String, score: Double, hrvValue: Double? = nil, rhrValue: Double? = nil, sleepScore: Double? = nil, respiratoryRate: Double? = nil, updatedAt: Date = Date()) {
        self.date = date
        self.score = score
        self.hrvValue = hrvValue
        self.rhrValue = rhrValue
        self.sleepScore = sleepScore
        self.respiratoryRate = respiratoryRate
        self.updatedAt = updatedAt
    }
    
    var isOptimal: Bool { score > 66 }
    var isWarning: Bool { score <= 66 && score >= 33 }
    var isLow: Bool { score < 33 }
}
