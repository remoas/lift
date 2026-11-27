import Foundation

/// A weight × reps pair, in the unit it's shown in.
public struct SetTarget: Codable, Hashable, Sendable {
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
/// Unloaded bodyweight / band → always reps + 1.
/// Added load on a bodyweight lift follows the ordinary weight rule.
/// Assistance decreases by the plate step after a hit, then becomes
/// unloaded Bodyweight at 0.
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

    public static func next(after top: SetTarget, repGoal: Int, step: Double, bodyweight: Bool, assisted: Bool = false) -> SetTarget {
        let goal = max(repGoal, 1)
        // Unloaded bodyweight, band, or assistance that has reached 0: always reps + 1.
        if (bodyweight || assisted) && top.weight <= 0 {
            return SetTarget(weight: 0, reps: top.reps + 1)
        }
        if assisted {
            if top.reps < goal {
                return SetTarget(weight: top.weight, reps: top.reps + 1)
            }
            return SetTarget(weight: max(top.weight - step, 0), reps: max(goal - 2, 1))
        }
        if top.reps < goal {
            return SetTarget(weight: top.weight, reps: top.reps + 1)
        }
        return SetTarget(weight: top.weight + step, reps: max(goal - 2, 1))
    }

    /// Target from last session's sets (already in the display unit); nil the first time.
    public static func next(lastSets: [SetTarget], repGoal: Int, step: Double, bodyweight: Bool, assisted: Bool = false) -> SetTarget? {
        topSet(lastSets).map { next(after: $0, repGoal: repGoal, step: step, bodyweight: bodyweight, assisted: assisted) }
    }

    /// Prefill for an unlogged set (Ben, 2:16 pm: "Prefill the next set with
    /// what I just did"): the set just logged this session if there is one;
    /// otherwise (the first set) the target; first time ever, last time's set or nil.
    public static func prefill(justLogged: SetTarget?, target: SetTarget?, lastTime: SetTarget? = nil) -> SetTarget? {
        justLogged ?? target ?? lastTime
    }

    /// Meeting or beating: at least the target weight and at least the target reps.
    public static func isHit(weight: Double, reps: Int, target: SetTarget, assisted: Bool = false) -> Bool {
        if assisted {
            return weight <= target.weight + 0.0001 && reps >= target.reps
        }
        return weight >= target.weight - 0.0001 && reps >= target.reps
    }
}
