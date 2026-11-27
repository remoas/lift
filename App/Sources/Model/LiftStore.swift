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
        #if DEBUG
        // UI tests: a named on-disk local store that survives relaunch (-LiftTestStore name [-LiftTestReset]).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-LiftTestStore"), i + 1 < args.count {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(args[i + 1]).store")
            if args.contains("-LiftTestReset") {
                for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix)) }
            }
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        }
        #endif
        let cloud = ModelConfiguration("Lift", schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: cloud) { return container }
        let local = ModelConfiguration("Lift", schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: local)
        } catch {
            fatalError("Could not open the Lift store: \(error)")
        }
    }

    /// Deletes a set for good. SwiftData keeps a deleted child in its parents'
    /// to-many arrays (Workout.sets, Exercise.sets) until they refault, so the
    /// removed exercise's sets came back in `workout.groups` and, via the parent's
    /// relationship on save, after relaunch (Ben, build 1.0 (2)). Unlink first.
    static func delete(_ set: SetEntry, context: ModelContext) {
        set.workout?.sets?.removeAll { $0 === set }
        set.exercise?.sets?.removeAll { $0 === set }
        set.workout = nil
        set.exercise = nil
        context.delete(set)
    }

    static func save(_ context: ModelContext) -> Bool {
        do { try context.save(); return true } catch { return false }
    }

    // MARK: Library

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
        if let rest = entry.restSeconds { ex.restSec = rest }
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
        ex.restSec = rest
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
                context.delete(ex)
            } else {
                keepers[ex.id] = ex
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

    // MARK: Starting

    /// A new blank workout: today's log. Its clock starts at the first logged set.
    @discardableResult
    static func startBlank(at date: Date = Date(), backLog: Bool = false, context: ModelContext) -> Workout {
        let workout = Workout(startedAt: date)
        workout.isBackLog = backLog
        context.insert(workout)
        _ = save(context)
        return workout
    }

    // MARK: Last time and Beat it

    struct BeatIt {
        /// Last session's sets in the display unit, in order ("185×8, 185×7…").
        let last: [SetTarget]
        let lastDate: Date?
        /// nil the first time.
        let target: SetTarget?
        /// Index in `last` of the top set the target comes from.
        let topIndex: Int?
    }

    /// The one source for the Last line, the Target line and the prefill (AC 64).
    static func beatIt(for exercise: Exercise, excluding workout: Workout?, unit: WeightUnit) -> BeatIt {
        let sets = lastSessionSets(for: exercise, excluding: workout).filter { $0.kind != .warmup }
        let step = exercise.step(for: unit)
        let last = sets.map { SetTarget(weight: UnitMath.convertLoadable($0.weight, from: $0.unit, to: unit, step: step), reps: $0.reps) }
        let target = Target.next(lastSets: last, repGoal: exercise.repGoal, step: step, bodyweight: exercise.equipment == .bodyweight)
        let top = Target.topSet(last)
        return BeatIt(last: last, lastDate: sets.first?.workout?.startedAt,
                      target: target, topIndex: top.flatMap { t in last.firstIndex(of: t) })
    }

    /// Sets prefilled from last time; the set the top set came from is prefilled
    /// AT the target. First time: one set with no weight, so the first tap asks.
    static func insertPrefilledSets(for exercise: Exercise, sets count: Int? = nil, rest: Int, exerciseOrder: Int, into workout: Workout, globalUnit: WeightUnit, context: ModelContext) {
        let unit = exercise.unit(global: globalUnit)
        let beat = beatIt(for: exercise, excluding: workout, unit: unit)
        let n = max(count ?? beat.last.count, 1)
        for i in 0..<n {
            let value = i < beat.last.count ? beat.last[i] : beat.last.last
            let set = SetEntry(order: i, exerciseOrder: exerciseOrder, kind: .working, weight: value?.weight ?? 0, unit: unit, reps: value?.reps ?? exercise.repGoal, exercise: exercise)
            set.restSeconds = rest
            context.insert(set)
            set.workout = workout
        }
        prefill(exercise, in: workout, globalUnit: globalUnit)
    }

    /// A logged set of `exercise` in `workout` met or beat its target.
    static func targetHit(_ exercise: Exercise, in workout: Workout, globalUnit: WeightUnit) -> Bool {
        let u = exercise.unit(global: globalUnit)
        guard let t = beatIt(for: exercise, excluding: workout, unit: u).target else { return false }
        return workout.doneSets.contains { s in
            s.exercise === exercise && s.kind != .warmup &&
            Target.isHit(weight: UnitMath.convert(s.weight, from: s.unit, to: u), reps: s.reps, target: t)
        }
    }

    /// The one source of truth for unlogged sets (AC 64, Ben 2:16 pm): the
    /// first set prefills at the target; every later set with the set just
    /// logged this session. The current row, the rest bar's Next and the set
    /// editor all read these values.
    static func prefill(_ exercise: Exercise, in workout: Workout, globalUnit: WeightUnit) {
        let u = exercise.unit(global: globalUnit)
        let beat = beatIt(for: exercise, excluding: workout, unit: u)
        let sets = workout.allSets.filter { $0.exercise === exercise && $0.kind != .warmup }.sorted { $0.order < $1.order }
        var justLogged: SetTarget?
        for (i, s) in sets.enumerated() {
            if s.isDone {
                justLogged = SetTarget(weight: UnitMath.convert(s.weight, from: s.unit, to: u), reps: s.reps)
                continue
            }
            let lastTime = i < beat.last.count ? beat.last[i] : beat.last.last
            guard let v = Target.prefill(justLogged: justLogged, target: beat.target, lastTime: lastTime) else { continue }
            s.weight = v.weight
            s.unit = u
            s.reps = v.reps
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
        insertPrefilledSets(for: exercise, rest: exercise.restSec ?? restDefault, exerciseOrder: order, into: workout, globalUnit: globalUnit, context: context)
        _ = save(context)
    }

    /// Swaps in place, keeping the slot's set count, rep range and rest. Ticked
    /// sets stay logged to the old exercise; only the unticked ones move.
    static func swap(_ old: Exercise, for new: Exercise, in workout: Workout, globalUnit: WeightUnit, context: ModelContext) {
        guard let slotIndex = exerciseOrder(of: old, in: workout) else { return }
        let oldSets = workout.allSets.filter { $0.exercise === old }
        let templateRest = oldSets.first?.restSeconds
        let unticked = oldSets.filter { !$0.isDone }
        let untickedCount = unticked.count
        for set in unticked { delete(set, context: context) }
        let keepsLogged = oldSets.count > untickedCount
        for set in workout.allSets where set.exerciseOrder > slotIndex { set.exerciseOrder += 1 }
        insertPrefilledSets(for: new, sets: max(untickedCount, 1), rest: new.restSec ?? templateRest ?? 120, exerciseOrder: keepsLogged ? slotIndex + 1 : slotIndex, into: workout, globalUnit: globalUnit, context: context)
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
        for s in sets { delete(s, context: context) }
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
                           reps: template?.reps ?? exercise.repGoal,
                           exercise: exercise)
        set.repMin = template?.repMin ?? exercise.repMin
        set.repMax = template?.repMax ?? exercise.repMax
        set.restSeconds = template?.restSeconds ?? exercise.restSec ?? 120
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
        // Finish and the 3 h auto-finish: the rest Activity goes now (AC 108).
        // The phone fallback notification goes with it, whatever path finished.
        if !workout.isBackLog {
            PhoneSync.shared.setLocalRest(nil)
            RestActivityController.shared.end()
        }
        for set in workout.allSets where !set.isDone { delete(set, context: context) }
        workout.endedAt = workout.isBackLog ? max(workout.startedAt.addingTimeInterval(60), workout.doneSets.compactMap(\.doneAt).max() ?? workout.startedAt) : date
        _ = save(context)
    }

    // MARK: Opening (today's workout)

    /// Auto-finish window after the last logged set (AC 67).
    static let staleAfter: TimeInterval = 3 * 3600

    /// The open log, finishing a stale one first. Never more than one open
    /// workout: extra empty ones (e.g. from another device) are dropped.
    /// Returns the open workout and, if one was auto-finished, that workout.
    static func openLog(_ context: ModelContext, now: Date = Date()) -> (open: Workout, autoFinished: Workout?) {
        let d = FetchDescriptor<Workout>(predicate: #Predicate { $0.endedAt == nil }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        var active = ((try? context.fetch(d)) ?? []).filter { !$0.isBackLog }
        var finished: Workout?
        if let w = active.first, let last = w.doneSets.compactMap(\.doneAt).max(), now.timeIntervalSince(last) > staleAfter {
            finish(w, at: last, context: context)
            finished = w
            active.removeFirst()
        }
        for extra in active.dropFirst() where extra.doneSets.isEmpty { context.delete(extra) }
        if let open = active.first {
            // Nothing logged yet: the clock hasn't started, so keep it fresh.
            if open.doneSets.isEmpty { open.startedAt = now }
            _ = save(context)
            return (open, finished)
        }
        return (startBlank(at: now, context: context), finished)
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
