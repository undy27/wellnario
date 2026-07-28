import XCTest
@testable import Wellnario

final class OuraSyncTests: XCTestCase {

    func testKeychainStoreTokenOperations() {
        let store = OuraKeychainStore.shared
        let testToken = "test_oura_personal_access_token_12345"

        // Clean up first
        store.deleteToken()
        XCTAssertFalse(store.isConnected)
        XCTAssertNil(store.getToken())

        // Save
        let saveSuccess = store.saveToken(testToken)
        XCTAssertTrue(saveSuccess)
        XCTAssertTrue(store.isConnected)
        XCTAssertEqual(store.getToken(), testToken)

        // Delete
        let deleteSuccess = store.deleteToken()
        XCTAssertTrue(deleteSuccess)
        XCTAssertFalse(store.isConnected)
        XCTAssertNil(store.getToken())
    }

    func testOuraDailyReadinessResponseDecoding() throws {
        let json = """
        {
            "data": [
                {
                    "id": "readiness-123",
                    "day": "2026-07-22",
                    "score": 85.0,
                    "temperature_deviation": -0.1,
                    "contributors": {
                        "activity_balance": 90,
                        "body_temperature": 95,
                        "hrv_balance": 88,
                        "previous_day_activity": 85,
                        "previous_night": 90,
                        "recovery_index": 82,
                        "resting_heart_rate": 92,
                        "sleep_balance": 88
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(OuraDailyReadinessResponse.self, from: json)

        XCTAssertEqual(response.data.count, 1)
        let item = response.data[0]
        XCTAssertEqual(item.id, "readiness-123")
        XCTAssertEqual(item.day, "2026-07-22")
        XCTAssertEqual(item.score, 85.0)
        XCTAssertEqual(item.contributors?.hrvBalance, 88)
        XCTAssertEqual(item.contributors?.restingHeartRate, 92)
    }

    func testOuraSleepResponseDecoding() throws {
        let json = """
        {
            "data": [
                {
                    "id": "sleep-456",
                    "day": "2026-07-22",
                    "bedtime_start": "2026-07-21T23:15:00+02:00",
                    "bedtime_end": "2026-07-22T07:30:00+02:00",
                    "total_sleep_duration": 28800.0,
                    "deep_sleep_duration": 5400.0,
                    "rem_sleep_duration": 7200.0,
                    "light_sleep_duration": 16200.0,
                    "efficiency": 92.0,
                    "latency": 600.0,
                    "average_hrv": 48.5,
                    "lowest_heart_rate": 52.0
                }
            ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(OuraSleepResponse.self, from: json)

        XCTAssertEqual(response.data.count, 1)
        let item = response.data[0]
        XCTAssertEqual(item.id, "sleep-456")
        XCTAssertEqual(item.day, "2026-07-22")
        XCTAssertEqual(item.totalSleepDuration, 28800.0)
        XCTAssertEqual(item.averageHrv, 48.5)
        XCTAssertEqual(item.lowestHeartRate, 52.0)
    }
}
