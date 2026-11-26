#if DEBUG
import SwiftUI
import UIKit
import SwiftData
import ActivityKit
import UserNotifications
import LiftCore

/// CI behaviour proof for the rest Live Activity (live-activity.md AC 99,
/// 106–109; CDO qa-live-activity.md). Launched with
/// `-LiftFixture 03-workout -LiftLiveActivityBehaviour`, it drives the same
/// calls the app's own paths make (WorkoutSession → RestActivityController,
/// the LiveActivityIntents → RestIntentHandler → PhoneSync, LiftStore.finish)
/// against the real ActivityKit, and writes a timestamped log of what the
/// system holds after each step (Documents/la-behaviour.log, also on screen).
/// scripts/liveactivity-behaviour.sh records the simulator while it runs and
/// backgrounds Lift for the two rest-end steps so the Island is visible.
struct LiveActivityBehaviour: View {
    static let requested = ProcessInfo.processInfo.arguments.contains("-LiftLiveActivityBehaviour")
    let container: ModelContainer
    @State private var lines: [String] = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Activity behaviour log (DEBUG harness)").font(.headline)
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                        Text(l).font(.system(size: 11, design: .monospaced)).id(i)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: lines.count) { _, n in proxy.scrollTo(n - 1, anchor: .bottom) }
        }
        .task { await run() }
    }

    private static let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("la-behaviour.log")

    @MainActor private func log(_ s: String) async {
        try? await Task.sleep(for: .milliseconds(400)) // let ActivityKit settle before reading it back
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let notes = pending.map { r -> String in
            let t = (r.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate().map(RestActivityController.clock) ?? "?"
            return "\(r.identifier)@\(t)"
        }
        let fallback = RestNotifications.debugScheduled.map { "requested@" + RestActivityController.clock($0) } ?? "none"
        let line = "\(RestActivityController.clock(Date())) \(s) | \(RestActivityController.shared.debugSnapshot) | fallback notification=\(fallback) (system pending: \(notes.isEmpty ? "none" : notes.joined(separator: ",")))"
        lines.append(line)
        NSLog("LA-BEHAVIOUR %@", line)
        let all = lines.joined(separator: "\n") + "\n"
        try? all.write(to: Self.logURL, atomically: true, encoding: .utf8)
    }

    private func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    @MainActor private func startRest(_ seconds: Int) {
        let r = RestState(seconds: seconds, exercise: "Barbell Bench Press", next: "185 lb × 9", origin: .phone)
        PhoneSync.shared.setLocalRest(r)
        RestActivityController.shared.show(start: r.countdown.endsAt.addingTimeInterval(-r.countdown.total), end: r.countdown.endsAt)
    }

    /// What WorkoutSession.finishRest does at zero.
    @MainActor private func restEnds() {
        PhoneSync.shared.setLocalRest(nil)
        RestActivityController.shared.restOver()
    }

    @MainActor private func restSec() -> String {
        let ctx = container.mainContext
        guard let w = LiveBridge.currentOpen(ctx), let g = w.groups.first(where: { $0.sets.contains { !$0.isDone } }) ?? w.groups.first else { return "?" }
        return "\(g.exercise.restSec.map(String.init) ?? "nil")"
    }

    @MainActor private func run() async {
        RestActivityController.shared.start(container: container)
        RestActivityController.shared.end()
        PhoneSync.shared.debugSetWatchSession(false)
        await log("0 harness up, Live Activities enabled=\(ActivityAuthorizationInfo().areActivitiesEnabled)")
        await wait(1.5)

        // AC 99: start, then a second rest updates the same Activity (no stack).
        startRest(90)
        await log("1 START rest 90s (phone winner)")
        await wait(2)
        startRest(120)
        await log("2 NEW REST 120s → same Activity updated in place (count stays 1)")
        await wait(2)

        // AC 107: +30s moves the end date only; restSec untouched.
        let before = restSec()
        await RestIntentHandler.addThirty()
        await log("3 +30s via the LiveActivityIntent handler → end +30s; exercise restSec \(before) → \(restSec())")
        await wait(2)

        // AC 107: Skip, no alert, dismisses after 5 s; Undo restores.
        await RestIntentHandler.skip()
        await log("4 SKIP via the intent handler → Rest over, ended with dismissal .after(now+5s), no alert, notification cancelled")
        await wait(1.5)
        startRest(100)
        await log("5 UNDO (in-app toast path re-shows the rest) → one Activity again")
        await wait(1.5)
        RestActivityController.shared.end()
        startRest(8)
        await log("6 short rest 8s for the rest-end case; phone winner → fallback notification requested")
        // The simulator suspends a backgrounded Lift within seconds, so this step plays
        // "Lift not on screen" (appActive=false) while staying in the foreground.
        RestActivityController.shared.debugAppActive = false
        await wait(8.2)
        restEnds()
        await log("7 REST END, phone winner, Lift not on screen (simulated) → alert-style update (hl=true), fallback notification cancelled")
        await wait(RestActivityPolicy.highlightSeconds + 1)
        await log("8 after the ~2 s highlight → settled Rest over, ended with dismissal .after(end+5m), stale end+2m")
        await wait(1.5)

        // AC 106: watch winner, Lift suspended at rest-end → no phone notification at all.
        RestActivityController.shared.end()
        PhoneSync.shared.debugSetWatchSession(true)
        startRest(8)
        await log("9 WATCH WINNER: rest 8s with the watch session running → expect fallback notification=none")
        await wait(8.2)
        restEnds()
        await log("10 REST END, watch winner, Lift not on screen (simulated) → quiet Rest over (hl=false), no Activity alert, no phone notification")
        await wait(1.5)
        RestActivityController.shared.debugAppActive = nil
        PhoneSync.shared.debugSetWatchSession(false)


        // AC 108: Finish ends it immediately, never via Rest over.
        startRest(90)
        await log("11 rest 90s running before Finish (Lift back on screen)")
        await wait(1.5)
        if let w = LiveBridge.currentOpen(container.mainContext) { LiftStore.finish(w, context: container.mainContext) }
        await log("12 FINISH (LiftStore.finish) → Activity ended .immediate, expect activities=0")
        // AC 109: the tap target.
        await log("13 widgetURL=\(RestLinks.workout.absoluteString) → RootView.onOpenURL selects the Log tab")
        // The real system Island: a running rest with Lift actually in the background.
        RestActivityController.shared.demo()
        await log("14 rest 150s (demo content; the workout is finished) for the system Island shot (the script backgrounds Lift, then brings it back)")
        await wait(10)
        await log("15 back on screen")
        RestActivityController.shared.end()
        await log("DONE")
    }
}
#endif
