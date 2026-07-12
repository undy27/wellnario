import XCTest

final class WellnarioSupplementFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateSupplementBatchAndIntake() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-data",
            "--language", "es",
            "--initial-tab", "supplements"
        ]
        app.launch()

        let addSupplement = app.buttons["supplements.add"]
        XCTAssertTrue(addSupplement.waitForExistence(timeout: 5))
        addSupplement.tap()
        XCTAssertTrue(app.descendants(matching: .any)["supplement.editor"].waitForExistence(timeout: 3))

        replaceText(in: app.textFields["supplement.name"], with: "Magnesio Codex")
        replaceText(in: app.textFields["supplement.brand"], with: "Well Labs")

        let componentAmount = app.textFields["supplement.component.amount"]
        reveal(componentAmount, in: app)
        replaceText(in: componentAmount, with: "200")

        let supplementSave = app.buttons["editor.save"]
        reveal(supplementSave, in: app)
        supplementSave.tap()
        XCTAssertTrue(app.staticTexts["Magnesio Codex"].waitForExistence(timeout: 5))

        app.buttons["Existencias"].tap()
        XCTAssertTrue(addSupplement.waitForExistence(timeout: 3))
        addSupplement.tap()
        XCTAssertTrue(app.descendants(matching: .any)["instance.editor"].waitForExistence(timeout: 3))

        replaceText(in: app.textFields["instance.label"], with: "Bote prueba")
        let instanceSave = app.buttons["editor.save"]
        reveal(instanceSave, in: app)
        instanceSave.tap()
        XCTAssertTrue(app.staticTexts["Bote prueba"].waitForExistence(timeout: 5))

        app.buttons["tab.tab.diary"].tap()
        let addIntake = app.buttons["diary.add"]
        XCTAssertTrue(addIntake.waitForExistence(timeout: 5))
        addIntake.tap()
        XCTAssertTrue(app.descendants(matching: .any)["intake.editor"].waitForExistence(timeout: 3))

        let intakeSave = app.buttons["editor.save"]
        reveal(intakeSave, in: app)
        intakeSave.tap()
        XCTAssertTrue(app.staticTexts["Magnesio Codex"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        XCTAssertTrue(element.isHittable)
        element.tap()
        element.typeText(text)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
