import Foundation

// The live workout as the phone and the watch both see it. The phone's
// SwiftData + CloudKit store is the only database; the watch holds this
// snapshot, edits it optimistically and sends commands (WatchConnectivity).
// Everything here is pure so both targets share one set of rules.

/// One set in the live workout. `id` is the SetEntry UUID on the phone, so a
/// command can never log the same set twice.
public struct LiveSet: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var weight: Double
    public var unit: WeightUnit
    public var reps: Int
    public var kind: SetKind
    public var isDone: Bool
    public var doneAt: Date?
    /// "phone" or "watch".
    public var source: String

    public init(id: UUID = UUID(), weight: Double, unit: WeightUnit, reps: Int, kind: SetKind = .working, isDone: Bool = false, doneAt: Date? = nil, source: String = "watch") {
        self.id = id; self.weight = weight; self.unit = unit; self.reps = reps
        self.kind = kind; self.isDone = isDone; self.doneAt = doneAt; self.source = source
    }
}

/// An exercise with what the Target rule needs: last session's sets (already in
/// `unit`), the rep goal, the plate step and whether it's bodyweight.
public struct LiveExercise: Codable, Hashable, Sendable, Identifiable {
    /// The phone's Exercise.id (library rows: LibraryExercise.rowID).
    public var id: UUID
    public var libraryID: String?
    public var name: String
    public var unit: WeightUnit
    public var step: Double
    public var bodyweight: Bool
    public var repGoal: Int
    public var restSeconds: Int
    public var last: [SetTarget]
    public var lastDate: Date?
    public var sets: [LiveSet]
    /// Earlier workouts' record-holding sets (the weight × reps Pareto front),
    /// enough for PRDetector to spot a new best on the watch.
    public var records: [SetSnapshot] = []
    public var equipment: Equipment = .other

    public init(id: UUID, libraryID: String? = nil, name: String, unit: WeightUnit, step: Double? = nil, bodyweight: Bool = false, repGoal: Int = Target.defaultRepGoal, restSeconds: Int = 120, last: [SetTarget] = [], lastDate: Date? = nil, sets: [LiveSet] = [], equipment: Equipment = .other, records: [SetSnapshot] = []) {
        self.equipment = equipment; self.records = records
        self.id = id; self.libraryID = libraryID; self.name = name; self.unit = unit
        self.step = step ?? unit.defaultStep; self.bodyweight = bodyweight; self.repGoal = repGoal
        self.restSeconds = restSeconds; self.last = last; self.lastDate = lastDate; self.sets = sets
    }

    /// A library entry the phone has never seen used: no history, no target.
    public init(library e: LibraryExercise, unit: WeightUnit, restDefault: Int) {
        self.init(id: e.rowID, libraryID: e.id, name: e.name, unit: unit, bodyweight: e.equipment == .bodyweight,
                  restSeconds: e.restSeconds ?? restDefault, equipment: e.equipment)
    }

    /// Beat it (the same rule as the phone's Target line and prefill).
    public var target: SetTarget? { Target.next(lastSets: last, repGoal: repGoal, step: step, bodyweight: bodyweight) }

    public var doneSets: [LiveSet] { sets.filter(\.isDone) }

    /// A logged working set met or beat the target.
    public var targetHit: Bool {
        guard let t = target else { return false }
        return doneSets.contains { $0.kind != .warmup && Target.isHit(weight: UnitMath.convert($0.weight, from: $0.unit, to: unit), reps: $0.reps, target: t) }
    }

    /// The set to log next: the first unlogged one (keeping its id, so the
    /// phone's row is the one ticked), at the Prefill rule's values.
    public var nextSet: LiveSet {
        let p = prefill
        if var open = sets.first(where: { !$0.isDone }) {
            open.weight = p.weight
            open.unit = unit
            open.reps = p.reps
            return open
        }
        return LiveSet(weight: p.weight, unit: unit, reps: p.reps)
    }

    public var prefill: SetTarget {
        let logged = doneSets.filter { $0.kind != .warmup }.map { SetTarget(weight: UnitMath.convert($0.weight, from: $0.unit, to: unit), reps: $0.reps) }
        return Prefill.next(loggedThisSession: logged, target: target, lastSets: last, repGoal: repGoal)
    }

    /// Records a candidate set would beat (empty the first session, like the phone).
    public func newRecords(weight: Double, reps: Int, workoutID: UUID, setID: UUID, now: Date = Date()) -> [RecordKind] {
        let today = doneSets.filter { $0.id != setID }.map {
            SetSnapshot(id: $0.id, workoutID: workoutID, weight: $0.weight, unit: $0.unit, reps: $0.reps, kind: $0.kind, date: $0.doneAt ?? now)
        }
        let candidate = SetSnapshot(id: setID, workoutID: workoutID, weight: weight, unit: unit, reps: reps, date: now)
        return PRDetector.newRecords(for: candidate, history: records + today)
    }

    /// Auto-count is tried only where the wrist travels (watch.md §3.3).
    public var countable: Bool { RepCountable.isCountable(name: name, equipment: equipment) }

    /// Last session's working volume (in `unit`), for Finish.
    public var lastVolume: Double { last.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    public var doneVolume: Double {
        doneSets.filter { $0.kind != .warmup }.reduce(0) { $0 + UnitMath.convert($1.weight, from: $1.unit, to: unit) * Double($1.reps) }
    }
}

/// The open workout, plus the memory the watch needs to add an exercise.
public struct LiveWorkout: Codable, Equatable, Sendable {
    public var workoutID: UUID
    /// Clock start; only meaningful once something is logged.
    public var startedAt: Date
    public var endedAt: Date?
    public var exercises: [LiveExercise]
    public var rest: RestState?
    /// Recently used exercises, newest first, with their Last sets (sets empty).
    public var recents: [LiveExercise]
    public var unit: WeightUnit
    public var restDefault: Int
    /// Ids of the last commands the phone applied (watch rebasing).
    public var applied: [UUID]
    /// The watch has a workout session running for this workout.
    public var watchSessionActive: Bool
    /// The most recently finished workout and when it ended, so a watch session
    /// for it ends at the same moment when the phone finished it.
    public var lastFinishedID: UUID?
    public var lastFinishedAt: Date?
    /// The phone's Apple Health choice (nil = not asked yet).
    public var healthEnabled: Bool?

    public init(workoutID: UUID = UUID(), startedAt: Date = Date(), endedAt: Date? = nil, exercises: [LiveExercise] = [], rest: RestState? = nil, recents: [LiveExercise] = [], unit: WeightUnit = .lb, restDefault: Int = 120, applied: [UUID] = [], watchSessionActive: Bool = false) {
        self.workoutID = workoutID; self.startedAt = startedAt; self.endedAt = endedAt; self.exercises = exercises
        self.rest = rest; self.recents = recents; self.unit = unit; self.restDefault = restDefault
        self.applied = applied; self.watchSessionActive = watchSessionActive
    }

    /// The watch's session for `id` should end now: the phone finished it.
    public func finishedElsewhere(_ id: UUID) -> Date? {
        if lastFinishedID == id { return lastFinishedAt ?? Date() }
        if workoutID == id, let endedAt { return endedAt }
        return nil
    }

    public var doneSets: [LiveSet] { exercises.flatMap(\.doneSets) }
    public var unloggedCount: Int { exercises.flatMap(\.sets).filter { !$0.isDone }.count }

    /// Beaten lifts with their best set (the heaviest hit), for Finish.
    public var beaten: [(exercise: LiveExercise, best: SetTarget)] {
        exercises.compactMap { ex in
            guard let t = ex.target else { return nil }
            let hits = ex.doneSets.filter { $0.kind != .warmup }
                .map { SetTarget(weight: UnitMath.convert($0.weight, from: $0.unit, to: ex.unit), reps: $0.reps) }
                .filter { Target.isHit(weight: $0.weight, reps: $0.reps, target: t) }
            guard let best = hits.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }) else { return nil }
            return (ex, best)
        }
    }

    /// Today's volume and the last time of these same exercises, in `unit`
    /// (nil when none of today's lifts has a last time).
    public var volumeComparison: (today: Double, last: Double)? {
        let logged = exercises.filter { !$0.doneSets.isEmpty }
        let withLast = logged.filter { $0.lastVolume > 0 }
        guard !withLast.isEmpty else { return nil }
        let today = withLast.reduce(0) { $0 + UnitMath.convert($1.doneVolume, from: $1.unit, to: unit) }
        let last = withLast.reduce(0) { $0 + UnitMath.convert($1.lastVolume, from: $1.unit, to: unit) }
        return (today, last)
    }
    public var clockStarted: Bool { !doneSets.isEmpty }

    /// "{n} of {m} targets beaten": m counts logged exercises that had a target.
    public var targetsBeaten: (beaten: Int, of: Int) {
        let logged = exercises.filter { !$0.doneSets.isEmpty && $0.target != nil }
        return (logged.filter(\.targetHit).count, logged.count)
    }

    /// The exercise the user is on: first with an unlogged set, else the last one.
    public var currentIndex: Int? {
        guard !exercises.isEmpty else { return nil }
        return exercises.firstIndex { ex in ex.doneSets.isEmpty || ex.sets.contains { !$0.isDone } } ?? exercises.count - 1
    }
}

// MARK: Commands

/// Everything the watch can do. Each one is idempotent on the phone.
public enum LiveCommand: Codable, Equatable, Sendable {
    /// Upsert by set id, marked done.
    case logSet(exerciseID: UUID, set: LiveSet)
    /// Undo of a log: the set goes back to unlogged.
    case unlogSet(setID: UUID)
    /// The exercise as the watch knows it (sets ignored).
    case addExercise(LiveExercise)
    case setRest(exerciseID: UUID, seconds: Int)
    /// Start / +30 s (new end) / skip (nil).
    case rest(RestState?)
    case finish(at: Date)
    /// Discard today's log (sent after the watch's 5 s Undo).
    case discard
    case watchSession(active: Bool)
    /// nil = the watch couldn't save; the phone saves instead.
    case healthSaved(healthKitID: UUID?)
}

public struct LiveEnvelope: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var workoutID: UUID
    public var sentAt: Date
    public var command: LiveCommand

    public init(id: UUID = UUID(), workoutID: UUID, sentAt: Date = Date(), command: LiveCommand) {
        self.id = id; self.workoutID = workoutID; self.sentAt = sentAt; self.command = command
    }
}

public enum LiveCoding {
    public static func encode<T: Encodable>(_ value: T) -> Data? {
        let e = JSONEncoder()
        return try? e.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let d = JSONDecoder()
        return try? d.decode(type, from: data)
    }
}

// MARK: Reducer (watch, optimistic)

public enum LiveReducer {
    /// Applies a command to the watch's copy. The phone applies the same command
    /// to SwiftData; the next snapshot replaces this guess.
    public static func apply(_ command: LiveCommand, to w: inout LiveWorkout, now: Date = Date()) {
        switch command {
        case .logSet(let exID, var set):
            guard let i = w.exercises.firstIndex(where: { $0.id == exID }) else { return }
            if !w.clockStarted { w.startedAt = set.doneAt ?? now }
            set.isDone = true
            set.doneAt = set.doneAt ?? now
            if let j = w.exercises[i].sets.firstIndex(where: { $0.id == set.id }) {
                w.exercises[i].sets[j] = set
            } else {
                w.exercises[i].sets.append(set)
            }
        case .unlogSet(let id):
            for i in w.exercises.indices {
                if let j = w.exercises[i].sets.firstIndex(where: { $0.id == id }) {
                    w.exercises[i].sets[j].isDone = false
                    w.exercises[i].sets[j].doneAt = nil
                }
            }
        case .addExercise(var ex):
            guard !w.exercises.contains(where: { $0.id == ex.id }) else { return }
            ex.sets = []
            w.exercises.append(ex)
        case .setRest(let exID, let seconds):
            if let i = w.exercises.firstIndex(where: { $0.id == exID }) { w.exercises[i].restSeconds = seconds }
            if let i = w.recents.firstIndex(where: { $0.id == exID }) { w.recents[i].restSeconds = seconds }
        case .rest(let r):
            w.rest = r
        case .finish(let at):
            w.endedAt = at
            w.rest = nil
            for i in w.exercises.indices { w.exercises[i].sets.removeAll { !$0.isDone } }
            w.exercises.removeAll { $0.sets.isEmpty }
        case .watchSession(let active):
            w.watchSessionActive = active
        case .discard:
            w.exercises = []
            w.rest = nil
        case .healthSaved:
            break
        }
    }

    /// The phone's snapshot plus the watch's commands it hasn't applied yet.
    /// A watch that started offline used its own workout id; the phone folds
    /// those into today's log, so they still show. Commands for the workout
    /// the phone last finished are dropped from the view (still delivered).
    public static func rebase(_ server: LiveWorkout, pending: [LiveEnvelope]) -> (workout: LiveWorkout, pending: [LiveEnvelope]) {
        let applied = Set(server.applied)
        let remaining = pending.filter { !applied.contains($0.id) }
        var w = server
        for p in remaining where p.workoutID == server.workoutID || p.workoutID != server.lastFinishedID {
            apply(p.command, to: &w, now: p.sentAt)
        }
        return (w, remaining)
    }

    /// Keeps the phone's applied-id list short.
    public static func remember(_ id: UUID, in applied: [UUID], limit: Int = 200) -> [UUID] {
        Array((applied.filter { $0 != id } + [id]).suffix(limit))
    }
}

/// The record-holding sets of a history: nothing else can matter to PRDetector
/// (heaviest, e1RM, most reps at or above a weight and set volume all grow
/// with weight and reps), so the phone sends only these to the watch.
public enum RecordFront {
    public static func front(_ sets: [SetSnapshot]) -> [SetSnapshot] {
        let s = sets.filter { $0.kind.countsForRecords && $0.reps > 0 }
            .sorted { ($0.weightKg, $0.reps) > ($1.weightKg, $1.reps) }
        var out: [SetSnapshot] = []
        var bestReps = 0
        for x in s where x.reps > bestReps {
            out.append(x)
            bestReps = x.reps
        }
        return out
    }
}

// MARK: Prefill (one rule for the phone and the watch)

/// Ben, 2:16pm 26 Nov: the first set of an exercise prefills at the target;
/// every later set prefills with the set just logged this session. The Beat
/// it line keeps showing the target until a set beats it.
public enum Prefill {
    public static func next(loggedThisSession: [SetTarget], target: SetTarget?, lastSets: [SetTarget], repGoal: Int) -> SetTarget {
        // The shared rule (Target.prefill, also behind LiftStore.prefill on the phone).
        Target.prefill(justLogged: loggedThisSession.last, target: target, lastTime: lastSets.first)
            ?? SetTarget(weight: 0, reps: repGoal)
    }
}

/// Families the wrist can count (watch.md §3.3–3.4). Anything the wrist barely
/// travels on shows "Counting off." instead of a guess.
public enum RepCountable {
    static let off = ["leg press", "hack squat", "calf", "hip thrust", "glute bridge", "carry", "farmer", "hold", "plank",
                      "wall sit", "dead hang", "leg extension", "leg curl", "adductor", "abductor", "back squat", "barbell squat",
                      "front squat", "box squat", "smith machine squat", "good morning", "sled"]

    public static func isCountable(name: String, equipment: Equipment) -> Bool {
        if equipment == .machine || equipment == .smithMachine || equipment == .sled { return false }
        let n = Search.fold(name)
        if off.contains(where: { n.contains($0) }) { return false }
        if equipment == .barbell, n.contains("squat") { return false }
        return true
    }
}

// MARK: Text shared by the phone and the watch

public enum BeatItText {
    /// "Last · Mon · 185×8, 185×7"
    /// Weekday within the last 6 days, else the date ("19 Nov") so an old week isn't misread.
    public static func last(_ sets: [SetTarget], date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard !sets.isEmpty else { return nil }
        let day = date.map { d in
            now.timeIntervalSince(d) > 6 * 86_400
                ? d.formatted(Date.FormatStyle(calendar: calendar).day().month(.abbreviated))
                : d.formatted(Date.FormatStyle(calendar: calendar).weekday(.abbreviated))
        }
        let list = sets.map { "\(UnitMath.format($0.weight))×\($0.reps)" }.joined(separator: ", ")
        return (["Last", day].compactMap { $0 } + [list]).joined(separator: " · ")
    }

    /// "185 × 9", or "12 reps" for bodyweight with no load.
    public static func number(_ t: SetTarget, bodyweight: Bool) -> String {
        bodyweight && t.weight <= 0 ? "\(t.reps) reps" : "\(UnitMath.format(t.weight)) × \(t.reps)"
    }
}
