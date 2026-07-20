import Foundation

enum AppleHealthShortcutAutomationCadence: String, Codable, CaseIterable, Sendable {
    case wakingUp
    case daily
    case weekly
}

/// Stores the setup the person chose in Wellnario before completing the
/// personal automation in Shortcuts. iOS intentionally keeps the actual
/// automation private to Shortcuts, so these values are a reusable setup
/// draft, never a claim that an automation is already active.
struct AppleHealthShortcutAutomationPreferences {
    private let defaults: UserDefaults
    private let cadenceKey = "appleHealth.shortcutAutomation.cadence.v1"
    private let timeKey = "appleHealth.shortcutAutomation.time.v1"
    private let weekdaysKey = "appleHealth.shortcutAutomation.weekdays.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var cadence: AppleHealthShortcutAutomationCadence {
        get {
            defaults.string(forKey: cadenceKey)
                .flatMap(AppleHealthShortcutAutomationCadence.init(rawValue:))
                ?? .wakingUp
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: cadenceKey) }
    }

    /// Seconds from the start of the current day, used only for time-of-day
    /// automations. Keeping a wall-clock value makes it stable across dates.
    var time: Date {
        get {
            let seconds = defaults.object(forKey: timeKey) as? TimeInterval ?? defaultTime
            return date(forSecondsFromStartOfDay: seconds)
        }
        nonmutating set {
            let seconds = Calendar.autoupdatingCurrent.startOfDay(for: newValue)
                .distance(to: newValue)
            defaults.set(seconds, forKey: timeKey)
        }
    }

    /// Calendar weekday values (1 = Sunday through 7 = Saturday).
    var weekdays: Set<Int> {
        get {
            let saved = defaults.array(forKey: weekdaysKey) as? [Int] ?? []
            let valid = Set(saved.filter { (1...7).contains($0) })
            return valid.isEmpty ? Self.defaultWeekdays : valid
        }
        nonmutating set {
            let valid = Set(newValue.filter { (1...7).contains($0) })
            defaults.set(Array((valid.isEmpty ? Self.defaultWeekdays : valid).sorted()), forKey: weekdaysKey)
        }
    }

    private var defaultTime: TimeInterval { 8 * 60 * 60 }
    private static let defaultWeekdays: Set<Int> = [2, 3, 4, 5, 6]

    private func date(forSecondsFromStartOfDay seconds: TimeInterval) -> Date {
        let start = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        return start.addingTimeInterval(min(max(0, seconds), 86_399))
    }
}
