import Foundation

/// Locale-aware formatting used by UI components and feature controllers.
/// Formatters are created on demand to avoid shared mutable formatter state.
@MainActor
enum WellnarioFormatters {
    static func number(_ value: Double, maximumFractionDigits: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func amount(_ value: Double, unit: String, maximumFractionDigits: Int = 2) -> String {
        "\(number(value, maximumFractionDigits: maximumFractionDigits)) \(unit)"
    }

    static func percent(_ ratio: Double, maximumFractionDigits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: ratio)) ?? "\(ratio * 100)%"
    }

    static func currency(_ value: Decimal, currencyCode: String = "EUR") -> String {
        let formatter = NumberFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value) \(currencyCode)"
    }

    static func dateHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: date).lowercased(with: LocalizationManager.shared.locale)
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func time(_ date: Date, timeZoneID: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.timeZone = timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func dateAndTime(_ date: Date, timeZoneID: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.locale
        formatter.timeZone = timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func numericDateAndTime(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZoneID: String? = nil
    ) -> String {
        let timeZone = timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.setLocalizedDateFormatFromTemplate("ddMMyyyy")

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        return "\(dateFormatter.string(from: date)) · \(timeFormatter.string(from: date))"
    }

    static func expiryDescription(_ expiryDate: Date, relativeTo referenceDate: Date = Date()) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: referenceDate)
        let end = calendar.startOfDay(for: expiryDate)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0

        switch days {
        case ..<(-1):
            return L10n.text("expiry.expired_days", abs(days))
        case -1:
            return L10n.text("expiry.yesterday")
        case 0:
            return L10n.text("expiry.today")
        case 1:
            return L10n.text("expiry.tomorrow")
        default:
            return L10n.text("expiry.days", days)
        }
    }

    static func relativeDay(_ date: Date, referenceDate: Date = Date()) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) { return L10n.text("date.today") }
        if calendar.isDateInYesterday(date) { return L10n.text("date.yesterday") }
        return shortDate(date)
    }

}
