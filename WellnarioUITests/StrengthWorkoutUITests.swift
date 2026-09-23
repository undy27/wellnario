import XCTest

final class StrengthWorkoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFitnessOpensAStrengthWorkoutFromTheWorkoutsHubAndAddsAnExercise() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-data",
            "--language", "es",
            "--initial-tab", "fitness"
        ]
        app.launch()

        let strength = app.buttons["fitness.strength.start"]
        XCTAssertTrue(strength.waitForExistence(timeout: 5))
        strength.tap()
        XCTAssertTrue(app.descendants(matching: .any)["strength.start"].waitForExistence(timeout: 3))

        let workoutHub = app.descendants(matching: .any)["strength.hub.workouts"]
        XCTAssertTrue(workoutHub.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["strength.hub.exercises"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["strength.hub.templates"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["strength.hub.metrics"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["strength.hub.reports"].exists)
        workoutHub.tap()

        let newWorkout = app.buttons["strength.workouts.new"]
        XCTAssertTrue(newWorkout.waitForExistence(timeout: 3))
        newWorkout.tap()
        let emptyWorkout = app.buttons["Iniciar entrenamiento vacío"]
        XCTAssertTrue(emptyWorkout.waitForExistence(timeout: 3))
        emptyWorkout.tap()
        XCTAssertTrue(app.descendants(matching: .any)["strength.workout"].waitForExistence(timeout: 3))

        let addExercise = app.buttons["strength.workout.add_exercise"]
        XCTAssertTrue(addExercise.waitForExistence(timeout: 3))
        addExercise.tap()
        XCTAssertTrue(app.tables["strength.exercise.picker"].waitForExistence(timeout: 3))
        let equipmentFilter = app.buttons["strength.exercise.filter.equipment"]
        let primaryMuscleFilter = app.buttons["strength.exercise.filter.primary_muscle"]
        let favoritesFilter = app.buttons["strength.exercise.filter.favorites"]
        XCTAssertTrue(equipmentFilter.waitForExistence(timeout: 3))
        XCTAssertTrue(primaryMuscleFilter.exists)
        XCTAssertTrue(favoritesFilter.exists)

        equipmentFilter.tap()
        let barbell = app.buttons["Barra"]
        XCTAssertTrue(barbell.waitForExistence(timeout: 3))
        barbell.tap()

        primaryMuscleFilter.tap()
        let quadriceps = app.buttons["Cuádriceps"]
        XCTAssertTrue(quadriceps.waitForExistence(timeout: 3))
        quadriceps.tap()

        let squat = app.descendants(matching: .any)["strength.exercise.Barbell_Squat"]
        XCTAssertTrue(squat.waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["strength.exercise.Barbell_Bench_Press_-_Medium_Grip"].exists)
        let favoriteSquat = app.buttons["strength.exercise.favorite.Barbell_Squat"]
        XCTAssertTrue(favoriteSquat.exists)
        favoriteSquat.tap()
        favoritesFilter.tap()
        XCTAssertTrue(squat.waitForExistence(timeout: 3))
        squat.tap()
        let done = app.buttons["strength.exercise.picker.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        XCTAssertTrue(app.descendants(matching: .any)["strength.workout"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Sentadilla con barra"].waitForExistence(timeout: 3))
    }
}
