import Foundation

public enum RecordKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case heaviestWeight
    case bestE1RM
    case mostReps
    case bestVolume

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .heaviestWeight: return "Heaviest weight"
        case .bestE1RM: return "Best e1RM"
        case .mostReps: return "Most reps"
        case .bestVolume: return "Best set volume"
        }
    }
}

/// The best values for one exercise, all in kilograms.
public struct RecordBook: Equatable, Sendable {
    public var heaviestKg: Double = 0
    public var bestE1RMKg: Double = 0
    public var bestVolumeKg: Double = 0
    /// Working sets considered, kept for the "most reps at this weight or heavier" check.
    public private(set) var sets: [SetSnapshot] = []

    public init() {}

    public var isEmpty: Bool { sets.isEmpty }

    public mutating func add(_ set: SetSnapshot) {
        guard set.kind.countsForRecords, set.reps > 0 else { return }
        sets.append(set)
        heaviestKg = max(heaviestKg, set.weightKg)
        if let e = set.e1RMKg { bestE1RMKg = max(bestE1RMKg, e) }
        bestVolumeKg = max(bestVolumeKg, set.volumeKg)
    }

    /// Most reps done at `weightKg` or heavier, or nil if never lifted that heavy.
    public func mostReps(atOrAboveKg weightKg: Double) -> Int? {
        sets.filter { $0.weightKg >= weightKg - PRDetector.toleranceKg }.map(\.reps).max()
    }
}

public enum PRDetector {
    /// Unit round-trips (e.g. 100 kg vs 220.5 lb) must never fake a PR.
    public static let toleranceKg = 0.05

    public static func book(from history: [SetSnapshot]) -> RecordBook {
        var book = RecordBook()
        for set in history { book.add(set) }
        return book
    }

    /// Records the candidate set beats.
    ///
    /// - `history`: this exercise's earlier working sets (earlier workouts plus
    ///   sets already ticked today).
    /// - The first-ever session sets baselines quietly: if no set exists from a
    ///   *different* workout, nothing is reported.
    public static func newRecords(for candidate: SetSnapshot, history: [SetSnapshot]) -> [RecordKind] {
        guard candidate.kind.countsForRecords, candidate.reps > 0 else { return [] }
        let earlier = history.filter { $0.id != candidate.id && $0.kind.countsForRecords && $0.reps > 0 }
        guard earlier.contains(where: { $0.workoutID != candidate.workoutID }) else { return [] }

        let book = book(from: earlier)
        var result: [RecordKind] = []
        let w = candidate.weightKg
        if w > 0, w > book.heaviestKg + toleranceKg { result.append(.heaviestWeight) }
        if let e = candidate.e1RMKg, e > book.bestE1RMKg + toleranceKg * 1.4 { result.append(.bestE1RM) }
        if let previousBest = book.mostReps(atOrAboveKg: w), candidate.reps > previousBest {
            result.append(.mostReps)
        }
        if candidate.volumeKg > 0, candidate.volumeKg > book.bestVolumeKg + toleranceKg * Double(candidate.reps) { result.append(.bestVolume) }
        return result
    }
}
