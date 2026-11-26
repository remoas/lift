import Foundation

/// One slot of a routine or a workout, for comparing structure only.
public struct PlanSlot: Equatable, Sendable {
    public var exerciseID: UUID
    public var name: String
    public var sets: Int
    public init(exerciseID: UUID, name: String, sets: Int) {
        self.exerciseID = exerciseID
        self.name = name
        self.sets = sets
    }
}

/// Plain-language diff for "Update {Routine} routine with today's changes".
/// Weights and reps are never part of it.
public enum RoutineDiff {
    public static func changes(routine: [PlanSlot], workout: [PlanSlot]) -> [String] {
        guard routine != workout else { return [] }
        var out: [String] = []
        let oldIDs = routine.map(\.exerciseID), newIDs = workout.map(\.exerciseID)
        var removed = routine.filter { !newIDs.contains($0.exerciseID) }
        var added = workout.filter { !oldIDs.contains($0.exerciseID) }
        // Pair an added and a removed exercise in the same position as a swap.
        for (i, slot) in workout.enumerated() where added.contains(slot) {
            if i < routine.count, let r = removed.firstIndex(of: routine[i]) {
                out.append("\(slot.name) instead of \(routine[i].name).")
                removed.remove(at: r)
                added.removeAll { $0 == slot }
            }
        }
        for a in added { out.append("\(a.name) added.") }
        for r in removed { out.append("\(r.name) removed.") }
        for slot in workout {
            if let old = routine.first(where: { $0.exerciseID == slot.exerciseID }), old.sets != slot.sets {
                out.append("\(slot.name) \(old.sets) → \(slot.sets) sets.")
            }
        }
        let keptOld = oldIDs.filter(newIDs.contains), keptNew = newIDs.filter(oldIDs.contains)
        if keptOld != keptNew { out.append("New order.") }
        return out
    }

    /// At most two sentences, then "…and n more changes".
    public static func summary(_ changes: [String]) -> String {
        guard changes.count > 2 else { return changes.joined(separator: " ") }
        let more = changes.count - 2
        return changes.prefix(2).joined(separator: " ") + " …and \(more) more change\(more == 1 ? "" : "s")"
    }
}

extension History {
    /// Sets from the most recent workout (any routine, or blank) that included
    /// this exercise. "Last time" and prefill both come from here.
    public static func lastSession(for exerciseID: UUID, in all: [LoggedSet], excluding workoutID: UUID? = nil) -> [LoggedSet] {
        let sets = all.filter { $0.exerciseID == exerciseID && $0.isDone && $0.snapshot.workoutID != workoutID }
        guard let latest = sets.max(by: { $0.snapshot.date < $1.snapshot.date })?.snapshot.workoutID else { return [] }
        return sets.filter { $0.snapshot.workoutID == latest }.sorted { $0.snapshot.date < $1.snapshot.date }
    }
}
