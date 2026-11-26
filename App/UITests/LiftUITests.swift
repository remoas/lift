import XCTest

/// Smoke tests over the DEBUG fixtures (in-memory data, nothing real).
final class LiftUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ frame: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LiftFixture", frame]
        app.launch()
        return app
    }

    func testWorkoutHasFinishAndDiscardWithoutAlerts() {
        let app = launch("03-workout")
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 10))
        app.buttons["Workout options"].tap()
        XCTAssertTrue(app.buttons["Discard workout"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testFinishWithSetsLeftShowsBackToWorkout() {
        let app = launch("25-finish-sets-left")
        XCTAssertTrue(app.buttons["Back to workout"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "not logged, so")).firstMatch.exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testSaveAsRoutineFieldIsInline() {
        let app = launch("27-finish-save-routine")
        XCTAssertTrue(app.textFields["Routine name"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testTodayStartsPush() {
        let app = launch("01-today")
        XCTAssertTrue(app.buttons["Start Push"].waitForExistence(timeout: 10))
    }
}
