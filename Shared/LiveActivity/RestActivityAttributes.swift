import ActivityKit
import Foundation
import LiftCore

/// The one rest-timer Live Activity (design/live-activity.md). Shared by the
/// app (starts and updates it) and the widget extension (draws it).
struct RestActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        /// The set now due (not the one just logged).
        var setNumber: Int?
        /// The prefill for that set (LiftStore.prefill), in the exercise's unit.
        var weight: Double
        var unit: WeightUnit
        var reps: Int
        var bodyweight: Bool
        var start: Date
        var end: Date
        /// Rest over (Lift wrote it, or the system marked the Activity stale at zero).
        var over: Bool = false
        /// The ~2 s accentSoft moment after an alert-style rest end.
        var highlight: Bool = false

        var ladder: [String] {
            RestActivityText.ladder(setNumber: setNumber, weight: weight, unit: unit, reps: reps, bodyweight: bodyweight)
        }
        var load: String { RestActivityText.load(weight: weight, unit: unit, reps: reps, bodyweight: bodyweight) }
    }

    var workoutID: String
}

/// A tap that isn't +30s or Skip opens the in-progress workout (AC 109).
enum RestLinks {
    static let workout = URL(string: "lift://workout")!
}
