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
        // Toolbar menus can refuse AX scroll-to-visible inside a cover; tap the point.
        let options = app.buttons["Workout options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Discard workout"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testFinishWithSetsLeftShowsBackToWorkout() {
        let app = launch("25-finish-sets-left")
        XCTAssertTrue(app.buttons["Back to workout"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "not logged, so")).firstMatch.exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    /// AC 62: launch lands on the Log, never setup.
    func testLaunchOpensLogWithAddExercise() {
        let app = launch("01-log-empty")
        XCTAssertTrue(app.buttons["Add exercise"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Log what you lift. Lift remembers it for next time."].exists)
        XCTAssertFalse(app.buttons["Finish"].exists)
    }

    /// AC 64/65: Last and Beat it lines; Finish is the primary once an exercise is in.
    func testActiveLogShowsLastAndTarget() {
        let app = launch("01b-log-active")
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Last · ")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).containing(NSPredicate(format: "label BEGINSWITH %@", "Beat it")).firstMatch.exists)
    }
}
