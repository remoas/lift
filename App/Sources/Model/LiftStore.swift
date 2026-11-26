import Foundation
import SwiftData
import LiftCore

/// Data operations shared by the screens. Every write saves locally at once;
/// iCloud sync happens in the background.
@MainActor
enum LiftStore {
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(LiftSchema.models)
        if inMemory {
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        // .automatic uses the CloudKit private database when the iCloud
        // entitlement is present (signed device builds) and stays local otherwise.
        let cloud = ModelConfiguration("Lift", schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: cloud) { return container }
        let local = ModelConfiguration("Lift", schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Could not open the Lift store: \(error)")
        }
    }

    static func save(_ context: ModelContext) -> Bool {
        do { try context.save(); return true } catch { return false }
    }

    // MARK: Library and routines (nothing is seeded into routines, AC 34)

    /// Creates empty Push, Pull and Legs once. Fixed IDs, so a second device
    /// never ends up with duplicates.
    static func ensureRoutines(_ context: ModelContext) {
        let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        guard routines.isEmpty else { return }
        for (i, r) in Defaults.routineNames.enumerated() {
            context.insert(Routine(id: r.id, name: r.name, order: i, isSeeded: true))
        }
        _ = save(context)
    }

    /// Applies a newer bundled seed to library rows already in use. Custom
    /// exercises and history are never touched.
    static func mergeLibrary(_ library: ExerciseLibrary = .bundled, context: ModelContext) {
        let key = "lift.library.appliedVersion"
        let applied = UserDefaults.standard.integer(forKey: key)
        guard library.version > applied else { return }
        let rows = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).filter { !$0.isCustom && $0.libraryID != nil }
        let byLibID = Dictionary(rows.map { ($0.libraryID!, $0) }, uniquingKeysWith: { a, _ in a })
        for u in LibraryMerge.updates(seed: library, appliedVersion: applied, existingLibraryIDs: Set(byLibID.keys)) {
            byLibID[u.libraryID]?.apply(library: u.entry)
        }
        if save(context) { UserDefaults.standard.set(library.version, forKey: key) }
    }

    /// The database row for a library pick, created the first time it's used.
    static func exercise(for entry: LibraryExercise, context: ModelContext) -> Exercise {
        let id = entry.rowID
        if let existing = try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first {
            return existing
        }
        let ex = Exercise(library: entry)
        if let rest = entry.restSeconds { ex.restOverride = rest }
        context.insert(ex)
        return ex
    }

    enum CreateError: Error { case duplicate(String) }

    /// A custom exercise, with the same tags as library ones. Name + variant
    /// must be unique (case- and diacritic-insensitive).
    static func createExercise(name: String, variant: String, primary: [MuscleGroup], secondary: [MuscleGroup], equipment: Equipment, unit: WeightUnit?, repRange: ClosedRange<Int>, rest: Int?, context: ModelContext) throws -> Exercise {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Search.fold(trimmed + "|" + v)
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let taken = existing.map { ($0.name, $0.variant) } + ExerciseLibrary.bundled.exercises.map { ($0.name, $0.variant) }
        if let match = taken.first(where: { Search.fold($0.0 + "|" + $0.1) == key }) {
            throw CreateError.duplicate(match.1.isEmpty ? match.0 : "\(match.0) (\(match.1))")
        }
        let ex = Exercise(name: trimmed, primary: primary, secondary: secondary, equipment: equipment, variant: v, repRange: repRange, isCustom: true)
        ex.unitOverride = unit
        ex.restOverride = rest
        context.insert(ex)
        _ = save(context)
        return ex
    }

    /// Removes duplicate rows that can appear when two devices create the same
    /// library exercise or routine before syncing.
    static func dedupe(_ context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        var keepers: [UUID: Exercise] = [:]
        for ex in exercises {
            if let keeper = keepers[ex.id] {
                for set in ex.sets ?? [] { set.exercise = keeper }
                for item in ex.routineItems ?? [] { item.exercise = keeper }
                context.delete(ex)
            } else {
                keepers[ex.id] = ex
            }
        }
        let routines = (try? context.fetch(FetchDescriptor<Routine>())) ?? []
        var seen: [UUID: Routine] = [:]
        for r in routines {
            if let keeper = seen[r.id] {
                if (keeper.items ?? []).isEmpty { for item in r.items ?? [] { item.routine = keeper } }
                context.delete(r)
            } else {
                seen[r.id] = r
            }
        }
        _ = save(context)
    }

    // MARK: Queries

    static func finishedWorkouts(_ context: ModelContext) -> [Workout] {
        let d = FetchDescriptor<Workout>(predicate: #Predicate { $0.endedAt != nil }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return (try? context.fetch(d)) ?? []
    }

    /// Done sets for one exercise across finished workouts plus `active`, keyed
    /// by exercise only (never by routine slot), oldest first.
    static func history(for exercise: Exercise, including active: Workout? = nil) -> [SetEntry] {
        (exercise.sets ?? [])
            .filter { $0.isDone && $0.workout != nil && ($0.workout?.endedAt != nil || $0.workout === active) }
            .sorted { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) }
    }

    /// Sets from the most recent finished workout that included this exercise.
    static func lastSessionSets(for exercise: Exercise, excluding workout: Workout? = nil) -> [SetEntry] {
        let sets = (exercise.sets ?? []).filter { $0.isDone && $0.workout?.endedAt != nil && $0.workout !== workout }
        guard let latest = sets.compactMap(\.workout).max(by: { $0.startedAt < $1.startedAt }) else { return [] }
        return sets.filter { $0.workout === latest }.sorted { $0.order < $1.order }
    }

    /// Next-in-line rotation: after the routine the last routine-based workout
    /// was started from. Blank workouts don't advance it.
    static func nextRoutine(routines: [Routine], finished: [Workout]) -> Routine? {
        let ordered = routines.sorted { $0.order < $1.order }
        let lastID = finished.first(where: { $0.routineID != nil })?.routineID
        guard let id = Rotation.next(order: ordered.map(\.id), lastCompleted: lastID) else { return nil }
        return ordered.first { $0.id == id }
    }

    // MARK: Starting

    /// A workout slot's plan: set count, rep range and rest.
    struct Slot {
        var sets: Int
        var repRange: ClosedRange<Int>
        var rest: Int
    }

    static func defaultSlot(for exercise: Exercise, sets: Int? = nil, restDefault: Int) -> Slot {
        let lastCount = (exercise.sets ?? []).isEmpty ? nil : lastSessionSets(for: exercise).count
        return Slot(sets: sets ?? lastCount ?? 3, repRange: exercise.repRange, rest: exercise.restOverride ?? restDefault)
    }

    /// Starts a workout as a day-of copy of a routine. Editing it never touches the routine.
    @discardableResult
    static func start(_ routine: Routine?, globalUnit: WeightUnit, at date: Date = Date(), backLog: Bool = false, context: ModelContext) -> Workout {
        let workout = Workout(routineID: routine?.id, routineName: routine?.name ?? "Workout", startedAt: date)
        workout.isBackLog = backLog
        context.insert(workout)
        for (i, item) in (routine?.sortedItems ?? []).enumerated() {
            guard let ex = item.exercise else { continue }
            let slot = Slot(sets: item.targetSets, repRange: item.repRange, rest: ex.restOverride ?? routine?.restSeconds ?? 120)
            insertPrefilledSets(for: ex, slot: slot, exerciseOrder: i, into: workout, globalUnit: globalUnit, context: context)
        }
        _ = save(context)
        return workout
    }

    /// Prefills from the same set number the last time this exercise was done
    /// (any workout). First time: no weight and reps at the top of the range.
    static func insertPrefilledSets(for exercise: Exercise, slot: Slot, exerciseOrder: Int, into workout: Workout, globalUnit: WeightUnit, context: ModelContext) {
        let unit = exercise.unit(global: globalUnit)
        let last = lastSessionSets(for: exercise, excluding: workout)
        for i in 0..<max(slot.sets, 1) {
            let prev = i < last.count ? last[i] : last.last
            let weight = prev.map { UnitMath.convertLoadable($0.weight, from: $0.unit, to: unit, step: exercise.step(for: unit)) } ?? 0
            let set = SetEntry(order: i, exerciseOrder: exerciseOrder, kind: prev?.kind ?? .working, weight: weight, unit: unit, reps: prev?.reps ?? slot.repRange.upperBound, exercise: exercise)
            set.repMin = slot.repRange.lowerBound
            set.repMax = slot.repRange.upperBound
            set.restSeconds = slot.rest
            context.insert(set)
            set.workout = workout
        }
    }

    // MARK: Day-of edits (this workout only)

    static func exerciseOrder(of exercise: Exercise, in workout: Workout) -> Int? {
        workout.allSets.first(where: { $0.exercise === exercise })?.exerciseOrder
    }

    private static func renumber(_ workout: Workout) {
        for (i, group) in workout.groups.enumerated() {
            for set in group.sets { set.exerciseOrder = i }
        }
    }

    static func addExercise(_ exercise: Exercise, to workout: Workout, globalUnit: WeightUnit, restDefault: Int, context: ModelContext) {
        if workout.allSets.contains(where: { $0.exercise === exercise }) {
            _ = addSet(to: exercise, in: workout, context: context)
            return
        }
        let order = (workout.allSets.map(\.exerciseOrder).max() ?? -1) + 1
        insertPrefilledSets(for: exercise, slot: defaultSlot(for: exercise, restDefault: restDefault), exerciseOrder: order, into: workout, globalUnit: globalUnit, context: context)
        _ = save(context)
    }

    /// Swaps in place, keeping the slot's set count, rep range and rest. Ticked
    /// sets stay logged to the old exercise; only the unticked ones move.
    static func swap(_ old: Exercise, for new: Exercise, in workout: Workout, globalUnit: WeightUnit, context: ModelContext) {
        guard let slotIndex = exerciseOrder(of: old, in: workout) else { return }
        let oldSets = workout.allSets.filter { $0.exercise === old }
        let template = oldSets.first
        let unticked = oldSets.filter { !$0.isDone }
        let slot = Slot(sets: max(unticked.count, 1),
                        repRange: (template?.repMin ?? new.repMin)...(max(template?.repMax ?? new.repMax, template?.repMin ?? new.repMin)),
                        rest: template?.restSeconds ?? 120)
        for set in unticked { context.delete(set) }
        let keepsLogged = oldSets.count > unticked.count
        for set in workout.allSets where set.exerciseOrder > slotIndex { set.exerciseOrder += 1 }
        insertPrefilledSets(for: new, slot: slot, exerciseOrder: keepsLogged ? slotIndex + 1 : slotIndex, into: workout, globalUnit: globalUnit, context: context)
        renumber(workout)
        _ = save(context)
    }

    /// Applies a new exercise order from Edit today.
    static func reorder(_ exercises: [Exercise], in workout: Workout, context: ModelContext) {
        for set in workout.allSets {
            if let ex = set.exercise, let k = exercises.firstIndex(where: { $0 === ex }) { set.exerciseOrder = k }
        }
        _ = save(context)
    }

    /// Everything needed to put a removed set back with its original UUID.
    struct RemovedSet {
        let id: UUID, order: Int, exerciseOrder: Int, kind: SetKind, weight: Double, unit: WeightUnit
        let reps: Int, isDone: Bool, doneAt: Date?, note: String, source: String
        let repMin: Int, repMax: Int, rest: Int
        init(_ s: SetEntry) {
            id = s.id; order = s.order; exerciseOrder = s.exerciseOrder; kind = s.kind; weight = s.weight; unit = s.unit
            reps = s.reps; isDone = s.isDone; doneAt = s.doneAt; note = s.note; source = s.source
            repMin = s.repMin; repMax = s.repMax; rest = s.restSeconds
        }

        func makeEntry(exercise: Exercise) -> SetEntry {
            let s = SetEntry(order: order, exerciseOrder: exerciseOrder, kind: kind, weight: weight, unit: unit, reps: reps, exercise: exercise)
            s.id = id
            s.isDone = isDone
            s.doneAt = doneAt
            s.note = note
            s.source = source
            s.repMin = repMin
            s.repMax = repMax
            s.restSeconds = rest
            return s
        }
    }

    /// Removes an exercise and its sets from this workout. Returns what's needed to undo.
    static func remove(_ exercise: Exercise, from workout: Workout, context: ModelContext) -> [RemovedSet] {
        let sets = workout.allSets.filter { $0.exercise === exercise }
        let removed = sets.map(RemovedSet.init)
        for s in sets { context.delete(s) }
        _ = save(context)
        return removed
    }

    /// Puts removed sets back with their original UUIDs, so records and history are unchanged.
    static func restore(_ removed: [RemovedSet], exercise: Exercise, into workout: Workout, context: ModelContext) {
        guard let slot = removed.first?.exerciseOrder else { return }
        for set in workout.allSets where set.exerciseOrder >= slot { set.exerciseOrder += 1 }
        for r in removed {
            let s = r.makeEntry(exercise: exercise)
            s.exerciseOrder = slot
            context.insert(s)
            s.workout = workout
        }
        renumber(workout)
        _ = save(context)
    }

    static func move(_ exercise: Exercise, by offset: Int, in workout: Workout, context: ModelContext) {
        var groups = workout.groups.map(\.exercise)
        guard let i = groups.firstIndex(where: { $0 === exercise }) else { return }
        let j = max(0, min(groups.count - 1, i + offset))
        guard i != j else { return }
        groups.insert(groups.remove(at: i), at: j)
        for set in workout.allSets {
            if let ex = set.exercise, let k = groups.firstIndex(where: { $0 === ex }) { set.exerciseOrder = k }
        }
        _ = save(context)
    }

    static func addSet(to exercise: Exercise, in workout: Workout, context: ModelContext) -> SetEntry {
        let existing = workout.allSets.filter { $0.exercise === exercise }.sorted { $0.order < $1.order }
        let template = existing.last
        let set = SetEntry(order: (template?.order ?? -1) + 1,
                           exerciseOrder: template?.exerciseOrder ?? (workout.allSets.map(\.exerciseOrder).max() ?? -1) + 1,
                           kind: template?.kind == .warmup ? .working : (template?.kind ?? .working),
                           weight: template?.weight ?? 0,
                           unit: template?.unit ?? .lb,
                           reps: template?.reps ?? exercise.repMax,
                           exercise: exercise)
        set.repMin = template?.repMin ?? exercise.repMin
        set.repMax = template?.repMax ?? exercise.repMax
        set.restSeconds = template?.restSeconds ?? exercise.restOverride ?? 120
        context.insert(set)
        set.workout = workout
        _ = save(context)
        return set
    }

    // MARK: Logging

    /// Records the set beats at the moment it's logged, in priority order.
    static func newRecords(for set: SetEntry, in workout: Workout) -> [RecordKind] {
        guard let ex = set.exercise else { return [] }
        let history = history(for: ex, including: workout).filter { $0 !== set }.map(\.snapshot)
        return PRDetector.newRecords(for: set.snapshot, history: history)
    }

    /// Ids of done sets in `workout` that are bests (recomputed, so unticks and
    /// edits after the fact stay honest).
    static func bestSetIDs(in workout: Workout) -> Set<UUID> {
        var ids = Set<UUID>()
        for set in workout.doneSets.sorted(by: { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) }) {
            guard let ex = set.exercise else { continue }
            let earlier = (ex.sets ?? []).filter {
                $0 !== set && $0.isDone && $0.workout != nil &&
                ($0.workout?.endedAt != nil || $0.workout === workout) &&
                (($0.workout === workout && ($0.doneAt ?? .distantPast) < (set.doneAt ?? .distantPast)) ||
                 ($0.workout !== workout && ($0.workout?.startedAt ?? .distantFuture) < workout.startedAt))
            }
            if !PRDetector.newRecords(for: set.snapshot, history: earlier.map(\.snapshot)).isEmpty { ids.insert(set.id) }
        }
        return ids
    }

    /// Drops un-ticked sets and stamps the end time.
    static func finish(_ workout: Workout, at date: Date = Date(), context: ModelContext) {
        for set in workout.allSets where !set.isDone { context.delete(set) }
        workout.endedAt = workout.isBackLog ? max(workout.startedAt.addingTimeInterval(60), workout.doneSets.compactMap(\.doneAt).max() ?? workout.startedAt) : date
        _ = save(context)
    }

    // MARK: Routine structure

    static func slots(of routine: Routine) -> [PlanSlot] {
        routine.sortedItems.compactMap { item in item.exercise.map { PlanSlot(exerciseID: $0.id, name: $0.name, sets: item.targetSets) } }
    }

    static func slots(of workout: Workout) -> [PlanSlot] {
        workout.groups.map { PlanSlot(exerciseID: $0.exercise.id, name: $0.exercise.name, sets: $0.sets.count) }
    }

    /// Rewrites a routine from a workout's structure: exercises, order, set
    /// counts, rep ranges and rest. Never weights or reps.
    static func update(_ routine: Routine, from workout: Workout, context: ModelContext) -> Bool {
        for item in routine.items ?? [] { context.delete(item) }
        for (i, g) in workout.groups.enumerated() {
            let first = g.sets.first
            let item = RoutineItem(order: i, targetSets: g.sets.count, repRange: (first?.repMin ?? 8)...max(first?.repMax ?? 12, first?.repMin ?? 8), exercise: g.exercise)
            context.insert(item)
            item.routine = routine
        }
        if let rest = workout.groups.first?.sets.first?.restSeconds { routine.restSeconds = rest }
        return save(context)
    }

    /// "Save as routine" for a blank workout.
    static func saveAsRoutine(_ workout: Workout, name: String, context: ModelContext) -> Routine {
        let count = (try? context.fetchCount(FetchDescriptor<Routine>())) ?? 0
        let routine = Routine(name: name, order: count)
        context.insert(routine)
        _ = update(routine, from: workout, context: context)
        return routine
    }

    // MARK: Export

    static func csv(_ context: ModelContext) -> String {
        var rows: [ExportRow] = []
        for w in finishedWorkouts(context).reversed() {
            for group in w.groups {
                for set in group.sets where set.isDone {
                    rows.append(ExportRow(workoutID: w.id, workoutStart: w.startedAt, workoutEnd: w.endedAt, routine: w.routineName, exercise: group.exercise.name, setOrder: set.order + 1, set: set.snapshot))
                }
            }
        }
        return CSVExport.csv(rows)
    }
}
