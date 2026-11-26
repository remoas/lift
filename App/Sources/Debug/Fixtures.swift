#if DEBUG
import SwiftUI
import SwiftData
import LiftCore

/// Screenshot fixtures for the 27 design frames (AC 24). DEBUG builds only:
/// selected with `-LiftFixture <frame>`, backed by an in-memory store and a
/// throwaway defaults suite, so the shipped app never contains demo data.
enum Fixtures {
    static let frames = [
        "01-log-empty", "01b-log-active", "01c-target-hit", "01d-stale-saved-toast",
        "03-workout", "04-rest", "05-set-editor", "06-pr-banner", "07-finish", "08-exercise",
        "10-history", "11-settings", "12-history-empty", "13-first-workout", "14-health-error", "15-restoring",
        "16-exercise-empty", "18a-picker-empty", "18a2-picker-empty-scrolled", "18b-picker-bench", "18c-picker-rdl", "18d-picker-zzqx", "18e-picker-press",
        "18f-picker-squat", "18g-picker-deadlift", "18h-picker-pull-up", "18i-picker-db-incline", "18j-picker-benhc", "18k-picker-pull-ups", "19-reorder",
        "24a-media-video", "24b-media-stills", "24c-media-reduce-motion", "24d-media-loading", "24e-media-none",
        "25-finish-sets-left", "26-discard-toast",
    ]

    /// Screen-recording starts (AC 61), not design frames.
    static let recordings = ["rec-pr"]

    /// Picker frames (§10.8): the query typed when the sheet opens.
    static var pickerQuery: String? {
        switch requested {
        case "18b-picker-bench": return "bench"
        case "18c-picker-rdl": return "rdl"
        case "18d-picker-zzqx": return "zzqx"
        case "18e-picker-press": return "press"
        case "18f-picker-squat": return "squat"
        case "18g-picker-deadlift": return "deadlift"
        case "18h-picker-pull-up": return "pull up"
        case "18i-picker-db-incline": return "db incline"
        case "18j-picker-benhc": return "benhc"
        case "18k-picker-pull-ups": return "Pull Ups"
        default: return nil
        }
    }
    static var isPicker: Bool { requested?.hasPrefix("18") == true }

    enum MediaMode { case normal, hidden, reduceMotion, loading }

    /// 08 matches the no-media layout; 24c/24d force their states.
    static var mediaMode: MediaMode {
        switch requested {
        case "08-exercise": return .hidden
        case "24c-media-reduce-motion": return .reduceMotion
        case "24d-media-loading": return .loading
        default: return .normal
        }
    }

    static let requested: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LiftFixture"), i + 1 < args.count,
              frames.contains(args[i + 1]) || recordings.contains(args[i + 1]) || LiveActivityGallery.names.contains(args[i + 1]) else { return nil }
        return args[i + 1]
    }()

    /// Objects the root needs to show a frame.
    @MainActor static var workout: Workout?
    @MainActor static var exercise: Exercise?

    @MainActor
    static func make(_ frame: String) -> (ModelContainer, AppSettings) {
        let suite = "lift.fixtures"
        UserDefaults().removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        let settings = AppSettings(defaults: defaults)
        settings.unit = .lb
        let container = LiftStore.makeContainer(inMemory: true)
        let b = Builder(context: container.mainContext, settings: settings)

        switch frame {
        case "01-log-empty", "15-restoring", "12-history-empty":
            break
        case "13-first-workout":
            // Nothing in history: no Last line, "First time. Log what you do."
            workout = b.active(["bench-press", "barbell-shoulder-press"], doneSets: 0)
        default:
            b.history(weeks: 3)
            if Fixtures.isPicker {
                // One shared history for every 18x shot (qa-search Nit 2): 3 weeks of
                // push/pull/legs plus Seated Dumbbell Press 4 times, so "press" floats it first.
                let cal = Calendar.current
                for d in [12, 9, 5, 2] { b.session(["seated-dumbbell-press"], at: cal.date(byAdding: .day, value: -d, to: Date())!, bump: 0) }
            }
            switch frame {
            case "01b-log-active":
                workout = b.active(["bench-press", "barbell-shoulder-press"], doneSets: 1)
            case "01c-target-hit":
                // AC 66: bench set 1 logged at the target, so Beat it reads hit.
                workout = b.active(["bench-press", "barbell-shoulder-press"], doneSets: 1, asLastTime: false)
            case "01d-stale-saved-toast":
                // AC 67: a workout last logged 3.5 h ago; launch auto-finishes it
                // (RootView.refreshLog) and shows the Saved toast on a fresh Log.
                let w = b.active(Builder.push, doneSets: 6)
                let start = Date().addingTimeInterval(-4.5 * 3600)
                w.startedAt = start
                for (i, s) in w.doneSets.enumerated() { s.doneAt = start.addingTimeInterval(Double(i + 1) * 180) }
            case "03-workout", "04-rest", "05-set-editor", "19-reorder":
                workout = b.active(Builder.push, doneSets: 2)
            case "06-pr-banner":
                workout = b.active(Builder.push, doneSets: 2, topSet: (205, 5))
            case "07-finish":
                workout = b.finishedToday(topSet: (205, 5))
            case "rec-pr":
                // Bench set 3 is a best, set 4 (added here) becomes a second bench
                // best within 4 s via the editor (replace in place), then the next
                // exercise's first set is a third best left to auto-dismiss.
                let w = b.active(Builder.push, doneSets: 2)
                if let bench = w.groups.first?.exercise { _ = LiftStore.addSet(to: bench, in: w, context: b.context) }
                let open = w.groups.flatMap(\.sets).filter { !$0.isDone }
                if open.count > 2 {
                    open[0].weight = 215; open[0].reps = 5
                    open[2].weight = max(open[2].weight, 95) + 40; open[2].reps = 6
                }
                workout = w
            case "25-finish-sets-left":
                workout = b.active(Builder.push, doneSets: 11)
            case "26-discard-toast":
                // After Discard: a fresh Log with the Undo toast.
                break
            case "24a-media-video", "24c-media-reduce-motion":
                // Reduce Motion matters for video: End still, "▶ Play" pill, no autoplay.
                exercise = b.exercise("barbell-shoulder-press")
            case "24b-media-stills", "24d-media-loading":
                exercise = b.exercise("bench-press")
            case "24e-media-none":
                exercise = b.exercise("triceps-pushdown")
            case "08-exercise":
                exercise = b.exercise("bench-press")
            case "16-exercise-empty":
                exercise = b.exercise("side-lateral-raise")
                exercise.map { b.clearHistory($0) }
            default: break
            }
        }
        _ = LiftStore.save(b.context)
        return (container, settings)
    }

    /// Debug-only staging data (in memory, never in the shipped app).
    @MainActor
    struct Builder {
        let context: ModelContext
        let settings: AppSettings

        static let push = ["bench-press", "barbell-shoulder-press", "incline-dumbbell-press", "side-lateral-raise", "triceps-pushdown"]
        static let pull = ["deadlift", "pullups", "bent-over-row", "face-pull", "barbell-curl"]
        static let legs = ["barbell-squat", "romanian-deadlift", "leg-press", "leg-curl", "calf-raises"]
        /// Starting weight (lb) and reps per exercise.
        static let base: [String: (Double, Int)] = [
            "bench-press": (185, 8), "barbell-shoulder-press": (115, 8), "incline-dumbbell-press": (60, 10),
            "side-lateral-raise": (20, 12), "triceps-pushdown": (50, 10),
            "deadlift": (315, 5), "pullups": (0, 9), "bent-over-row": (155, 8), "face-pull": (40, 12), "barbell-curl": (70, 9),
            "barbell-squat": (245, 6), "romanian-deadlift": (205, 8), "leg-press": (360, 10), "leg-curl": (90, 10), "calf-raises": (180, 12), "seated-dumbbell-press": (50, 10),
        ]

        func exercise(_ id: String) -> Exercise? {
            ExerciseLibrary.bundled.exercise(id).map { LiftStore.exercise(for: $0, context: context) }
        }

        /// Finished sessions, three a week (push, pull, legs), weights climbing 5 lb a week.
        func history(weeks: Int) {
            let cal = Calendar.current
            let now = Date()
            for w in stride(from: weeks, through: 1, by: -1) {
                for (d, day) in [Self.push, Self.pull, Self.legs].enumerated() {
                    let date = cal.date(byAdding: .hour, value: -(24 * (7 * w - 2 * d)) + 2, to: now)!
                    session(day, at: date, bump: Double(-5 * w))
                }
            }
        }

        @discardableResult
        func session(_ ids: [String], at date: Date, bump: Double, topSet: (Double, Int)? = nil, finished: Bool = true) -> Workout {
            let w = Workout(startedAt: date)
            context.insert(w)
            var logged = 0
            for (e, id) in ids.enumerated() {
                guard let ex = exercise(id), let base = Self.base[id] else { continue }
                let reps = [base.1, max(base.1 - 1, 1), max(base.1 - 2, 1)]
                for s in 0..<3 {
                    var weight = base.0 > 0 ? base.0 + bump : 0
                    var r = reps[s]
                    if e == 0, s == 0, let top = topSet { weight = top.0; r = top.1 }
                    let set = SetEntry(order: s, exerciseOrder: e, weight: max(weight, 0), unit: .lb, reps: r, exercise: ex)
                    set.restSeconds = base.1 <= 8 ? 150 : 90
                    set.isDone = true
                    set.doneAt = date.addingTimeInterval(Double(logged + 1) * 150)
                    logged += 1
                    context.insert(set)
                    set.workout = w
                }
            }
            if finished { w.endedAt = date.addingTimeInterval(52 * 60) }
            return w
        }

        /// Today's open log with these exercises added the real way (prefilled
        /// from last time, the top set at the target), `doneSets` ticked.
        /// `asLastTime`: ticked sets repeat last time's numbers (target not hit
        /// yet, so the current exercise shows the bar); false keeps the prefill.
        func active(_ ids: [String], doneSets: Int, topSet: (Double, Int)? = nil, asLastTime: Bool = true) -> Workout {
            let started = Date().addingTimeInterval(-18 * 60 - 42)
            let w = LiftStore.startBlank(at: started, context: context)
            for id in ids {
                guard let ex = exercise(id) else { continue }
                LiftStore.addExercise(ex, to: w, globalUnit: .lb, restDefault: 120, context: context)
            }
            if asLastTime {
                var n = 0
                for g in w.groups {
                    let last = LiftStore.beatIt(for: g.exercise, excluding: w, unit: .lb).last
                    for (j, s) in g.sets.enumerated() {
                        if n < doneSets, j < last.count { s.weight = last[j].weight; s.reps = last[j].reps }
                        n += 1
                    }
                }
            }
            let sets = w.groups.flatMap(\.sets)
            for (i, s) in sets.prefix(doneSets).enumerated() {
                if i == 1, let topSet { s.weight = topSet.0; s.reps = topSet.1 }
                if s.weight == 0, s.exercise?.equipment.allowsZeroWeight == false { s.weight = 135 }
                s.isDone = true
                s.doneAt = started.addingTimeInterval(Double(i + 1) * 180)
            }
            // Same rule the session applies after each logged set (AC 64).
            for g in w.groups { LiftStore.prefill(g.exercise, in: w, globalUnit: .lb) }
            return w
        }

        /// Today's push, all logged, top bench set beating its target; left open
        /// so the summary shows before Done, like the real flow.
        func finishedToday(topSet: (Double, Int)?) -> Workout {
            let w = active(Self.push, doneSets: .max, asLastTime: false)
            if let topSet, let first = w.groups.first?.sets.first { first.weight = topSet.0; first.reps = topSet.1 }
            return w
        }

        func clearHistory(_ ex: Exercise) {
            for s in ex.sets ?? [] { context.delete(s) }
        }
    }
}

/// Shows one frame. Uses the real views; only the starting state is staged.
struct FixtureRoot: View {
    let frame: String
    @Environment(CloudSyncMonitor.self) private var cloud
    @Environment(ToastCenter.self) private var toasts
    @Namespace private var liftNS

    var body: some View {
        content
            .environment(\.liftNamespace, liftNS)
            .overlay { ToastOverlay() }
            .onAppear {
                if Theme.Motion.slowFactor < 1 {
                    // UIKit transitions (zoom, push, cover) at Slow Animations speed too.
                    // Applied again once the window is key: run2's slow tape opened in 67 ms.
                    let apply = {
                        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                            for w in scene.windows { w.layer.speed = Float(Theme.Motion.slowFactor) }
                        }
                    }
                    apply()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: apply)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: apply)
                }
                if frame == "15-restoring" { cloud.debugSimulateFirstRestore() }
                // Health is written after Done, so its error is a toast on the Log.
                if frame == "26-discard-toast" {
                    // Same call RootView makes on Discard: hidden, then deleted when the toast ends.
                    toasts.show("Workout discarded", undo: {}, onCommit: {})
                }
                if frame == "14-health-error" { toasts.show("Couldn't save to Apple Health. Your workout is safe in Lift.") }
            }
    }

    @ViewBuilder private var content: some View {
        switch frame {
        case "01b-log-active", "01c-target-hit", "03-workout", "04-rest", "05-set-editor", "06-pr-banner", "13-first-workout", "19-reorder", "rec-pr":
            if let w = Fixtures.workout { RootView(workout: w) }
        case "07-finish", "25-finish-sets-left":
            if let w = Fixtures.workout { FinishView(workout: w, onDone: {}) }
        case "08-exercise", "16-exercise-empty", "24a-media-video", "24b-media-stills", "24c-media-reduce-motion", "24d-media-loading", "24e-media-none":
            // On a push stack, so Back shows as in the real flow (QA 14).
            if let ex = Fixtures.exercise {
                // Initial path: the detail is already on top, with no push
                // animation for the capture to catch mid-way (24e was blank).
                NavigationStack(path: .constant([ex.id])) {
                    Theme.Colors.bgCanvas
                        .navigationTitle(Date().formatted(.dateTime.weekday(.wide)))
                        .navigationDestination(for: UUID.self) { _ in ExerciseDetailView(exercise: ex) }
                }
            }
        case "10-history", "12-history-empty": RootView(initialTab: .history)
        case "11-settings": SettingsView()
        case _ where Fixtures.isPicker: ExercisePicker(mode: .add) { _ in }
        default: RootView()
        }
    }
}
#endif
