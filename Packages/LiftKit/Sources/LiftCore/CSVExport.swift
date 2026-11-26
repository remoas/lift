import Foundation

public struct ExportRow: Sendable {
    public var workoutID: UUID
    public var workoutStart: Date
    public var workoutEnd: Date?
    public var routine: String
    public var exercise: String
    public var setOrder: Int
    public var set: SetSnapshot

    public init(workoutID: UUID, workoutStart: Date, workoutEnd: Date?, routine: String, exercise: String, setOrder: Int, set: SetSnapshot) {
        self.workoutID = workoutID
        self.workoutStart = workoutStart
        self.workoutEnd = workoutEnd
        self.routine = routine
        self.exercise = exercise
        self.setOrder = setOrder
        self.set = set
    }
}

public enum CSVExport {
    public static let header = ["workout_id", "workout_start", "workout_end", "routine", "exercise", "set_order", "set_type", "weight", "unit", "reps", "weight_kg", "e1rm_kg", "set_done_at", "set_id"]

    public static func csv(_ rows: [ExportRow]) -> String {
        let iso = ISO8601DateFormatter()
        var lines = [header.joined(separator: ",")]
        for r in rows {
            let fields = [
                r.workoutID.uuidString,
                iso.string(from: r.workoutStart),
                r.workoutEnd.map { iso.string(from: $0) } ?? "",
                r.routine,
                r.exercise,
                String(r.setOrder),
                r.set.kind.rawValue,
                UnitMath.format(r.set.weight),
                r.set.unit.rawValue,
                String(r.set.reps),
                UnitMath.format(r.set.weightKg),
                r.set.e1RMKg.map { UnitMath.format($0) } ?? "",
                iso.string(from: r.set.date),
                r.set.id.uuidString,
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
