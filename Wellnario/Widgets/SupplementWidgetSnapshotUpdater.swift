import Foundation
import WidgetKit

@MainActor
enum SupplementWidgetSnapshotUpdater {
    static func refresh(repository: WellnarioRepositoryProtocol) {
        do {
            let languageCode = LocalizationManager.shared.language.rawValue
            let store = SupplementWidgetDataStore()
            let snapshot = try makeSnapshot(repository: repository, languageCode: languageCode)
            store.save(snapshot)
            store.retainSelections(in: Set(snapshot.packages.map(\.id)))
        } catch {
            // Preserve the most recent snapshot if the database is temporarily
            // unavailable; the widget must remain useful while the app recovers.
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WellnarioSupplementWidget.kind)
    }

    nonisolated static func supportsWidgetRegistration(for unit: DoseUnit) -> Bool {
        // Discrete units are confirmed as a number of intakes. Mass and volume
        // units are also supported: the app asks for their exact amount before
        // creating the consumption record.
        true
    }

    static func makeSnapshot(
        repository: WellnarioRepositoryProtocol,
        languageCode: String,
        currentDate: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) throws -> SupplementWidgetSnapshot {
        let language = CatalogLanguage(languageCode: languageCode)
        let today = LocalDay(containing: currentDate, in: timeZone)
        let packagesWithIntakeToday = Set(
            try repository
                .fetchConsumptions(from: today, through: today, limit: nil)
                .map(\.instanceID)
        )
        let supplements = try Dictionary(
            uniqueKeysWithValues: repository.fetchSupplements(includeArchived: false).map { ($0.id, $0) }
        )
        let presentationKeys = try Dictionary(
            uniqueKeysWithValues: repository.fetchPresentationTypes().map { ($0.id, $0.nameKey) }
        )
        let packages = try repository
            .fetchInstances(supplementID: nil, includeArchived: false)
            .compactMap { instance -> SupplementWidgetPackage? in
                guard let supplement = supplements[instance.supplementID] else { return nil }
                return SupplementWidgetPackage(
                    id: instance.id.uuidString,
                    supplementName: supplement.name,
                    instanceLabel: instance.label,
                    doseDescription: amountDescription(
                        supplement.basisQuantity,
                        unit: supplement.basisUnit,
                        languageCode: languageCode
                    ),
                    inventoryDescription: instance.totalQuantity.map {
                        inventoryDescription(
                            $0,
                            unit: instance.totalUnit ?? supplement.basisUnit,
                            language: language
                        )
                    },
                    hasIntakeToday: packagesWithIntakeToday.contains(instance.id),
                    presentationKey: presentationKeys[supplement.presentationTypeID]
                )
            }
        return SupplementWidgetSnapshot(packages: packages, languageCode: languageCode)
    }

    private static func amountDescription(
        _ quantity: Decimal,
        unit: DoseUnit,
        languageCode: String
    ) -> String {
        "\(FeatureFormatting.decimal(quantity)) \(unit.symbol(languageCode: languageCode))"
    }

    private static func inventoryDescription(
        _ quantity: Decimal,
        unit: DoseUnit,
        language: CatalogLanguage
    ) -> String {
        let remaining = language == .english ? "remaining" : "restantes"
        return "\(FeatureFormatting.decimal(quantity)) \(unit.symbol(languageCode: language.rawValue)) \(remaining)"
    }
}
