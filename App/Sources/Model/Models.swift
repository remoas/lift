import Foundation
import SwiftData
import LiftCore

// CloudKit-backed SwiftData rules: every property has a default, no unique
// constraints, and every relationship is optional with an inverse.

@Model
final class Exercise {
    var id: UUID = UUID()
    /// Stable library ID ("bench-press"); nil for custom exercises.
    var libraryID: String?
    var name: String = ""
    var primaryMusclesRaw: String = ""
    var secondaryMusclesRaw: String = ""
    var equipmentRaw: String = Equipment.barbell.rawValue
    /// Free text: wide, neutral, chin-up, assisted, weighted, incline 30°…
    var variant: String = ""
    /// Comma-separated search aliases ("RDL").
    var aliasesRaw: String = ""
    var isCustom: Bool = false
    /// Vendored CC0 media key (see ExerciseMedia); nil = placeholder tile. Customs stay nil.
    var mediaRef: String?
    /// nil = follow the global unit.
    var unitOverrideRaw: String?
    /// nil = the unit's default step (5 lb / 2.5 kg).
    var plateStep: Double?
    /// Default rep range when the exercise is added somewhere.
    var repMin: Int = 8
    var repMax: Int = 12
    /// Per-exercise rest; nil = the routine's (or Settings') default.
    var restOverride: Int?
    /// Sticky note that follows the exercise into every workout.
    var note: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.exercise)
    var routineItems: [RoutineItem]? = []

    @Relationship(deleteRule: .nullify, inverse: \SetEntry.exercise)
    var sets: [SetEntry]? = []

    init(id: UUID = UUID(), name: String, primary: [MuscleGroup], secondary: [MuscleGroup] = [], equipment: Equipment, variant: String = "", aliases: [String] = [], repRange: ClosedRange<Int> = 8...12, isCustom: Bool) {
        self.id = id
        self.name = name
        self.primaryMusclesRaw = MuscleGroup.join(primary)
        self.secondaryMusclesRaw = MuscleGroup.join(secondary)
        self.equipmentRaw = equipment.rawValue
        self.variant = variant
        self.aliasesRaw = aliases.joined(separator: ",")
        self.repMin = repRange.lowerBound
        self.repMax = repRange.upperBound
        self.isCustom = isCustom
    }

    /// Library row, created the first time it's picked.
    convenience init(library e: LibraryExercise) {
        self.init(id: e.rowID, name: e.name, primary: e.primaryMuscles, secondary: e.secondaryMuscles, equipment: e.equipment, variant: e.variant, aliases: e.aliases, repRange: e.repRange, isCustom: false)
        libraryID = e.id
        mediaRef = e.mediaRef
    }

    /// Refresh from a newer seed. Never touches the user's note, unit, rest,
    /// plate step or history.
    func apply(library e: LibraryExercise) {
        name = e.name
        primaryMuscles = e.primaryMuscles
        secondaryMuscles = e.secondaryMuscles
        equipment = e.equipment
        variant = e.variant
        aliasesRaw = e.aliases.joined(separator: ",")
        mediaRef = e.mediaRef
    }

    var primaryMuscles: [MuscleGroup] {
        get { MuscleGroup.parse(primaryMusclesRaw) }
        set { primaryMusclesRaw = MuscleGroup.join(newValue) }
    }

    var secondaryMuscles: [MuscleGroup] {
        get { MuscleGroup.parse(secondaryMusclesRaw) }
        set { secondaryMusclesRaw = MuscleGroup.join(newValue) }
    }

    var aliases: [String] { aliasesRaw.split(separator: ",").map { String($0) } }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var searchEntry: SearchEntry {
        SearchEntry(id: id, name: name, variant: variant, aliases: aliases, primary: primaryMuscles, secondary: secondaryMuscles, equipment: equipment)
    }

    var unitOverride: WeightUnit? {
        get { unitOverrideRaw.flatMap(WeightUnit.init(rawValue:)) }
        set { unitOverrideRaw = newValue?.rawValue }
    }

    func unit(global: WeightUnit) -> WeightUnit { unitOverride ?? global }

    func step(for unit: WeightUnit) -> Double {
        // A custom step is stored in the exercise's own unit.
        if let plateStep, unitOverride == nil || unitOverride == unit { return plateStep }
        return unit.defaultStep
    }

    var repRange: ClosedRange<Int> { min(repMin, repMax)...max(repMin, repMax) }
}

@Model
final class Routine {
    var id: UUID = UUID()
    var name: String = ""
    /// Position in the rotation.
    var order: Int = 0
    var isSeeded: Bool = false
    /// "Rest between sets" default for this day.
    var restSeconds: Int = 120

    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.routine)
    var items: [RoutineItem]? = []

    init(id: UUID = UUID(), name: String, order: Int, isSeeded: Bool = false) {
        self.id = id
        self.name = name
        self.order = order
        self.isSeeded = isSeeded
    }

    var sortedItems: [RoutineItem] { (items ?? []).sorted { $0.order < $1.order } }
}

@Model
final class RoutineItem {
    var id: UUID = UUID()
    var order: Int = 0
    var targetSets: Int = 3
    var repMin: Int = 8
    var repMax: Int = 12
    var routine: Routine?
    var exercise: Exercise?

    init(order: Int, targetSets: Int = 3, repRange: ClosedRange<Int>, exercise: Exercise?) {
        self.order = order
        self.targetSets = targetSets
        self.repMin = repRange.lowerBound
        self.repMax = repRange.upperBound
        self.exercise = exercise
    }

    var repRange: ClosedRange<Int> { min(repMin, repMax)...max(repMin, repMax) }
}

@Model
final class Workout {
    var id: UUID = UUID()
    var routineID: UUID?
    var routineName: String = ""
    var startedAt: Date = Date()
    /// nil while the workout is in progress.
    var endedAt: Date?
    var device: String = "iPhone"
    var healthKitID: String?
    var note: String = ""
    /// Logged after the fact from History (no rest timer).
    var isBackLog: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.workout)
    var sets: [SetEntry]? = []

    init(routineID: UUID?, routineName: String, startedAt: Date = Date()) {
        self.routineID = routineID
        self.routineName = routineName
        self.startedAt = startedAt
    }

    var isActive: Bool { endedAt == nil }
    var allSets: [SetEntry] { sets ?? [] }
    var doneSets: [SetEntry] { allSets.filter(\.isDone) }

    /// Exercises in workout order, each with its sets in order.
    var groups: [(exercise: Exercise, sets: [SetEntry])] {
        var order: [UUID] = []
        var map: [UUID: (Exercise, [SetEntry])] = [:]
        for set in allSets.sorted(by: { ($0.exerciseOrder, $0.order) < ($1.exerciseOrder, $1.order) }) {
            guard let ex = set.exercise else { continue }
            if map[ex.id] == nil { order.append(ex.id); map[ex.id] = (ex, []) }
            map[ex.id]!.1.append(set)
        }
        return order.compactMap { id in map[id].map { (exercise: $0.0, sets: $0.1) } }
    }

    var volumeKg: Double { doneSets.filter { $0.kind != .warmup }.reduce(0) { $0 + $1.snapshot.volumeKg } }
}

@Model
final class SetEntry {
    /// Stable across devices so the Watch (phase 2) can never duplicate a set.
    var id: UUID = UUID()
    var order: Int = 0
    var exerciseOrder: Int = 0
    var kindRaw: String = SetKind.working.rawValue
    /// The number exactly as entered…
    var weight: Double = 0
    /// …and the unit it was entered in.
    var unitRaw: String = WeightUnit.lb.rawValue
    var reps: Int = 0
    var rpe: Double?
    /// The workout slot's plan, copied in at start (and kept on swap).
    var repMin: Int = 8
    var repMax: Int = 12
    var restSeconds: Int = 120
    var note: String = ""
    /// "phone" now; "watch" in phase 2.
    var source: String = "phone"
    var isDone: Bool = false
    var doneAt: Date?
    var workout: Workout?
    var exercise: Exercise?

    init(order: Int, exerciseOrder: Int, kind: SetKind = .working, weight: Double, unit: WeightUnit, reps: Int, exercise: Exercise?) {
        self.order = order
        self.exerciseOrder = exerciseOrder
        self.kindRaw = kind.rawValue
        self.weight = weight
        self.unitRaw = unit.rawValue
        self.reps = reps
        self.exercise = exercise
    }

    var kind: SetKind {
        get { SetKind(rawValue: kindRaw) ?? .working }
        set { kindRaw = newValue.rawValue }
    }

    var unit: WeightUnit {
        get { WeightUnit(rawValue: unitRaw) ?? .lb }
        set { unitRaw = newValue.rawValue }
    }

    var snapshot: SetSnapshot {
        SetSnapshot(id: id, workoutID: workout?.id ?? UUID(), weight: weight, unit: unit, reps: reps, kind: kind, date: doneAt ?? workout?.startedAt ?? Date())
    }

    var logged: LoggedSet? {
        guard let ex = exercise else { return nil }
        return LoggedSet(snapshot: snapshot, exerciseID: ex.id, isDone: isDone, source: source)
    }

    /// No weight entered yet (first time on this exercise).
    var needsWeight: Bool { weight <= 0 && !(exercise?.equipment.allowsZeroWeight ?? false) }
}

enum LiftSchema {
    static let models: [any PersistentModel.Type] = [Exercise.self, Routine.self, RoutineItem.self, Workout.self, SetEntry.self]
}
