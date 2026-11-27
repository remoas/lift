import Foundation
import SwiftData
import LiftCore

/// Converts between the phone's SwiftData store and the shared live workout
/// the watch sees, and applies the watch's commands. The phone's store is the
/// only database; every command is idempotent (set UUIDs, applied-id list).
@MainActor
enum LiveBridge {
    static let recentsLimit = 25

    // MARK: Phone → watch

    static func snapshot(_ context: ModelContext, unit: WeightUnit, restDefault: Int, healthEnabled: Bool?, rest: RestState?, applied: [UUID]) -> LiveWorkout {
        let open = currentOpen(context) ?? LiftStore.openLog(context).open
        let exercises = open.groups.map { live($0.exercise, sets: $0.sets, workout: open, unit: unit, restDefault: restDefault) }
        let inToday = Set(exercises.map(\.id))
        let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let used: [(Exercise, Date)] = all.compactMap { ex in
            guard let d = (ex.sets ?? []).filter({ $0.isDone && $0.workout?.endedAt != nil }).compactMap(\.doneAt).max() else { return nil }
            return (ex, d)
        }
        let recents = used.sorted { $0.1 > $1.1 }.prefix(recentsLimit)
            .filter { !inToday.contains($0.0.id) }
            .map { live($0.0, sets: [], workout: open, unit: unit, restDefault: restDefault) }
        let last = LiftStore.finishedWorkouts(context).first
        var w = LiveWorkout(workoutID: open.id, startedAt: open.startedAt, endedAt: open.endedAt, exercises: exercises,
                            rest: rest, recents: Array(recents), unit: unit, restDefault: restDefault, applied: applied,
                            watchSessionActive: open.device == "Watch")
        w.lastFinishedID = last?.id
        w.lastFinishedAt = last?.endedAt
        w.healthEnabled = healthEnabled
        return w
    }

    /// Today's open log without side effects (no auto-finish, no save).
    static func currentOpen(_ context: ModelContext) -> Workout? {
        let d = FetchDescriptor<Workout>(predicate: #Predicate { $0.endedAt == nil }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return ((try? context.fetch(d)) ?? []).first { !$0.isBackLog }
    }

    static func live(_ ex: Exercise, sets: [SetEntry], workout: Workout?, unit global: WeightUnit, restDefault: Int) -> LiveExercise {
        let unit = ex.unit(global: global)
        let beat = LiftStore.beatIt(for: ex, excluding: workout, unit: unit)
        let earlier = LiftStore.history(for: ex).filter { $0.workout !== workout }.map(\.snapshot)
        let name = ex.variant.isEmpty || ex.name.localizedCaseInsensitiveContains(ex.variant) ? ex.name : "\(ex.name) (\(ex.variant))"
        return LiveExercise(id: ex.id, libraryID: ex.libraryID, name: name, unit: unit, step: ex.step(for: unit),
                            bodyweight: ex.loadKind == .bodyweight, repGoal: ex.repGoal,
                            restSeconds: ex.restSec ?? restDefault, last: beat.last, lastDate: beat.lastDate,
                            sets: sets.map { LiveSet(id: $0.id, weight: $0.weight, unit: $0.unit, reps: $0.reps, kind: $0.kind,
                                                     isDone: $0.isDone, doneAt: $0.doneAt, source: $0.source) },
                            equipment: ex.equipment, records: RecordFront.front(earlier))
    }

    // MARK: Watch → phone

    enum Effect {
        case none
        case rest(RestState?)
        case finished(Workout)
        case discarded(Workout)
        case watchSession(Bool)
        case healthFailed(Workout)
    }

    /// The workout a command is for. A watch that started before it heard from
    /// the phone uses its own id: an empty open log adopts it, otherwise its
    /// sets join today's log.
    static func workout(for id: UUID, _ context: ModelContext) -> Workout {
        if let w = try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })).first { return w }
        let open = LiftStore.openLog(context).open
        if open.doneSets.isEmpty { open.id = id }
        return open
    }

    static func exercise(_ id: UUID, libraryID: String?, _ context: ModelContext) -> Exercise? {
        if let ex = try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first { return ex }
        let lib = ExerciseLibrary.bundled.exercises
        guard let entry = libraryID.flatMap({ l in lib.first { $0.id == l } }) ?? lib.first(where: { $0.rowID == id }) else { return nil }
        return LiftStore.exercise(for: entry, context: context)
    }

    static func apply(_ env: LiveEnvelope, _ context: ModelContext, unit: WeightUnit, restDefault: Int) -> Effect {
        let w = workout(for: env.workoutID, context)
        defer { _ = LiftStore.save(context) }
        switch env.command {
        case .logSet(let exID, let s):
            guard let ex = exercise(exID, libraryID: nil, context) else { return .none }
            let sid = s.id
            let entry: SetEntry
            if let existing = try? context.fetch(FetchDescriptor<SetEntry>(predicate: #Predicate { $0.id == sid })).first {
                entry = existing
            } else {
                let mine = w.allSets.filter { $0.exercise === ex }
                let order = (mine.map(\.order).max() ?? -1) + 1
                let exOrder = mine.first?.exerciseOrder ?? (w.allSets.map(\.exerciseOrder).max() ?? -1) + 1
                entry = SetEntry(order: order, exerciseOrder: exOrder, kind: s.kind, weight: s.weight, unit: s.unit, reps: s.reps, exercise: ex)
                entry.id = sid
                entry.repMin = ex.repMin
                entry.repMax = ex.repMax
                entry.restSeconds = ex.restSec ?? restDefault
                context.insert(entry)
                entry.workout = w
            }
            if !w.isBackLog, w.doneSets.isEmpty { w.startedAt = s.doneAt ?? env.sentAt }
            entry.weight = s.weight
            entry.unit = s.unit
            entry.reps = s.reps
            entry.kind = s.kind
            entry.isDone = true
            entry.doneAt = s.doneAt ?? env.sentAt
            entry.source = "watch"
            // The phone's one prefill rule (Ben 2:16pm), same as a phone log.
            LiftStore.prefill(ex, in: w, globalUnit: unit)
            return .none
        case .unlogSet(let sid):
            if let set = try? context.fetch(FetchDescriptor<SetEntry>(predicate: #Predicate { $0.id == sid })).first {
                set.isDone = false
                set.doneAt = nil
                if let ex = set.exercise { LiftStore.prefill(ex, in: w, globalUnit: unit) }
            }
            return .none
        case .addExercise(let le):
            guard let ex = exercise(le.id, libraryID: le.libraryID, context) else { return .none }
            if !w.allSets.contains(where: { $0.exercise === ex }) {
                LiftStore.addExercise(ex, to: w, globalUnit: unit, restDefault: restDefault, context: context)
            }
            return .none
        case .setRest(let exID, let seconds):
            guard let ex = exercise(exID, libraryID: nil, context) else { return .none }
            ex.restSec = seconds
            for set in w.allSets where set.exercise === ex && !set.isDone && set.kind != .warmup { set.restSeconds = seconds }
            return .none
        case .rest(let r):
            return .rest(r)
        case .finish(let at):
            guard w.isActive else { return .none }
            if w.doneSets.isEmpty { return .none }
            LiftStore.finish(w, at: at, context: context)
            return .finished(w)
        case .discard:
            return w.isActive ? .discarded(w) : .none
        case .watchSession(let active):
            if active { w.device = "Watch" }
            return .watchSession(active)
        case .healthSaved(let hk):
            if let hk { w.healthKitID = hk.uuidString; return .none }
            return .healthFailed(w)
        }
    }
}
