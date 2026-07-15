import Foundation

@MainActor
enum AppleHealthUIFormatting {
    static func number(_ value: Double, maximumFractionDigits: Int = 0) -> String {
        WellnarioFormatters.number(value, maximumFractionDigits: maximumFractionDigits)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int((seconds / 60).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return L10n.text("apple_health.duration.minutes", minutes) }
        if minutes == 0 { return L10n.text("apple_health.duration.hours", hours) }
        return L10n.text("apple_health.duration.hours_minutes", hours, minutes)
    }

    static func compactDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int((seconds / 60).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return L10n.text("apple_health.duration.compact.minutes", minutes) }
        if minutes == 0 { return L10n.text("apple_health.duration.compact.hours", hours) }
        return L10n.text("apple_health.duration.compact.hours_minutes", hours, minutes)
    }

    static func sleepRange(_ session: AppleHealthSleepSession) -> String {
        let start = WellnarioFormatters.time(session.startDate)
        let end = WellnarioFormatters.time(session.endDate)
        let range = L10n.text("apple_health.sleep.range", start, end)
        return L10n.text(
            "apple_health.sleep.day_range",
            WellnarioFormatters.relativeDay(session.endDate),
            range
        )
    }

    static func syncedAt(_ date: Date) -> String {
        L10n.text("apple_health.synced_at", WellnarioFormatters.dateAndTime(date))
    }

    static func weekdayInitial(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: date).uppercased(with: formatter.locale)
    }

    static func workoutTitle(_ kind: AppleHealthWorkoutKind) -> String {
        L10n.text("apple_health.workout.\(kind.rawValue)")
    }

    static func workoutSymbol(_ kind: AppleHealthWorkoutKind) -> String {
        switch kind {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .yoga: "figure.yoga"
        case .highIntensityIntervalTraining: "figure.highintensity.intervaltraining"
        case .other: "figure.mixed.cardio"
        }
    }
}
