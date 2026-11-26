import XCTest
@testable import LiftCore

final class LiveWorkoutTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func bench(last: [SetTarget] = [.init(weight: 185, reps: 8), .init(weight: 185, reps: 7)]) -> LiveExercise {
        LiveExercise(id: UUID(), name: "Bench Press", unit: .lb, repGoal: 10, restSeconds: 150, last: last, lastDate: t0)
    }

    func testTargetAndPrefillUseTheTargetRule() {
        let ex = bench()
        XCTAssertEqual(ex.target, SetTarget(weight: 185, reps: 9))
        XCTAssertEqual(ex.nextSet.weight, 185)
        XCTAssertEqual(ex.nextSet.reps, 9)
        let first = LiveExercise(id: UUID(), name: "New", unit: .kg)
        XCTAssertNil(first.target)
        XCTAssertEqual(first.prefill, SetTarget(weight: 0, reps: 10))
    }

    func testAtGoalStepsUp() {
        XCTAssertEqual(bench(last: [.init(weight: 100, reps: 10)]).target, SetTarget(weight: 105, reps: 8))
    }

    func testLogHitsTargetAndPrefillFollowsLastLogged() {
        var w = LiveWorkout(exercises: [bench()])
        let ex = w.exercises[0]
        LiveReducer.apply(.logSet(exerciseID: ex.id, set: LiveSet(weight: 185, unit: .lb, reps: 9)), to: &w, now: t0)
        XCTAssertTrue(w.exercises[0].targetHit)
        XCTAssertEqual(w.exercises[0].prefill, SetTarget(weight: 185, reps: 9))
        XCTAssertEqual(w.startedAt, t0, "clock starts at the first logged set")
        XCTAssertEqual(w.targetsBeaten.beaten, 1)
        XCTAssertEqual(w.targetsBeaten.of, 1)
    }

    func testLogIsIdempotentBySetID() {
        var w = LiveWorkout(exercises: [bench()])
        let set = LiveSet(weight: 185, unit: .lb, reps: 6)
        let cmd = LiveCommand.logSet(exerciseID: w.exercises[0].id, set: set)
        LiveReducer.apply(cmd, to: &w)
        LiveReducer.apply(cmd, to: &w)
        XCTAssertEqual(w.exercises[0].sets.count, 1)
        LiveReducer.apply(.unlogSet(setID: set.id), to: &w)
        XCTAssertTrue(w.exercises[0].doneSets.isEmpty)
    }

    func testAddExerciseOnceAndCurrentIndex() {
        var w = LiveWorkout()
        XCTAssertNil(w.currentIndex)
        let ex = bench()
        LiveReducer.apply(.addExercise(ex), to: &w)
        LiveReducer.apply(.addExercise(ex), to: &w)
        XCTAssertEqual(w.exercises.count, 1)
        XCTAssertEqual(w.currentIndex, 0)
    }

    func testFinishDropsUnloggedSets() {
        var ex = bench()
        ex.sets = [LiveSet(weight: 185, unit: .lb, reps: 9, isDone: true, doneAt: t0), LiveSet(weight: 185, unit: .lb, reps: 8)]
        var w = LiveWorkout(exercises: [ex, LiveExercise(id: UUID(), name: "Row", unit: .lb, sets: [LiveSet(weight: 100, unit: .lb, reps: 8)])])
        LiveReducer.apply(.finish(at: t0), to: &w)
        XCTAssertEqual(w.exercises.count, 1)
        XCTAssertEqual(w.exercises[0].sets.count, 1)
        XCTAssertEqual(w.endedAt, t0)
    }

    func testRebaseKeepsUnappliedWatchCommands() {
        let ex = bench()
        let server = LiveWorkout(workoutID: UUID(), exercises: [ex])
        let a = LiveEnvelope(workoutID: server.workoutID, command: .logSet(exerciseID: ex.id, set: LiveSet(weight: 185, unit: .lb, reps: 9)))
        let b = LiveEnvelope(workoutID: server.workoutID, command: .logSet(exerciseID: ex.id, set: LiveSet(weight: 185, unit: .lb, reps: 8)))
        var applied = server
        applied.applied = [a.id]
        LiveReducer.apply(a.command, to: &applied)
        let r = LiveReducer.rebase(applied, pending: [a, b])
        XCTAssertEqual(r.pending.map(\.id), [b.id])
        XCTAssertEqual(r.workout.exercises[0].doneSets.count, 2)
    }

    func testRebaseDropsCommandsForTheFinishedWorkoutFromView() {
        var server = LiveWorkout(workoutID: UUID(), exercises: [bench()])
        let finished = UUID()
        server.lastFinishedID = finished
        let old = LiveEnvelope(workoutID: finished, command: .setRest(exerciseID: server.exercises[0].id, seconds: 60))
        let r = LiveReducer.rebase(server, pending: [old])
        XCTAssertEqual(r.workout, server)
        XCTAssertEqual(r.pending.count, 1, "still delivered to the phone")
    }

    func testRebaseKeepsOfflineWatchWorkoutCommands() {
        let ex = bench()
        let server = LiveWorkout(workoutID: UUID(), exercises: [])
        let offline = LiveEnvelope(workoutID: UUID(), command: .addExercise(ex))
        XCTAssertEqual(LiveReducer.rebase(server, pending: [offline]).workout.exercises.map(\.id), [ex.id])
    }

    func testFinishedElsewhere() {
        let t = Date(timeIntervalSince1970: 5)
        var w = LiveWorkout()
        let mine = UUID()
        XCTAssertNil(w.finishedElsewhere(mine))
        w.lastFinishedID = mine
        w.lastFinishedAt = t
        XCTAssertEqual(w.finishedElsewhere(mine), t)
    }

    func testRememberIsBoundedAndUnique() {
        var ids: [UUID] = []
        let first = UUID()
        ids = LiveReducer.remember(first, in: ids)
        ids = LiveReducer.remember(first, in: ids)
        XCTAssertEqual(ids.count, 1)
        for _ in 0..<300 { ids = LiveReducer.remember(UUID(), in: ids, limit: 200) }
        XCTAssertEqual(ids.count, 200)
    }

    func testRoundTripsThroughJSON() {
        var w = LiveWorkout(exercises: [bench()], rest: RestState(seconds: 90, from: t0, exercise: "Bench Press", next: "185 × 9", origin: .watch))
        w.applied = [UUID()]
        let env = LiveEnvelope(workoutID: w.workoutID, sentAt: t0, command: .logSet(exerciseID: w.exercises[0].id, set: LiveSet(weight: 185, unit: .lb, reps: 9)))
        XCTAssertEqual(LiveCoding.decode(LiveWorkout.self, from: LiveCoding.encode(w)!), w)
        XCTAssertEqual(LiveCoding.decode(LiveEnvelope.self, from: LiveCoding.encode(env)!), env)
    }

    func testTextLines() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let line = BeatItText.last([.init(weight: 185, reps: 8), .init(weight: 185, reps: 7)], date: nil, calendar: cal)
        XCTAssertEqual(line, "Last · 185×8, 185×7")
        XCTAssertNil(BeatItText.last([], date: nil))
        XCTAssertEqual(BeatItText.number(.init(weight: 0, reps: 12), bodyweight: true), "12 reps")
        XCTAssertEqual(BeatItText.number(.init(weight: 102.5, reps: 8), bodyweight: false), "102.5 × 8")
    }
}

final class RestTimerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testCountdownAndAddThirty() {
        let r = RestState(seconds: 120, from: t0, origin: .phone)
        XCTAssertEqual(r.remaining(at: t0.addingTimeInterval(30)), 90)
        let more = r.adding(30, now: t0.addingTimeInterval(30))
        XCTAssertEqual(more.endsAt, t0.addingTimeInterval(150))
        XCTAssertFalse(more.isOver(at: t0.addingTimeInterval(149)))
        XCTAssertTrue(more.isOver(at: t0.addingTimeInterval(150)))
    }

    func testAddThirtyAfterRestEndedCountsFromNow() {
        let r = RestState(seconds: 60, from: t0, origin: .watch)
        let now = t0.addingTimeInterval(100)
        XCTAssertEqual(r.adding(30, now: now).endsAt, now.addingTimeInterval(30))
    }

    func testAlertBody() {
        XCTAssertEqual(RestState(seconds: 60, exercise: "Bench Press", next: "185 × 6", origin: .phone).alertBody, "Rest's up. Bench Press, 185 × 6.")
        XCTAssertEqual(RestState(seconds: 60, origin: .phone).alertBody, "Rest's up.")
    }

    func testPhoneOnlyGetsTheNotification() {
        let r = RestState(seconds: 90, from: t0, origin: .phone)
        let p = RestAlertPolicy.plan(rest: r, now: t0, watchSessionActive: false, watchReachable: false)
        XCTAssertEqual(p.phoneNotificationAt, t0.addingTimeInterval(90))
        XCTAssertNil(p.watchAlertAt)
    }

    func testActiveWatchAlertsAndPhoneStaysQuiet() {
        let r = RestState(seconds: 90, from: t0, origin: .phone)
        let p = RestAlertPolicy.plan(rest: r, now: t0, watchSessionActive: true, watchReachable: true)
        XCTAssertNil(p.phoneNotificationAt, "no duplicate buzz on the wrist")
        XCTAssertEqual(p.watchAlertAt, t0.addingTimeInterval(90))
    }

    func testUnreachableWatchFallsBackToThePhone() {
        let r = RestState(seconds: 90, from: t0, origin: .watch)
        let p = RestAlertPolicy.plan(rest: r, now: t0, watchSessionActive: true, watchReachable: false)
        XCTAssertEqual(p.phoneNotificationAt, r.endsAt)
        XCTAssertNil(p.watchAlertAt)
    }

    func testSkipOrAlmostOverSchedulesNothing() {
        XCTAssertEqual(RestAlertPolicy.plan(rest: nil, now: t0, watchSessionActive: false, watchReachable: false), .init())
        let r = RestState(seconds: 60, from: t0, origin: .phone)
        XCTAssertEqual(RestAlertPolicy.plan(rest: r, now: t0.addingTimeInterval(59.5), watchSessionActive: false, watchReachable: false), .init())
    }

    func testAddThirtyMovesTheScheduledAlert() {
        let r = RestState(seconds: 60, from: t0, origin: .phone).adding(30, now: t0.addingTimeInterval(10))
        XCTAssertEqual(RestAlertPolicy.plan(rest: r, now: t0.addingTimeInterval(10), watchSessionActive: false, watchReachable: false).phoneNotificationAt, t0.addingTimeInterval(90))
    }

    func testRestChoicesIncludeCustom() {
        XCTAssertEqual(RestChoices.all(including: 120), RestChoices.base)
        XCTAssertTrue(RestChoices.all(including: 100).contains(100))
    }

    func testHealthSavedExactlyOnce() {
        XCTAssertTrue(HealthOwnership.phoneShouldSave(healthEnabled: true, watchRanSession: false, watchSaveFailed: false, alreadySaved: false))
        XCTAssertFalse(HealthOwnership.phoneShouldSave(healthEnabled: true, watchRanSession: true, watchSaveFailed: false, alreadySaved: false))
        XCTAssertTrue(HealthOwnership.phoneShouldSave(healthEnabled: true, watchRanSession: true, watchSaveFailed: true, alreadySaved: false))
        XCTAssertFalse(HealthOwnership.phoneShouldSave(healthEnabled: true, watchRanSession: false, watchSaveFailed: false, alreadySaved: true))
        XCTAssertFalse(HealthOwnership.phoneShouldSave(healthEnabled: nil, watchRanSession: false, watchSaveFailed: false, alreadySaved: false))
    }
}
