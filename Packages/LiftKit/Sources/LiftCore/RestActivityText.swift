import Foundation

/// Copy and rules for the rest-timer Live Activity (design/live-activity.md).
/// Pure, so the phone app, the widget extension and the tests share it.
public enum RestActivityText {
    /// Full load copy. Unloaded bodyweight / band is "Bodyweight × 12".
    public static func load(weight: Double, unit: WeightUnit, reps: Int, kind: LoadKind, style: LoadText.Style = .full) -> String {
        LoadText.pair(weight: weight, unit: unit, reps: reps, kind: kind, style: style)
    }

    /// Compatibility: `bodyweight: true` is the unloaded / added-load kind.
    public static func load(weight: Double, unit: WeightUnit, reps: Int, bodyweight: Bool) -> String {
        load(weight: weight, unit: unit, reps: reps, kind: bodyweight ? .bodyweight : .loaded)
    }

    /// §8 ladder, widest first: "Set 3 · 185 lb × 9" → "185 lb × 9" → "185×9".
    /// Bodyweight: "Set 3 · Bodyweight × 9" → "Bodyweight × 9" → "9 reps".
    /// Never cut mid-number; the view picks the first that fits.
    public static func ladder(setNumber: Int?, weight: Double, unit: WeightUnit, reps: Int, kind: LoadKind) -> [String] {
        let full = load(weight: weight, unit: unit, reps: reps, kind: kind, style: .full)
        let tightest = load(weight: weight, unit: unit, reps: reps, kind: kind, style: .tightest)
        var out: [String] = []
        if let n = setNumber { out.append("Set \(n) · \(full)") }
        out.append(full)
        if tightest != full { out.append(tightest) }
        return out
    }

    public static func ladder(setNumber: Int?, weight: Double, unit: WeightUnit, reps: Int, bodyweight: Bool) -> [String] {
        ladder(setNumber: setNumber, weight: weight, unit: unit, reps: reps, kind: bodyweight ? .bodyweight : .loaded)
    }

    public static func beat(weight: Double, unit: WeightUnit, reps: Int, kind: LoadKind) -> String {
        LoadText.beat(weight: weight, unit: unit, reps: reps, kind: kind)
    }

    /// §8 / AC 111, widest first: the full name, then word-boundary tails
    /// ("Single-Arm Dumbbell Incline…"), never a cut mid-word.
    public static func nameCandidates(_ name: String) -> [String] {
        let words = name.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 1 else { return [name] }
        var out = [name]
        for k in stride(from: words.count - 1, through: 1, by: -1) {
            var head = words.prefix(k).joined(separator: " ")
            // No dangling punctuation before the ellipsis ("Press (Neutral…" is fine; "Press -…" isn't).
            while let last = head.last, ",-·(/".contains(last) { head.removeLast() }
            head = head.trimmingCharacters(in: .whitespaces)
            if !head.isEmpty, out.last != head + "…" { out.append(head + "…") }
        }
        return out
    }

    /// "Rest over · Set 3".
    public static func restOver(setNumber: Int?) -> String {
        setNumber.map { "Rest over · Set \($0)" } ?? "Rest over"
    }

    /// The fallback notification when no Activity is running:
    /// "Rest over. Barbell Bench Press, 185 lb × 9."
    public static func notificationBody(exercise: String?, next: String?) -> String {
        switch (exercise, next) {
        case let (e?, n?): return "Rest over. \(e), \(n)."
        case let (e?, nil): return "Rest over. \(e)."
        case let (nil, n?): return "Rest over. \(n)."
        default: return "Rest over."
        }
    }
}

/// When the Activity alerts, and how long it stays (design/live-activity.md §5–6).
public enum RestActivityPolicy {
    public enum RestEnd: Equatable, Sendable {
        /// Alert-style update: the phone is the winner and Lift isn't on screen.
        case alert
        /// Copy change only: the watch is buzzing, or the rest bar is in view.
        case quiet
    }

    public static func atRestEnd(watchAlerts: Bool, appActive: Bool) -> RestEnd {
        !watchAlerts && !appActive ? .alert : .quiet
    }

    /// The system dims it 2 min after rest-end.
    public static func staleDate(end: Date) -> Date { end.addingTimeInterval(120) }
    /// Gone 5 min after rest-end.
    public static func dismissAt(end: Date) -> Date { end.addingTimeInterval(300) }
    /// Skip leaves "Rest over" up for the length of the in-app Undo.
    public static let skipDismissAfter: TimeInterval = 5
    /// The rest-over highlight.
    public static let highlightSeconds: TimeInterval = 2
}
