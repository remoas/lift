import XCTest
@testable import LiftCore

final class RestActivityTests: XCTestCase {
    func testLongNamesTruncateAtAWordBoundary() {
        let c = RestActivityText.nameCandidates("Single-Arm Dumbbell Incline Bench Press")
        XCTAssertEqual(c, ["Single-Arm Dumbbell Incline Bench Press", "Single-Arm Dumbbell Incline Bench…",
                           "Single-Arm Dumbbell Incline…", "Single-Arm Dumbbell…", "Single-Arm…"])
        XCTAssertFalse(c.contains { $0.hasSuffix("Ben…") })
        XCTAssertEqual(RestActivityText.nameCandidates("Squat"), ["Squat"])
    }

    func testLoadFollowsTheExerciseUnit() {
        XCTAssertEqual(RestActivityText.load(weight: 185, unit: .lb, reps: 9, bodyweight: false), "185 lb × 9")
        XCTAssertEqual(RestActivityText.load(weight: 80, unit: .kg, reps: 8, bodyweight: false), "80 kg × 8")
    }

    func testBodyweightReadsBodyweightWord() {
        XCTAssertEqual(RestActivityText.load(weight: 0, unit: .lb, reps: 9, bodyweight: true), "Bodyweight × 9")
        XCTAssertEqual(RestActivityText.load(weight: 25, unit: .lb, reps: 9, bodyweight: true), "BW + 25 lb × 9")
        XCTAssertEqual(RestActivityText.load(weight: 40, unit: .lb, reps: 8, kind: .assisted), "BW − 40 lb × 8")
    }

    func testLadderDropsSetFirstThenCompacts() {
        XCTAssertEqual(RestActivityText.ladder(setNumber: 3, weight: 185, unit: .lb, reps: 9, bodyweight: false),
                       ["Set 3 · 185 lb × 9", "185 lb × 9", "185×9"])
        XCTAssertEqual(RestActivityText.ladder(setNumber: 3, weight: 0, unit: .lb, reps: 9, bodyweight: true),
                       ["Set 3 · Bodyweight × 9", "Bodyweight × 9", "9 reps"])
        XCTAssertEqual(RestActivityText.ladder(setNumber: 3, weight: 25, unit: .lb, reps: 8, kind: .bodyweight),
                       ["Set 3 · BW + 25 lb × 8", "BW + 25 lb × 8", "BW+25×8"])
        XCTAssertEqual(RestActivityText.ladder(setNumber: nil, weight: 185, unit: .lb, reps: 7, bodyweight: false),
                       ["185 lb × 7", "185×7"])
    }

    func testLastLinePrefixesTheLoad() {
        XCTAssertEqual(RestActivityText.last("Bodyweight × 12"), "Last: Bodyweight × 12")
        XCTAssertEqual(RestActivityText.last("BW + 25 lb × 8"), "Last: BW + 25 lb × 8")
        XCTAssertEqual(RestActivityText.last("185 lb × 9"), "Last: 185 lb × 9")
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
