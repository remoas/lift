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
        var counting = false
        var countedReps: Int?
    }

    static let names = ["w01-empty", "w02-exercise", "w03-target-hit", "w04-counting", "w05-rest", "w06-add", "w07-end", "w08-finish"]

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
                                unit: .lb, bodyweight: e?.equipment == .bodyweight, repGoal: 10, restSeconds: rest, last: last, lastDate: monday, sets: sets)
        }
        let benchLast = [SetTarget(weight: 185, reps: 8), SetTarget(weight: 185, reps: 7), SetTarget(weight: 185, reps: 6)]
        var bench = ex("bench-press", "Bench Press", last: benchLast, rest: 150)
        let row = ex("bent-over-barbell-row", "Barbell Row", last: [SetTarget(weight: 135, reps: 10), SetTarget(weight: 135, reps: 10)], rest: 120)
        let pull = ex("pullups", "Pull-Up", last: [SetTarget(weight: 0, reps: 9)], rest: 120)
        var live = LiveWorkout(startedAt: now.addingTimeInterval(-24 * 60), exercises: [bench, row], unit: .lb)
        live.recents = [pull, ex("barbell-squat", "Squat", last: [SetTarget(weight: 225, reps: 5)], rest: 180)]
        live.healthEnabled = true
        let hit = LiveSet(weight: 185, unit: .lb, reps: 9, isDone: true, doneAt: now.addingTimeInterval(-60), source: "watch")
        switch name {
        case "w01-empty":
            return Frame(live: LiveWorkout(exercises: [], recents: live.recents))
        case "w03-target-hit":
            bench.sets = [hit]
            live.exercises[0] = bench
            return Frame(live: live)
        case "w04-counting":
            return Frame(live: live, counting: true, countedReps: 7)
        case "w05-rest":
            bench.sets = [hit]
            live.exercises[0] = bench
            live.rest = RestState(seconds: 150, from: now.addingTimeInterval(-48), setID: hit.id, exercise: bench.name, next: "185 × 9", origin: .watch)
            return Frame(live: live)
        case "w06-add":
            return Frame(live: live, adding: true)
        case "w07-end":
            bench.sets = [hit, LiveSet(weight: 185, unit: .lb, reps: 8, isDone: true, doneAt: now, source: "watch")]
            live.exercises[0] = bench
            live.exercises[1].sets = [LiveSet(weight: 135, unit: .lb, reps: 10, isDone: true, doneAt: now, source: "phone")]
            return Frame(live: live, page: 2)
        case "w08-finish":
            bench.sets = [hit]
            live.exercises[0] = bench
            live.exercises[1].sets = [LiveSet(weight: 135, unit: .lb, reps: 10, isDone: true, doneAt: now, source: "phone")]
            return Frame(live: live, page: 2, finishing: true)
        default:
            return Frame(live: live)
        }
    }
}
