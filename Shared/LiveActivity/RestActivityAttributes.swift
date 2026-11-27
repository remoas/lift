import ActivityKit
import Foundation
import LiftCore

/// Visible state of the workout Live Activity (design/delta-live-activity-bodyweight.md).
enum RestActivityPhase: String, Codable, Hashable, Sendable {
    case resting, restOver, ready
}

/// The one rest-timer Live Activity (design/live-activity.md). Shared by the
/// app (starts and updates it) and the widget extension (draws it).
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        /// The set now due (not the one just logged).
        var setNumber: Int?
        /// The prefill (or stepper value) for that set, in the exercise's unit.
        var weight: Double
        var unit: WeightUnit
        var reps: Int
        var bodyweight: Bool
        var kind: LoadKind
        var start: Date
        var end: Date
        /// Rest over (Lift wrote it, or the system marked the Activity stale at zero).
        var over: Bool = false
        /// The ~2 s accentSoft moment after an alert-style rest end.
        var highlight: Bool = false
        var phase: RestActivityPhase = .resting
        var targetWeight: Double? = nil
        var targetReps: Int? = nil
        /// A first-time loaded lift that still needs a weight in the app.
        var needsWeight: Bool = false

        init(exercise: String, setNumber: Int? = nil, weight: Double, unit: WeightUnit, reps: Int,
             bodyweight: Bool = false, kind: LoadKind = .loaded, start: Date, end: Date,
             over: Bool = false, highlight: Bool = false, phase: RestActivityPhase = .resting,
             targetWeight: Double? = nil, targetReps: Int? = nil, needsWeight: Bool = false) {
            self.exercise = exercise
            self.setNumber = setNumber
            self.weight = weight
            self.unit = unit
            self.reps = reps
            self.bodyweight = bodyweight
            self.kind = bodyweight && kind == .loaded ? .bodyweight : kind
            self.start = start
            self.end = end
            self.over = over
            self.highlight = highlight
            self.phase = phase
            self.targetWeight = targetWeight
            self.targetReps = targetReps
            self.needsWeight = needsWeight
        }

        var loadKind: LoadKind { kind }
        var ladder: [String] {
            RestActivityText.ladder(setNumber: setNumber, weight: weight, unit: unit, reps: reps, kind: kind)
        }
        var load: String { RestActivityText.load(weight: weight, unit: unit, reps: reps, kind: kind) }
        var beat: String? {
            guard let tw = targetWeight, let tr = targetReps else { return nil }
            return LoadText.beat(weight: tw, unit: unit, reps: tr, kind: kind)
        }
        var compactTrailing: String {
            LoadText.compactTrailing(weight: weight, unit: unit, reps: reps, kind: kind)
        }
    }

    var workoutID: String
}

/// A tap that isn't a button opens the in-progress workout (AC 109).
enum RestLinks {
    static let workout = URL(string: "lift://workout")!
}
