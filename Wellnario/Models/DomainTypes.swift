import Foundation

public enum DomainValueError: Error, Equatable, LocalizedError, Sendable {
    case invalidDecimal(String)
    case invalidDate(String)
    case incompatibleUnits(DoseUnit, DoseUnit)
    case arithmeticFailure

    public var errorDescription: String? {
        switch self {
        case let .invalidDecimal(value):
            return "Invalid decimal value: \(value)"
        case let .invalidDate(value):
            return "Invalid local date: \(value)"
        case let .incompatibleUnits(source, destination):
            return "Cannot convert \(source.rawValue) to \(destination.rawValue)."
        case .arithmeticFailure:
            return "The decimal calculation could not be completed."
        }
    }
}

public enum DoseUnitFamily: String, Codable, Sendable {
    case mass
    case volume
    case internationalUnit
    case discrete
}

/// Units are deliberately explicit. Discrete units are only compatible with
/// themselves: a capsule cannot silently be converted into a tablet or scoop.
public enum DoseUnit: String, CaseIterable, Codable, Hashable, Sendable {
    case microgram = "ug"
    case milligram = "mg"
    case gram = "g"
    case milliliter = "mL"
    case liter = "L"
    case internationalUnit = "IU"
    case capsule
    case tablet
    case drop
    case scoop
    case sachet
    case gummy
    case serving

    public var family: DoseUnitFamily {
        switch self {
        case .microgram, .milligram, .gram:
            return .mass
        case .milliliter, .liter:
            return .volume
        case .internationalUnit:
            return .internationalUnit
        case .capsule, .tablet, .drop, .scoop, .sachet, .gummy, .serving:
            return .discrete
        }
    }

    public func symbol(languageCode: String? = nil) -> String {
        switch self {
        case .microgram: return "µg"
        case .milligram: return "mg"
        case .gram: return "g"
        case .milliliter: return "ml"
        case .liter: return "l"
        case .internationalUnit: return "IU"
        case .capsule: return languageCode == "en" ? "caps" : "cáps."
        case .tablet: return languageCode == "en" ? "tabs" : "comp."
        case .drop: return languageCode == "en" ? "drops" : "gotas"
        case .scoop: return languageCode == "en" ? "scoops" : "cacitos"
        case .sachet: return languageCode == "en" ? "sachets" : "sobres"
        case .gummy: return languageCode == "en" ? "gummies" : "gominolas"
        case .serving: return languageCode == "en" ? "servings" : "porciones"
        }
    }

    public func isCompatible(with other: DoseUnit) -> Bool {
        if self == other { return true }
        return family == other.family && (family == .mass || family == .volume)
    }

    /// Converts an amount without passing through binary floating point.
    public func convert(_ amount: Decimal, to destination: DoseUnit) throws -> Decimal {
        guard isCompatible(with: destination) else {
            throw DomainValueError.incompatibleUnits(self, destination)
        }
        guard self != destination else { return amount }

        let sourceFactor = factorToFamilyBase
        let destinationFactor = destination.factorToFamilyBase
        let baseAmount = try DecimalMath.multiply(amount, sourceFactor)
        return try DecimalMath.divide(baseAmount, destinationFactor)
    }

    private var factorToFamilyBase: Decimal {
        switch self {
        case .microgram: return Decimal(string: "0.001")!
        case .milligram: return 1
        case .gram: return 1_000
        case .milliliter: return 1
        case .liter: return 1_000
        case .internationalUnit, .capsule, .tablet, .drop, .scoop, .sachet, .gummy, .serving:
            return 1
        }
    }
}

public struct Quantity: Codable, Hashable, Sendable {
    public var amount: Decimal
    public var unit: DoseUnit

    public init(amount: Decimal, unit: DoseUnit) {
        self.amount = amount
        self.unit = unit
    }

    public func converted(to destination: DoseUnit) throws -> Quantity {
        Quantity(amount: try unit.convert(amount, to: destination), unit: destination)
    }
}

/// A calendar day is stored separately from the UTC instant. This means an
/// intake remains on the day on which it was originally recorded after travel
/// or a daylight-saving transition.
public struct LocalDay: Codable, Hashable, Comparable, CustomStringConvertible, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else {
            throw DomainValueError.invalidDate("\(year)-\(month)-\(day)")
        }
        let verified = calendar.dateComponents([.year, .month, .day], from: date)
        guard verified.year == year, verified.month == month, verified.day == day else {
            throw DomainValueError.invalidDate("\(year)-\(month)-\(day)")
        }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(iso8601 value: String) throws {
        let pieces = value.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              pieces[0].count == 4,
              pieces[1].count == 2,
              pieces[2].count == 2,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]) else {
            throw DomainValueError.invalidDate(value)
        }
        try self.init(year: year, month: month, day: day)
    }

    public init(containing date: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year!
        self.month = components.month!
        self.day = components.day!
    }

    public var iso8601: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso8601 }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        lhs.iso8601 < rhs.iso8601
    }

    public func adding(days: Int) throws -> LocalDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              let advanced = calendar.date(byAdding: .day, value: days, to: date) else {
            throw DomainValueError.invalidDate(iso8601)
        }
        return LocalDay(containing: advanced, in: calendar.timeZone)
    }

    public func startDate(in timeZone: TimeZone) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let result = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            throw DomainValueError.invalidDate(iso8601)
        }
        return result
    }
}

public enum DecimalCodec {
    private static let locale = Locale(identifier: "en_US_POSIX")

    public static func encode(_ value: Decimal) throws -> String {
        guard isFinite(value) else { throw DomainValueError.invalidDecimal("NaN") }
        var value = value
        return NSDecimalString(&value, locale)
    }

    public static func decode(_ value: String) throws -> Decimal {
        guard let decimal = Decimal(string: value, locale: locale), isFinite(decimal) else {
            throw DomainValueError.invalidDecimal(value)
        }
        return decimal
    }

    public static func isFinite(_ value: Decimal) -> Bool {
        NSDecimalNumber(decimal: value) != NSDecimalNumber.notANumber
    }
}

public enum DecimalMath {
    public static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        let error = NSDecimalAdd(&result, &lhs, &rhs, .bankers)
        try validate(error)
        return result
    }

    public static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        let error = NSDecimalMultiply(&result, &lhs, &rhs, .bankers)
        try validate(error)
        return result
    }

    public static func divide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard rhs != 0 else { throw DomainValueError.arithmeticFailure }
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        let error = NSDecimalDivide(&result, &lhs, &rhs, .bankers)
        try validate(error)
        return result
    }

    private static func validate(_ error: Decimal.CalculationError) throws {
        switch error {
        case .noError, .lossOfPrecision:
            return
        case .underflow, .overflow, .divideByZero:
            throw DomainValueError.arithmeticFailure
        @unknown default:
            throw DomainValueError.arithmeticFailure
        }
    }
}
