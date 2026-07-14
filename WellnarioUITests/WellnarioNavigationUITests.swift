import XCTest

final class WellnarioNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFiveWellnessDestinationsAreReachable() {
        let app = launch(language: "es", initialTab: "today")
        XCTAssertTrue(app.descendants(matching: .any)["wellnario.floatingTabBar"].waitForExistence(timeout: 5))

        let destinations = [
            ("tab.tab.supplements", "navigation.supplements"),
            ("tab.tab.sleep", "sleep.root"),
            ("tab.tab.health", "health.root"),
            ("tab.tab.fitness", "fitness.root")
        ]
        for (identifier, rootIdentifier) in destinations {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing tab: \(identifier)")
            button.tap()
            XCTAssertTrue(button.isSelected)
            XCTAssertTrue(app.descendants(matching: .any)[rootIdentifier].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testChangingLanguageRebuildsRootAndKeepsSettingsOpen() {
        let app = launch(language: "es", initialTab: "today")
        let settings = app.buttons["today.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["settings.integration.apple_health"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.integration.oura"].exists)

        let english = app.descendants(matching: .any)["settings.language.en"]
        XCTAssertTrue(english.waitForExistence(timeout: 3))
        for _ in 0..<4 where !english.isHittable { app.swipeUp() }
        XCTAssertTrue(english.isHittable)
        english.tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 5))
        let todayTab = app.buttons["tab.tab.today"]
        XCTAssertTrue(todayTab.waitForExistence(timeout: 3))
        let localized = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Today"),
            object: todayTab
        )
        XCTAssertEqual(XCTWaiter.wait(for: [localized], timeout: 3), .completed)
        XCTAssertEqual(todayTab.label, "Today")
        XCTAssertTrue(todayTab.isSelected)
        XCTAssertTrue(app.staticTexts["Settings"].firstMatch.exists)
    }

    @MainActor
    func testSleepTrendPeriodSelectorOffersAllRanges() {
        let app = launch(language: "es", initialTab: "sleep")
        let selector = app.segmentedControls["sleep.trend.period.selector"]
        XCTAssertTrue(selector.waitForExistence(timeout: 5))

        for title in ["7d", "30d", "6m", "Desde el principio"] {
            XCTAssertTrue(selector.buttons[title].exists, "Missing sleep trend period: \(title)")
        }

        let thirtyDays = selector.buttons["30d"]
        for _ in 0..<4 where !thirtyDays.isHittable { app.swipeUp() }
        XCTAssertTrue(thirtyDays.isHittable)
        thirtyDays.tap()
        XCTAssertTrue(thirtyDays.isSelected)
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

    @MainActor
    func testActiveDetailIsReachable() {
        let app = launch(language: "es", initialTab: "supplements")
        let actives = app.buttons["Activos"]
        XCTAssertTrue(actives.waitForExistence(timeout: 5))
        actives.tap()

        let vitaminC = app.staticTexts["Vitamina C"]
        XCTAssertTrue(vitaminC.waitForExistence(timeout: 3))
        vitaminC.tap()

        XCTAssertTrue(app.navigationBars["Vitamina C"].waitForExistence(timeout: 3))

        let trends = app.buttons["active.detail.trends"]
        XCTAssertTrue(trends.waitForExistence(timeout: 3))
        trends.tap()
        XCTAssertTrue(app.navigationBars["Tendencias"].waitForExistence(timeout: 3))

        let back = app.buttons["trends.back_to_active"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
        XCTAssertTrue(app.navigationBars["Vitamina C"].waitForExistence(timeout: 3))
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
