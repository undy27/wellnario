import Foundation
import XCTest
@testable import Wellnario

final class RepositoryTests: XCTestCase {
    func testSeedsAreBilingualIdempotentAndHaveIllustrationVariants() throws {
        let (repository, url) = try makeRepository()

        let firstActives = try repository.fetchActives()
        let firstPresentations = try repository.fetchPresentationTypes()
        XCTAssertGreaterThanOrEqual(firstActives.count, 10)
        XCTAssertGreaterThanOrEqual(firstPresentations.count, 8)
        XCTAssertTrue(firstPresentations.allSatisfy { $0.illustrations.count >= 3 })

        let vitaminC = try XCTUnwrap(firstActives.first { $0.nameKey == "active.vitamin_c.name" })
        XCTAssertEqual(vitaminC.localizedName(language: .spanish), "Vitamina C")
        XCTAssertEqual(vitaminC.localizedName(language: .english), "Vitamin C")

        let reopened = try WellnarioRepository(databaseURL: url)
        XCTAssertEqual(try reopened.fetchActives(includeArchived: true).count, firstActives.count)
        XCTAssertEqual(try reopened.fetchPresentationTypes().count, firstPresentations.count)
        XCTAssertEqual(
            try reopened.fetchPresentationTypes().flatMap(\.illustrations).count,
            firstPresentations.flatMap(\.illustrations).count
        )
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

        let diary = try repository.diary(from: from, through: through)
        XCTAssertEqual(diary.map(\.day), [
            try LocalDay(year: 2026, month: 7, day: 3),
            try LocalDay(year: 2026, month: 7, day: 1)
        ])
        let dashboard = try repository.dashboard(on: from, expiringWithinDays: 30)
        XCTAssertEqual(dashboard.consumptionCount, 1)
        XCTAssertEqual(dashboard.activeProgress.first(where: { $0.id == active.id })?.consumedAmount, 100)
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
