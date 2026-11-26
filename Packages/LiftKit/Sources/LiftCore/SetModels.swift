import Foundation

public enum SetKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case warmup
    case working
    case drop
    case failure

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .warmup: return "Warm-up"
        case .working: return "Working"
        case .drop: return "Drop"
        case .failure: return "Failure"
        }
    }

    public var shortLabel: String {
        switch self {
        case .warmup: return "W"
        case .working: return ""
        case .drop: return "D"
        case .failure: return "F"
        }
    }

    /// Records only count working sets (failure sets are still working sets taken to failure).
    public var countsForRecords: Bool { self == .working || self == .failure }
}

/// A logged set as plain values. Every set has its own UUID so the Watch
/// (phase 2) can resend a set without ever duplicating it.
public struct SetSnapshot: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var workoutID: UUID
    public var weight: Double
    public var unit: WeightUnit
    public var reps: Int
    public var kind: SetKind
    public var date: Date

    public init(id: UUID = UUID(), workoutID: UUID, weight: Double, unit: WeightUnit, reps: Int, kind: SetKind = .working, date: Date) {
        self.id = id
        self.workoutID = workoutID
        self.weight = weight
        self.unit = unit
        self.reps = reps
        self.kind = kind
        self.date = date
    }

    public var weightKg: Double { UnitMath.kilograms(weight, unit) }
    public var e1RMKg: Double? { OneRepMax.epley(weightKg: weightKg, reps: reps) }
    public var volumeKg: Double { weightKg * Double(max(reps, 0)) }
}
