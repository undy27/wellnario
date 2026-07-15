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
    func testSettingsCanReturnToToday() {
        let app = launch(language: "es", initialTab: "today")
        let settings = app.buttons["today.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 3))
        let back = app.buttons["settings.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()

        XCTAssertTrue(app.descendants(matching: .any)["today.root"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["settings.root"].exists)
    }

    @MainActor
    func testTodayFitnessAndMedicalReviewsShareTheLastSummaryRow() {
        let app = launch(language: "es", initialTab: "today")
        let fitness = app.descendants(matching: .any)["today.summary.fitness"]
        let reviews = app.descendants(matching: .any)["today.summary.reviews"]

        XCTAssertTrue(fitness.waitForExistence(timeout: 5))
        XCTAssertTrue(reviews.waitForExistence(timeout: 5))
        XCTAssertEqual(fitness.frame.width, reviews.frame.width, accuracy: 1)
        XCTAssertEqual(fitness.frame.minY, reviews.frame.minY, accuracy: 1)
        XCTAssertLessThan(fitness.frame.width, app.frame.width / 2)
    }

    @MainActor
    func testSettingsOpenFromSupplementsWithoutChangingSelectedTab() {
        let app = launch(language: "es", initialTab: "supplements")
        let supplementsTab = app.buttons["tab.tab.supplements"]
        XCTAssertTrue(supplementsTab.waitForExistence(timeout: 5))
        XCTAssertTrue(supplementsTab.isSelected)

        let settings = app.buttons["supplements.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 3))
        XCTAssertTrue(supplementsTab.isSelected)

        let back = app.buttons["settings.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["navigation.supplements"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(supplementsTab.isSelected)
    }

    @MainActor
    func testChangingAppearanceKeepsSettingsOpenAndPersistsSelection() {
        let app = launch(language: "es", initialTab: "fitness")
        let settings = app.buttons["fitness.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        let light = app.descendants(matching: .any)["settings.appearance.light"]
        XCTAssertTrue(light.waitForExistence(timeout: 3))
        for _ in 0..<3 where !light.isHittable { app.swipeUp() }
        XCTAssertTrue(light.isHittable)
        light.tap()

        XCTAssertTrue(app.descendants(matching: .any)["settings.root"].waitForExistence(timeout: 5))
        let rebuiltLight = app.descendants(matching: .any)["settings.appearance.light"]
        XCTAssertTrue(rebuiltLight.waitForExistence(timeout: 3))
        XCTAssertTrue(rebuiltLight.isSelected)
        XCTAssertTrue(app.buttons["tab.tab.fitness"].isSelected)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Configuración — modo claro"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testAppleHealthSetupShowsSourceSelectionSection() {
        let app = launch(language: "es", initialTab: "today")
        let settings = app.buttons["today.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        let appleHealth = app.descendants(matching: .any)["settings.integration.apple_health"]
        XCTAssertTrue(appleHealth.waitForExistence(timeout: 3))
        appleHealth.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["settings.integration.apple_health.detail"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.integration.apple_health.sources"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts["settings.integration.apple_health.sources.empty"]
                .waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testSleepTrendPeriodSelectorOffersAllRanges() {
        let app = launch(language: "es", initialTab: "sleep")
        let selector = app.segmentedControls["sleep.trend.period.selector"]
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        let metricSelector = app.segmentedControls["sleep.trend.metric.selector"]
        XCTAssertTrue(metricSelector.waitForExistence(timeout: 3))
        let referenceSelector = app.segmentedControls["sleep.trend.reference.selector"]
        XCTAssertTrue(referenceSelector.waitForExistence(timeout: 3))

        for title in ["7d", "30d", "6m", "Desde el principio"] {
            XCTAssertTrue(selector.buttons[title].exists, "Missing sleep trend period: \(title)")
        }
        for title in ["Calidad", "Duración", "REM", "Profundo", "Ligero"] {
            XCTAssertTrue(metricSelector.buttons[title].exists, "Missing sleep trend metric: \(title)")
        }
        for title in ["Media", "Tendencia"] {
            XCTAssertTrue(referenceSelector.buttons[title].exists, "Missing sleep reference line: \(title)")
        }

        let rem = metricSelector.buttons["REM"]
        for _ in 0..<4 where !rem.isHittable { app.swipeUp() }
        XCTAssertTrue(rem.isHittable)
        rem.tap()
        XCTAssertTrue(rem.isSelected)

        for title in ["30d", "6m", "Desde el principio"] {
            let period = selector.buttons[title]
            for _ in 0..<4 where !period.isHittable { app.swipeUp() }
            XCTAssertTrue(period.isHittable)
            period.tap()
            XCTAssertTrue(period.isSelected)
        }
    }

    @MainActor
    func testSleepCardsCanBeShownOrHiddenFromEditor() {
        let app = launch(language: "es", initialTab: "sleep")
        let editCards = app.buttons["sleep.cards.edit"]
        XCTAssertTrue(editCards.waitForExistence(timeout: 5))
        editCards.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["sleep.cards.editor.root"]
                .waitForExistence(timeout: 3)
        )
        let factorsSwitch = app.switches["sleep.cards.editor.visibility.factors"]
        XCTAssertTrue(factorsSwitch.waitForExistence(timeout: 3))
        if factorsSwitch.value as? String != "1" {
            factorsSwitch.tap()
            XCTAssertEqual(factorsSwitch.value as? String, "1")
        }
        factorsSwitch.tap()

        let done = app.buttons["sleep.cards.editor.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()

        XCTAssertTrue(app.descendants(matching: .any)["sleep.root"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["sleep.factor.summary"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["sleep.latest.card"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["sleep.trend.card"].exists)
    }

    @MainActor
    func testSleepTitleRemainsVisibleWhileContentScrolls() {
        let app = launch(language: "es", initialTab: "sleep")
        let navigationBar = app.navigationBars["Sueño"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        let title = navigationBar.staticTexts["Sueño"]
        XCTAssertTrue(title.exists)
        let initialFrame = title.frame

        app.swipeUp()

        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.frame.minY, initialFrame.minY, accuracy: 1)
        XCTAssertEqual(title.frame.height, initialFrame.height, accuracy: 1)
    }

    @MainActor
    func testHealthAndFitnessTitlesRemainVisibleWhileContentScrolls() {
        for (tab, titleText) in [("health", "Salud"), ("fitness", "Fitness")] {
            let app = launch(language: "es", initialTab: tab)
            let navigationBar = app.navigationBars[titleText]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
            let title = navigationBar.staticTexts[titleText]
            XCTAssertTrue(title.exists)
            let initialFrame = title.frame

            app.swipeUp()

            XCTAssertTrue(title.exists)
            XCTAssertEqual(title.frame.minY, initialFrame.minY, accuracy: 1)
            XCTAssertEqual(title.frame.height, initialFrame.height, accuracy: 1)
            app.terminate()
        }
    }

    @MainActor
    func testHealthAndFitnessCardEditorsAreReachable() {
        let cases = [
            (tab: "health", prefix: "health.cards", card: "biologicalAge"),
            (tab: "fitness", prefix: "fitness.cards", card: "weeklySummary")
        ]

        for item in cases {
            let app = launch(language: "es", initialTab: item.tab)
            let editCards = app.buttons["\(item.prefix).edit"]
            XCTAssertTrue(editCards.waitForExistence(timeout: 5))
            editCards.tap()

            XCTAssertTrue(
                app.descendants(matching: .any)["\(item.prefix).editor.root"]
                    .waitForExistence(timeout: 4)
            )
            XCTAssertTrue(
                app.switches["\(item.prefix).editor.visibility.\(item.card)"]
                    .waitForExistence(timeout: 3)
            )
            app.terminate()
        }
    }

    @MainActor
    func testMedicalReviewCanBeCreatedFromHealthCard() {
        let app = launch(language: "es", initialTab: "health")
        let medicalReviews = app.buttons["health.medical_reviews.open"]
        XCTAssertTrue(medicalReviews.waitForExistence(timeout: 5))
        for _ in 0..<5 where !medicalReviews.isHittable { app.swipeUp() }
        XCTAssertTrue(medicalReviews.isHittable)
        medicalReviews.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["health.medical_reviews.root"]
                .waitForExistence(timeout: 3)
        )
        let add = app.buttons["health.medical_reviews.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["health.medical_reviews.editor.root"]
                .waitForExistence(timeout: 3)
        )
        let name = app.textFields["health.medical_reviews.editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Dermatología")
        let cadence = app.buttons["health.medical_reviews.editor.cadence"]
        XCTAssertEqual(cadence.value as? String, "Cada año")
        cadence.tap()
        let sixMonths = app.buttons["Cada 6 meses"]
        XCTAssertTrue(sixMonths.waitForExistence(timeout: 3))
        sixMonths.tap()
        XCTAssertEqual(cadence.value as? String, "Cada 6 meses")

        let save = app.buttons["health.medical_reviews.editor.save"]
        for _ in 0..<4 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable)
        save.tap()

        XCTAssertTrue(app.staticTexts["Dermatología"].waitForExistence(timeout: 4))
        let selectedCadence = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Cada 6 meses")
        ).firstMatch
        XCTAssertTrue(selectedCadence.exists)

        let createdReview = app.staticTexts["Dermatología"]
        XCTAssertTrue(createdReview.isHittable)
        createdReview.tap()
        XCTAssertTrue(app.staticTexts["Historial"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["health.medical_reviews.history.row.0"]
                .exists
        )
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
            "--appearance", "dark",
            "--initial-tab", initialTab
        ]
        app.launch()
        return app
    }
}
