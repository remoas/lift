import XCTest
@testable import LiftCore

final class RestActivityTests: XCTestCase {
    func testLoadFollowsTheExerciseUnit() {
        XCTAssertEqual(RestActivityText.load(weight: 185, unit: .lb, reps: 9, bodyweight: false), "185 lb × 9")
        XCTAssertEqual(RestActivityText.load(weight: 80, unit: .kg, reps: 8, bodyweight: false), "80 kg × 8")
    }

    func testBodyweightReadsReps() {
        XCTAssertEqual(RestActivityText.load(weight: 0, unit: .lb, reps: 9, bodyweight: true), "9 reps")
        XCTAssertEqual(RestActivityText.load(weight: 25, unit: .lb, reps: 9, bodyweight: true), "BW + 25 lb × 9")
    }

    func testLadderDropsSetFirstThenCompacts() {
        XCTAssertEqual(RestActivityText.ladder(setNumber: 3, weight: 185, unit: .lb, reps: 9, bodyweight: false),
                       ["Set 3 · 185 lb × 9", "185 lb × 9", "185×9"])
        XCTAssertEqual(RestActivityText.ladder(setNumber: 3, weight: 0, unit: .lb, reps: 9, bodyweight: true),
                       ["Set 3 · 9 reps", "9 reps"])
        XCTAssertEqual(RestActivityText.ladder(setNumber: nil, weight: 185, unit: .lb, reps: 7, bodyweight: false),
                       ["185 lb × 7", "185×7"])
    }

    func testRestOverAndFallbackCopy() {
        XCTAssertEqual(RestActivityText.restOver(setNumber: 3), "Rest over · Set 3")
        XCTAssertEqual(RestActivityText.notificationBody(exercise: "Barbell Bench Press", next: "185 lb × 9"),
                       "Rest over. Barbell Bench Press, 185 lb × 9.")
    }

    func testOnlyThePhoneWinnerAlertsAndOnlyOffScreen() {
        XCTAssertEqual(RestActivityPolicy.atRestEnd(watchAlerts: true, appActive: false), .quiet)
        XCTAssertEqual(RestActivityPolicy.atRestEnd(watchAlerts: true, appActive: true), .quiet)
        XCTAssertEqual(RestActivityPolicy.atRestEnd(watchAlerts: false, appActive: true), .quiet)
        XCTAssertEqual(RestActivityPolicy.atRestEnd(watchAlerts: false, appActive: false), .alert)
    }

    func testStaleAndDismissal() {
        let end = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(RestActivityPolicy.staleDate(end: end).timeIntervalSince(end), 120)
        XCTAssertEqual(RestActivityPolicy.dismissAt(end: end).timeIntervalSince(end), 300)
    }
}
