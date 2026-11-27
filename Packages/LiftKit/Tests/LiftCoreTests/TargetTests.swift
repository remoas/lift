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

    func testUnloadedBodyweightAlwaysAddsRep() {
        XCTAssertEqual(Target.next(lastSets: [t(0, 15)], repGoal: 10, step: 5, bodyweight: true), t(0, 16))
    }

    func testAddedLoadFollowsTheOrdinaryWeightRule() {
        // Below the goal: same added load × (reps + 1).
        XCTAssertEqual(Target.next(lastSets: [t(25, 8)], repGoal: 10, step: 5, bodyweight: true), t(25, 9))
        // At the goal: next plate step × (goal − 2). 25 lb × 10 at a goal of 10 → BW + 30 lb × 8.
        XCTAssertEqual(Target.next(lastSets: [t(25, 10)], repGoal: 10, step: 5, bodyweight: true), t(30, 8))
    }

    func testAssistanceDecreasesAfterAHit() {
        XCTAssertEqual(Target.next(lastSets: [t(40, 8)], repGoal: 10, step: 5, bodyweight: false, assisted: true), t(40, 9))
        XCTAssertEqual(Target.next(lastSets: [t(40, 10)], repGoal: 10, step: 5, bodyweight: false, assisted: true), t(35, 8))
        // Assistance that reaches 0 becomes unloaded Bodyweight (reps at goal − 2).
        XCTAssertEqual(Target.next(lastSets: [t(5, 10)], repGoal: 10, step: 5, bodyweight: false, assisted: true), t(0, 8))
        // From unloaded, the bodyweight rule applies: reps + 1.
        XCTAssertEqual(Target.next(lastSets: [t(0, 12)], repGoal: 10, step: 5, bodyweight: false, assisted: true), t(0, 13))
    }

    func testAssistedHitPrefersLessAssistance() {
        XCTAssertTrue(Target.isHit(weight: 40, reps: 8, target: t(40, 8), assisted: true))
        XCTAssertTrue(Target.isHit(weight: 35, reps: 8, target: t(40, 8), assisted: true))
        XCTAssertFalse(Target.isHit(weight: 45, reps: 8, target: t(40, 8), assisted: true))
        XCTAssertFalse(Target.isHit(weight: 40, reps: 7, target: t(40, 8), assisted: true))
    }

    func testTinyGoalNeverZeroReps() {
        XCTAssertEqual(Target.next(after: t(100, 3), repGoal: 2, step: 5, bodyweight: false), t(105, 1))
    }

    func testFirstTimeHasNoTarget() {
        XCTAssertNil(Target.next(lastSets: [], repGoal: 10, step: 5, bodyweight: false))
    }

    func testFirstSetPrefillsAtTarget() {
        let target = Target.next(lastSets: [t(180, 8), t(180, 7), t(180, 6)], repGoal: 10, step: 5, bodyweight: false)
        XCTAssertEqual(Target.prefill(justLogged: nil, target: target, lastTime: t(180, 8)), t(180, 9))
    }

    func testLaterSetsPrefillWithWhatWasJustLogged() {
        let target = t(180, 9)
        // Missed: logged 180 × 8, so the next set reads 180 × 8 (target line stays 180 × 9).
        XCTAssertEqual(Target.prefill(justLogged: t(180, 8), target: target), t(180, 8))
        // Beat it: logged 185 × 9, next set reads 185 × 9.
        XCTAssertEqual(Target.prefill(justLogged: t(185, 9), target: target), t(185, 9))
    }

    func testBodyweightFirstSetPrefillsTargetAndAMissStaysPut() {
        let last = t(0, 12)
        let target = Target.next(lastSets: [last], repGoal: 10, step: 5, bodyweight: true)
        XCTAssertEqual(target, t(0, 13))
        // Set 1: stepper is the target; Last: is last session (12).
        XCTAssertEqual(Target.prefill(justLogged: nil, target: target, lastTime: last), t(0, 13))
        // Later set after logging 10: stepper stays at 10, Beat stays 13.
        XCTAssertEqual(Target.prefill(justLogged: t(0, 10), target: target, lastTime: last), t(0, 10))
    }

    func testFirstTimeEverHasNoPrefill() {
        XCTAssertNil(Target.prefill(justLogged: nil, target: nil, lastTime: nil))
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
