import Foundation
import UIKit
import XCTest
@testable import Wellnario

final class RepositoryTests: XCTestCase {
    func testSeedsAreBilingualIdempotentAndHaveIllustrationVariants() throws {
        let (repository, url) = try makeRepository()

        let firstActives = try repository.fetchActives()
        let firstPresentations = try repository.fetchPresentationTypes()
        XCTAssertEqual(firstActives.count, SeedData.activeSeeds.count)
        XCTAssertGreaterThanOrEqual(firstPresentations.count, 8)
        XCTAssertTrue(firstPresentations.allSatisfy { $0.illustrations.count >= 3 })

        let seededImageKeys = firstActives.filter(\.isSeeded).compactMap(\.imageKey)
        XCTAssertEqual(Set(seededImageKeys).count, SeedData.activeSeeds.count)
        XCTAssertTrue(firstActives.filter(\.isSeeded).allSatisfy { !$0.categories.isEmpty })
        for imageKey in seededImageKeys {
            XCTAssertNotNil(UIImage(named: imageKey), "Missing active artwork: \(imageKey)")
        }

        let vitaminC = try XCTUnwrap(firstActives.first { $0.nameKey == "active.vitamin_c.name" })
        XCTAssertEqual(vitaminC.localizedName(language: .spanish), "Vitamina C")
        XCTAssertEqual(vitaminC.localizedName(language: .english), "Vitamin C")
        XCTAssertEqual(Set(vitaminC.categories), [.immunity, .aesthetics, .antioxidant])

        let expandedCatalog: [(slug: String, spanish: String, english: String, unit: DoseUnit)] = [
            ("ashwagandha", "Ashwagandha", "Ashwagandha", .milligram),
            ("astaxanthin", "Astaxantina", "Astaxanthin", .milligram),
            ("berberine", "Berberina", "Berberine", .milligram),
            ("coenzyme_q10", "Coenzima Q10", "Coenzyme Q10", .milligram),
            ("hydrolyzed_collagen", "Colágeno hidrolizado", "Hydrolyzed collagen", .gram),
            ("spermidine", "Espermidina", "Spermidine", .milligram),
            ("l_arginine", "L-arginina", "L-arginine", .gram),
            ("glycine", "Glicina", "Glycine", .gram),
            ("taurine", "Taurina", "Taurine", .gram),
            ("resveratrol", "Resveratrol", "Resveratrol", .milligram),
            ("nicotinamide_riboside", "Nicotinamida ribósido", "Nicotinamide riboside", .milligram),
            ("quercetin", "Quercetina", "Quercetin", .milligram),
            ("lutein", "Luteína", "Lutein", .milligram),
            ("sulforaphane", "Sulforafano", "Sulforaphane", .milligram)
        ]
        for item in expandedCatalog {
            let active = try XCTUnwrap(firstActives.first { $0.nameKey == "active.\(item.slug).name" })
            XCTAssertEqual(active.localizedName(language: .spanish), item.spanish)
            XCTAssertEqual(active.localizedName(language: .english), item.english)
            XCTAssertEqual(active.baseUnit, item.unit)
            XCTAssertFalse(try XCTUnwrap(active.localizedDescription(language: .spanish)).isEmpty)
            XCTAssertFalse(try XCTUnwrap(active.localizedDescription(language: .english)).isEmpty)
        }

        let reopened = try WellnarioRepository(databaseURL: url)
        XCTAssertEqual(try reopened.fetchActives(includeArchived: true).count, firstActives.count)
        XCTAssertEqual(try reopened.fetchPresentationTypes().count, firstPresentations.count)
        XCTAssertEqual(
            try reopened.fetchPresentationTypes().flatMap(\.illustrations).count,
            firstPresentations.flatMap(\.illustrations).count
        )
    }

    func testActiveCategoriesSupportMultipleAssignmentsAndPersistUpdates() throws {
        let (repository, url) = try makeRepository()
        let active = try repository.createActive(
            ActiveDraft(
                name: "Categorized active",
                baseUnit: .milligram,
                categories: [.sleep, .antioxidant]
            )
        )
        XCTAssertEqual(Set(active.categories), [.sleep, .antioxidant])

        let updated = try repository.updateActive(
            id: active.id,
            with: ActiveDraft(
                name: active.customName ?? "Categorized active",
                baseUnit: active.baseUnit,
                categories: [.physicalPerformance, .aesthetics, .antioxidant]
            )
        )
        XCTAssertEqual(
            Set(updated.categories),
            [.physicalPerformance, .aesthetics, .antioxidant]
        )

        let reopened = try WellnarioRepository(databaseURL: url)
        let persisted = try XCTUnwrap(try reopened.active(id: active.id))
        XCTAssertEqual(
            Set(persisted.categories),
            [.physicalPerformance, .aesthetics, .antioxidant]
        )
    }

    func testActiveFavoritesAreUserScopedAndPersist() throws {
        let (repository, url) = try makeRepository()
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.magnesium.name" }
        )
        XCTAssertFalse(active.isFavorite)

        let favorite = try repository.setActiveFavorite(id: active.id, isFavorite: true)
        XCTAssertTrue(favorite.isFavorite)
        XCTAssertTrue(try XCTUnwrap(try WellnarioRepository(databaseURL: url).active(id: active.id)).isFavorite)

        let otherUserRepository = try WellnarioRepository(databaseURL: url, userID: UUID())
        XCTAssertFalse(try XCTUnwrap(try otherUserRepository.active(id: active.id)).isFavorite)

        let restored = try repository.setActiveFavorite(id: active.id, isFavorite: false)
        XCTAssertFalse(restored.isFavorite)
    }

    func testTargetPersistsSelectedCompatibleUnit() throws {
        let (repository, url) = try makeRepository()
        let active = try repository.createActive(
            ActiveDraft(name: "Target unit active", baseUnit: .milligram)
        )
        let day = try LocalDay(year: 2026, month: 7, day: 16)
        let target = try repository.setTarget(
            activeID: active.id,
            lowerBound: 1.5,
            upperBound: 1.5,
            unit: .gram,
            effectiveFrom: day
        )
        XCTAssertEqual(target.unit, .gram)
        XCTAssertEqual(target.lowerBound, 1.5)

        let reopened = try WellnarioRepository(databaseURL: url)
        XCTAssertEqual(try XCTUnwrap(try reopened.targetHistory(activeID: active.id).last).unit, .gram)
        XCTAssertThrowsError(
            try repository.setTarget(
                activeID: active.id,
                lowerBound: 1,
                upperBound: 1,
                unit: .milliliter,
                effectiveFrom: day
            )
        )
    }

    func testPackageTotalAndOptionalBrandPersistAcrossRepositoryReopen() throws {
        let (repository, url) = try makeRepository()
        let presentation = try presentation(repository, key: "presentation.powder.name")
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.creatine.name" }
        )
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Creatina sin marca",
            brand: "",
            presentationTypeID: presentation.id,
            basisQuantity: 100,
            basisUnit: .gram,
            components: [SupplementComponentDraft(activeID: active.id, amount: 100, unit: .gram)]
        ))
        let expiry = try LocalDay(year: 2028, month: 6, day: 30)
        let instance = try repository.createInstance(SupplementInstanceDraft(
            supplementID: supplement.id,
            expirationDay: expiry,
            totalQuantity: 500,
            totalUnit: .gram
        ))

        XCTAssertEqual(supplement.brand, "")
        XCTAssertEqual(instance.totalQuantity, 500)
        XCTAssertEqual(instance.totalUnit, .gram)

        let reopened = try WellnarioRepository(databaseURL: url)
        let persistedSupplement = try XCTUnwrap(try reopened.supplement(id: supplement.id))
        let persistedInstance = try XCTUnwrap(try reopened.instance(id: instance.id))
        XCTAssertEqual(persistedSupplement.brand, "")
        XCTAssertEqual(persistedInstance.expirationDay, expiry)
        XCTAssertEqual(persistedInstance.totalQuantity, 500)
        XCTAssertEqual(persistedInstance.totalUnit, .gram)
    }

    @MainActor
    func testSupplementPhotoStoreRoundTripsAndRemovesUserPhoto() throws {
        let (repository, _) = try makeRepository()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        }

        let reference = try SupplementPhotoStore.save(image, databaseURL: repository.databaseURL)
        XCTAssertTrue(reference.hasPrefix("user-photo:"))
        XCTAssertNotNil(SupplementPhotoStore.image(reference: reference, databaseURL: repository.databaseURL))

        SupplementPhotoStore.remove(reference: reference, databaseURL: repository.databaseURL)
        XCTAssertNil(SupplementPhotoStore.image(reference: reference, databaseURL: repository.databaseURL))
    }

    func testFormulaPersistenceAndHistoryRemainInvariantAfterFormulaChange() throws {
        let (repository, url) = try makeRepository()
        let active = try repository.createActive(
            ActiveDraft(name: "Test magnesium", baseUnit: .milligram)
        )
        let capsule = try presentation(repository, key: "presentation.capsule.name")
        let initialDraft = SupplementDraft(
            name: "Magnesium Complex",
            brand: "Well Labs",
            presentationTypeID: capsule.id,
            basisQuantity: 2,
            basisUnit: .capsule,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 200, unit: .milligram)
            ]
        )
        let supplement = try repository.createSupplement(initialDraft)
        let instance = try repository.createInstance(
            SupplementInstanceDraft(supplementID: supplement.id, label: "LOT-A")
        )
        let first = try repository.createConsumption(
            ConsumptionDraft(
                instanceID: instance.id,
                quantity: decimal("1.5"),
                unit: .capsule,
                consumedAt: try utcDate(2026, 7, 1, hour: 9),
                timeZoneID: "UTC"
            )
        )
        XCTAssertEqual(try XCTUnwrap(first.activeSnapshots.first).amount, 150)

        var changedDraft = initialDraft
        changedDraft.components = [
            SupplementComponentDraft(activeID: active.id, amount: 400, unit: .milligram)
        ]
        _ = try repository.updateSupplement(id: supplement.id, with: changedDraft)

        let historical = try XCTUnwrap(repository.consumption(id: first.id))
        XCTAssertEqual(try XCTUnwrap(historical.activeSnapshots.first).amount, 150)

        let edited = try repository.updateConsumption(
            id: first.id,
            with: ConsumptionDraft(
                instanceID: instance.id,
                quantity: decimal("1.5"),
                unit: .capsule,
                consumedAt: first.consumedAt,
                timeZoneID: "UTC",
                notes: "Corrected note"
            )
        )
        XCTAssertEqual(try XCTUnwrap(edited.activeSnapshots.first).amount, 150)

        let second = try repository.createConsumption(
            ConsumptionDraft(
                instanceID: instance.id,
                quantity: 1,
                unit: .capsule,
                consumedAt: try utcDate(2026, 7, 2, hour: 9),
                timeZoneID: "UTC"
            )
        )
        XCTAssertEqual(try XCTUnwrap(second.activeSnapshots.first).amount, 200)

        let reopened = try WellnarioRepository(databaseURL: url)
        XCTAssertEqual(
            try XCTUnwrap(try reopened.consumption(id: first.id)?.activeSnapshots.first).amount,
            150
        )
        XCTAssertEqual(try reopened.fetchSupplements().first?.name, "Magnesium Complex")
    }

    func testDailyAggregationIncludesZeroDaysAndUsesAllDaysForAverage() throws {
        let (repository, _) = try makeRepository()
        let active = try repository.createActive(
            ActiveDraft(name: "Aggregation active", baseUnit: .milligram)
        )
        let from = try LocalDay(year: 2026, month: 7, day: 1)
        let through = try LocalDay(year: 2026, month: 7, day: 4)
        _ = try repository.setTarget(
            activeID: active.id,
            lowerBound: 50,
            upperBound: 150,
            effectiveFrom: from
        )
        let capsule = try presentation(repository, key: "presentation.capsule.name")
        let supplement = try repository.createSupplement(
            SupplementDraft(
                name: "Aggregation product",
                brand: "Well Labs",
                presentationTypeID: capsule.id,
                basisQuantity: 1,
                basisUnit: .capsule,
                components: [
                    SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
                ]
            )
        )
        let instance = try repository.createInstance(SupplementInstanceDraft(supplementID: supplement.id))
        _ = try repository.createConsumption(
            ConsumptionDraft(
                instanceID: instance.id,
                quantity: 1,
                unit: .capsule,
                consumedAt: try utcDate(2026, 7, 1, hour: 10),
                timeZoneID: "UTC"
            )
        )
        _ = try repository.createConsumption(
            ConsumptionDraft(
                instanceID: instance.id,
                quantity: 2,
                unit: .capsule,
                consumedAt: try utcDate(2026, 7, 3, hour: 10),
                timeZoneID: "UTC"
            )
        )
        _ = try repository.setTarget(
            activeID: active.id,
            lowerBound: 180,
            upperBound: 220,
            effectiveFrom: try LocalDay(year: 2026, month: 7, day: 3)
        )

        let series = try repository.dailyConsumption(activeID: active.id, from: from, through: through)
        XCTAssertEqual(series.points.map(\.amount), [100, 0, 200, 0])
        XCTAssertEqual(series.points.map(\.targetLower), [50, 50, 180, 180])
        XCTAssertEqual(series.points.map(\.targetUpper), [150, 150, 220, 220])
        XCTAssertEqual(series.total, 300)
        XCTAssertEqual(series.average, 75)
        XCTAssertEqual(series.daysWithinTarget, 2)
        XCTAssertEqual(series.points.map(\.status), [.within, .below, .within, .below])

        let aggregationDays = try (0..<4).map { try from.adding(days: $0) }
        let weeklyValues = try WeeklyConsumptionAggregator.values(
            actives: [active],
            consumptions: try repository.fetchConsumptions(
                from: from,
                through: through,
                limit: nil
            ),
            days: aggregationDays
        )
        XCTAssertEqual(weeklyValues[active.id], [100, 0, 200, 0])

        let diary = try repository.diary(from: from, through: through)
        XCTAssertEqual(diary.map(\.day), [
            try LocalDay(year: 2026, month: 7, day: 3),
            try LocalDay(year: 2026, month: 7, day: 1)
        ])
        let dashboard = try repository.dashboard(on: from, expiringWithinDays: 30)
        XCTAssertEqual(dashboard.consumptionCount, 1)
        XCTAssertEqual(dashboard.activeProgress.first(where: { $0.id == active.id })?.consumedAmount, 100)
    }

    func testSingleValueTargetUsesConfiguredMarginWhileExplicitRangeRemainsUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WellnarioTargetMarginTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaultsSuite = "WellnarioTargetMarginTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
        }

        let repository = try WellnarioRepository(
            databaseURL: directory.appendingPathComponent("test.sqlite"),
            preferencesDefaults: defaults
        )
        let preferences = ActiveTargetMarginPreferences(defaults: defaults)
        XCTAssertEqual(preferences.percentage, 10)

        let active = try repository.createActive(
            ActiveDraft(name: "Margin active", baseUnit: .milligram)
        )
        let from = try LocalDay(year: 2026, month: 7, day: 1)
        let dayTwo = try LocalDay(year: 2026, month: 7, day: 2)
        let dayThree = try LocalDay(year: 2026, month: 7, day: 3)
        let dayFour = try LocalDay(year: 2026, month: 7, day: 4)
        let dayFive = try LocalDay(year: 2026, month: 7, day: 5)
        _ = try repository.setTarget(
            activeID: active.id,
            lowerBound: 26,
            upperBound: 26,
            effectiveFrom: from
        )

        let capsule = try presentation(repository, key: "presentation.capsule.name")
        let supplement = try repository.createSupplement(
            SupplementDraft(
                name: "Margin product",
                brand: "Well Labs",
                presentationTypeID: capsule.id,
                basisQuantity: 1,
                basisUnit: .capsule,
                components: [
                    SupplementComponentDraft(activeID: active.id, amount: 1, unit: .milligram)
                ]
            )
        )
        let instance = try repository.createInstance(
            SupplementInstanceDraft(supplementID: supplement.id)
        )
        for (day, amount) in [
            (from, decimal("23.4")),
            (dayTwo, decimal("28.6")),
            (dayThree, decimal("23.39")),
            (dayFour, decimal("28.61"))
        ] {
            _ = try repository.createConsumption(
                ConsumptionDraft(
                    instanceID: instance.id,
                    quantity: amount,
                    unit: .capsule,
                    consumedAt: try day.startDate(in: TimeZone(secondsFromGMT: 0)!).addingTimeInterval(36_000),
                    timeZoneID: "UTC"
                )
            )
        }

        let exactTargetSeries = try repository.dailyConsumption(
            activeID: active.id,
            from: from,
            through: dayFour
        )
        XCTAssertEqual(exactTargetSeries.points.map(\.targetLower), Array(repeating: decimal("23.4"), count: 4))
        XCTAssertEqual(exactTargetSeries.points.map(\.targetUpper), Array(repeating: decimal("28.6"), count: 4))
        XCTAssertEqual(exactTargetSeries.points.map(\.status), [.within, .within, .below, .above])

        preferences.setPercentage(50)
        _ = try repository.setTarget(
            activeID: active.id,
            lowerBound: 20,
            upperBound: 30,
            effectiveFrom: dayFive
        )
        let explicitRangeSeries = try repository.dailyConsumption(
            activeID: active.id,
            from: dayFive,
            through: dayFive
        )
        XCTAssertEqual(explicitRangeSeries.points.first?.targetLower, 20)
        XCTAssertEqual(explicitRangeSeries.points.first?.targetUpper, 30)
    }

    func testCRUDDeletesUnusedRecordsAndArchivesRecordsWithHistory() throws {
        let (repository, _) = try makeRepository()
        let active = try repository.createActive(ActiveDraft(name: "CRUD active", baseUnit: .milligram))
        let updatedActive = try repository.updateActive(
            id: active.id,
            with: ActiveDraft(name: "Updated CRUD active", description: "Updated", baseUnit: .gram)
        )
        XCTAssertEqual(updatedActive.customName, "Updated CRUD active")
        XCTAssertEqual(updatedActive.baseUnit, .gram)

        let capsule = try presentation(repository, key: "presentation.capsule.name")
        let supplement = try repository.createSupplement(
            SupplementDraft(
                name: "CRUD product",
                brand: "CRUD brand",
                presentationTypeID: capsule.id,
                basisQuantity: 1,
                basisUnit: .capsule,
                components: [SupplementComponentDraft(activeID: active.id, amount: 1, unit: .gram)]
            )
        )
        let instance = try repository.createInstance(
            SupplementInstanceDraft(
                supplementID: supplement.id,
                label: "Before",
                expirationDay: try LocalDay(year: 2027, month: 1, day: 1)
            )
        )
        let updatedInstance = try repository.updateInstance(
            id: instance.id,
            with: SupplementInstanceDraft(supplementID: supplement.id, label: "After")
        )
        XCTAssertEqual(updatedInstance.label, "After")

        let consumption = try repository.createConsumption(
            ConsumptionDraft(
                instanceID: instance.id,
                quantity: 1,
                unit: .capsule,
                consumedAt: try utcDate(2026, 7, 5, hour: 8),
                timeZoneID: "UTC"
            )
        )
        XCTAssertEqual(try repository.deleteActive(id: active.id), .archived)
        XCTAssertThrowsError(
            try repository.createActive(ActiveDraft(name: "Updated CRUD active", baseUnit: .gram))
        )

        let archivedActiveDraft = SupplementDraft(
            name: "Updated while active archived",
            brand: "CRUD brand",
            presentationTypeID: capsule.id,
            basisQuantity: 1,
            basisUnit: .capsule,
            components: [SupplementComponentDraft(activeID: active.id, amount: 1, unit: .gram)]
        )
        let editedWithArchivedActive = try repository.updateSupplement(
            id: supplement.id,
            with: archivedActiveDraft
        )
        XCTAssertEqual(editedWithArchivedActive.name, "Updated while active archived")

        XCTAssertEqual(try repository.deleteInstance(id: instance.id), .archived)
        let editedArchivedConsumption = try repository.updateConsumption(
            id: consumption.id,
            with: ConsumptionDraft(
                instanceID: instance.id,
                quantity: 1,
                unit: .capsule,
                consumedAt: consumption.consumedAt,
                timeZoneID: consumption.timeZoneID,
                notes: "Edited after archiving"
            )
        )
        XCTAssertEqual(editedArchivedConsumption.notes, "Edited after archiving")

        XCTAssertEqual(try repository.deleteSupplement(id: supplement.id), .archived)
        XCTAssertNotNil(try repository.instance(id: instance.id)?.archivedAt)
        XCTAssertNotNil(try repository.supplement(id: supplement.id)?.archivedAt)
        XCTAssertNotNil(try repository.active(id: active.id)?.archivedAt)

        _ = try repository.restoreActive(id: active.id)
        _ = try repository.restoreSupplement(id: supplement.id)
        XCTAssertNotNil(try repository.instance(id: instance.id)?.archivedAt)
        _ = try repository.restoreInstance(id: instance.id)
        XCTAssertNil(try repository.instance(id: instance.id)?.archivedAt)
        try repository.deleteConsumption(id: consumption.id)
        XCTAssertEqual(try repository.deleteInstance(id: instance.id), .deleted)
        XCTAssertEqual(try repository.deleteSupplement(id: supplement.id), .deleted)
        XCTAssertEqual(try repository.deleteActive(id: active.id), .deleted)
        XCTAssertNil(try repository.active(id: active.id))
    }

    func testMutationPostsRepositoryNotification() throws {
        let (repository, _) = try makeRepository()
        let expectation = expectation(forNotification: .wellnarioRepositoryDidChange, object: repository) { note in
            guard let change = note.userInfo?[WellnarioRepositoryNotificationKey.change] as? RepositoryChange else {
                return false
            }
            return change.entity == .active && change.mutation == .created
        }
        _ = try repository.createActive(ActiveDraft(name: "Notification active", baseUnit: .milligram))
        wait(for: [expectation], timeout: 1)
    }

    private func makeRepository() throws -> (WellnarioRepository, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WellnarioRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        return (try WellnarioRepository(databaseURL: url), url)
    }

    private func presentation(
        _ repository: WellnarioRepository,
        key: String
    ) throws -> PresentationType {
        try XCTUnwrap(repository.fetchPresentationTypes().first { $0.nameKey == key })
    }

    private func utcDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int
    ) throws -> Date {
        let localDay = try LocalDay(year: year, month: month, day: day)
        return try localDay.startDate(in: TimeZone(secondsFromGMT: 0)!).addingTimeInterval(Double(hour * 3_600))
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

}
