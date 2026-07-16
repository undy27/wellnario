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
            "--appearance", "light",
            "--initial-tab", "supplements"
        ]
        app.launch()

        let addSupplement = app.buttons["supplements.add"]
        XCTAssertTrue(addSupplement.waitForExistence(timeout: 5))
        addSupplement.tap()
        XCTAssertTrue(app.descendants(matching: .any)["supplement.package.wizard.step1"].waitForExistence(timeout: 3))

        replaceText(in: app.textFields["supplement.package.name"], with: "Magnesio Codex")
        replaceText(in: app.textFields["supplement.package.brand"], with: "Well Labs")
        let currency = app.buttons["supplement.package.currency"]
        reveal(currency, in: app)
        currency.tap()
        let usd = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "(USD)")).firstMatch
        XCTAssertTrue(usd.waitForExistence(timeout: 3))
        usd.tap()
        XCTAssertEqual(currency.value as? String, "USD")
        let next = app.buttons["supplement.package.wizard.next"]
        reveal(next, in: app)
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["supplement.package.wizard.step2"].waitForExistence(timeout: 3))

        replaceText(in: app.textFields["supplement.package.total"], with: "60")
        reveal(next, in: app)
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["supplement.package.wizard.step3"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Composición por cápsula"].exists)

        let componentAmount = app.textFields["supplement.component.amount"]
        reveal(componentAmount, in: app)
        replaceText(in: componentAmount, with: "200")

        reveal(next, in: app)
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["supplement.package.wizard.step4"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["supplement.package.inventory.count"].label, "1")

        let supplementSave = app.buttons["supplement.package.wizard.create"]
        reveal(supplementSave, in: app)
        supplementSave.tap()
        XCTAssertTrue(app.staticTexts["Magnesio Codex"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["supplements.log_intake"].exists)

        app.staticTexts["Magnesio Codex"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Magnesio Codex"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Registrar toma"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Existencias"].tap()
        let inventoryIntake = app.buttons["supplements.log_intake"]
        XCTAssertTrue(inventoryIntake.waitForExistence(timeout: 3))
        inventoryIntake.tap()
        XCTAssertTrue(app.descendants(matching: .any)["intake.editor"].waitForExistence(timeout: 3))
        let freeInstanceSelector = app.buttons["intake.instance.selector"]
        XCTAssertTrue(freeInstanceSelector.waitForExistence(timeout: 3))
        XCTAssertTrue(freeInstanceSelector.isEnabled)
        app.navigationBars["Registrar toma"].buttons["Cancelar"].tap()

        let inventoryItem = app.staticTexts["Magnesio Codex"].firstMatch
        XCTAssertTrue(inventoryItem.waitForExistence(timeout: 5))
        inventoryItem.tap()
        XCTAssertTrue(app.descendants(matching: .any)["instance.editor"].waitForExistence(timeout: 3))

        let addIntake = app.buttons["instance.log_intake"]
        reveal(addIntake, in: app)
        addIntake.tap()
        XCTAssertTrue(app.descendants(matching: .any)["intake.editor"].waitForExistence(timeout: 3))
        let instanceSelector = app.buttons["intake.instance.selector"]
        XCTAssertTrue(instanceSelector.waitForExistence(timeout: 3))
        XCTAssertFalse(instanceSelector.isEnabled)
        XCTAssertTrue(
            (instanceSelector.value as? String)?.contains("Magnesio Codex") == true,
            "The selected inventory item was not preserved: \(String(describing: instanceSelector.value))"
        )

        let intakeSave = app.buttons["intake.save"]
        reveal(intakeSave, in: app)
        intakeSave.tap()
        XCTAssertTrue(app.descendants(matching: .any)["instance.editor"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCreateContinuousPackageWithoutInitialInventory() {
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
        replaceText(in: app.textFields["supplement.package.name"], with: "Creatina continua")

        let next = app.buttons["supplement.package.wizard.next"]
        reveal(next, in: app)
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["supplement.package.wizard.step2"].waitForExistence(timeout: 3))

        app.buttons["Peso o volumen"].tap()
        replaceText(in: app.textFields["supplement.package.total"], with: "500")
        reveal(next, in: app)
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["supplement.package.wizard.step3"].waitForExistence(timeout: 3))

        replaceText(in: app.textFields["supplement.package.basis"], with: "100")
        XCTAssertTrue(app.staticTexts["Composición por 100 g"].waitForExistence(timeout: 3))
        let componentAmount = app.textFields["supplement.component.amount"]
        reveal(componentAmount, in: app)
        replaceText(in: componentAmount, with: "3")

        reveal(next, in: app)
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["supplement.package.wizard.step4"].waitForExistence(timeout: 3))
        app.buttons["supplement.package.inventory.decrement"].tap()
        XCTAssertEqual(app.staticTexts["supplement.package.inventory.count"].label, "0")

        let create = app.buttons["supplement.package.wizard.create"]
        reveal(create, in: app)
        create.tap()
        XCTAssertTrue(app.staticTexts["Creatina continua"].waitForExistence(timeout: 5))

        app.buttons["Existencias"].tap()
        XCTAssertTrue(app.staticTexts["No hay existencias"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFavoriteFilterAndExactTargetFromActiveDetail() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-data",
            "--language", "es",
            "--initial-tab", "supplements"
        ]
        app.launch()

        XCTAssertFalse(app.buttons["supplements.trends"].exists)
        app.buttons["Activos"].tap()
        let trendsButton = app.buttons["supplements.trends"]
        XCTAssertTrue(trendsButton.waitForExistence(timeout: 3))
        trendsButton.tap()
        XCTAssertTrue(app.navigationBars["Tendencias"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trends.active.selector"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.segmentedControls["trends.reference.selector"].exists)
        XCTAssertTrue(app.segmentedControls["trends.period.selector"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["trends.chart"].exists)
        XCTAssertTrue(app.segmentedControls["trends.reference.selector"].buttons["Tendencia"].isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let favoritesFilter = app.buttons["actives.category.favorites"]
        XCTAssertTrue(favoritesFilter.waitForExistence(timeout: 5))
        favoritesFilter.tap()
        XCTAssertTrue(app.staticTexts["No hay activos favoritos"].waitForExistence(timeout: 3))

        app.buttons["actives.category.all"].tap()
        let magnesium = app.staticTexts["Magnesio"].firstMatch
        XCTAssertTrue(magnesium.waitForExistence(timeout: 5))
        let magnesiumCard = app.cells.containing(.staticText, identifier: "Magnesio").firstMatch
        XCTAssertTrue(magnesiumCard.waitForExistence(timeout: 3))
        XCTAssertTrue(
            magnesiumCard.label.contains("No marcado como favorito"),
            "Unexpected active card accessibility label: \(magnesiumCard.label)"
        )
        XCTAssertTrue(
            magnesiumCard.label.contains("Objetivo: NC"),
            "The compact unconfigured target was not shown: \(magnesiumCard.label)"
        )
        XCTAssertTrue(
            magnesiumCard.label.contains("Consumo de los últimos 7 días: 0 mg"),
            "Unexpected weekly consumption summary: \(magnesiumCard.label)"
        )
        XCTAssertTrue(
            magnesiumCard.images["active.weekly.chart"].exists,
            "The seven-day chart is missing from the active card"
        )
        magnesium.tap()

        let favoriteButton = app.buttons["active.detail.favorite"]
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 3))
        favoriteButton.tap()
        XCTAssertEqual(favoriteButton.label, "Favorito")

        let amount = app.textFields["active.detail.target.amount"]
        reveal(amount, in: app)
        let unit = app.buttons["active.detail.target.unit"]
        unit.tap()
        let grams = app.buttons["g"]
        XCTAssertTrue(grams.waitForExistence(timeout: 3))
        grams.tap()
        replaceText(in: amount, with: "1")

        let saveTarget = app.buttons["active.detail.target.save"]
        reveal(saveTarget, in: app)
        saveTarget.tap()
        let currentTarget = app.staticTexts["active.detail.target.current"]
        XCTAssertTrue(currentTarget.waitForExistence(timeout: 5))
        XCTAssertTrue(
            currentTarget.label.contains("1 g"),
            "Unexpected target summary: \(currentTarget.label)"
        )

        app.navigationBars.buttons.element(boundBy: 0).tap()
        favoritesFilter.tap()
        XCTAssertTrue(app.staticTexts["Magnesio"].firstMatch.waitForExistence(timeout: 5))
        let favoriteMagnesiumCard = app.cells
            .containing(.staticText, identifier: "Magnesio")
            .firstMatch
        XCTAssertTrue(favoriteMagnesiumCard.waitForExistence(timeout: 3))
        XCTAssertTrue(
            favoriteMagnesiumCard.label.contains("Marcado como favorito"),
            "Unexpected favorite card accessibility label: \(favoriteMagnesiumCard.label)"
        )
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
        for _ in 0..<6 where !isFullyVisible(element, in: app) {
            app.swipeUp()
        }
        XCTAssertTrue(isFullyVisible(element, in: app))
    }

    @MainActor
    private func isFullyVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let frame = element.frame
        return frame.minY >= app.frame.minY && frame.maxY <= app.frame.maxY - 8
    }
}
