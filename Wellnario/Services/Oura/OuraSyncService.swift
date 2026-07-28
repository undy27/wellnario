import Foundation

// MARK: - Oura API Models

struct OuraPersonalInfo: Codable, Sendable {
    let id: String?
    let email: String?
}

struct OuraReadinessContributor: Codable, Sendable {
    let activityBalance: Int?
    let bodyTemperature: Int?
    let hrvBalance: Int?
    let previousDayActivity: Int?
    let previousNight: Int?
    let recoveryIndex: Int?
    let restingHeartRate: Int?
    let sleepBalance: Int?

    enum CodingKeys: String, CodingKey {
        case activityBalance = "activity_balance"
        case bodyTemperature = "body_temperature"
        case hrvBalance = "hrv_balance"
        case previousDayActivity = "previous_day_activity"
        case previousNight = "previous_night"
        case recoveryIndex = "recovery_index"
        case restingHeartRate = "resting_heart_rate"
        case sleepBalance = "sleep_balance"
    }
}

struct OuraDailyReadinessData: Codable, Sendable {
    let id: String
    let day: String
    let score: Double?
    let temperatureDeviation: Double?
    let contributors: OuraReadinessContributor?

    enum CodingKeys: String, CodingKey {
        case id, day, score, contributors
        case temperatureDeviation = "temperature_deviation"
    }
}

struct OuraDailyReadinessResponse: Codable, Sendable {
    let data: [OuraDailyReadinessData]
}

struct OuraSleepData: Codable, Sendable {
    let id: String
    let day: String
    let bedtimeStart: String?
    let bedtimeEnd: String?
    let totalSleepDuration: Double?
    let deepSleepDuration: Double?
    let remSleepDuration: Double?
    let lightSleepDuration: Double?
    let efficiency: Double?
    let latency: Double?
    let averageHrv: Double?
    let lowestHeartRate: Double?

    enum CodingKeys: String, CodingKey {
        case id, day, efficiency, latency
        case bedtimeStart = "bedtime_start"
        case bedtimeEnd = "bedtime_end"
        case totalSleepDuration = "total_sleep_duration"
        case deepSleepDuration = "deep_sleep_duration"
        case remSleepDuration = "rem_sleep_duration"
        case lightSleepDuration = "light_sleep_duration"
        case averageHrv = "average_hrv"
        case lowestHeartRate = "lowest_heart_rate"
    }
}

struct OuraSleepResponse: Codable, Sendable {
    let data: [OuraSleepData]
}

struct OuraDailyActivityData: Codable, Sendable {
    let id: String
    let day: String
    let score: Double?
    let activeCalories: Double?
    let totalCalories: Double?
    let steps: Int?

    enum CodingKeys: String, CodingKey {
        case id, day, score, steps
        case activeCalories = "active_calories"
        case totalCalories = "total_calories"
    }
}

struct OuraDailyActivityResponse: Codable, Sendable {
    let data: [OuraDailyActivityData]
}

struct OuraEnhancedTagData: Codable, Sendable {
    let id: String?
    let startDay: String?
    let day: String?
    let startTime: String?
    let timestamp: String?
    let tagTypeCode: String?
    let customName: String?
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case id, comment, day, timestamp
        case startDay = "start_day"
        case startTime = "start_time"
        case tagTypeCode = "tag_type_code"
        case customName = "custom_name"
    }
}

struct OuraEnhancedTagResponse: Codable, Sendable {
    let data: [OuraEnhancedTagData]
    let nextToken: String?

    enum CodingKeys: String, CodingKey {
        case data
        case nextToken = "next_token"
    }
}

struct OuraTagData: Codable, Sendable {
    let id: String
    let day: String?
    let text: String?
    let tags: [String]?
}

struct OuraTagResponse: Codable, Sendable {
    let data: [OuraTagData]
}

enum OuraSyncError: LocalizedError, Sendable {
    case missingToken
    case invalidURL
    case unauthorized
    case serverError(statusCode: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No se ha encontrado una clave de API de Oura."
        case .invalidURL:
            return "URL no válida."
        case .unauthorized:
            return "Clave de API de Oura no válida o revocada."
        case .serverError(let code):
            return "Error de servidor en la API de Oura (\(code))."
        case .invalidResponse:
            return "Respuesta no válida de los servidores de Oura."
        }
    }
}

// MARK: - Oura Sync Service

actor OuraSyncService {
    private let keychainStore: OuraKeychainStore
    private let urlSession: URLSession
    private let baseURL = "https://api.ouraring.com/v2/usercollection"

    private(set) var lastSyncDate: Date? {
        get {
            UserDefaults.standard.object(forKey: "oura_last_sync_date") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "oura_last_sync_date")
        }
    }

    init(
        keychainStore: OuraKeychainStore = .shared,
        urlSession: URLSession = .shared
    ) {
        self.keychainStore = keychainStore
        self.urlSession = urlSession
    }

    // MARK: - API Calls

    func validateToken(_ token: String) async throws -> OuraPersonalInfo {
        guard let url = URL(string: "\(baseURL)/personal_info") else {
            throw OuraSyncError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OuraSyncError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw OuraSyncError.unauthorized
        }
        guard httpResponse.statusCode == 200 else {
            throw OuraSyncError.serverError(statusCode: httpResponse.statusCode)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(OuraPersonalInfo.self, from: data)
    }

    func fetchReadiness(start: String, end: String) async throws -> [OuraDailyReadinessData] {
        guard let token = keychainStore.getToken() else {
            throw OuraSyncError.missingToken
        }
        var components = URLComponents(string: "\(baseURL)/daily_readiness")
        components?.queryItems = [
            URLQueryItem(name: "start_date", value: start),
            URLQueryItem(name: "end_date", value: end)
        ]
        guard let url = components?.url else {
            throw OuraSyncError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OuraSyncError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw OuraSyncError.unauthorized
        }
        guard httpResponse.statusCode == 200 else {
            throw OuraSyncError.serverError(statusCode: httpResponse.statusCode)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(OuraDailyReadinessResponse.self, from: data).data
    }

    func fetchSleep(start: String, end: String) async throws -> [OuraSleepData] {
        guard let token = keychainStore.getToken() else {
            throw OuraSyncError.missingToken
        }
        var components = URLComponents(string: "\(baseURL)/sleep")
        components?.queryItems = [
            URLQueryItem(name: "start_date", value: start),
            URLQueryItem(name: "end_date", value: end)
        ]
        guard let url = components?.url else {
            throw OuraSyncError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OuraSyncError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw OuraSyncError.unauthorized
        }
        guard httpResponse.statusCode == 200 else {
            throw OuraSyncError.serverError(statusCode: httpResponse.statusCode)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(OuraSleepResponse.self, from: data).data
    }

    func fetchTags(start: String, end: String) async throws -> [OuraEnhancedTagData] {
        guard let token = keychainStore.getToken() else {
            throw OuraSyncError.missingToken
        }
        var allTags: [OuraEnhancedTagData] = []
        var nextToken: String? = nil

        repeat {
            var components = URLComponents(string: "\(baseURL)/enhanced_tag")
            var queryItems = [
                URLQueryItem(name: "start_date", value: start),
                URLQueryItem(name: "end_date", value: end)
            ]
            if let nextToken {
                queryItems.append(URLQueryItem(name: "next_token", value: nextToken))
            }
            components?.queryItems = queryItems
            guard let url = components?.url else {
                throw OuraSyncError.invalidURL
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OuraSyncError.invalidResponse
            }
            if httpResponse.statusCode == 401 {
                throw OuraSyncError.unauthorized
            }
            guard httpResponse.statusCode == 200 else {
                throw OuraSyncError.serverError(statusCode: httpResponse.statusCode)
            }
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(OuraEnhancedTagResponse.self, from: data)
            allTags.append(contentsOf: decoded.data)
            nextToken = decoded.nextToken
        } while nextToken != nil

        return allTags
    }

    func fetchUserTags(start: String, end: String) async throws -> [OuraTagData] {
        guard let token = keychainStore.getToken() else {
            throw OuraSyncError.missingToken
        }
        var components = URLComponents(string: "\(baseURL)/tag")
        components?.queryItems = [
            URLQueryItem(name: "start_date", value: start),
            URLQueryItem(name: "end_date", value: end)
        ]
        guard let url = components?.url else {
            throw OuraSyncError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OuraSyncError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw OuraSyncError.unauthorized
        }
        guard httpResponse.statusCode == 200 else {
            throw OuraSyncError.serverError(statusCode: httpResponse.statusCode)
        }
        let decoder = JSONDecoder()
        return try decoder.decode(OuraTagResponse.self, from: data).data
    }

    // MARK: - Sync into Local Database

    func sync(into recoveryDataStore: RecoveryDataStore) async throws {
        let calendar = Calendar.current
        let today = Date()
        let startDate = calendar.date(byAdding: .day, value: -30, to: today) ?? today

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: tomorrow)

        let readinessItems = try await fetchReadiness(start: startString, end: endString)
        
        for item in readinessItems {
            guard let score = item.score else { continue }
            let recoveryScore = RecoveryScore(date: item.day, score: score, updatedAt: today)
            await MainActor.run {
                try? recoveryDataStore.saveScore(recoveryScore)
            }
        }

        // Sync tags from /v2/usercollection/enhanced_tag
        if let tagItems = try? await fetchTags(start: startString, end: endString) {
            await MainActor.run {
                for item in tagItems {
                    let textToUse = (item.customName?.isEmpty == false ? item.customName : nil)
                        ?? (item.comment?.isEmpty == false ? item.comment : nil)
                        ?? item.tagTypeCode ?? ""
                    let formattedName = formatOuraTag(textToUse)
                    guard !formattedName.isEmpty else { continue }

                    let definition = WellnessLocalStore.getOrCreateOuraFactor(for: formattedName)
                    
                    if WellnessLocalStore.isSleepFactorEnabled(definition.id) {
                        let rawDayStr = item.startDay ?? item.day
                        ?? item.startTime?.prefix(10).description
                        ?? item.timestamp?.prefix(10).description

                        if let dayString = rawDayStr, let dayDate = formatter.date(from: dayString) {
                            WellnessLocalStore.setSleepFactorValue(1, for: definition, on: dayDate)
                        }
                    }
                }
            }
        }

        lastSyncDate = today
    }

    nonisolated private func formatOuraTag(_ text: String) -> String {
        var name = text
        if name.hasPrefix("tag_") {
            name = String(name.dropFirst(4))
        }
        name = name.replacingOccurrences(of: "_", with: " ")
        return name.capitalized
    }
}
