import Foundation

/// Automatic sleep factors derived from compliance with the targets set for a
/// favorite supplement. Their IDs use the persistent active UUID so a factor's
/// enabled state survives a name or language change.
enum SleepSupplementFactorCadence: String, CaseIterable, Sendable {
    case daily
    case weekly
}

@MainActor
enum SleepSupplementFactorCatalog {
    private static let idPrefix = "automatic.supplement."

    static func definitions(
        repository: WellnarioRepositoryProtocol?
    ) -> [SleepFactorDefinition] {
        guard let repository,
              let favorites = try? repository.fetchActives(includeArchived: false) else {
            return []
        }
        let language = CatalogLanguage(languageCode: LocalizationManager.shared.language.rawValue)
        let locale = LocalizationManager.shared.locale
        let definitions: [SleepFactorDefinition] = favorites
            .filter(\.isFavorite)
            .flatMap { active -> [SleepFactorDefinition] in
                let name = active.localizedName(language: language).lowercased(with: locale)
                return SleepSupplementFactorCadence.allCases.map { cadence in
                    SleepFactorDefinition(
                        id: id(for: active.id, cadence: cadence),
                        category: .automatic,
                        title: title(for: name, cadence: cadence),
                        valueKind: .discrete,
                        source: .automatic,
                        symbolName: "pills.fill",
                        analysisStep: 1,
                        analysisStepLabel: ""
                    )
                }
            }
        return definitions.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    static func isSupplementFactor(_ factorID: String) -> Bool {
        metadata(for: factorID) != nil
    }

    /// The first calendar day with an intake registered for this supplement.
    /// Sleep analyses use it as their lower bound, so a person's time before
    /// starting to use Wellnario cannot be mistaken for non-compliance.
    static func firstTrackedDay(
        for definition: SleepFactorDefinition,
        referenceDay: LocalDay,
        repository: WellnarioRepositoryProtocol
    ) -> LocalDay? {
        guard let metadata = metadata(for: definition.id),
              let active = try? repository.active(id: metadata.activeID),
              active.isFavorite,
              !active.isArchived else {
            return nil
        }

        return (try? repository.dailyConsumption(
            activeID: active.id,
            from: referenceDay,
            through: referenceDay
        ))?.firstRecordedDay
    }

    /// Returns the calendar day on which the intake associated with a sleep
    /// session should be evaluated. An overnight session belongs to the day
    /// on which it began, rather than the morning on which it ended.
    static func sourceDay(
        sleepDate: Date,
        sleepStartDate: Date? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> LocalDay {
        let sourceDate = sleepStartDate
            ?? calendar.date(byAdding: .day, value: -1, to: sleepDate)
            ?? sleepDate
        return LocalDay(containing: sourceDate, in: calendar.timeZone)
    }

    /// Returns `nil` until the person has started tracking the supplement or
    /// when no target exists for the relevant period. This avoids treating
    /// untracked days as failed targets in the sleep analysis.
    static func value(
        for definition: SleepFactorDefinition,
        sleepDate: Date,
        sleepStartDate: Date? = nil,
        repository: WellnarioRepositoryProtocol,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Double? {
        guard let metadata = metadata(for: definition.id),
              let active = try? repository.active(id: metadata.activeID),
              active.isFavorite,
              !active.isArchived else {
            return nil
        }

        let day = sourceDay(
            sleepDate: sleepDate,
            sleepStartDate: sleepStartDate,
            calendar: calendar
        )

        switch metadata.cadence {
        case .daily:
            guard let series = try? repository.dailyConsumption(
                activeID: active.id,
                from: day,
                through: day
            ), let firstRecordedDay = series.firstRecordedDay,
              firstRecordedDay <= day,
              let point = series.points.first,
              point.status != .noTarget else {
                return nil
            }
            return point.status == .within ? 1 : 0

        case .weekly:
            guard let from = try? day.adding(days: -6),
                  let series = try? repository.dailyConsumption(
                    activeID: active.id,
                    from: from,
                    through: day
                  ), let firstRecordedDay = series.firstRecordedDay,
                  firstRecordedDay <= from,
                  series.points.count == 7 else {
                return nil
            }

            var amount: Decimal = 0
            var lower: Decimal = 0
            var upper: Decimal = 0
            for point in series.points {
                guard let targetLower = point.targetLower,
                      let targetUpper = point.targetUpper else {
                    return nil
                }
                amount += point.amount
                lower += targetLower
                upper += targetUpper
            }
            return amount >= lower && amount <= upper ? 1 : 0
        }
    }

    private static func id(for activeID: UUID, cadence: SleepSupplementFactorCadence) -> String {
        "\(idPrefix)\(cadence.rawValue).\(activeID.uuidString.lowercased())"
    }

    private static func title(for name: String, cadence: SleepSupplementFactorCadence) -> String {
        let key: String
        switch cadence {
        case .daily: key = "sleep.factor.automatic.supplement.daily"
        case .weekly: key = "sleep.factor.automatic.supplement.weekly"
        }
        return L10n.text(key, name)
    }

    private static func metadata(
        for factorID: String
    ) -> (activeID: UUID, cadence: SleepSupplementFactorCadence)? {
        guard factorID.hasPrefix(idPrefix) else { return nil }
        let pieces = factorID.dropFirst(idPrefix.count).split(separator: ".", maxSplits: 1)
        guard pieces.count == 2,
              let cadence = SleepSupplementFactorCadence(rawValue: String(pieces[0])),
              let activeID = UUID(uuidString: String(pieces[1])) else {
            return nil
        }
        return (activeID, cadence)
    }
}
