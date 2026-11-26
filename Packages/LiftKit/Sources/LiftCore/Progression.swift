import Foundation

/// A target for the next session.
public struct SetTarget: Equatable, Sendable {
    public var weight: Double
    public var reps: Int
    public init(weight: Double, reps: Int) {
        self.weight = weight
        self.reps = reps
    }
}

public enum Progression {
    /// Double progression within a rep range. When every working set reached the
    /// top of the range, add one plate step and drop to the bottom of the range.
    /// Otherwise keep the weight and aim for one more rep (capped at the top).
    /// Weight stays in the unit it was entered in.
    public static func doubleProgression(lastWorkingSets: [SetTarget], repRange: ClosedRange<Int>, step: Double) -> [SetTarget] {
        guard !lastWorkingSets.isEmpty else { return [] }
        let allAtTop = lastWorkingSets.allSatisfy { $0.reps >= repRange.upperBound }
        if allAtTop {
            return lastWorkingSets.map { SetTarget(weight: $0.weight + step, reps: repRange.lowerBound) }
        }
        return lastWorkingSets.map { SetTarget(weight: $0.weight, reps: min($0.reps + 1, repRange.upperBound)) }
    }
}
