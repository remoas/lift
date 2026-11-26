import Foundation

// MARK: Undo window

/// One pending destructive action at a time (discard a workout, delete a
/// workout or set, remove an exercise). Nothing is asked up front: the action
/// shows an Undo toast and is only committed when its window ends, when it is
/// replaced by a newer action, or when the toast is dismissed.
public struct UndoWindow<ID: Hashable & Sendable>: Sendable {
    public static var defaultDuration: TimeInterval { 5 }

    public private(set) var pending: (id: ID, deadline: Date)?
    public init() {}

    /// Starts a window. Returns the previous pending ID, which must now be committed.
    @discardableResult
    public mutating func begin(_ id: ID, at now: Date, duration: TimeInterval = UndoWindow.defaultDuration) -> ID? {
        let previous = pending?.id
        pending = (id, now.addingTimeInterval(duration))
        return previous == id ? nil : previous
    }

    /// Undo inside the window. True means: restore, never commit.
    public mutating func undo(_ id: ID, at now: Date) -> Bool {
        guard let p = pending, p.id == id, now <= p.deadline else { return false }
        pending = nil
        return true
    }

    /// The ID to commit if its window has ended; nil otherwise.
    public mutating func expire(at now: Date) -> ID? {
        guard let p = pending, now > p.deadline else { return nil }
        pending = nil
        return p.id
    }

    /// Commit now (toast swiped away, app backgrounded).
    public mutating func flush() -> ID? {
        defer { pending = nil }
        return pending?.id
    }

    public func isPending(_ id: ID) -> Bool { pending?.id == id }
}

// MARK: Rest defaults

/// Rest lives on the exercise. A day's "Rest between sets" is only a default:
/// it fills exercises that have no rest of their own and never overwrites one.
public enum RestDefaults {
    /// `current`: each exercise's own rest (nil = not set). Returns only the
    /// assignments to make.
    public static func fill(_ current: [UUID: Int?], default seconds: Int) -> [UUID: Int] {
        var out: [UUID: Int] = [:]
        for (id, rest) in current where rest == nil { out[id] = seconds }
        return out
    }

    /// The rest a set uses: warm-ups use the warm-up default, everything else
    /// the exercise's own rest, then the day default, then Settings.
    public static func effective(kind: SetKind, exercise: Int?, dayDefault: Int?, settingsWorking: Int, settingsWarmup: Int) -> Int {
        if kind == .warmup { return settingsWarmup }
        return exercise ?? dayDefault ?? settingsWorking
    }
}

// MARK: Finishing

extension SessionPlan {
    /// Sets shown in the summary as "N sets not logged".
    public var unloggedCount: Int { allSets.filter { !$0.isDone }.count }

    /// What Done saves: logged sets only. Unlogged sets are dropped, never
    /// saved as zeros; exercises left with nothing logged leave the workout.
    public func finalized() -> SessionPlan {
        var p = self
        p.blocks = blocks.compactMap { b in
            let done = b.sets.filter(\.isDone)
            return done.isEmpty ? nil : Block(exerciseID: b.exerciseID, sets: done)
        }
        p.retained = retained.filter(\.isDone)
        return p
    }

    /// A workout with nothing logged is not saved at all.
    public var isEmptyWhenFinalized: Bool { doneSets.isEmpty }
}

// MARK: Workout outcome

/// How a workout ended. Only `.finished` with at least one logged set is
/// saved, feeds comparisons, or reaches Health.
public enum WorkoutOutcome: Equatable, Sendable {
    case inProgress
    /// Discarded; still undoable until its window ends.
    case discardPending
    case discarded
    case finished
}

public struct WorkoutRecord: Equatable, Sendable {
    public var id: UUID
    public var routineID: UUID?
    public var startedAt: Date
    public var outcome: WorkoutOutcome
    public var plan: SessionPlan

    public init(id: UUID, routineID: UUID?, startedAt: Date, outcome: WorkoutOutcome, plan: SessionPlan) {
        self.id = id
        self.routineID = routineID
        self.startedAt = startedAt
        self.outcome = outcome
        self.plan = plan
    }

    /// Counts for rotation, week dots, history and comparisons.
    public var counts: Bool { outcome == .finished && !plan.doneSets.isEmpty }
}

public enum Outcomes {
    /// What Done sends to Apple Health; nil when nothing should be written.
    public struct HealthPayload: Equatable, Sendable {
        public var workoutID: UUID
        public var setCount: Int
        public var volumeKg: Double
    }

    public static func healthPayload(for record: WorkoutRecord, healthEnabled: Bool?) -> HealthPayload? {
        guard healthEnabled == true, record.counts else { return nil }
        let final = record.plan.finalized()
        return HealthPayload(workoutID: record.id, setCount: final.doneSets.count,
                             volumeKg: final.doneSets.filter { $0.snapshot.kind != .warmup }.reduce(0) { $0 + $1.snapshot.volumeKg })
    }
}
