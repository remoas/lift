import Foundation

/// A set inside a workout, as plain values. History and records key on
/// `exerciseID` and the set's own UUID, never on routine slots, so a workout
/// can be freely edited mid-session without losing or mis-filing a set.
public struct LoggedSet: Hashable, Codable, Sendable, Identifiable {
    public var snapshot: SetSnapshot
    public var exerciseID: UUID
    public var isDone: Bool
    /// Device that logged it ("phone" now, "watch" in phase 2).
    public var source: String

    public var id: UUID { snapshot.id }

    public init(snapshot: SetSnapshot, exerciseID: UUID, isDone: Bool, source: String = "phone") {
        self.snapshot = snapshot
        self.exerciseID = exerciseID
        self.isDone = isDone
        self.source = source
    }
}

/// The day-of plan for one workout. It starts as a copy of a routine (or empty)
/// and every edit here changes only this workout, never the saved routine.
public struct SessionPlan: Equatable, Sendable {
    public struct Block: Equatable, Sendable, Identifiable {
        public var exerciseID: UUID
        public var sets: [LoggedSet]
        public var id: UUID { exerciseID }
        public init(exerciseID: UUID, sets: [LoggedSet]) {
            self.exerciseID = exerciseID
            self.sets = sets
        }
    }

    public var workoutID: UUID
    /// The routine this workout was started from; nil for a blank workout.
    public var routineID: UUID?
    public var blocks: [Block]
    /// Logged sets of exercises swapped out mid-workout. They stay in the
    /// workout's history even though the exercise left the plan.
    public var retained: [LoggedSet] = []

    public init(workoutID: UUID, routineID: UUID?, blocks: [Block] = []) {
        self.workoutID = workoutID
        self.routineID = routineID
        self.blocks = blocks
    }

    /// Every set that belongs to this workout, logged or not.
    public var allSets: [LoggedSet] { blocks.flatMap(\.sets) + retained }
    public var doneSets: [LoggedSet] { allSets.filter(\.isDone) }

    // MARK: Exercises

    public mutating func addExercise(_ exerciseID: UUID, sets: [LoggedSet], at index: Int? = nil) {
        if let i = blocks.firstIndex(where: { $0.exerciseID == exerciseID }) {
            blocks[i].sets += sets
            return
        }
        let block = Block(exerciseID: exerciseID, sets: sets)
        if let index, index >= 0, index <= blocks.count { blocks.insert(block, at: index) } else { blocks.append(block) }
    }

    /// Replaces an exercise in place. Sets already logged are kept (moved to
    /// `retained`), unlogged sets are dropped, the new exercise takes the slot.
    public mutating func swapExercise(_ oldID: UUID, for newID: UUID, newSets: [LoggedSet]) {
        guard let i = blocks.firstIndex(where: { $0.exerciseID == oldID }) else { return }
        retained += blocks[i].sets.filter(\.isDone)
        blocks.remove(at: i)
        addExercise(newID, sets: newSets, at: i)
    }

    /// Removes an exercise and all its sets. Returns what was removed so the
    /// caller can offer Undo.
    @discardableResult
    public mutating func removeExercise(_ exerciseID: UUID) -> (index: Int, block: Block)? {
        guard let i = blocks.firstIndex(where: { $0.exerciseID == exerciseID }) else { return nil }
        return (i, blocks.remove(at: i))
    }

    public mutating func restore(_ removed: (index: Int, block: Block)) {
        blocks.insert(removed.block, at: min(removed.index, blocks.count))
    }

    public mutating func moveExercise(from source: Int, to destination: Int) {
        guard blocks.indices.contains(source) else { return }
        let block = blocks.remove(at: source)
        blocks.insert(block, at: max(0, min(destination, blocks.count)))
    }

    // MARK: Sets

    public mutating func addSet(_ set: LoggedSet) {
        addExercise(set.exerciseID, sets: [set])
    }

    @discardableResult
    public mutating func removeSet(_ setID: UUID) -> LoggedSet? {
        for b in blocks.indices {
            if let s = blocks[b].sets.firstIndex(where: { $0.id == setID }) {
                return blocks[b].sets.remove(at: s)
            }
        }
        return nil
    }

    public mutating func setDone(_ setID: UUID, _ done: Bool, at date: Date) {
        for b in blocks.indices {
            if let s = blocks[b].sets.firstIndex(where: { $0.id == setID }) {
                blocks[b].sets[s].isDone = done
                blocks[b].sets[s].snapshot.date = date
            }
        }
    }

    /// The first unticked set in plan order: the screen's primary action.
    public var currentSetID: UUID? {
        blocks.lazy.flatMap(\.sets).first(where: { !$0.isDone })?.id
    }

    // MARK: Records

    /// Records a set beats, against `pastSets` (earlier workouts) plus the sets
    /// already logged in this workout for the same exercise.
    public func newRecords(for setID: UUID, pastSets: [LoggedSet]) -> [RecordKind] {
        guard let set = allSets.first(where: { $0.id == setID }) else { return [] }
        let history = (pastSets + doneSets).filter { $0.exerciseID == set.exerciseID && $0.isDone && $0.id != setID }
        return PRDetector.newRecords(for: set.snapshot, history: history.map(\.snapshot))
    }

    /// The routine the rotation advances past when this workout finishes. A
    /// blank workout never advances the rotation.
    public var rotationRoutineID: UUID? { routineID }
}

public enum History {
    /// One exercise's logged sets across workouts, oldest first. Keyed on
    /// exercise ID only, so plan edits never change what counts.
    public static func sets(for exerciseID: UUID, in all: [LoggedSet]) -> [LoggedSet] {
        all.filter { $0.exerciseID == exerciseID && $0.isDone }.sorted { $0.snapshot.date < $1.snapshot.date }
    }

    /// Best e1RM per workout, for the exercise chart.
    public static func e1RMSeries(for exerciseID: UUID, in all: [LoggedSet]) -> [(workoutID: UUID, date: Date, e1RMKg: Double, set: SetSnapshot)] {
        var best: [UUID: SetSnapshot] = [:]
        for s in sets(for: exerciseID, in: all) where s.snapshot.kind.countsForRecords {
            guard let e = s.snapshot.e1RMKg else { continue }
            if let cur = best[s.snapshot.workoutID], let ce = cur.e1RMKg, ce >= e { continue }
            best[s.snapshot.workoutID] = s.snapshot
        }
        return best.map { (workoutID: $0.key, date: $0.value.date, e1RMKg: $0.value.e1RMKg ?? 0, set: $0.value) }
            .sorted { $0.date < $1.date }
    }
}

extension History {
    /// Sets from the most recent workout (any routine, or blank) that included
    /// this exercise. "Last time" and prefill both come from here.
    public static func lastSession(for exerciseID: UUID, in all: [LoggedSet], excluding workoutID: UUID? = nil) -> [LoggedSet] {
        let sets = all.filter { $0.exerciseID == exerciseID && $0.isDone && $0.snapshot.workoutID != workoutID }
        guard let latest = sets.max(by: { $0.snapshot.date < $1.snapshot.date })?.snapshot.workoutID else { return [] }
        return sets.filter { $0.snapshot.workoutID == latest }.sorted { $0.snapshot.date < $1.snapshot.date }
    }
}
