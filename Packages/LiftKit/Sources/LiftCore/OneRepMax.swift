import Foundation

public enum OneRepMax {
    /// Epley sets are only trusted up to this many reps.
    public static let maxReps = 12

    /// Epley estimate: weight × (1 + reps / 30). Returns nil above 12 reps or for
    /// empty sets. A single counts as itself so a true 1RM is never inflated.
    public static func epley(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, reps >= 1, reps <= maxReps else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }
}
