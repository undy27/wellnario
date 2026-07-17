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
        XCTAssertEqual(instance.label, "")
        XCTAssertEqual(instance.totalQuantity, 500)
        XCTAssertEqual(instance.totalUnit, .gram)
        XCTAssertEqual(instance.initialQuantity, 500)
        XCTAssertEqual(instance.initialUnit, .gram)

        let reopened = try WellnarioRepository(databaseURL: url)
        let persistedSupplement = try XCTUnwrap(try reopened.supplement(id: supplement.id))
        let persistedInstance = try XCTUnwrap(try reopened.instance(id: instance.id))
        XCTAssertEqual(persistedSupplement.brand, "")
        XCTAssertEqual(persistedInstance.label, "")
        XCTAssertEqual(persistedInstance.expirationDay, expiry)
        XCTAssertEqual(persistedInstance.totalQuantity, 500)
        XCTAssertEqual(persistedInstance.totalUnit, .gram)
        XCTAssertEqual(persistedInstance.initialQuantity, 500)
        XCTAssertEqual(persistedInstance.initialUnit, .gram)
    }

    func testConsumptionCreateUpdateAndDeleteKeepInventoryInSync() throws {
        let (repository, _) = try makeRepository()
        let presentation = try presentation(repository, key: "presentation.capsule.name")
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.magnesium.name" }
        )
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Magnesio",
            brand: "",
            presentationTypeID: presentation.id,
            basisQuantity: 1,
            basisUnit: .capsule,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
            ]
        ))
        let instance = try repository.createInstance(SupplementInstanceDraft(
            supplementID: supplement.id,
            totalQuantity: 30,
            totalUnit: .capsule
        ))

        let consumption = try repository.createConsumption(ConsumptionDraft(
            instanceID: instance.id,
            quantity: 1,
            unit: .capsule,
            consumedAt: try utcDate(2026, 7, 17, hour: 9),
            timeZoneID: "UTC"
        ))
        var updatedInstance = try XCTUnwrap(repository.instance(id: instance.id))
        XCTAssertEqual(updatedInstance.totalQuantity, 29)
        XCTAssertEqual(updatedInstance.initialQuantity, 30)

        _ = try repository.updateConsumption(
            id: consumption.id,
            with: ConsumptionDraft(
                instanceID: instance.id,
                quantity: 3,
                unit: .capsule,
                consumedAt: consumption.consumedAt,
                timeZoneID: "UTC"
            )
        )
        updatedInstance = try XCTUnwrap(repository.instance(id: instance.id))
        XCTAssertEqual(updatedInstance.totalQuantity, 27)
        XCTAssertEqual(updatedInstance.initialQuantity, 30)

        try repository.deleteConsumption(id: consumption.id)
        updatedInstance = try XCTUnwrap(repository.instance(id: instance.id))
        XCTAssertEqual(updatedInstance.totalQuantity, 30)
        XCTAssertEqual(updatedInstance.initialQuantity, 30)
    }

    @MainActor
    func testReconciliationAddsMissingContinuousConsumptionAcrossEveryDay() throws {
        let (repository, _) = try makeRepository()
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.creatine.name" }
        )
        let powder = try presentation(repository, key: "presentation.powder.name")
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Creatina continua",
            brand: "",
            presentationTypeID: powder.id,
            basisQuantity: 5,
            basisUnit: .gram,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 5, unit: .gram)
            ]
        ))
        let instance = try repository.createInstance(SupplementInstanceDraft(
            supplementID: supplement.id,
            totalQuantity: 100,
            totalUnit: .gram
        ))
        _ = try repository.createConsumption(ConsumptionDraft(
            instanceID: instance.id,
            quantity: 10,
            unit: .gram,
            consumedAt: try utcDate(2026, 7, 1, hour: 9),
            timeZoneID: "UTC"
        ))

        let result = try InventoryReconciliationService(repository: repository).reconcile(
            instanceID: instance.id,
            actualQuantity: 80,
            correctionNote: "Correction",
            now: try utcDate(2026, 7, 4, hour: 18),
            timeZone: try XCTUnwrap(TimeZone(identifier: "UTC"))
        )

        XCTAssertEqual(result.direction, .addedConsumption)
        XCTAssertEqual(result.adjustedConsumptionCount, 4)
        XCTAssertEqual(try repository.instance(id: instance.id)?.totalQuantity, 80)
        let corrected = try repository.fetchConsumptions(from: nil, through: nil, limit: nil)
            .filter { $0.instanceID == instance.id && $0.notes == "Correction" }
        XCTAssertEqual(corrected.count, 4)
        XCTAssertEqual(corrected.reduce(Decimal.zero) { $0 + $1.quantity }, 10)
        XCTAssertEqual(Set(corrected.map(\.localDay)).count, 4)

        let beforeReduction = Dictionary(
            grouping: try repository.fetchConsumptions(from: nil, through: nil, limit: nil)
                .filter { $0.instanceID == instance.id },
            by: \.localDay
        ).mapValues { $0.reduce(Decimal.zero) { $0 + $1.quantity } }
        let reduction = try InventoryReconciliationService(repository: repository).reconcile(
            instanceID: instance.id,
            actualQuantity: 85,
            now: try utcDate(2026, 7, 4, hour: 18),
            timeZone: try XCTUnwrap(TimeZone(identifier: "UTC"))
        )
        let afterReduction = Dictionary(
            grouping: try repository.fetchConsumptions(from: nil, through: nil, limit: nil)
                .filter { $0.instanceID == instance.id },
            by: \.localDay
        ).mapValues { $0.reduce(Decimal.zero) { $0 + $1.quantity } }
        XCTAssertEqual(reduction.direction, .removedConsumption)
        XCTAssertEqual(try repository.instance(id: instance.id)?.totalQuantity, 85)
        for (day, amountBefore) in beforeReduction {
            XCTAssertEqual(amountBefore - (afterReduction[day] ?? 0), Decimal(string: "1.25"))
        }
    }

    @MainActor
    func testReconciliationRemovesDiscreteConsumptionAtSpacedPoints() throws {
        let (repository, _) = try makeRepository()
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.magnesium.name" }
        )
        let capsule = try presentation(repository, key: "presentation.capsule.name")
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Magnesio discreto",
            brand: "",
            presentationTypeID: capsule.id,
            basisQuantity: 1,
            basisUnit: .capsule,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
            ]
        ))
        let instance = try repository.createInstance(SupplementInstanceDraft(
            supplementID: supplement.id,
            totalQuantity: 10,
            totalUnit: .capsule
        ))
        for day in [1, 3, 5] {
            _ = try repository.createConsumption(ConsumptionDraft(
                instanceID: instance.id,
                quantity: 1,
                unit: .capsule,
                consumedAt: try utcDate(2026, 7, day, hour: 9),
                timeZoneID: "UTC"
            ))
        }

        let result = try InventoryReconciliationService(repository: repository).reconcile(
            instanceID: instance.id,
            actualQuantity: 9,
            now: try utcDate(2026, 7, 5, hour: 18),
            timeZone: try XCTUnwrap(TimeZone(identifier: "UTC"))
        )

        XCTAssertEqual(result.direction, .removedConsumption)
        XCTAssertEqual(result.adjustedConsumptionCount, 2)
        XCTAssertEqual(try repository.instance(id: instance.id)?.totalQuantity, 9)
        let remaining = try repository.fetchConsumptions(from: nil, through: nil, limit: nil)
            .filter { $0.instanceID == instance.id }
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.quantity, 1)

        let addition = try InventoryReconciliationService(repository: repository).reconcile(
            instanceID: instance.id,
            actualQuantity: 6,
            correctionNote: "Correction",
            now: try utcDate(2026, 7, 5, hour: 18),
            timeZone: try XCTUnwrap(TimeZone(identifier: "UTC"))
        )
        let spacedCorrections = try repository.fetchConsumptions(from: nil, through: nil, limit: nil)
            .filter { $0.instanceID == instance.id && $0.notes == "Correction" }
        XCTAssertEqual(addition.direction, .addedConsumption)
        XCTAssertEqual(addition.adjustedConsumptionCount, 3)
        XCTAssertEqual(spacedCorrections.count, 3)
        XCTAssertEqual(Set(spacedCorrections.map(\.localDay)).count, 3)
        XCTAssertTrue(spacedCorrections.allSatisfy { $0.quantity == 1 })
        XCTAssertEqual(try repository.instance(id: instance.id)?.totalQuantity, 6)
    }

    @MainActor
    func testContinuousProductCardDoesNotShowCompositionReferenceAmounts() throws {
        let (repository, _) = try makeRepository()
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.creatine.name" }
        )
        let powder = try XCTUnwrap(
            repository.fetchPresentationTypes().first { $0.nameKey == "presentation.powder.name" }
        )
        _ = try repository.createSupplement(SupplementDraft(
            name: "Creatina en polvo",
            brand: "",
            presentationTypeID: powder.id,
            basisQuantity: 5,
            basisUnit: .gram,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 3, unit: .gram)
            ]
        ))

        let controller = SupplementsViewController(repository: repository)
        controller.loadViewIfNeeded()
        let table = try XCTUnwrap(descendant(of: UITableView.self, identifier: nil, in: controller.view))
        let cell = try XCTUnwrap(
            table.dataSource?.tableView(table, cellForRowAt: IndexPath(row: 0, section: 0))
        )

        XCTAssertTrue(cell.accessibilityLabel?.contains("Creatina en polvo") == true)
        XCTAssertFalse(cell.accessibilityLabel?.contains("3 g") == true)
        XCTAssertFalse(cell.accessibilityLabel?.contains("5 g") == true)
    }

    @MainActor
    func testTrendsShowsFavoriteConsumptionSummaryWithTargetColor() throws {
        let (repository, _) = try makeRepository()
        let today = LocalDay(containing: Date(), in: .current)
        let capsule = try presentation(repository, key: "presentation.capsule.name")

        func favorite(named name: String, capsules: Decimal) throws -> Active {
            let active = try repository.createActive(ActiveDraft(name: name, baseUnit: .milligram))
            _ = try repository.setActiveFavorite(id: active.id, isFavorite: true)
            _ = try repository.setTarget(
                activeID: active.id,
                lowerBound: 100,
                upperBound: 100,
                unit: .milligram,
                effectiveFrom: try today.adding(days: -29)
            )
            let supplement = try repository.createSupplement(SupplementDraft(
                name: "Producto \(name)",
                brand: "",
                presentationTypeID: capsule.id,
                basisQuantity: 1,
                basisUnit: .capsule,
                components: [
                    SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
                ]
            ))
            let instance = try repository.createInstance(SupplementInstanceDraft(
                supplementID: supplement.id,
                totalQuantity: 30,
                totalUnit: .capsule
            ))
            _ = try repository.createConsumption(ConsumptionDraft(
                instanceID: instance.id,
                quantity: capsules,
                unit: .capsule,
                consumedAt: Date(),
                timeZoneID: TimeZone.current.identifier
            ))
            return active
        }

        let below = try favorite(named: "Por debajo", capsules: 1)
        let within = try favorite(named: "En rango", capsules: 7)
        let above = try favorite(named: "Por encima", capsules: 9)

        let controller = TrendsViewController(repository: repository, activeID: below.id)
        controller.loadViewIfNeeded()
        let card = try XCTUnwrap(descendant(
            of: PremiumCardView.self,
            identifier: "trends.favorites.card",
            in: controller.view
        ))
        XCTAssertFalse(card.isHidden)

        func assertSevenDayColor(_ active: Active, _ color: UIColor) throws {
            let value = try XCTUnwrap(descendant(
                of: UILabel.self,
                identifier: "trends.favorites.\(active.id.uuidString).7d",
                in: controller.view
            ))
            XCTAssertEqual(
                value.textColor.resolvedColor(with: controller.traitCollection),
                color.resolvedColor(with: controller.traitCollection)
            )
        }

        try assertSevenDayColor(below, WellnarioPalette.yellow)
        try assertSevenDayColor(within, WellnarioPalette.success)
        try assertSevenDayColor(above, WellnarioPalette.danger)
    }

    func testEditingLegacyConsumptionAppliesMissingInventoryDeduction() throws {
        let (repository, _) = try makeRepository()
        let presentation = try presentation(repository, key: "presentation.capsule.name")
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.magnesium.name" }
        )
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Magnesio heredado",
            brand: "",
            presentationTypeID: presentation.id,
            basisQuantity: 1,
            basisUnit: .capsule,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
            ]
        ))
        let instance = try repository.createInstance(SupplementInstanceDraft(
            supplementID: supplement.id,
            totalQuantity: 30,
            totalUnit: .capsule
        ))
        let consumption = try repository.createConsumption(ConsumptionDraft(
            instanceID: instance.id,
            quantity: 1,
            unit: .capsule,
            consumedAt: try utcDate(2026, 7, 17, hour: 9),
            timeZoneID: "UTC"
        ))

        // Simulates a take created by the version that stored the history but
        // did not yet touch inventory.
        try repository.database.execute(
            """
            UPDATE consumptions SET inventory_applied = 0 WHERE id = ?;
            """,
            bindings: [.text(consumption.id.uuidString)]
        )
        try repository.database.execute(
            """
            UPDATE supplement_instances SET total_quantity = ? WHERE id = ?;
            """,
            bindings: [.text("30"), .text(instance.id.uuidString)]
        )

        _ = try repository.updateConsumption(
            id: consumption.id,
            with: ConsumptionDraft(
                instanceID: instance.id,
                quantity: 1,
                unit: .capsule,
                consumedAt: consumption.consumedAt,
                timeZoneID: "UTC",
                notes: "Conciliada"
            )
        )
        XCTAssertEqual(try repository.instance(id: instance.id)?.totalQuantity, 29)

        try repository.deleteConsumption(id: consumption.id)
        XCTAssertEqual(try repository.instance(id: instance.id)?.totalQuantity, 30)
    }

    func testUntrackedInventoryIsNotMarkedAsDeductedAndCanBeReconciledLater() throws {
        let (repository, _) = try makeRepository()
        let presentation = try presentation(repository, key: "presentation.capsule.name")
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.magnesium.name" }
        )
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Magnesio sin cantidad",
            brand: "",
            presentationTypeID: presentation.id,
            basisQuantity: 1,
            basisUnit: .capsule,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
            ]
        ))
        let instance = try repository.createInstance(SupplementInstanceDraft(
            supplementID: supplement.id
        ))
        let consumption = try repository.createConsumption(ConsumptionDraft(
            instanceID: instance.id,
            quantity: 1,
            unit: .capsule,
            consumedAt: try utcDate(2026, 7, 17, hour: 9),
            timeZoneID: "UTC"
        ))

        let unappliedRow = try XCTUnwrap(repository.database.query(
            "SELECT inventory_applied FROM consumptions WHERE id = ?;",
            bindings: [.text(consumption.id.uuidString)]
        ).first)
        XCTAssertEqual(try unappliedRow.integer("inventory_applied"), 0)

        _ = try repository.updateInstance(
            id: instance.id,
            with: SupplementInstanceDraft(
                supplementID: supplement.id,
                totalQuantity: 10,
                totalUnit: .capsule
            )
        )
        _ = try repository.updateConsumption(
            id: consumption.id,
            with: ConsumptionDraft(
                instanceID: instance.id,
                quantity: 1,
                unit: .capsule,
                consumedAt: consumption.consumedAt,
                timeZoneID: consumption.timeZoneID
            )
        )

        XCTAssertEqual(try repository.instance(id: instance.id)?.totalQuantity, 9)
        let appliedRow = try XCTUnwrap(repository.database.query(
            "SELECT inventory_applied FROM consumptions WHERE id = ?;",
            bindings: [.text(consumption.id.uuidString)]
        ).first)
        XCTAssertEqual(try appliedRow.integer("inventory_applied"), 1)
    }

    @MainActor
    func testOpenInstanceEditorRefreshesRemainingContentAfterIntake() throws {
        let (repository, _) = try makeRepository()
        let presentation = try presentation(repository, key: "presentation.capsule.name")
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.magnesium.name" }
        )
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Magnesio visible",
            brand: "",
            presentationTypeID: presentation.id,
            basisQuantity: 1,
            basisUnit: .capsule,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
            ]
        ))
        let instance = try repository.createInstance(SupplementInstanceDraft(
            supplementID: supplement.id,
            totalQuantity: 10,
            totalUnit: .capsule
        ))
        let controller = InstanceEditorViewController(repository: repository, instance: instance)
        controller.loadViewIfNeeded()
        let remainingField = try XCTUnwrap(descendant(
            of: UITextField.self,
            identifier: "instance.remaining_quantity",
            in: controller.view
        ))
        XCTAssertEqual(remainingField.text, "10")

        _ = try repository.createConsumption(ConsumptionDraft(
            instanceID: instance.id,
            quantity: 1,
            unit: .capsule,
            consumedAt: Date(),
            timeZoneID: TimeZone.current.identifier
        ))

        XCTAssertEqual(try repository.instance(id: instance.id)?.totalQuantity, 9)
        XCTAssertEqual(remainingField.text, "9")

        controller.performSave()
        XCTAssertEqual(try repository.instance(id: instance.id)?.totalQuantity, 9)
    }

    @MainActor
    func testFinishingIntakeDismissesPresentedNavigationSheet() async throws {
        let (repository, _) = try makeRepository()
        let presenter = UIViewController()
        let editor = IntakeEditorViewController(repository: repository)
        let navigationController = UINavigationController(rootViewController: editor)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        presenter.present(navigationController, animated: false)
        XCTAssertTrue(presenter.presentedViewController === navigationController)

        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        editor.finishSaving(message: "Guardada")

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(presenter.presentedViewController)
        window.isHidden = true
        window.rootViewController = nil
    }

    @MainActor
    func testSavingActiveTargetReturnsToPreviousScreen() throws {
        let (repository, _) = try makeRepository()
        let active = try repository.createActive(
            ActiveDraft(name: "Objetivo navegable", baseUnit: .milligram)
        )
        let root = UIViewController()
        let navigationController = UINavigationController(rootViewController: root)
        let detail = ActiveDetailViewController(repository: repository, activeID: active.id)
        navigationController.pushViewController(detail, animated: false)
        detail.loadViewIfNeeded()

        let amountField = try XCTUnwrap(descendant(
            of: UITextField.self,
            identifier: "active.detail.target.amount",
            in: detail.view
        ))
        let saveButton = try XCTUnwrap(descendant(
            of: UIButton.self,
            identifier: "active.detail.target.save",
            in: detail.view
        ))
        amountField.text = "26"

        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        saveButton.sendActions(for: .touchUpInside)

        XCTAssertTrue(navigationController.topViewController === root)
        let target = try XCTUnwrap(repository.active(id: active.id)?.currentTarget)
        XCTAssertEqual(target.lowerBound, 26)
        XCTAssertEqual(target.upperBound, 26)
        XCTAssertEqual(target.unit, .milligram)
    }

    @MainActor
    func testInstanceEditorCorrectsRemainingContentWithoutChangingConsumptionHistory() throws {
        let (repository, _) = try makeRepository()
        let presentation = try presentation(repository, key: "presentation.capsule.name")
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.magnesium.name" }
        )
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Magnesio",
            brand: "Wellnario",
            presentationTypeID: presentation.id,
            basisQuantity: 1,
            basisUnit: .capsule,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
            ]
        ))
        let instance = try repository.createInstance(SupplementInstanceDraft(
            supplementID: supplement.id,
            label: "Envase abierto",
            totalQuantity: 60,
            totalUnit: .capsule
        ))
        let consumption = try repository.createConsumption(ConsumptionDraft(
            instanceID: instance.id,
            quantity: 2,
            unit: .capsule,
            consumedAt: Date(),
            timeZoneID: TimeZone.current.identifier
        ))

        let controller = InstanceEditorViewController(repository: repository, instance: instance)
        controller.loadViewIfNeeded()
        let remainingField = try XCTUnwrap(descendant(
            of: UITextField.self,
            identifier: "instance.remaining_quantity",
            in: controller.view
        ))
        let labelField = try XCTUnwrap(descendant(
            of: UITextField.self,
            identifier: "instance.label",
            in: controller.view
        ))
        XCTAssertEqual(remainingField.text, "60")
        XCTAssertNotNil(descendant(
            of: UIButton.self,
            identifier: "instance.remaining_unit",
            in: controller.view
        ))

        remainingField.text = "0"
        labelField.text = ""
        controller.performSave()

        let corrected = try XCTUnwrap(repository.instance(id: instance.id))
        XCTAssertEqual(corrected.label, "")
        XCTAssertEqual(corrected.totalQuantity, 0)
        XCTAssertEqual(corrected.totalUnit, .capsule)
        XCTAssertEqual(corrected.initialQuantity, 60)
        XCTAssertEqual(corrected.initialUnit, .capsule)
        XCTAssertNotNil(try repository.consumption(id: consumption.id))
    }

    @MainActor
    func testContinuousMarqueeDetectsOverflowAndKeepsFullAccessibilityText() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let marquee = ContinuousMarqueeLabel()
        marquee.frame = CGRect(x: 0, y: 0, width: 90, height: 24)
        window.addSubview(marquee)
        marquee.text = "Etiqueta identificativa especialmente larga para este envase"
        marquee.isMarqueeEnabled = true
        marquee.layoutIfNeeded()

        XCTAssertTrue(marquee.isOverflowing)
        XCTAssertEqual(
            marquee.accessibilityLabel,
            "Etiqueta identificativa especialmente larga para este envase"
        )
        if WellnarioMotion.animationsEnabled {
            let visibleLabels = marquee.subviews.compactMap { $0 as? UILabel }.filter { !$0.isHidden }
            XCTAssertEqual(visibleLabels.count, 2)
            XCTAssertTrue(visibleLabels.allSatisfy { !($0.layer.animationKeys() ?? []).isEmpty })
        }

        marquee.text = "Abierto"
        marquee.layoutIfNeeded()
        XCTAssertFalse(marquee.isOverflowing)
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

    @MainActor
    func testInstanceEditorShowsProductPhotoWhenAvailable() throws {
        let (repository, _) = try makeRepository()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        }
        let photoReference = try SupplementPhotoStore.save(image, databaseURL: repository.databaseURL)
        let capsule = try presentation(repository, key: "presentation.capsule.name")
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.magnesium.name" }
        )
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Producto fotografiado",
            brand: "",
            imageReference: photoReference,
            presentationTypeID: capsule.id,
            basisQuantity: 1,
            basisUnit: .capsule,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
            ]
        ))
        let instance = try repository.createInstance(SupplementInstanceDraft(
            supplementID: supplement.id,
            totalQuantity: 30,
            totalUnit: .capsule
        ))

        let controller = InstanceEditorViewController(repository: repository, instance: instance)
        controller.loadViewIfNeeded()

        let photoView = try XCTUnwrap(descendant(
            of: UIImageView.self,
            identifier: "instance.product_photo",
            in: controller.view
        ))
        let genericArtwork = try XCTUnwrap(descendant(
            of: PresentationArtworkView.self,
            identifier: "instance.presentation_artwork",
            in: controller.view
        ))
        XCTAssertNotNil(photoView.image)
        XCTAssertFalse(photoView.isHidden)
        XCTAssertTrue(genericArtwork.isHidden)
    }

    @MainActor
    func testSupplementEditorShowsControlsToReplaceOrRemoveProductPhoto() throws {
        let (repository, _) = try makeRepository()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        }
        let photoReference = try SupplementPhotoStore.save(image, databaseURL: repository.databaseURL)
        let capsule = try presentation(repository, key: "presentation.capsule.name")
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.magnesium.name" }
        )
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Producto fotografiado",
            brand: "",
            imageReference: photoReference,
            presentationTypeID: capsule.id,
            basisQuantity: 1,
            basisUnit: .capsule,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
            ]
        ))

        let controller = SupplementEditorViewController(
            repository: repository,
            supplement: supplement
        )
        controller.loadViewIfNeeded()

        let photoPreview = try XCTUnwrap(descendant(
            of: UIImageView.self,
            identifier: "supplement.photo.preview",
            in: controller.view
        ))
        let choosePhoto = try XCTUnwrap(descendant(
            of: UIButton.self,
            identifier: "supplement.photo.choose",
            in: controller.view
        ))
        let removePhoto = try XCTUnwrap(descendant(
            of: UIButton.self,
            identifier: "supplement.photo.remove",
            in: controller.view
        ))
        XCTAssertNotNil(photoPreview.image)
        XCTAssertFalse(photoPreview.isHidden)
        XCTAssertFalse(removePhoto.isHidden)
        XCTAssertTrue(choosePhoto.isEnabled)
    }

    @MainActor
    func testIntakeInstanceMenuShowsProductPhotoThumbnail() throws {
        let (repository, _) = try makeRepository()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        }
        let photoReference = try SupplementPhotoStore.save(image, databaseURL: repository.databaseURL)
        let capsule = try presentation(repository, key: "presentation.capsule.name")
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.magnesium.name" }
        )
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Producto fotografiado",
            brand: "",
            imageReference: photoReference,
            presentationTypeID: capsule.id,
            basisQuantity: 1,
            basisUnit: .capsule,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
            ]
        ))
        _ = try repository.createInstance(SupplementInstanceDraft(
            supplementID: supplement.id,
            totalQuantity: 30,
            totalUnit: .capsule
        ))

        let controller = IntakeEditorViewController(repository: repository)
        controller.loadViewIfNeeded()

        let selector = try XCTUnwrap(descendant(
            of: UIButton.self,
            identifier: "intake.instance.selector",
            in: controller.view
        ))
        let action = try XCTUnwrap(selector.menu?.children.first as? UIAction)
        XCTAssertNotNil(action.image)
    }

    @MainActor
    func testManagedIntakesShowProductPhotoWhenAvailable() throws {
        let (repository, _) = try makeRepository()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 24)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        }
        let photoReference = try SupplementPhotoStore.save(image, databaseURL: repository.databaseURL)
        let capsule = try presentation(repository, key: "presentation.capsule.name")
        let active = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.magnesium.name" }
        )
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Producto fotografiado",
            brand: "",
            imageReference: photoReference,
            presentationTypeID: capsule.id,
            basisQuantity: 1,
            basisUnit: .capsule,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
            ]
        ))
        let instance = try repository.createInstance(SupplementInstanceDraft(
            supplementID: supplement.id,
            totalQuantity: 30,
            totalUnit: .capsule
        ))
        _ = try repository.createConsumption(ConsumptionDraft(
            instanceID: instance.id,
            quantity: 1,
            unit: .capsule,
            consumedAt: Date(),
            timeZoneID: TimeZone.current.identifier
        ))

        let controller = DiaryViewController(repository: repository, presentationMode: .manage)
        controller.loadViewIfNeeded()
        let table = try XCTUnwrap(descendant(of: UITableView.self, identifier: nil, in: controller.view))
        let cell = try XCTUnwrap(table.dataSource?.tableView(table, cellForRowAt: IndexPath(row: 0, section: 0)))
        let photoView = try XCTUnwrap(descendant(
            of: UIImageView.self,
            identifier: "diary.product_photo",
            in: cell
        ))
        XCTAssertNotNil(photoView.image)
        XCTAssertFalse(photoView.isHidden)
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

    func testDailyConsumptionIgnoresLeadingDaysBeforeFirstRecordedIntake() throws {
        let (repository, _) = try makeRepository()
        let active = try repository.createActive(
            ActiveDraft(name: "Leading zero active", baseUnit: .milligram)
        )
        let presentation = try presentation(repository, key: "presentation.capsule.name")
        let supplement = try repository.createSupplement(SupplementDraft(
            name: "Leading zero product",
            brand: "",
            presentationTypeID: presentation.id,
            basisQuantity: 1,
            basisUnit: .capsule,
            components: [
                SupplementComponentDraft(activeID: active.id, amount: 100, unit: .milligram)
            ]
        ))
        let instance = try repository.createInstance(
            SupplementInstanceDraft(supplementID: supplement.id)
        )
        let from = try LocalDay(year: 2026, month: 7, day: 1)
        let firstRecordedDay = try LocalDay(year: 2026, month: 7, day: 3)
        let through = try LocalDay(year: 2026, month: 7, day: 6)
        _ = try repository.createConsumption(ConsumptionDraft(
            instanceID: instance.id,
            quantity: 1,
            unit: .capsule,
            consumedAt: try utcDate(2026, 7, 3, hour: 9),
            timeZoneID: "UTC"
        ))
        _ = try repository.createConsumption(ConsumptionDraft(
            instanceID: instance.id,
            quantity: 2,
            unit: .capsule,
            consumedAt: try utcDate(2026, 7, 5, hour: 9),
            timeZoneID: "UTC"
        ))

        let series = try repository.dailyConsumption(
            activeID: active.id,
            from: from,
            through: through
        )

        XCTAssertEqual(series.points.map(\.amount), [0, 0, 100, 0, 200, 0])
        XCTAssertEqual(series.amountsFromFirstRecordedDay, [nil, nil, 100, 0, 200, 0])
        XCTAssertEqual(series.firstRecordedDay, firstRecordedDay)
        XCTAssertEqual(series.recordedDayCount, 4)
        XCTAssertEqual(series.total, 300)
        XCTAssertEqual(series.average, 75)
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

    func testDefaultReminderPlannerUsesTargetsAndDoesNotRestoreManuallyClearedReminders() throws {
        let (repository, _) = try makeRepository()
        let suiteName = "WellnarioDefaultReminderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SupplementProductReminderStore(defaults: defaults)
        let preferences = SupplementReminderSchedulePreferences(defaults: defaults)
        let calcium = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.calcium.name" }
        )
        let today = LocalDay(containing: Date(), in: .current)
        _ = try repository.setTarget(
            activeID: calcium.id,
            lowerBound: 1_000,
            upperBound: 1_000,
            unit: .milligram,
            effectiveFrom: today
        )
        let capsule = try presentation(repository, key: "presentation.capsule.name")
        let product = try repository.createSupplement(
            SupplementDraft(
                name: "Calcio objetivo",
                brand: "",
                presentationTypeID: capsule.id,
                basisQuantity: 1,
                basisUnit: .capsule,
                components: [
                    SupplementComponentDraft(
                        activeID: calcium.id,
                        amount: 500,
                        unit: .milligram
                    )
                ]
            )
        )
        let planner = SupplementDefaultReminderPlanner(
            schedulePreferences: preferences,
            store: store
        )

        XCTAssertEqual(try planner.seedMissing(in: repository), 1)
        XCTAssertEqual(
            store.reminders(for: product.id).map(\.timeMinutes),
            [preferences.minutes(for: .breakfast), preferences.minutes(for: .dinner)]
        )

        store.set([], for: product.id)
        XCTAssertTrue(store.hasConfiguration(for: product.id))
        XCTAssertEqual(try planner.seedMissing(in: repository), 0)
        XCTAssertTrue(store.reminders(for: product.id).isEmpty)

        let quercetin = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.quercetin.name" }
        )
        _ = try repository.setTarget(
            activeID: quercetin.id,
            lowerBound: 250,
            upperBound: 500,
            unit: .milligram,
            effectiveFrom: today
        )
        let quercetinProduct = try repository.createSupplement(
            SupplementDraft(
                name: "Quercetina objetivo",
                brand: "",
                presentationTypeID: capsule.id,
                basisQuantity: 1,
                basisUnit: .capsule,
                components: [
                    SupplementComponentDraft(
                        activeID: quercetin.id,
                        amount: 250,
                        unit: .milligram
                    )
                ]
            )
        )
        XCTAssertEqual(try planner.seedMissing(in: repository), 1)
        XCTAssertEqual(
            store.reminders(for: quercetinProduct.id).map(\.timeMinutes),
            [preferences.minutes(for: .breakfast)]
        )

        let sulforaphane = try XCTUnwrap(
            repository.fetchActives().first { $0.nameKey == "active.sulforaphane.name" }
        )
        _ = try repository.setTarget(
            activeID: sulforaphane.id,
            lowerBound: 5,
            upperBound: 5,
            unit: .milligram,
            effectiveFrom: today
        )
        let sulforaphaneProduct = try repository.createSupplement(
            SupplementDraft(
                name: "Sulforafano concentrado",
                brand: "",
                presentationTypeID: capsule.id,
                basisQuantity: 1,
                basisUnit: .capsule,
                components: [
                    SupplementComponentDraft(
                        activeID: sulforaphane.id,
                        amount: 85,
                        unit: .milligram
                    )
                ]
            )
        )
        store.set(
            [
                SupplementProductReminder(
                    supplementID: sulforaphaneProduct.id,
                    timeMinutes: preferences.minutes(for: .breakfast)
                )
            ],
            for: sulforaphaneProduct.id,
            marksUserConfiguration: false
        )

        XCTAssertEqual(try planner.seedMissing(in: repository), 1)
        let sulforaphaneReminders = store.reminders(for: sulforaphaneProduct.id)
        XCTAssertEqual(sulforaphaneReminders.count, 1)
        XCTAssertEqual(sulforaphaneReminders[0].recurrence, .everyDays)
        XCTAssertEqual(sulforaphaneReminders[0].intervalDays, 17)
        XCTAssertEqual(
            sulforaphaneReminders[0].timeMinutes,
            preferences.minutes(for: .breakfast)
        )
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

    @MainActor
    private func descendant<View: UIView>(
        of type: View.Type,
        identifier: String?,
        in root: UIView
    ) -> View? {
        if let root = root as? View,
           identifier == nil || root.accessibilityIdentifier == identifier {
            return root
        }
        for subview in root.subviews {
            if let result = descendant(of: type, identifier: identifier, in: subview) {
                return result
            }
        }
        return nil
    }

}
