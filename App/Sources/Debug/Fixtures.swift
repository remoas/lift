#if DEBUG
import SwiftUI
import SwiftData
import LiftCore

/// Screenshot fixtures for the 27 design frames (AC 24). DEBUG builds only:
/// selected with `-LiftFixture <frame>`, backed by an in-memory store and a
/// throwaway defaults suite, so the shipped app never contains demo data.
enum Fixtures {
    static let frames = [
        "01-today", "02a-welcome", "02b-days", "02c-build-empty", "02d-setup-picker", "02e-build-filled",
        "03-workout", "04-rest", "05-set-editor", "06-pr-banner", "07-finish", "08-exercise", "09-routines",
        "10-history", "11-settings", "12-history-empty", "13-first-workout", "14-health-error", "15-restoring",
        "16-exercise-empty", "17-choose-workout", "18-exercise-picker", "19-reorder", "20-finish-changed",
        "21-finish-blank", "22-today-day-empty", "23-routines-empty",
        "24a-media-video", "24b-media-stills", "24c-media-reduce-motion", "24d-media-loading", "24e-media-none",
        "25-finish-sets-left", "26-discard-toast", "27-finish-save-routine",
    ]

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
        guard let i = args.firstIndex(of: "-LiftFixture"), i + 1 < args.count, frames.contains(args[i + 1]) else { return nil }
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
        settings.daysPerWeek = 6
        let container = LiftStore.makeContainer(inMemory: true)
        let b = Builder(context: container.mainContext, settings: settings)
        LiftStore.ensureRoutines(b.context)

        switch frame {
        case "02a-welcome", "02b-days", "02c-build-empty", "02d-setup-picker":
            settings.hasOnboarded = false
        case "02e-build-filled":
            settings.hasOnboarded = false
            b.fill("Push")
        case "23-routines-empty":
            settings.hasOnboarded = true
        case "15-restoring":
            settings.hasOnboarded = true
        case "12-history-empty":
            settings.hasOnboarded = true
            b.fillAll()
        case "13-first-workout":
            settings.hasOnboarded = true
            b.fillAll()
            workout = b.active("Push", doneSets: 1)
        case "22-today-day-empty":
            settings.hasOnboarded = true
            b.fill("Pull"); b.fill("Legs")
            b.history(weeks: 2, thisWeek: ["Pull", "Legs"], skip: ["Push"])
        default:
            settings.hasOnboarded = true
            b.fillAll()
            b.history(weeks: 3, thisWeek: ["Pull", "Legs"])
            switch frame {
            case "03-workout", "04-rest", "05-set-editor", "19-reorder":
                workout = b.active("Push", doneSets: 2)
            case "06-pr-banner":
                workout = b.active("Push", doneSets: 2, topSet: (205, 5))
            case "07-finish":
                workout = b.finishedToday("Push", topSet: (205, 5))
            case "20-finish-changed":
                workout = b.finishedToday("Push", topSet: nil, swap: ("incline-dumbbell-press", "cable-crossover"))
            case "21-finish-blank", "27-finish-save-routine":
                workout = b.finishedToday(nil, topSet: nil)
            case "25-finish-sets-left":
                workout = b.active("Push", doneSets: 11)
            case "26-discard-toast":
                workout = b.active("Pull", doneSets: 2)
            case "24a-media-video":
                exercise = b.exercise("barbell-shoulder-press")
            case "24b-media-stills", "24c-media-reduce-motion", "24d-media-loading":
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

    @MainActor
    struct Builder {
        let context: ModelContext
        let settings: AppSettings

        static let plan: [String: [(String, Int, ClosedRange<Int>, Double)]] = [
            "Push": [("bench-press", 3, 6...8, 185), ("barbell-shoulder-press", 3, 6...8, 115), ("incline-dumbbell-press", 3, 8...12, 60),
                     ("side-lateral-raise", 3, 12...15, 20), ("triceps-pushdown", 3, 10...12, 50)],
            "Pull": [("deadlift", 3, 3...5, 315), ("pullups", 3, 6...10, 0), ("bent-over-row", 3, 6...10, 155), ("face-pull", 3, 12...15, 40), ("barbell-curl", 3, 8...12, 70)],
            "Legs": [("barbell-squat", 3, 5...8, 245), ("romanian-deadlift", 3, 6...10, 205), ("leg-press", 3, 8...12, 360), ("leg-curl", 3, 10...12, 90), ("calf-raises", 3, 10...15, 180)],
        ]

        func routine(_ name: String) -> Routine? {
            (try? context.fetch(FetchDescriptor<Routine>()))?.first { $0.name == name }
        }

        func exercise(_ id: String) -> Exercise? {
            ExerciseLibrary.bundled.exercise(id).map { LiftStore.exercise(for: $0, context: context) }
        }

        func fill(_ day: String) {
            guard let r = routine(day) else { return }
            for (i, p) in (Self.plan[day] ?? []).enumerated() {
                guard let ex = exercise(p.0) else { continue }
                let item = RoutineItem(order: i, targetSets: p.1, repRange: p.2, exercise: ex)
                context.insert(item)
                item.routine = r
            }
        }

        func fillAll() { ["Push", "Pull", "Legs"].forEach(fill) }

        /// Finished sessions: `weeks` past weeks of PPL ×2, then `thisWeek`.
        /// Weights climb 5 lb a week so the chart and bests have a story.
        func history(weeks: Int, thisWeek: [String], skip: Set<String> = []) {
            let cal = Calendar.current
            let weekStart = Week.start(of: Date())
            for w in stride(from: weeks, through: 1, by: -1) {
                let start = cal.date(byAdding: .day, value: -7 * w, to: weekStart)!
                for (d, day) in ["Push", "Pull", "Legs", "Push", "Pull", "Legs"].enumerated() where !skip.contains(day) {
                    let date = cal.date(byAdding: .hour, value: 24 * d + 7, to: start)!
                    session(day, at: date, bump: Double(-5 * w))
                }
            }
            let now = Date()
            for (i, day) in thisWeek.enumerated() {
                // Earlier this week, but never before Monday 00:00.
                let back = Double(thisWeek.count - i) * 86_400 * 0.9
                let date = max(weekStart.addingTimeInterval(3_600 * Double(i + 1)), now.addingTimeInterval(-back))
                session(day, at: date, bump: 0)
            }
        }

        @discardableResult
        func session(_ day: String?, at date: Date, bump: Double, topSet: (Double, Int)? = nil, finished: Bool = true, doneSets: Int = .max) -> Workout {
            let r = day.flatMap(routine)
            let w = Workout(routineID: r?.id, routineName: r?.name ?? "Workout", startedAt: date)
            context.insert(w)
            let plan = day.flatMap { Self.plan[$0] } ?? [("bench-press", 3, 6...8, 185), ("dumbbell-row", 3, 8...12, 70), ("hammer-curls-2", 2, 10...12, 35)]
            var logged = 0
            for (e, p) in plan.enumerated() {
                guard let ex = exercise(p.0) else { continue }
                let reps = [p.2.upperBound, p.2.upperBound, max(p.2.upperBound - 1, p.2.lowerBound)]
                for s in 0..<p.1 {
                    var weight = p.3 > 0 ? p.3 + bump : 0
                    var r = reps[min(s, 2)]
                    if e == 0, s == 1, let top = topSet { weight = top.0; r = top.1 }
                    let set = SetEntry(order: s, exerciseOrder: e, weight: max(weight, 0), unit: .lb, reps: r, exercise: ex)
                    set.repMin = p.2.lowerBound; set.repMax = p.2.upperBound
                    set.restSeconds = p.2.upperBound <= 8 ? 150 : 90
                    if logged < doneSets {
                        set.isDone = true
                        set.doneAt = date.addingTimeInterval(Double(logged + 1) * 150)
                        logged += 1
                    }
                    context.insert(set)
                    set.workout = w
                }
            }
            if finished { w.endedAt = date.addingTimeInterval(52 * 60) }
            return w
        }

        func active(_ day: String, doneSets: Int, topSet: (Double, Int)? = nil) -> Workout {
            let started = Date().addingTimeInterval(-18 * 60 - 42)
            let w = LiftStore.start(routine(day), globalUnit: .lb, at: started, context: context)
            let sets = w.groups.flatMap(\.sets)
            for (i, s) in sets.prefix(doneSets).enumerated() {
                if i == 1, let topSet { s.weight = topSet.0; s.reps = topSet.1 }
                if s.weight == 0, s.exercise?.equipment.allowsZeroWeight == false { s.weight = 135 }
                s.isDone = true
                s.doneAt = started.addingTimeInterval(Double(i + 1) * 180)
            }
            return w
        }

        func finishedToday(_ day: String?, topSet: (Double, Int)?, swap: (String, String)? = nil) -> Workout {
            let w = session(day, at: Date().addingTimeInterval(-55 * 60), bump: 5, topSet: topSet, finished: false)
            if let swap, let old = exercise(swap.0), let new = exercise(swap.1) {
                LiftStore.swap(old, for: new, in: w, globalUnit: .lb, context: context)
                for s in w.allSets where s.exercise === new { s.isDone = true; s.doneAt = Date().addingTimeInterval(-20 * 60); if s.weight == 0 { s.weight = 30 } }
            }
            // Left open: the summary is shown before Done, like the real flow.
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
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var finished: [Workout]

    var body: some View {
        content
            .overlay { ToastOverlay() }
            .onAppear {
                if frame == "15-restoring" { cloud.debugSimulateFirstRestore() }
                // Health is written after Done now, so its error is a toast on Today.
                if frame == "26-discard-toast" {
                    // Same call RootView makes on Discard: hidden, then deleted when the toast ends.
                    toasts.show("Pull discarded", undo: {}, onCommit: {})
                }
                if frame == "14-health-error" { toasts.show("Couldn't save to Apple Health. Your workout is safe in Lift.") }
            }
    }

    @ViewBuilder private var content: some View {
        switch frame {
        case "02a-welcome": SetupFlow(onFinish: {})
        case "02b-days": SetupFlow(onFinish: {}, startAt: [.days])
        case "02c-build-empty", "02d-setup-picker", "02e-build-filled": SetupFlow(onFinish: {}, startAt: [.days, .build(0)])
        case "03-workout", "04-rest", "05-set-editor", "06-pr-banner", "13-first-workout", "19-reorder":
            if let w = Fixtures.workout { ActiveWorkoutView(workout: w, onClose: {}, onFinished: { _ in }) }
        case "07-finish", "20-finish-changed", "21-finish-blank", "25-finish-sets-left":
            if let w = Fixtures.workout { FinishView(workout: w, onDone: {}) }
        case "27-finish-save-routine":
            if let w = Fixtures.workout { FinishView(workout: w, onDone: {}, startWithSaveAsRoutine: true) }
        case "26-discard-toast":
            RootView()
        case "08-exercise", "16-exercise-empty", "24a-media-video", "24b-media-stills", "24c-media-reduce-motion", "24d-media-loading", "24e-media-none":
            if let ex = Fixtures.exercise { NavigationStack { ExerciseDetailView(exercise: ex) } }
        case "09-routines", "23-routines-empty": RootView(initialTab: .routines)
        case "10-history", "12-history-empty": RootView(initialTab: .history)
        case "11-settings": SettingsView()
        case "17-choose-workout":
            RootView().sheet(isPresented: .constant(true)) {
                ChooseWorkoutSheet(routines: routines, finished: finished,
                                   next: LiftStore.nextRoutine(routines: routines, finished: finished)) { _ in }
            }
        case "18-exercise-picker": ExercisePicker(mode: .add) { _ in }
        default: RootView()
        }
    }
}
#endif
