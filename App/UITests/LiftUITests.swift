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

/// Ben, build 1.0 (2): "I've removed an exercise but it keeps coming back."
/// Real RootView on a local on-disk store: add, log a set, remove, relaunch.
final class RemoveExerciseTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LiftTestStore", "remove-exercise"] + extra
        app.launch()
        return app
    }

    private func add(_ name: String, in app: XCUIApplication) {
        let add = app.buttons["Add exercise"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(name + "\n")   // Return adds the top result
        XCTAssertTrue(app.buttons["\(name) options"].waitForExistence(timeout: 5))
    }

    func testRemovedExerciseStaysGoneAfterRelaunch() {
        // 1) Add two exercises and log a bench set (real UI, on-disk store).
        var app = launch(["-LiftTestReset"])
        add("Barbell Bench Press", in: app)
        add("Barbell Full Squat", in: app)
        let current = app.descendants(matching: .any)["current-set"].firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        current.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        sleep(2)
        app.terminate()

        // 2) Remove bench through the app's Remove path (the row menu's action), toast and all.
        app = launch(["-LiftTestRemove", "Barbell Bench Press"])
        let bench = app.buttons["Barbell Bench Press options"]
        XCTAssertTrue(app.buttons["Barbell Full Squat options"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Barbell Bench Press removed"].waitForExistence(timeout: 5), "Remove ran")
        XCTAssertFalse(bench.exists, "gone right after Remove")
        sleep(7)   // past the 5 s Undo window: the bug restored it here
        XCTAssertFalse(bench.exists, "still gone after the Undo window")
        app.terminate()

        // 3) Relaunch: still gone, squat kept.
        app = launch([])
        XCTAssertTrue(app.buttons["Barbell Full Squat options"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Barbell Bench Press options"].exists, "the removed exercise stays gone after relaunch")
    }
}
