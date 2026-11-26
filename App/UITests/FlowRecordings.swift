import XCTest

/// Drives the three shared-transition flows (AC 61) while the CI script records
/// the simulator screen. Skipped unless LIFT_RECORD is set (TEST_RUNNER_LIFT_RECORD).
final class FlowRecordings: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIFT_RECORD"] != nil, "recording pass only")
    }

    private func launch(_ frame: String) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-LiftFixture", frame]
        if let k = ProcessInfo.processInfo.environment["LIFT_SLOW"] {
            // Same switch as Simulator › Slow Animations.
            args += ["-UIAnimationDragCoefficient", k]
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func pause(_ s: Double) {
        let slow = ProcessInfo.processInfo.environment["LIFT_SLOW"].flatMap(Double.init) ?? 1
        Thread.sleep(forTimeInterval: s * max(1, slow / 2))
    }

    private func edgeSwipeBack(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
    }

    /// (1) Start Push: Today → workout, Close to the mini bar, Resume from the bar.
    func testFlow1TodayToWorkout() {
        let app = launch("01-today")
        let start = app.buttons["Start Push"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        pause(1.5)
        start.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        pause(2)
        app.buttons["Close"].tap()
        let bar = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "in progress. Resume")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        pause(2)
        bar.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10))
        pause(2)
    }

    /// (2) Exercise row with media → detail, swipe back; again with the back button.
    func testFlow2ExerciseRowToDetail() {
        let app = launch("01-today")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Barbell Bench Press")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        pause(1.5)
        row.tap()
        pause(3)
        edgeSwipeBack(app)
        pause(2)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        pause(3)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause(2)
    }

    /// (3) PR from a logged set, swipe-up dismiss; a second PR, 4 s auto-dismiss.
    func testFlow3PRBanner() {
        let app = launch("rec-pr")
        let current = app.descendants(matching: .any)["current-set"].firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 15))
        pause(1.5)
        current.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let banner = app.descendants(matching: .any)["PR banner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        pause(1.8)
        let c = banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        c.press(forDuration: 0.05, thenDragTo: banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.5)), withVelocity: .slow, thenHoldForDuration: 0.05)
        pause(2)
        // Skip the rest timer the first tick started, then log the next PR.
        let next = app.descendants(matching: .any)["current-set"].firstMatch
        if next.waitForExistence(timeout: 5) {
            next.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            XCTAssertTrue(banner.waitForExistence(timeout: 5))
            pause(6)   // 4 s auto-dismiss plus the reverse morph
        }
    }
}
