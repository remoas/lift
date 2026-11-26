import Foundation
import LiftCore

/// Screenshot frames (DEBUG builds only, launched with -LiftFixture <name>).
/// In-memory data for review captures; release builds never contain these.
enum WatchFixtures {
    struct Frame {
        var live: LiveWorkout
        var page = 0
        var adding = false
        var finishing = false
        var restPicker = false
        var countedReps: Int?
        var restUp = false
        var newBest: String?
        var skipToast = false
        var dimmed = false
        var unreachable = false
        var healthOff = false
        var focusWeight = false
    }

    /// CDO's frames (design/watch/w01–w14).
    static let names = ["w01-empty", "w02-exercise", "w03-counting", "w04-counting-off", "w05-first-time", "w06-rest",
                        "w07-rest-up", "w08-target-hit", "w09-add", "w10-finish", "w11-always-on", "w12-unreachable",
                        "w13-skip-toast", "w14-rest-picker",
                        // CDO QA 1, item 17: states that had no frame.
                        "w15-target-hit-quiet", "w16-health-off", "w17-rest-off", "w18-finish-sets-left",
                        "w19-crown-focus", "w20-after-miss"]

    #if DEBUG
    static let requested: Frame? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-LiftFixture"), i + 1 < args.count else { return nil }
        return frame(args[i + 1])
    }()
    #else
    static let requested: Frame? = nil
    #endif

    static func frame(_ name: String, now: Date = Date()) -> Frame {
        let monday = Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now
        func lib(_ id: String) -> LibraryExercise? { ExerciseLibrary.bundled.exercises.first { $0.id == id } }
        func ex(_ libID: String, _ fallback: String, last: [SetTarget], rest: Int, sets: [LiveSet] = []) -> LiveExercise {
            let e = lib(libID)
            return LiveExercise(id: e?.rowID ?? UUID(), libraryID: e?.id, name: e.map { WatchText.displayName($0.name, variant: $0.variant) } ?? fallback,
                                unit: .lb, bodyweight: e?.equipment == .bodyweight, repGoal: 10, restSeconds: rest, last: last, lastDate: last.isEmpty ? nil : monday, sets: sets, equipment: e?.equipment ?? .other)
        }
        let benchLast = [SetTarget(weight: 185, reps: 8), SetTarget(weight: 185, reps: 7), SetTarget(weight: 185, reps: 6)]
        var bench = ex("bench-press", "Bench Press", last: benchLast, rest: 150)
        let row = ex("bent-over-barbell-row", "Barbell Row", last: [SetTarget(weight: 135, reps: 10), SetTarget(weight: 135, reps: 10)], rest: 120)
        let pull = ex("pullups", "Pull-Up", last: [SetTarget(weight: 0, reps: 9)], rest: 120)
        var live = LiveWorkout(startedAt: now.addingTimeInterval(-24 * 60), exercises: [bench, row], unit: .lb)
        live.recents = [pull, ex("barbell-squat", "Squat", last: [SetTarget(weight: 225, reps: 5)], rest: 180)]
        live.healthEnabled = true
        let hit = LiveSet(weight: 185, unit: .lb, reps: 9, isDone: true, doneAt: now.addingTimeInterval(-60), source: "watch")
        let legPress = ex("leg-press", "Leg Press", last: [SetTarget(weight: 320, reps: 9)], rest: 120)
        let facePull = ex("face-pull", "Face Pull", last: [], rest: 90)
        func resting(_ w: inout LiveWorkout) {
            bench.sets = [hit]
            w.exercises[0] = bench
            w.rest = RestState(seconds: 150, from: now.addingTimeInterval(-48), setID: hit.id, exercise: bench.name, next: "185 × 9", origin: .watch)
        }
        switch name {
        case "w01-empty":
            return Frame(live: LiveWorkout(exercises: [], recents: live.recents))
        case "w03-counting":
            return Frame(live: live, countedReps: 6)
        case "w04-counting-off":
            live.exercises.insert(legPress, at: 0)
            return Frame(live: live)
        case "w05-first-time":
            live.exercises.insert(facePull, at: 0)
            return Frame(live: live)
        case "w06-rest":
            resting(&live)
            return Frame(live: live)
        case "w07-rest-up":
            bench.sets = [hit]
            live.exercises[0] = bench
            return Frame(live: live, restUp: true)
        case "w08-target-hit":
            bench.sets = [LiveSet(weight: 205, unit: .lb, reps: 5, isDone: true, doneAt: now, source: "watch")]
            live.exercises[0] = bench
            return Frame(live: live, newBest: "205 × 5")
        case "w09-add":
            return Frame(live: live, adding: true)
        case "w10-finish":
            bench.sets = [hit]
            live.exercises[0] = bench
            live.exercises[1].sets = [LiveSet(weight: 115, unit: .lb, reps: 10, isDone: true, doneAt: now, source: "phone")]
            live.exercises[1].last = [SetTarget(weight: 115, reps: 9)]
            return Frame(live: live, finishing: true)
        case "w11-always-on":
            resting(&live)
            return Frame(live: live, dimmed: true)
        case "w12-unreachable":
            return Frame(live: live, unreachable: true)
        case "w13-skip-toast":
            return Frame(live: live, skipToast: true)
        case "w14-rest-picker":
            return Frame(live: live, restPicker: true)
        case "w15-target-hit-quiet":
            bench.sets = [hit]
            live.exercises[0] = bench
            return Frame(live: live)
        case "w16-health-off":
            return Frame(live: live, healthOff: true)
        case "w17-rest-off":
            bench.restSeconds = 0
            live.exercises[0] = bench
            return Frame(live: live, restPicker: true)
        case "w18-finish-sets-left":
            bench.sets = [hit, LiveSet(weight: 185, unit: .lb, reps: 9, isDone: false, doneAt: nil, source: "phone")]
            live.exercises[0] = bench
            return Frame(live: live, finishing: true)
        case "w19-crown-focus":
            return Frame(live: live, focusWeight: true)
        case "w20-after-miss":
            // Ben 2:16pm: set 2 prefills with the 185 × 7 just logged; Beat it stays 185 × 9.
            bench.sets = [LiveSet(weight: 185, unit: .lb, reps: 7, isDone: true, doneAt: now.addingTimeInterval(-150), source: "watch")]
            live.exercises[0] = bench
            return Frame(live: live)
        default:
            return Frame(live: live)
        }
    }
}
