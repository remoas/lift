import ActivityKit
import Foundation
import SwiftData
import UIKit
import LiftCore

/// The one workout Live Activity (design/live-activity.md ACs 99–112 and
/// delta-live-activity-bodyweight.md ACs 113–118).
///
/// - Starts when a workout becomes active (at least one exercise, not finished).
/// - One Activity, updated in place; never stacked.
/// - Three visible states: Resting, Rest over, Ready for next set.
/// - Ends `.immediate` on Finish, Discard, or the 3 h auto-finish.
/// - Fails silently when Live Activities are off or `request` throws.
@MainActor
final class RestActivityController {
    static let shared = RestActivityController()

    private var container: ModelContainer?
    private var settings: AppSettings?
    private var chain: Task<Void, Never>?
    private var pending: Task<Void, Never>?
    private var workoutID = ""

    /// When the Log screen is up, Log set goes through WorkoutSession (PR banner, rest, watch).
    var logHandler: ((SetEntry) -> Void)?

    func start(container: ModelContainer, settings: AppSettings? = nil) {
        self.container = container
        if let settings { self.settings = settings }
    }

    private var activities: [Activity<RestActivityAttributes>] { Activity<RestActivityAttributes>.activities }
    private var live: Activity<RestActivityAttributes>? {
        activities.first { $0.activityState == .active || $0.activityState == .stale }
    }

    /// An Activity is up and will carry the rest-end moment.
    var isRunning: Bool { ActivityAuthorizationInfo().areActivitiesEnabled && live != nil }

    // MARK: Events

    /// A new rest, +30s (end date only), or an Undo restore.
    func show(start: Date, end: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let state = makeState(start: start, end: end, phase: .resting) else { return }
        pending?.cancel()
        let content = ActivityContent(state: state, staleDate: end)
        push(content)
    }

    /// Ready for the next set: no running timer, stepper and Log set visible.
    func presentReady() {
        guard let open = openWorkout(), !open.groups.isEmpty else { end(); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let state = makeState(start: Date(), end: Date(), phase: .ready) else { return }
        pending?.cancel()
        push(ActivityContent(state: state, staleDate: nil))
    }

    /// Start or refresh the Activity for an active workout, or end it if none.
    func sync() {
        guard let open = openWorkout(), !open.groups.isEmpty else { end(); return }
        if let rest = PhoneSync.shared.rest, !rest.isOver(at: Date()) {
            show(start: rest.countdown.endsAt.addingTimeInterval(-rest.countdown.total), end: rest.countdown.endsAt)
        } else if live?.content.state.phase == .restOver || live?.content.state.over == true,
                  live.map({ $0.content.state.end <= Date() && PhoneSync.shared.rest == nil }) == true {
            // Stay on Rest over until the set is logged or rest is dismissed.
            return
        } else {
            presentReady()
        }
    }

    /// The rest-end handler (the same one that owns the watch/phone alert).
    /// The Activity stays up in Rest over so the set can be logged from the lock screen.
    func restOver() {
        guard let a = live else { return }
        pending?.cancel()
        var state = makeState(start: a.content.state.start, end: min(a.content.state.end, Date()), phase: .restOver) ?? a.content.state
        state.end = min(state.end, Date())
        state.over = true
        state.phase = .restOver
        var appActive = UIApplication.shared.applicationState == .active
        #if DEBUG
        if let forced = debugAppActive { appActive = forced }
        #endif
        let kind = RestActivityPolicy.atRestEnd(watchAlerts: PhoneSync.shared.watchAlerts, appActive: appActive)
        state.highlight = kind == .alert
        let content = ActivityContent(state: state, staleDate: nil)
        if kind == .alert {
            RestNotifications.cancel()
            let alert = AlertConfiguration(title: LocalizedStringResource(stringLiteral: RestActivityText.restOver(setNumber: state.setNumber)),
                                           body: LocalizedStringResource(stringLiteral: "\(state.exercise), \(state.load)"),
                                           sound: .default)
            enqueue { await a.update(content, alertConfiguration: alert) }
            var settled = state
            settled.highlight = false
            let after = ActivityContent(state: settled, staleDate: nil)
            pending = Task { [weak self] in
                try? await Task.sleep(for: .seconds(RestActivityPolicy.highlightSeconds))
                guard !Task.isCancelled else { return }
                self?.enqueue { await a.update(after) }
            }
        } else {
            enqueue { await a.update(content) }
        }
    }

    /// Skip: rest is dismissed, the Activity moves to Ready (no alert).
    func skipped() {
        pending?.cancel()
        presentReady()
    }

    /// Lift woke up: flip a Resting Activity whose timer has ended to Rest over
    /// without dismissing it, and end anything whose workout is gone.
    func sweep(now: Date = Date()) {
        guard let open = openWorkout(), !open.groups.isEmpty else { end(); return }
        for a in activities where a.activityState == .active || a.activityState == .stale {
            let state = a.content.state
            if state.phase == .ready { continue }
            guard state.end <= now else { continue }
            if state.phase == .resting || (!state.over && state.phase != .restOver) {
                restOver()
            }
        }
    }

    #if DEBUG
    /// The behaviour harness plays "Lift isn't on screen" without being suspended.
    var debugAppActive: Bool?

    /// For the behaviour log: what the system holds right now.
    var debugSnapshot: String {
        let all = activities
        let rows = all.map { a in
            let s = a.content.state
            return "[\(a.id.prefix(6)) \(a.activityState) end=\(Self.clock(s.end)) stale=\(a.content.staleDate.map(Self.clock) ?? "nil") over=\(s.over) phase=\(s.phase.rawValue) hl=\(s.highlight) next=\"\(s.ladder.first ?? "")\"]"
        }
        return "activities=\(all.count) " + rows.joined(separator: " ")
    }
    static func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }
    #endif

    /// Finish, Discard, auto-finish: gone now, never via Rest over.
    func end() {
        pending?.cancel()
        let all = activities
        guard !all.isEmpty else { return }
        enqueue { for a in all { await a.end(nil, dismissalPolicy: .immediate) } }
    }

    func adjustReps(_ delta: Int) {
        guard let a = live else { return }
        Haptics.step()
        var state = a.content.state
        state.reps = min(99, max(1, state.reps + delta))
        let stale: Date? = state.phase == .resting ? state.end : nil
        enqueue { await a.update(ActivityContent(state: state, staleDate: stale)) }
    }

    func logSet() {
        guard let due = dueSet(), !due.needsWeight else { return }
        if let reps = live?.content.state.reps {
            due.reps = min(99, max(1, reps))
        }
        Haptics.tick()
        if let logHandler {
            logHandler(due)
            return
        }
        guard let container else { return }
        let context = container.mainContext
        guard let open = openWorkout() else { return }
        if open.doneSets.isEmpty { open.startedAt = Date() }
        due.isDone = true
        due.doneAt = Date()
        if let ex = due.exercise { LiftStore.prefill(ex, in: open, globalUnit: due.unit) }
        _ = LiftStore.save(context)
        let seconds = due.kind == .warmup ? (settings?.warmupRestSeconds ?? 60) : due.restSeconds
        let auto = settings?.autoStartRest ?? true
        if auto, seconds > 0, !open.isBackLog {
            let r = RestCountdown(seconds: seconds, setID: due.id)
            let next = currentDue().map { s in
                RestActivityText.load(weight: s.weight, unit: s.unit, reps: s.reps, kind: s.exercise?.loadKind ?? .loaded)
            }
            PhoneSync.shared.setLocalRest(RestState(countdown: r, exercise: currentDue()?.exercise?.name, next: next, origin: .phone))
            show(start: r.endsAt.addingTimeInterval(-r.total), end: r.endsAt)
        } else {
            presentReady()
        }
    }

    #if DEBUG
    /// Review only (-LiftLiveActivityDemo): a real system Activity with fixture
    /// content, so CI can shoot the actual Dynamic Island once Lift backgrounds.
    func demo() {
        let now = Date()
        let state = RestActivityAttributes.ContentState(exercise: "Barbell Bench Press", setNumber: 3, weight: 185, unit: .lb, reps: 9,
                                                        bodyweight: false, kind: .loaded, start: now.addingTimeInterval(-30), end: now.addingTimeInterval(150),
                                                        over: false, highlight: false, phase: .resting,
                                                        targetWeight: 185, targetReps: 9)
        _ = try? Activity.request(attributes: RestActivityAttributes(workoutID: "demo"),
                                  content: ActivityContent(state: state, staleDate: state.end), pushType: nil)
    }
    #endif

    private func push(_ content: ActivityContent<RestActivityAttributes.ContentState>) {
        enqueue { [weak self] in
            guard let self else { return }
            if let a = self.live {
                await a.update(content)
            } else {
                for a in self.activities { await a.end(nil, dismissalPolicy: .immediate) }
                let attrs = RestActivityAttributes(workoutID: self.workoutID)
                _ = try? Activity.request(attributes: attrs, content: content, pushType: nil)
            }
        }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = chain
        chain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    // MARK: Content

    private func openWorkout() -> Workout? {
        guard let container else { return nil }
        return LiveBridge.currentOpen(container.mainContext)
    }

    private func dueSet() -> SetEntry? {
        currentDue()
    }

    private func currentDue() -> SetEntry? {
        guard let open = openWorkout() else { return nil }
        let groups = open.groups
        guard let group = groups.first(where: { $0.sets.contains { !$0.isDone } }) ?? groups.last else { return nil }
        let working = group.sets.filter { $0.kind != .warmup }
        return working.first { !$0.isDone } ?? working.last
    }

    /// Name, Set N, the prefill or stepper seed of the set now due, and the target to beat.
    private func makeState(start: Date, end: Date, phase: RestActivityPhase) -> RestActivityAttributes.ContentState? {
        guard let container, let open = LiveBridge.currentOpen(container.mainContext) else { return nil }
        workoutID = open.id.uuidString
        let groups = open.groups
        guard let group = groups.first(where: { $0.sets.contains { !$0.isDone } }) ?? groups.last else { return nil }
        let ex = group.exercise
        let working = group.sets.filter { $0.kind != .warmup }
        let due = working.first { !$0.isDone }
        let name = ex.variant.isEmpty || ex.name.localizedCaseInsensitiveContains(ex.variant) ? ex.name : "\(ex.name) (\(ex.variant))"
        let shown = due ?? working.last
        let kind = ex.loadKind
        let unit = shown?.unit ?? ex.unit(global: .lb)
        let beat = LiftStore.beatIt(for: ex, excluding: open, unit: unit)
        // AC 115 / Ben 2:16pm: first set of an exercise prefills the target;
        // later sets prefill what was just logged, so a miss does not snap back.
        // Beat stays the target. Last: is the previous set (this session, or last time).
        let previous = working.last(where: { $0.isDone })
        let justLogged = previous.map { SetTarget(weight: UnitMath.convert($0.weight, from: $0.unit, to: unit), reps: $0.reps) }
        let lastTime: SetTarget?
        if let i = beat.topIndex, beat.last.indices.contains(i) {
            lastTime = beat.last[i]
        } else {
            lastTime = beat.last.first
        }
        let seed = Target.prefill(justLogged: justLogged, target: beat.target, lastTime: lastTime)
        var reps = seed?.reps ?? shown?.reps ?? ex.repGoal
        // Keep a stepper value the user already chose if this is the same due set.
        if let live, live.content.state.setNumber == due.flatMap({ d in working.firstIndex { $0 === d } }).map({ $0 + 1 }),
           phase != .resting, live.content.state.exercise == name {
            reps = live.content.state.reps
        }
        let lastWeight = justLogged?.weight ?? lastTime?.weight
        let lastReps = justLogged?.reps ?? lastTime?.reps
        return RestActivityAttributes.ContentState(
            exercise: name,
            setNumber: due.flatMap { d in working.firstIndex { $0 === d } }.map { $0 + 1 },
            weight: seed?.weight ?? shown?.weight ?? 0,
            unit: unit,
            reps: reps,
            bodyweight: kind == .bodyweight,
            kind: kind,
            start: start, end: end,
            over: phase == .restOver,
            highlight: false,
            phase: phase,
            targetWeight: beat.target?.weight,
            targetReps: beat.target?.reps,
            needsWeight: shown?.needsWeight ?? false,
            lastWeight: lastWeight,
            lastReps: lastReps)
    }
}

/// Intents from the Lock Screen and the Island (LiveActivityIntent runs here).
enum RestIntentHandler {
    @MainActor static func addThirty() async { PhoneSync.shared.addRestFromActivity(30) }
    @MainActor static func skip() async { PhoneSync.shared.skipRestFromActivity() }
    @MainActor static func adjustReps(_ delta: Int) async { RestActivityController.shared.adjustReps(delta) }
    @MainActor static func logSet() async { RestActivityController.shared.logSet() }
}
