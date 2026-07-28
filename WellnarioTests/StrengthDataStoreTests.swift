import Foundation
import XCTest
@testable import Wellnario

@MainActor
final class StrengthDataStoreTests: XCTestCase {
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

        var workout = store.workout(from: template, title: "Leg day")
        workout.exercises[0].sets[0].weight = 100
        workout.exercises[0].sets[0].repetitions = 8
        workout.exercises[0].sets[0].isWarmup = true
        workout.exercises[0].sets[0].isFailure = true
        workout.exercises[0].sets[0].isDropSet = true
        workout.exercises[0].sets[0].completedAt = Date()
        _ = try store.saveWorkout(workout)
        XCTAssertEqual(try store.workoutCount(), 1)

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
    }
}
