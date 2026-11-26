import ActivityKit
import Foundation
import SwiftData
import UIKit
import LiftCore

/// The one rest-timer Live Activity (design/live-activity.md, AC 99–112).
///
/// - One Activity, updated in place; a new rest after an ended one ends the
///   old one `.immediate` first, so two never stack.
/// - The tick is the system's (`Text`/`ProgressView(timerInterval:)`); Lift
///   pushes only for a new rest, +30s, Skip, rest-end and workout end.
/// - While running, `staleDate` is the rest end, so the card flips to
///   "Rest over" at zero even when Lift is suspended (no push server). When
///   Lift writes Rest over itself, stale moves to end + 2 min and it is
///   dismissed at end + 5 min.
/// - Fails silently when Live Activities are off or `request` throws; the
///   rest bar, the watch and the notification fallback still run.
@MainActor
final class RestActivityController {
    static let shared = RestActivityController()

    private var container: ModelContainer?
    private var chain: Task<Void, Never>?
    private var pending: Task<Void, Never>?
    private var workoutID = ""

    func start(container: ModelContainer) { self.container = container }

    private var activities: [Activity<RestActivityAttributes>] { Activity<RestActivityAttributes>.activities }
    private var live: Activity<RestActivityAttributes>? {
        activities.first { $0.activityState == .active || $0.activityState == .stale }
    }

    /// An Activity is up and will carry the rest-end moment.
    var isRunning: Bool { ActivityAuthorizationInfo().areActivitiesEnabled && live != nil }

    // MARK: Events

    /// A new rest, +30s (end date only), or an Undo restore.
    func show(start: Date, end: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let state = makeState(start: start, end: end) else { return }
        pending?.cancel()
        let content = ActivityContent(state: state, staleDate: end)
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

    /// The rest-end handler (the same one that owns the watch/phone alert).
    func restOver() {
        guard let a = live else { return }
        var state = a.content.state
        let end = min(state.end, Date())
        state.end = end
        state.over = true
        var appActive = UIApplication.shared.applicationState == .active
        #if DEBUG
        if let forced = debugAppActive { appActive = forced }
        #endif
        let kind = RestActivityPolicy.atRestEnd(watchAlerts: PhoneSync.shared.watchAlerts, appActive: appActive)
        state.highlight = kind == .alert
        let content = ActivityContent(state: state, staleDate: RestActivityPolicy.staleDate(end: end))
        let dismiss = ActivityUIDismissalPolicy.after(RestActivityPolicy.dismissAt(end: end))
        if kind == .alert {
            // The Activity alert is the one banner; the notification was only the fallback.
            RestNotifications.cancel()
            let alert = AlertConfiguration(title: LocalizedStringResource(stringLiteral: RestActivityText.restOver(setNumber: state.setNumber)),
                                           body: LocalizedStringResource(stringLiteral: "\(state.exercise), \(state.load)"),
                                           sound: .default)
            enqueue { await a.update(content, alertConfiguration: alert) }
            var settled = state
            settled.highlight = false
            let after = ActivityContent(state: settled, staleDate: content.staleDate)
            pending = Task { [weak self] in
                try? await Task.sleep(for: .seconds(RestActivityPolicy.highlightSeconds))
                guard !Task.isCancelled else { return }
                self?.enqueue { await a.end(after, dismissalPolicy: dismiss) }
            }
        } else {
            enqueue { await a.end(content, dismissalPolicy: dismiss) }
        }
    }

    /// Skip: Rest over with no alert, gone after the 5 s Undo window.
    func skipped() {
        guard let a = live else { return }
        pending?.cancel()
        var state = a.content.state
        state.end = Date()
        state.over = true
        state.highlight = false
        let content = ActivityContent(state: state, staleDate: nil)
        enqueue { await a.end(content, dismissalPolicy: .after(Date().addingTimeInterval(RestActivityPolicy.skipDismissAfter))) }
    }

    /// Lift woke up (foreground): an Activity whose rest ended while Lift was
    /// suspended gets its Rest over end and +5 min dismissal now; past that, it goes.
    func sweep(now: Date = Date()) {
        for a in activities where a.activityState == .active || a.activityState == .stale {
            var state = a.content.state
            guard state.end <= now else { continue }
            if now >= RestActivityPolicy.dismissAt(end: state.end) {
                enqueue { await a.end(nil, dismissalPolicy: .immediate) }
            } else {
                state.over = true
                state.highlight = false
                let content = ActivityContent(state: state, staleDate: RestActivityPolicy.staleDate(end: state.end))
                enqueue { await a.end(content, dismissalPolicy: .after(RestActivityPolicy.dismissAt(end: state.end))) }
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
            return "[\(a.id.prefix(6)) \(a.activityState) end=\(Self.clock(s.end)) stale=\(a.content.staleDate.map(Self.clock) ?? "nil") over=\(s.over) hl=\(s.highlight) next=\"\(s.ladder.first ?? "")\"]"
        }
        return "activities=\(all.count) " + rows.joined(separator: " ")
    }
    static func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }
    #endif

    /// Rest Off on the next lift, Finish, Discard, auto-finish: gone now.
    func end() {
        pending?.cancel()
        let all = activities
        guard !all.isEmpty else { return }
        enqueue { for a in all { await a.end(nil, dismissalPolicy: .immediate) } }
    }

    #if DEBUG
    /// Review only (-LiftLiveActivityDemo): a real system Activity with fixture
    /// content, so CI can shoot the actual Dynamic Island once Lift backgrounds.
    func demo() {
        let now = Date()
        let state = RestActivityAttributes.ContentState(exercise: "Barbell Bench Press", setNumber: 3, weight: 185, unit: .lb, reps: 9,
                                                        bodyweight: false, start: now.addingTimeInterval(-30), end: now.addingTimeInterval(150),
                                                        over: false, highlight: false)
        _ = try? Activity.request(attributes: RestActivityAttributes(workoutID: "demo"),
                                  content: ActivityContent(state: state, staleDate: state.end), pushType: nil)
    }
    #endif

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = chain
        chain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    // MARK: Content

    /// Name, Set N and the prefill of the set now due (the rows LiftStore.prefill wrote).
    private func makeState(start: Date, end: Date) -> RestActivityAttributes.ContentState? {
        guard let container, let open = LiveBridge.currentOpen(container.mainContext) else { return nil }
        workoutID = open.id.uuidString
        let groups = open.groups
        guard let group = groups.first(where: { $0.sets.contains { !$0.isDone } }) ?? groups.last else { return nil }
        let ex = group.exercise
        let working = group.sets.filter { $0.kind != .warmup }
        let due = working.first { !$0.isDone }
        let name = ex.variant.isEmpty || ex.name.localizedCaseInsensitiveContains(ex.variant) ? ex.name : "\(ex.name) (\(ex.variant))"
        let shown = due ?? working.last
        return RestActivityAttributes.ContentState(
            exercise: name,
            setNumber: due.flatMap { d in working.firstIndex { $0 === d } }.map { $0 + 1 },
            weight: shown?.weight ?? 0,
            unit: shown?.unit ?? ex.unit(global: .lb),
            reps: shown?.reps ?? ex.repGoal,
            bodyweight: ex.equipment == .bodyweight,
            start: start, end: end)
    }
}

/// +30s and Skip from the Lock Screen and the Island (LiveActivityIntent runs here).
enum RestIntentHandler {
    @MainActor static func addThirty() async { PhoneSync.shared.addRestFromActivity(30) }
    @MainActor static func skip() async { PhoneSync.shared.skipRestFromActivity() }
}
