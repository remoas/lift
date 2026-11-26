import XCTest

/// Drives the shared-transition flows 2 and 3 (AC 61; flow 1 was dropped with the mini bar) while the CI script records
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
            args += ["-UIAnimationDragCoefficient", k, "-LiftSlowAnimations"]
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
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.45)).withOffset(CGVector(dx: 1, dy: 0))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45))
        start.press(forDuration: 0.01, thenDragTo: end)
    }

    /// (2) Exercise row with media → detail, swipe back; again with the back button.
    func testFlow2ExerciseRowToDetail() {
        let app = launch("01b-log-active")
        let row = app.buttons.matching(NSPredicate(format: "label == %@", "Barbell Bench Press")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        pause(3)
        row.tap()
        pause(3)
        edgeSwipeBack(app)
        pause(2)
        if !row.waitForExistence(timeout: 3) {
            // Record the attempt either way; fall back so the back-button half still runs.
            XCTContext.runActivity(named: "edge swipe did not pop; using Back") { _ in }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            pause(1.5)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        pause(3)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause(2)
    }

    /// Brings the current set fully on screen (QA quick-log 11: the logged set was off the tape).
    private func reveal(_ el: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !(el.isHittable && el.frame.maxY < app.frame.height * 0.72) {
            let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app
            list.swipeUp(velocity: .slow)
            pause(0.8)
        }
    }

    /// (3) A best from a logged set; a second best on the same exercise within
    /// 4 s replaces it in place; swipe-up dismiss; then a third best on the next
    /// exercise left untouched for the 4 s auto-dismiss.
    func testFlow3PRBanner() {
        let app = launch("rec-pr")
        let banner = app.descendants(matching: .any)["PR banner"].firstMatch
        let current = app.descendants(matching: .any)["current-set"].firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 15))
        reveal(current, in: app)
        pause(2)
        // 1) Bench set 3: 215 × 5, a best.
        current.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        pause(1.2)
        // 2) Bench set 4 (prefilled with what was just logged) + 5 lb: a second best, replaces in place.
        let next = app.descendants(matching: .any)["current-set"].firstMatch
        if next.waitForExistence(timeout: 3) {
            next.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
            let more = app.buttons["More weight"]
            if more.waitForExistence(timeout: 3) {
                more.tap()
                app.buttons["Log set"].firstMatch.tap()
            }
        }
        XCTAssertTrue(banner.waitForExistence(timeout: 3))
        pause(2)
        // 3) Swipe-up dismiss.
        let c = banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        c.press(forDuration: 0.05, thenDragTo: banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.5)), withVelocity: .slow, thenHoldForDuration: 0.05)
        pause(3)
        // 4) Next exercise's first set: a best, untouched until it auto-dismisses.
        let third = app.descendants(matching: .any)["current-set"].firstMatch
        if third.waitForExistence(timeout: 5) {
            reveal(third, in: app)
            third.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            _ = banner.waitForExistence(timeout: 8)
            pause(6)   // 4 s auto-dismiss plus the reverse morph, no touches
        }
    }
}
