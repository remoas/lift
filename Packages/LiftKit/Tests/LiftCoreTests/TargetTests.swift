import XCTest
@testable import LiftCore

final class TargetTests: XCTestCase {
    func t(_ w: Double, _ r: Int) -> SetTarget { SetTarget(weight: w, reps: r) }

    func testTopSetIsHeaviestThenMostReps() {
        XCTAssertEqual(Target.topSet([t(185, 8), t(185, 7), t(185, 6)]), t(185, 8))
        XCTAssertEqual(Target.topSet([t(135, 12), t(185, 5), t(185, 6), t(175, 9)]), t(185, 6))
        XCTAssertNil(Target.topSet([]))
    }

    func testBelowGoalAddsOneRep() {
        XCTAssertEqual(Target.next(lastSets: [t(185, 8), t(185, 7), t(185, 6)], repGoal: 10, step: 5, bodyweight: false), t(185, 9))
    }

    func testAtGoalAddsStepAndDropsToGoalMinusTwo() {
        XCTAssertEqual(Target.next(lastSets: [t(185, 10), t(185, 9)], repGoal: 10, step: 5, bodyweight: false), t(190, 8))
        XCTAssertEqual(Target.next(lastSets: [t(60, 12)], repGoal: 10, step: 2.5, bodyweight: false), t(62.5, 8))
    }

    func testBodyweightAlwaysAddsRep() {
        XCTAssertEqual(Target.next(lastSets: [t(0, 15)], repGoal: 10, step: 5, bodyweight: true), t(0, 16))
    }

    func testTinyGoalNeverZeroReps() {
        XCTAssertEqual(Target.next(after: t(100, 3), repGoal: 2, step: 5, bodyweight: false), t(105, 1))
    }

    func testFirstTimeHasNoTarget() {
        XCTAssertNil(Target.next(lastSets: [], repGoal: 10, step: 5, bodyweight: false))
    }

    func testHit() {
        XCTAssertTrue(Target.isHit(weight: 185, reps: 9, target: t(185, 9)))
        XCTAssertTrue(Target.isHit(weight: 190, reps: 10, target: t(185, 9)))
        XCTAssertFalse(Target.isHit(weight: 185, reps: 8, target: t(185, 9)))
        XCTAssertFalse(Target.isHit(weight: 180, reps: 12, target: t(185, 9)))
    }
}

/// AC 63: nothing logged means nothing saved and nothing in Health.
final class NothingLoggedTests: XCTestCase {
    func testNothingLoggedSavesNothing() {
        let w = UUID(), ex = UUID()
        let unlogged = LoggedSet(snapshot: SetSnapshot(workoutID: w, weight: 185, unit: .lb, reps: 8, date: Date()), exerciseID: ex, isDone: false)
        let plan = SessionPlan(workoutID: w, routineID: nil, blocks: [.init(exerciseID: ex, sets: [unlogged])])
        XCTAssertTrue(plan.isEmptyWhenFinalized)
        let record = WorkoutRecord(id: w, routineID: nil, startedAt: Date(), outcome: .finished, plan: plan)
        XCTAssertNil(Outcomes.healthPayload(for: record, healthEnabled: true))
    }
}
