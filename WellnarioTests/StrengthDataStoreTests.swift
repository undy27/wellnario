import Foundation
import XCTest
@testable import Wellnario

@MainActor
final class StrengthDataStoreTests: XCTestCase {
    func testHidingAnExerciseRemovesItFromTheUserLibraryWithoutDeletingHistoryData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WellnarioHiddenExerciseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("strength.sqlite")

        let repository = try WellnarioRepository(databaseURL: databaseURL)
        let store = try StrengthDataStore(databaseURL: databaseURL, userID: repository.userID)
        let exerciseID = "Barbell_Squat"

        XCTAssertTrue(try store.fetchExercises().contains { $0.id == exerciseID })
        try store.hideExercise(id: exerciseID)
        XCTAssertFalse(try store.fetchExercises().contains { $0.id == exerciseID })
        XCTAssertNotNil(try store.exercise(id: exerciseID))

        let reloadedStore = try StrengthDataStore(databaseURL: databaseURL, userID: repository.userID)
        XCTAssertFalse(try reloadedStore.fetchExercises().contains { $0.id == exerciseID })
    }

    func testDeletingAPredefinedTemplateDoesNotRestoreItOnTheNextLaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WellnarioStrengthTemplateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("strength.sqlite")

        let repository = try WellnarioRepository(databaseURL: databaseURL)
        let store = try StrengthDataStore(databaseURL: databaseURL, userID: repository.userID)
        let fullBody = try XCTUnwrap(store.fetchTemplates().first { $0.nameKey == "strength.template.full_body" })
        try store.deleteTemplate(id: fullBody.id)

        let reloadedStore = try StrengthDataStore(databaseURL: databaseURL, userID: repository.userID)
        XCTAssertFalse(try reloadedStore.fetchTemplates().contains { $0.nameKey == "strength.template.full_body" })
    }

    func testCatalogSeedsTemplatesAndCompletedWorkout() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WellnarioStrengthTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("strength.sqlite")

        let repository = try WellnarioRepository(databaseURL: databaseURL)
        let store = try StrengthDataStore(databaseURL: databaseURL, userID: repository.userID)
        let exercises = try store.fetchExercises()
        XCTAssertEqual(exercises.count, 581)

        let squat = try XCTUnwrap(exercises.first { $0.id == "Barbell_Squat" })
        XCTAssertEqual(squat.nameEnglish, "Barbell Squat")
        XCTAssertEqual(squat.localizedName(language: .spanish), "Sentadilla con barra")
        XCTAssertEqual(squat.primaryMuscles, ["quadriceps"])
        XCTAssertFalse(squat.instructionsEnglish.isEmpty)
        XCTAssertTrue(exercises.allSatisfy { $0.nameSpanish != $0.nameEnglish })
        XCTAssertFalse(exercises.contains { $0.nameSpanish.hasPrefix("Con barra:") })

        XCTAssertTrue(try store.fetchFavoriteExerciseIDs().isEmpty)
        try store.setExerciseFavorite(id: squat.id, isFavorite: true)
        XCTAssertTrue(try store.fetchFavoriteExerciseIDs().contains(squat.id))
        try store.setExerciseFavorite(id: squat.id, isFavorite: false)
        XCTAssertFalse(try store.fetchFavoriteExerciseIDs().contains(squat.id))

        try store.setExerciseCustomName(id: squat.id, name: "Sentadilla trasera")
        XCTAssertEqual(
            try store.exercise(id: squat.id)?.localizedName(language: .english),
            "Sentadilla trasera"
        )
        try store.setExerciseCustomName(id: squat.id, name: nil)
        XCTAssertEqual(try store.exercise(id: squat.id)?.localizedName(language: .spanish), "Sentadilla con barra")

        let curl = try XCTUnwrap(exercises.first { $0.id == "Standing_One-Arm_Dumbbell_Curl_Over_Incline_Bench" })
        XCTAssertEqual(curl.nameSpanish, "Curl unilateral de pie con mancuerna sobre banco inclinado")

        let predefinedTemplates = try store.fetchTemplates()
        let fullBody = try XCTUnwrap(predefinedTemplates.first {
            $0.nameKey == "strength.template.full_body"
        })
        XCTAssertEqual(fullBody.exercises.count, 4)
        XCTAssertTrue(fullBody.exercises.allSatisfy { $0.sets.count == 3 })

        let templateExercise = StrengthWorkoutTemplateExercise(
            id: UUID(),
            exercise: squat,
            order: 0,
            defaultRestSeconds: 120,
            sets: [
                StrengthWorkoutSet(order: 1, repetitions: 8, restSeconds: 120),
                StrengthWorkoutSet(order: 2, repetitions: 8, restSeconds: 120),
                StrengthWorkoutSet(order: 3, repetitions: 8, restSeconds: 120)
            ]
        )
        let template = try store.saveTemplate(StrengthWorkoutTemplateDraft(
            name: "Leg day",
            exercises: [templateExercise]
        ))
        XCTAssertTrue(try store.fetchTemplates().contains(where: { $0.id == template.id }))
        XCTAssertEqual(template.exercises.first?.sets.count, 3)

        let updatedTemplate = try store.updateTemplate(
            id: template.id,
            draft: StrengthWorkoutTemplateDraft(name: "Updated leg day", exercises: [templateExercise])
        )
        XCTAssertEqual(updatedTemplate.name, "Updated leg day")

        var workout = store.workout(from: template, title: "Leg day")
        workout.exercises[0].sets[0].weight = 100
        workout.exercises[0].sets[0].repetitions = 8
        workout.exercises[0].sets[0].isWarmup = true
        workout.exercises[0].sets[0].isFailure = true
        workout.exercises[0].sets[0].isDropSet = true
        workout.exercises[0].sets[0].completedAt = Date()
        _ = try store.saveWorkout(workout)
        XCTAssertEqual(try store.workoutCount(), 1)
        XCTAssertEqual(try store.fetchWorkoutSummaries().first?.exerciseCount, 1)
        XCTAssertEqual(try store.fetchWorkoutSummaries().first?.totalVolume, 800)
        XCTAssertEqual(try store.fetchReport().sessionVolumes.count, 1)
        XCTAssertEqual(try store.fetchReport().exerciseVolumes.first?.value, 800)
        let previousSet = try XCTUnwrap(store.previousSet(exerciseID: squat.id, setOrder: 1))
        XCTAssertEqual(previousSet.weight, 100)
        XCTAssertEqual(previousSet.repetitions, 8)

        let persistedSets = try repository.database.query(
            """
            SELECT weight, repetitions, rest_seconds, is_warmup, is_failure, is_drop_set, completed_at
            FROM strength_workout_sets;
            """
        )
        let firstSet = try XCTUnwrap(persistedSets.first)
        XCTAssertEqual(try firstSet.string("weight"), "100")
        XCTAssertEqual(try firstSet.integer("repetitions"), 8)
        XCTAssertEqual(try firstSet.integer("rest_seconds"), 120)
        XCTAssertEqual(try firstSet.integer("is_warmup"), 1)
        XCTAssertEqual(try firstSet.integer("is_failure"), 1)
        XCTAssertEqual(try firstSet.integer("is_drop_set"), 1)
        XCTAssertNotNil(try firstSet.optionalDouble("completed_at"))

        var loadedWorkout = try store.fetchWorkout(id: workout.id)
        XCTAssertEqual(loadedWorkout.exercises.first?.exercise.id, squat.id)
        XCTAssertEqual(loadedWorkout.exercises.first?.sets.first?.weight, 100)
        loadedWorkout.exercises[0].sets[0].repetitions = 10
        _ = try store.updateWorkout(loadedWorkout)
        XCTAssertEqual(try store.fetchWorkoutSummaries().first?.totalVolume, 1000)

        let metric = try store.saveBodyMetric(StrengthBodyMetricDraft(
            name: "Body weight",
            value: 76.5,
            unit: "kg",
            measuredAt: Date()
        ))
        XCTAssertEqual(try store.fetchBodyMetrics().first?.id, metric.id)
        try store.deleteBodyMetric(id: metric.id)
        XCTAssertTrue(try store.fetchBodyMetrics().isEmpty)

        try store.deleteWorkout(id: workout.id)
        XCTAssertEqual(try store.workoutCount(), 0)
    }
}
