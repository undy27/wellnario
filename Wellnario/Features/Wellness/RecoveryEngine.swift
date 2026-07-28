import Foundation
import HealthKit

final class RecoveryEngine: @unchecked Sendable {
    private let dataStore: RecoveryDataStore
    
    init(dataStore: RecoveryDataStore) {
        self.dataStore = dataStore
    }
    
    func sync(
        sleepTrend: [AppleHealthSleepDay],
        healthStore: HKHealthStore,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = Date()
    ) async throws {
        // We only process the last 30 days to avoid huge recalculations,
        // but we need 60 days of history to compute the baseline.
        let processWindowStart = calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        let baselineWindowStart = calendar.date(byAdding: .day, value: -60, to: processWindowStart) ?? .distantPast
        
        let recentSleepDays = sleepTrend.filter { $0.date >= processWindowStart }.sorted(by: { $0.date < $1.date })
        guard let firstSleepDay = recentSleepDays.first else { return }
        
        // Fetch raw samples for the baseline window + process window
        async let hrvSamples = fetchTimedQuantities(from: healthStore, identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: baselineWindowStart, end: now)
        async let rhrSamples = fetchTimedQuantities(from: healthStore, identifier: .restingHeartRate, unit: .count().unitDivided(by: .minute()), start: baselineWindowStart, end: now)
        async let respSamples = fetchTimedQuantities(from: healthStore, identifier: .respiratoryRate, unit: .count().unitDivided(by: .minute()), start: baselineWindowStart, end: now)
        
        let (hrv, rhr, resp) = try await (hrvSamples, rhrSamples, respSamples)
        
        // Group samples by sleep day
        // Apple Watch typically takes HRV/RHR/Resp during sleep.
        // We will associate samples to a sleep day if they fall between (sleepStartDate - 2h) and (date + 2h).
        // For simplicity, we can just group by the local day of the sample.
        
        var hrvByDay: [String: [Double]] = [:]
        var rhrByDay: [String: [Double]] = [:]
        var respByDay: [String: [Double]] = [:]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.calendar = calendar
        
        for sample in hrv {
            let key = dateFormatter.string(from: sample.startDate)
            hrvByDay[key, default: []].append(sample.value)
        }
        for sample in rhr {
            let key = dateFormatter.string(from: sample.startDate)
            rhrByDay[key, default: []].append(sample.value)
        }
        for sample in resp {
            let key = dateFormatter.string(from: sample.startDate)
            respByDay[key, default: []].append(sample.value)
        }
        
        // Compute baseline over 60 days
        var dailyHRV: [String: Double] = [:]
        var dailyRHR: [String: Double] = [:]
        var dailyResp: [String: Double] = [:]
        
        for (day, values) in hrvByDay { dailyHRV[day] = values.reduce(0, +) / Double(values.count) }
        for (day, values) in rhrByDay { dailyRHR[day] = values.reduce(0, +) / Double(values.count) }
        for (day, values) in respByDay { dailyResp[day] = values.reduce(0, +) / Double(values.count) }
        
        for sleepDay in recentSleepDays {
            let targetDayStr = dateFormatter.string(from: sleepDay.date)
            let targetDate = calendar.startOfDay(for: sleepDay.date)
            let baselineStart = calendar.date(byAdding: .day, value: -60, to: targetDate)!
            
            var baselineHRVs: [Double] = []
            var baselineRHRs: [Double] = []
            
            var curr = baselineStart
            while curr < targetDate {
                let dayStr = dateFormatter.string(from: curr)
                if let v = dailyHRV[dayStr] { baselineHRVs.append(v) }
                if let v = dailyRHR[dayStr] { baselineRHRs.append(v) }
                curr = calendar.date(byAdding: .day, value: 1, to: curr)!
            }
            
            let hrvMean = baselineHRVs.reduce(0, +) / max(1, Double(baselineHRVs.count))
            let hrvStd = standardDeviation(baselineHRVs, mean: hrvMean)
            
            let rhrMean = baselineRHRs.reduce(0, +) / max(1, Double(baselineRHRs.count))
            let rhrStd = standardDeviation(baselineRHRs, mean: rhrMean)
            
            let baseline = RecoveryBaseline(
                date: targetDayStr,
                hrvMean: hrvMean,
                hrvStdDev: hrvStd,
                rhrMean: rhrMean,
                rhrStdDev: rhrStd
            )
            try await MainActor.run {
                try dataStore.saveBaseline(baseline)
            }
            
            let todayHRV = dailyHRV[targetDayStr]
            let todayRHR = dailyRHR[targetDayStr]
            let todayResp = dailyResp[targetDayStr]
            
            let zHRV = hrvStd > 0 ? ((todayHRV ?? hrvMean) - hrvMean) / hrvStd : 0
            let zRHR = rhrStd > 0 ? ((todayRHR ?? rhrMean) - rhrMean) / rhrStd : 0
            
            // HRV higher is better, RHR lower is better
            let combinedZ = (zHRV - zRHR) / 2.0
            
            var baseScore = 50.0 + (combinedZ * 15.0)
            
            // Sleep quality factor
            if let sq = sleepDay.qualityScore {
                baseScore += (sq - 50) * 0.2
            }
            
            // Respiratory rate penalization (if > 10% higher than baseline)
            if let resp = todayResp {
                let baselineRespMean = dailyResp.values.reduce(0, +) / max(1, Double(dailyResp.count))
                if baselineRespMean > 0 && resp > baselineRespMean * 1.1 {
                    baseScore -= 10.0
                }
            }
            
            baseScore = max(0, min(100, baseScore))
            
            let score = RecoveryScore(
                date: targetDayStr,
                score: baseScore,
                hrvValue: todayHRV,
                rhrValue: todayRHR,
                sleepScore: sleepDay.qualityScore,
                respiratoryRate: todayResp
            )
            try await MainActor.run {
                try dataStore.saveScore(score)
            }
        }
    }
    
    private func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let sum = values.reduce(0) { $0 + pow($1 - mean, 2) }
        return sqrt(sum / Double(values.count - 1))
    }
    
    private func fetchTimedQuantities(
        from healthStore: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [AppleHealthTimedQuantity] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let quantities = (samples as? [HKQuantitySample])?.map { sample in
                    AppleHealthTimedQuantity(
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        value: sample.quantity.doubleValue(for: unit)
                    )
                } ?? []
                continuation.resume(returning: quantities)
            }
            healthStore.execute(query)
        }
    }
}


