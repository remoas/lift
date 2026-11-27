import Foundation

/// How a set's load is shown (design/delta-live-activity-bodyweight.md §2).
/// Assisted is detected from the library id, name or variant, and wins over
/// equipment so a band-assisted pull-up is "BW −", not "BW +".
public enum LoadKind: String, Codable, Hashable, Sendable {
    case loaded
    case bodyweight
    case assisted

    public static func resolve(equipment: Equipment, id: String = "", name: String = "", variant: String = "") -> LoadKind {
        if LoadText.isAssisted(id: id, name: name, variant: variant) { return .assisted }
        if equipment == .bodyweight || equipment == .band { return .bodyweight }
        return .loaded
    }
}

/// One formatter for every surface: the Log set row, Beat it, Last, the rest
/// bar, the Live Activity, History, Finish, the PR banner, exercise-detail
/// bests, VoiceOver, and the watch Last / Beat it lines.
public enum LoadText {
    public enum Style: Sendable {
        /// "Bodyweight × 12", "BW + 25 lb × 8", "BW − 40 lb × 8", "185 lb × 9".
        case full
        /// Same as full for these forms (the Activity / Last column).
        case tight
        /// "12 reps", "BW+25×8", "BW−40×8", "185×9".
        case tightest
    }

    public static func isAssisted(id: String, name: String, variant: String) -> Bool {
        [id, name, variant].contains { $0.localizedCaseInsensitiveContains("assisted") }
    }

    public static func pair(weight: Double, unit: WeightUnit, reps: Int, kind: LoadKind, style: Style = .full) -> String {
        let w = UnitMath.format(weight)
        let sym = unit.symbol
        switch kind {
        case .loaded:
            switch style {
            case .full, .tight: return "\(w) \(sym) × \(reps)"
            case .tightest: return "\(w)×\(reps)"
            }
        case .bodyweight:
            if weight <= 0 {
                switch style {
                case .full, .tight: return "Bodyweight × \(reps)"
                case .tightest: return "\(reps) reps"
                }
            }
            switch style {
            case .full, .tight: return "BW + \(w) \(sym) × \(reps)"
            case .tightest: return "BW+\(w)×\(reps)"
            }
        case .assisted:
            if weight <= 0 {
                switch style {
                case .full, .tight: return "Bodyweight × \(reps)"
                case .tightest: return "\(reps) reps"
                }
            }
            switch style {
            case .full, .tight: return "BW − \(w) \(sym) × \(reps)"
            case .tightest: return "BW−\(w)×\(reps)"
            }
        }
    }

    public static func pair(_ set: SetSnapshot, in unit: WeightUnit, step: Double, kind: LoadKind, style: Style = .full) -> String {
        let w = UnitMath.convertLoadable(set.weight, from: set.unit, to: unit, step: step)
        return pair(weight: w, unit: unit, reps: set.reps, kind: kind, style: style)
    }

    /// "Beat 12 reps", "Beat BW + 25 lb × 8", "Beat 185 lb × 9".
    public static func beat(weight: Double, unit: WeightUnit, reps: Int, kind: LoadKind) -> String {
        let style: Style = (kind != .loaded && weight <= 0) ? .tightest : .full
        return "Beat \(pair(weight: weight, unit: unit, reps: reps, kind: kind, style: style))"
    }

    /// Compact Island trailing: "12", "BW+25×8", "185×9".
    public static func compactTrailing(weight: Double, unit: WeightUnit, reps: Int, kind: LoadKind) -> String {
        if kind != .loaded && weight <= 0 { return "\(reps)" }
        return pair(weight: weight, unit: unit, reps: reps, kind: kind, style: .tightest)
    }

    /// "bodyweight, 12 reps"; "bodyweight plus 25 pounds, 8 reps";
    /// "bodyweight minus 40 pounds, 8 reps". Never "0 pounds".
    public static func voiceOver(weight: Double, unit: WeightUnit, reps: Int, kind: LoadKind) -> String {
        let unitWord = unit == .lb ? "pounds" : "kilograms"
        let repsWord = "\(reps) reps"
        switch kind {
        case .loaded:
            return "\(UnitMath.format(weight)) \(unitWord) by \(reps)"
        case .bodyweight:
            return weight <= 0 ? "bodyweight, \(repsWord)" : "bodyweight plus \(UnitMath.format(weight)) \(unitWord), \(repsWord)"
        case .assisted:
            return weight <= 0 ? "bodyweight, \(repsWord)" : "bodyweight minus \(UnitMath.format(weight)) \(unitWord), \(repsWord)"
        }
    }
}
