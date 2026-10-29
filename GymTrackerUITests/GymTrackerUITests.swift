import XCTest

/// Drives the real app on the simulator through the flows the unit tests cannot reach: the
/// screens. The app launches with `--ui-testing`, which gives it an in-memory store holding the
/// demo history, so every test starts from the same place and touches no real data.
///
/// XCUITest's API is main-actor bound while the test target's default isolation is not, so each
/// test is marked `@MainActor` and launches the app itself instead of in `setUp`.
final class GymTrackerUITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    @MainActor
    private func tab(_ name: String) {
        let item = app.tabBars.buttons[name].exists ? app.tabBars.buttons[name] : app.buttons[name].firstMatch
        item.tap()
    }

    /// Lists only materialise the rows near the screen, so an element further down the form is
    /// not in the tree until the form is scrolled to it.
    @MainActor
    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<6 where !element.exists { app.swipeUp() }
        for _ in 0..<6 where !element.exists { app.swipeDown() }
        XCTAssertTrue(element.exists, "\(element) not found after scrolling")
    }

    // MARK: Workout

    @MainActor
    func testWeightButtonsStepByAPlateInPounds() {
        launch()
        app.buttons["Start workout"].firstMatch.tap()
        let weight = app.textFields["Weight in lb"].firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        let before = Double(weight.value as? String ?? "") ?? 0
        XCTAssertGreaterThan(before, 0, "the first set is prescribed a load")

        app.buttons["5 lb more"].firstMatch.tap()
        XCTAssertEqual(Double(weight.value as? String ?? ""), before + 5)
        app.buttons["5 lb less"].firstMatch.tap()
        app.buttons["5 lb less"].firstMatch.tap()
        XCTAssertEqual(Double(weight.value as? String ?? ""), before - 5, "a pound load stored in kilograms still steps both ways")
    }

    // MARK: Nutrition

    @MainActor
    func testTappingAPastWeighInBringsItsDayUpForCorrection() {
        launch()
        tab("Nutrition")
        let list = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All weigh-ins'")).firstMatch
        scrollTo(list)
        list.tap()
        // Newest first: the second row is yesterday's.
        let yesterday = app.buttons.matching(NSPredicate(format: "label CONTAINS ' lb'")).element(boundBy: 1)
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
        yesterday.tap()

        let field = app.textFields["Weight for Yesterday"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the tab shows yesterday, not today, after the pop")
        XCTAssertFalse((field.value as? String ?? "").isEmpty, "with the weigh-in in the field, ready to retype")
    }

    // MARK: Session editor

    @MainActor
    func testAnAddedSetSurvivesATabSwitchAndIsDroppedOnLeaving() {
        launch()
        tab("Progress")
        // The Last session card reads out its exercises and verdicts.
        let lastSession = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Held' OR label CONTAINS 'Progressed' OR label CONTAINS 'Missed'")).firstMatch
        XCTAssertTrue(lastSession.waitForExistence(timeout: 5))
        lastSession.tap()
        let addSet = app.buttons["Add set"].firstMatch
        XCTAssertTrue(addSet.waitForExistence(timeout: 5))
        // The list only materialises rows near the screen, so count the one thing that is new
        // and at the top: a set whose reps are still empty, under the first exercise.
        let emptySets = app.textFields.matching(NSPredicate(format: "label == 'Reps' AND NOT (value MATCHES '[0-9]+')"))
        XCTAssertEqual(emptySets.count, 0, "a finished session has reps on every set")
        addSet.tap()
        XCTAssertEqual(emptySets.count, 1)

        tab("Today")
        tab("Progress")
        XCTAssertTrue(addSet.waitForExistence(timeout: 5), "still in the editor")
        XCTAssertEqual(emptySets.count, 1, "a tab switch is not leaving: the empty set stays")

        app.navigationBars.buttons.element(boundBy: 0).tap()   // back
        XCTAssertTrue(lastSession.waitForExistence(timeout: 5))
        lastSession.tap()
        XCTAssertTrue(addSet.waitForExistence(timeout: 5))
        XCTAssertEqual(emptySets.count, 0, "leaving drops the set with no reps")
    }

    // MARK: Settings

    @MainActor
    func testProfileAgeIsTypedAndKept() {
        launch()
        tab("Settings")
        let age = app.textFields["Age in years"]
        scrollTo(age)
        age.tap()
        age.doubleTap()
        age.typeText(XCUIKeyboardKey.delete.rawValue)
        age.typeText("35")
        app.toolbars.buttons["Done"].tap()
        XCTAssertEqual(age.value as? String, "35")

        tab("Today")
        tab("Settings")
        scrollTo(age)
        XCTAssertEqual(age.value as? String, "35", "written through to settings")
    }

    @MainActor
    func testExportOpensTheShareSheet() {
        launch()
        tab("Settings")
        let export = app.buttons["Export to CSV"]
        scrollTo(export)
        export.tap()
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the share sheet with the CSV files")
    }
}
