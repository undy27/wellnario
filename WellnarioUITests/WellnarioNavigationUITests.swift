import XCTest

final class WellnarioNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFiveDestinationsAndPremiumPlaceholderAreReachable() {
        let app = launch(language: "es", initialTab: "today")
        XCTAssertTrue(app.descendants(matching: .any)["wellnario.floatingTabBar"].waitForExistence(timeout: 5))

        let destinationIDs = [
            "tab.tab.supplements",
            "tab.tab.diary",
            "tab.tab.trends",
            "tab.tab.more"
        ]
        for identifier in destinationIDs {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing tab: \(identifier)")
            button.tap()
            XCTAssertTrue(button.isSelected)
        }

        XCTAssertTrue(app.descendants(matching: .any)["more.root"].waitForExistence(timeout: 3))
        let sleep = app.descendants(matching: .any)["more.feature.sleep"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 3))
        sleep.tap()
        XCTAssertTrue(app.descendants(matching: .any)["placeholder.sleep"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["placeholder.status"].exists)
    }

    @MainActor
    func testChangingLanguageRebuildsRootAndKeepsSettingsOpen() {
        let app = launch(language: "es", initialTab: "more")
        XCTAssertTrue(app.descendants(matching: .any)["more.root"].waitForExistence(timeout: 5))

        let settings = app.descendants(matching: .any)["more.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 3))

        let english = app.descendants(matching: .any)["settings.language.en"]
        XCTAssertTrue(english.waitForExistence(timeout: 3))
        english.tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 5))
        let moreTab = app.buttons["tab.tab.more"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 3))
        let localized = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "More"),
            object: moreTab
        )
        XCTAssertEqual(XCTWaiter.wait(for: [localized], timeout: 3), .completed)
        XCTAssertEqual(moreTab.label, "More")
        XCTAssertTrue(moreTab.isSelected)
        XCTAssertTrue(app.staticTexts["Settings"].firstMatch.exists)
    }

    @MainActor
    func testArchivedRecoveryCenterIsReachable() {
        let app = launch(language: "es", initialTab: "supplements")
        let more = app.buttons["supplements.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()

        let archived = app.buttons["Archivados"]
        XCTAssertTrue(archived.waitForExistence(timeout: 3))
        archived.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["supplements.archived.root"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.segmentedControls["archive.segments"].exists)
    }

    @discardableResult
    @MainActor
    private func launch(language: String, initialTab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-data",
            "--language", language,
            "--initial-tab", initialTab
        ]
        app.launch()
        return app
    }
}
