import XCTest
@testable import LiftCore

final class SessionPlanTests: XCTestCase {
    let bench = UUID(), ohp = UUID(), dips = UUID(), fly = UUID()
    let past = UUID(), today = UUID(), routine = UUID()
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func set(_ ex: UUID, _ w: Double, _ r: Int, workout: UUID, done: Bool = true, unit: WeightUnit = .lb, kind: SetKind = .working, offset: TimeInterval = 0) -> LoggedSet {
        LoggedSet(snapshot: SetSnapshot(workoutID: workout, weight: w, unit: unit, reps: r, kind: kind, date: t0.addingTimeInterval(offset)), exerciseID: ex, isDone: done)
    }

    var pastSets: [LoggedSet] {
        [set(bench, 185, 8, workout: past), set(bench, 185, 8, workout: past), set(ohp, 115, 9, workout: past)]
    }

    func plan() -> SessionPlan {
        SessionPlan(workoutID: today, routineID: routine, blocks: [
            .init(exerciseID: bench, sets: [set(bench, 185, 8, workout: today, done: false, offset: 100), set(bench, 185, 8, workout: today, done: false, offset: 101)]),
            .init(exerciseID: ohp, sets: [set(ohp, 115, 9, workout: today, done: false, offset: 102)]),
        ])
    }

    func testReorderMidWorkoutKeepsRecords() {
        var p = plan()
        let first = p.blocks[0].sets[0].id
        p.setDone(first, true, at: t0.addingTimeInterval(200))
        p.moveExercise(from: 0, to: 2) // OHP first, bench last
        XCTAssertEqual(p.blocks.map(\.exerciseID), [ohp, bench])
        XCTAssertTrue(p.doneSets.contains { $0.id == first })
        // Bench 205 x 5 is still a PR against bench history only.
        let heavy = set(bench, 205, 5, workout: today, done: true, offset: 300)
        p.addSet(heavy)
        XCTAssertEqual(PRBannerContent.top(p.newRecords(for: heavy.id, pastSets: pastSets)), .heaviestWeight)
        // Current set is now the first unticked in the new order (OHP).
        XCTAssertEqual(p.currentSetID, p.blocks[0].sets[0].id)
    }

    func testSwapKeepsLoggedSetsAndHistory() {
        var p = plan()
        let logged = p.blocks[0].sets[0].id
        let unlogged = p.blocks[0].sets[1].id
        p.setDone(logged, true, at: t0.addingTimeInterval(200))
        p.swapExercise(bench, for: dips, newSets: [set(dips, 0, 10, workout: today, done: false, unit: .lb)])
        XCTAssertEqual(p.blocks.map(\.exerciseID), [dips, ohp], "Swap takes the same slot")
        XCTAssertTrue(p.allSets.contains { $0.id == logged && $0.isDone }, "Logged bench set survives the swap")
        XCTAssertFalse(p.allSets.contains { $0.id == unlogged }, "Unlogged bench set is dropped")
        // Bench history still includes today's logged set, keyed by exercise.
        let benchHistory = History.sets(for: bench, in: pastSets + p.doneSets)
        XCTAssertEqual(benchHistory.count, 3)
        // Dips start fresh: no fake PR from bench numbers.
        let d = p.blocks[0].sets[0].id
        p.setDone(d, true, at: t0.addingTimeInterval(300))
        XCTAssertEqual(p.newRecords(for: d, pastSets: pastSets), [])
    }

    func testSwapBackToSameExerciseMerges() {
        var p = plan()
        let logged = p.blocks[0].sets[0].id
        p.setDone(logged, true, at: t0)
        p.swapExercise(bench, for: fly, newSets: [])
        p.swapExercise(fly, for: bench, newSets: [set(bench, 185, 8, workout: today, done: false)])
        XCTAssertEqual(p.allSets.filter { $0.exerciseID == bench && $0.isDone }.count, 1)
    }

    func testRemoveAndUndoRestoresSetsAndRecords() {
        var p = plan()
        let a = p.blocks[0].sets[0].id
        p.setDone(a, true, at: t0.addingTimeInterval(200))
        let removed = p.removeExercise(bench)
        XCTAssertNotNil(removed)
        XCTAssertFalse(p.allSets.contains { $0.id == a })
        XCTAssertEqual(History.sets(for: bench, in: pastSets + p.doneSets).count, 2)
        p.restore(removed!)
        XCTAssertEqual(p.blocks.map(\.exerciseID), [bench, ohp])
        XCTAssertTrue(p.doneSets.contains { $0.id == a })
    }

    func testRemovedSetNoLongerBlocksLaterPR() {
        var p = plan()
        let heavy = set(bench, 225, 5, workout: today, done: true, offset: 150)
        p.addSet(heavy)
        let next = set(bench, 205, 5, workout: today, done: true, offset: 250)
        p.addSet(next)
        XCTAssertFalse(p.newRecords(for: next.id, pastSets: pastSets).contains(.heaviestWeight))
        p.removeSet(heavy.id)
        XCTAssertTrue(p.newRecords(for: next.id, pastSets: pastSets).contains(.heaviestWeight))
    }

    func testAddExerciseAndSetsToBlankWorkout() {
        var p = SessionPlan(workoutID: today, routineID: nil)
        p.addExercise(fly, sets: [set(fly, 30, 12, workout: today, done: false)])
        p.addSet(set(fly, 30, 12, workout: today, done: false))
        XCTAssertEqual(p.blocks.count, 1)
        XCTAssertEqual(p.blocks[0].sets.count, 2)
        XCTAssertNil(p.rotationRoutineID, "A blank workout never advances the rotation")
    }

    func testUnitSwitchMidWorkoutNoPR() {
        // AC 9: log 100 kg, switch to lb, log 220 lb -> no PR.
        let w1 = UUID()
        let base = [set(bench, 100, 5, workout: w1, unit: .kg)]
        var p = SessionPlan(workoutID: today, routineID: routine)
        let lb = set(bench, 220, 5, workout: today, done: true, unit: .lb)
        p.addSet(lb)
        XCTAssertEqual(p.newRecords(for: lb.id, pastSets: base), [])
    }


    func testE1RMSeriesBestPerWorkout() {
        let all = pastSets + [set(bench, 205, 5, workout: today, offset: 10), set(bench, 185, 8, workout: today, offset: 11)]
        let series = History.e1RMSeries(for: bench, in: all)
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series.last!.set.weight, 205)
    }
}

final class PresentationTests: XCTestCase {
    func testBannerPriorityAndCopy() {
        XCTAssertEqual(PRBannerContent.top([.bestVolume, .mostReps, .bestE1RM, .heaviestWeight]), .heaviestWeight)
        XCTAssertEqual(PRBannerContent.top([.bestVolume, .mostReps]), .mostReps)
        let w = UUID()
        let hist = [SetSnapshot(workoutID: w, weight: 200, unit: .lb, reps: 5, date: Date())]
        let set = SetSnapshot(workoutID: UUID(), weight: 205, unit: .lb, reps: 5, date: Date())
        let b = PRBannerContent.make(kinds: [.heaviestWeight, .bestE1RM], exercise: "Bench Press", set: set, history: hist, unit: .lb)!
        XCTAssertEqual(b.headline, "205 lb × 5")
        XCTAssertEqual(b.why, "Heaviest yet, up 5 lb from 200. Estimated max is now 239 lb.")
        XCTAssertEqual(b.accessibility, "New best, Bench Press, 205 pounds by 5")
    }

    func testPlateLine() {
        XCTAssertEqual(WeightText.plateLine(target: 190, plates: .standardLb), "45 bar, then 45 + 25 + 2.5 a side")
        XCTAssertEqual(WeightText.plateLine(target: 187, plates: .standardLb), "Closest you can load: 185")
        XCTAssertEqual(WeightText.plateLine(target: 45, plates: .standardLb), "Just the bar (45)")
    }

    func testRestCountdown() {
        let now = Date(timeIntervalSince1970: 0)
        var r = RestCountdown(seconds: 120, from: now)
        XCTAssertEqual(r.progress(at: now.addingTimeInterval(60)), 0.5, accuracy: 0.001)
        r.adjust(by: 15, now: now)
        XCTAssertEqual(r.remaining(at: now), 135)
        r.adjust(by: -300, now: now)
        XCTAssertEqual(r.remaining(at: now), 0)
        XCTAssertEqual(RestCountdown.format(102), "1:42")
    }

    func testWeekCountMondayStart() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Atlantic/Bermuda")!
        let f = ISO8601DateFormatter()
        let thu = f.date(from: "2026-11-26T12:00:00-04:00")!
        let mon = f.date(from: "2026-11-23T08:00:00-04:00")!
        let sun = f.date(from: "2026-11-22T20:00:00-04:00")!
        XCTAssertEqual(Week.count([mon, sun, thu], inWeekOf: thu, calendar: cal), 2)
        XCTAssertEqual(Week.ordinal(3), "third")
    }

    func testSetRowAccessibility() {
        let m = SetRowModel(id: UUID(), number: 3, kind: .working, lastTime: "185 × 7", weightText: "185", unit: .lb, reps: 7, secondary: nil, state: .current)
        XCTAssertEqual(m.accessibilityLabel, "Set 3, last time 185 by 7, today 185 pounds by 7. Not done.")
    }

    func testExerciseDetailLedeNamesEstimatedMax() {
        XCTAssertEqual(ExerciseDetailLede.text(workoutCount: 0, loadKind: .loaded), "Not logged yet.")
        XCTAssertEqual(ExerciseDetailLede.text(workoutCount: 1, loadKind: .loaded),
                       "You've logged this once. Next time, you'll have a number to beat.")
        XCTAssertEqual(ExerciseDetailLede.text(workoutCount: 4, loadKind: .bodyweight), "Logged 4 times.")
        XCTAssertEqual(ExerciseDetailLede.text(workoutCount: 4, loadKind: .loaded, latestText: "240 lb", holdingForThree: true),
                       "Estimated max holding at 240 lb for 3 sessions.")
        XCTAssertEqual(ExerciseDetailLede.text(workoutCount: 4, loadKind: .loaded, latestText: "228 lb", delta: 13, since: "November"),
                       "Your estimated max is 228 lb, up 13 since November.")
        XCTAssertEqual(ExerciseDetailLede.text(workoutCount: 4, loadKind: .loaded, latestText: "210 lb", delta: -8, since: "September"),
                       "Your estimated max is 210 lb, down 8 since September.")
        XCTAssertEqual(ExerciseDetailLede.text(workoutCount: 2, loadKind: .loaded, latestText: "228 lb"),
                       "Your estimated max is 228 lb.")
        for copy in [
            ExerciseDetailLede.text(workoutCount: 4, loadKind: .loaded, latestText: "240 lb", holdingForThree: true),
            ExerciseDetailLede.text(workoutCount: 4, loadKind: .loaded, latestText: "228 lb", delta: 13, since: "November"),
            ExerciseDetailLede.text(workoutCount: 4, loadKind: .loaded, latestText: "210 lb", delta: -8, since: "September"),
            ExerciseDetailLede.text(workoutCount: 2, loadKind: .loaded, latestText: "228 lb"),
        ] {
            XCTAssertTrue(copy?.localizedCaseInsensitiveContains("estimated max") == true, copy ?? "nil")
        }
    }

}

final class ExerciseKeyedTests: XCTestCase {
    /// AC 33: Bench in a blank workout beats the Push best -> banner, and
    /// Push's next prefill uses it.
    func testBlankWorkoutSharesHistoryWithRoutine() {
        let bench = UUID(), pushWorkout = UUID(), blank = UUID(), t = Date(timeIntervalSince1970: 0)
        let pushSets = [
            LoggedSet(snapshot: SetSnapshot(workoutID: pushWorkout, weight: 185, unit: .lb, reps: 8, date: t), exerciseID: bench, isDone: true),
            LoggedSet(snapshot: SetSnapshot(workoutID: pushWorkout, weight: 185, unit: .lb, reps: 8, date: t.addingTimeInterval(60)), exerciseID: bench, isDone: true),
        ]
        var plan = SessionPlan(workoutID: blank, routineID: nil)
        let heavy = LoggedSet(snapshot: SetSnapshot(workoutID: blank, weight: 205, unit: .lb, reps: 5, date: t.addingTimeInterval(86_400)), exerciseID: bench, isDone: true)
        plan.addSet(heavy)
        let kinds = plan.newRecords(for: heavy.id, pastSets: pushSets)
        XCTAssertEqual(PRBannerContent.top(kinds), .heaviestWeight)
        let last = History.lastSession(for: bench, in: pushSets + plan.doneSets)
        XCTAssertEqual(last.map(\.snapshot.weight), [205])
        XCTAssertNil(plan.rotationRoutineID)
    }
}


final class LifecycleTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 2_000_000)

    func testDiscardCommitsOnlyAfterWindow() {
        var w = UndoWindow<UUID>()
        let workout = UUID()
        XCTAssertNil(w.begin(workout, at: t0))
        XCTAssertTrue(w.isPending(workout))
        XCTAssertNil(w.expire(at: t0.addingTimeInterval(4.9)), "Still undoable at 4.9 s")
        XCTAssertEqual(w.expire(at: t0.addingTimeInterval(5.1)), workout, "Deleted after 5 s")
        XCTAssertFalse(w.isPending(workout))
        XCTAssertNil(w.expire(at: t0.addingTimeInterval(10)), "Committed once only")
    }

    func testUndoRestoresAndNeverCommits() {
        var w = UndoWindow<UUID>()
        let workout = UUID()
        w.begin(workout, at: t0)
        XCTAssertTrue(w.undo(workout, at: t0.addingTimeInterval(3)))
        XCTAssertNil(w.expire(at: t0.addingTimeInterval(6)))
        XCTAssertFalse(w.undo(workout, at: t0.addingTimeInterval(7)), "Nothing left to undo")
    }

    func testUndoTooLateFails() {
        var w = UndoWindow<UUID>()
        let workout = UUID()
        w.begin(workout, at: t0)
        XCTAssertFalse(w.undo(workout, at: t0.addingTimeInterval(5.5)))
    }

    func testNewActionCommitsThePreviousOne() {
        var w = UndoWindow<UUID>()
        let a = UUID(), b = UUID()
        w.begin(a, at: t0)
        XCTAssertEqual(w.begin(b, at: t0.addingTimeInterval(1)), a)
        XCTAssertFalse(w.undo(a, at: t0.addingTimeInterval(2)))
        XCTAssertTrue(w.undo(b, at: t0.addingTimeInterval(2)))
    }

    func testFlushCommitsImmediately() {
        var w = UndoWindow<UUID>()
        let a = UUID()
        w.begin(a, at: t0)
        XCTAssertEqual(w.flush(), a)
        XCTAssertNil(w.flush())
    }

    func testRestDefaultFillsOnlyExercisesWithoutRest() {
        let bench = UUID(), curl = UUID(), fly = UUID()
        let fills = RestDefaults.fill([bench: 180, curl: nil, fly: nil], default: 90)
        XCTAssertEqual(fills, [curl: 90, fly: 90])
        XCTAssertNil(fills[bench], "Never overwrites an exercise's own rest")
        XCTAssertEqual(RestDefaults.fill([bench: 180], default: 60), [:])
    }

    func testEffectiveRest() {
        XCTAssertEqual(RestDefaults.effective(kind: .working, exercise: 180, dayDefault: 90, settingsWorking: 120, settingsWarmup: 60), 180)
        XCTAssertEqual(RestDefaults.effective(kind: .working, exercise: nil, dayDefault: 90, settingsWorking: 120, settingsWarmup: 60), 90)
        XCTAssertEqual(RestDefaults.effective(kind: .working, exercise: nil, dayDefault: nil, settingsWorking: 120, settingsWarmup: 60), 120)
        XCTAssertEqual(RestDefaults.effective(kind: .warmup, exercise: 180, dayDefault: 90, settingsWorking: 120, settingsWarmup: 60), 60)
    }

    func testFinalizeDropsUnloggedSetsNeverSavesZeros() {
        let bench = UUID(), curl = UUID(), today = UUID()
        func s(_ ex: UUID, _ w: Double, _ r: Int, done: Bool) -> LoggedSet {
            LoggedSet(snapshot: SetSnapshot(workoutID: today, weight: w, unit: .lb, reps: r, date: t0), exerciseID: ex, isDone: done)
        }
        let plan = SessionPlan(workoutID: today, routineID: nil, blocks: [
            .init(exerciseID: bench, sets: [s(bench, 185, 8, done: true), s(bench, 185, 8, done: false)]),
            .init(exerciseID: curl, sets: [s(curl, 0, 12, done: false), s(curl, 0, 12, done: false)]),
        ])
        XCTAssertEqual(plan.unloggedCount, 3)
        let final = plan.finalized()
        XCTAssertEqual(final.allSets.count, 1)
        XCTAssertEqual(final.blocks.map(\.exerciseID), [bench], "Exercise with nothing logged leaves the workout")
        XCTAssertFalse(final.allSets.contains { $0.snapshot.weight == 0 })
        XCTAssertEqual(final.unloggedCount, 0)
        // Finalising is a pure preview: the live plan is untouched until Done.
        XCTAssertEqual(plan.allSets.count, 4)
        XCTAssertFalse(plan.isEmptyWhenFinalized)
        XCTAssertTrue(SessionPlan(workoutID: today, routineID: nil, blocks: [.init(exerciseID: curl, sets: [s(curl, 0, 12, done: false)])]).isEmptyWhenFinalized)
    }
}

final class OutcomeTests: XCTestCase {
    let push = UUID(), pull = UUID(), legs = UUID()
    let t0 = Date(timeIntervalSince1970: 3_000_000)
    var order: [UUID] { [push, pull, legs] }

    func plan(_ workout: UUID, logged: Int, unlogged: Int) -> SessionPlan {
        let ex = UUID()
        let sets = (0..<(logged + unlogged)).map { i in
            LoggedSet(snapshot: SetSnapshot(workoutID: workout, weight: 185, unit: .lb, reps: 8, date: t0), exerciseID: ex, isDone: i < logged)
        }
        return SessionPlan(workoutID: workout, routineID: nil, blocks: [.init(exerciseID: ex, sets: sets)])
    }

    func record(_ routine: UUID?, _ outcome: WorkoutOutcome, at offset: TimeInterval, logged: Int = 3, unlogged: Int = 0) -> WorkoutRecord {
        let id = UUID()
        return WorkoutRecord(id: id, routineID: routine, startedAt: t0.addingTimeInterval(offset), outcome: outcome, plan: plan(id, logged: logged, unlogged: unlogged))
    }






    func testRestDefaultNeverOverwritesAcrossRepeatedSaves() {
        let bench = UUID(), curl = UUID()
        var rests: [UUID: Int?] = [bench: 180, curl: nil]
        for (id, v) in RestDefaults.fill(rests, default: 90) { rests[id] = v }
        XCTAssertEqual(rests[curl], 90)
        // Changing the day default later fills nothing: both now have their own rest.
        XCTAssertTrue(RestDefaults.fill(rests, default: 60).isEmpty)
        XCTAssertEqual(rests[bench], 180)
    }
}
