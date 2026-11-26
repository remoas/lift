import Foundation

/// A weight × reps pair, in the unit it's shown in.
public struct SetTarget: Equatable, Sendable {
    public var weight: Double
    public var reps: Int
    public init(weight: Double, reps: Int) {
        self.weight = weight
        self.reps = reps
    }
}

/// "Beat it": the one progression rule (CDO quick-log spec §2).
///
/// Top set = the heaviest weight, and the most reps at that weight.
/// Reps below the rep goal → same weight × (reps + 1).
/// Reps at or above the goal → next weight step × (goal − 2).
/// Bodyweight → always reps + 1.
///
/// The prefill and the target line both come from `next(lastSets:…)`.
public enum Target {
    public static let defaultRepGoal = 10

    /// The heaviest weight, then the most reps at that weight.
    public static func topSet(_ sets: [SetTarget]) -> SetTarget? {
        sets.filter { $0.reps > 0 }.max { a, b in
            if abs(a.weight - b.weight) > 0.0001 { return a.weight < b.weight }
            return a.reps < b.reps
        }
    }

    public static func next(after top: SetTarget, repGoal: Int, step: Double, bodyweight: Bool) -> SetTarget {
        let goal = max(repGoal, 1)
        if bodyweight || top.reps < goal {
            return SetTarget(weight: top.weight, reps: top.reps + 1)
        }
        return SetTarget(weight: top.weight + step, reps: max(goal - 2, 1))
    }

    /// Target from last session's sets (already in the display unit); nil the first time.
    public static func next(lastSets: [SetTarget], repGoal: Int, step: Double, bodyweight: Bool) -> SetTarget? {
        topSet(lastSets).map { next(after: $0, repGoal: repGoal, step: step, bodyweight: bodyweight) }
    }

    /// Meeting or beating: at least the target weight and at least the target reps.
    public static func isHit(weight: Double, reps: Int, target: SetTarget) -> Bool {
        weight >= target.weight - 0.0001 && reps >= target.reps
    }
}
