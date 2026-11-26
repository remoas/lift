import Foundation

// Device-neutral presentation logic shared by the iPhone set row, rest bar and
// PR banner now, and the Watch and Live Activity in phase 2.

public enum SetRowState: Equatable, Sendable {
    case upcoming
    case current
    case done
    case best
}

public struct SetRowModel: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var number: Int
    public var kind: SetKind
    public var lastTime: String?      // "185 × 8", nil = never done
    public var weightText: String?    // "185", nil = "Add weight"
    public var unit: WeightUnit
    public var reps: Int
    public var secondary: String?     // "84 kg" when the other unit is shown
    public var state: SetRowState

    public init(id: UUID, number: Int, kind: SetKind, lastTime: String?, weightText: String?, unit: WeightUnit, reps: Int, secondary: String?, state: SetRowState) {
        self.id = id
        self.number = number
        self.kind = kind
        self.lastTime = lastTime
        self.weightText = weightText
        self.unit = unit
        self.reps = reps
        self.secondary = secondary
        self.state = state
    }

    public var isDone: Bool { state == .done || state == .best }

    public var accessibilityLabel: String {
        let last = lastTime.map { "last time \($0.replacingOccurrences(of: " × ", with: " by "))" } ?? "first time"
        let unitWord = unit == .lb ? "pounds" : "kilograms"
        let today = weightText.map { "today \($0) \(unitWord) by \(reps)" } ?? "no weight yet, \(reps) reps"
        let status = state == .best ? "Done, new best." : (isDone ? "Done." : "Not done.")
        return "Set \(number), \(last), \(today). \(status)"
    }
}

public enum WeightText {
    /// "185 × 8" in `unit`, converting and snapping if needed.
    /// "185 × 8". Bodyweight: "9 reps", or "BW + 25 × 9" with added load (never "0 × 9").
    public static func pair(_ set: SetSnapshot, in unit: WeightUnit, step: Double, bodyweight: Bool = false) -> String {
        let w = UnitMath.convertLoadable(set.weight, from: set.unit, to: unit, step: step)
        if bodyweight { return w <= 0 ? "\(set.reps) reps" : "BW + \(UnitMath.format(w)) × \(set.reps)" }
        return "\(UnitMath.format(w)) × \(set.reps)"
    }

    public static func weight(_ kg: Double, in unit: WeightUnit) -> String {
        let v = UnitMath.convert(kg, from: .kg, to: unit)
        return "\(UnitMath.format(v.rounded())) \(unit.symbol)"
    }

    /// "45 bar, then 45 + 25 + 2.5 a side" or "Closest you can load: 187.5".
    public static func plateLine(target: Double, plates: PlateSet) -> String {
        let load = PlateCalculator.load(target: target, using: plates)
        if !load.isExact { return "Closest you can load: \(UnitMath.format(load.loaded))" }
        if load.perSide.isEmpty { return "Just the bar (\(UnitMath.format(plates.bar)))" }
        return "\(UnitMath.format(plates.bar)) bar, then \(load.perSide.map(UnitMath.format).joined(separator: " + ")) a side"
    }
}

/// The single banner shown for a set: the strongest kind only.
public struct PRBannerContent: Equatable, Sendable {
    public var kind: RecordKind
    public var exercise: String
    public var headline: String   // "205 × 5"
    public var why: String
    public var accessibility: String

    /// Priority: Heaviest > Estimated max > Most reps > Biggest set.
    public static func top(_ kinds: [RecordKind]) -> RecordKind? {
        RecordKind.allCases.first(where: kinds.contains)
    }

    public static func make(kinds: [RecordKind], exercise: String, set: SetSnapshot, history: [SetSnapshot], unit: WeightUnit) -> PRBannerContent? {
        guard let kind = top(kinds) else { return nil }
        let book = PRDetector.book(from: history)
        let w = UnitMath.format(set.weight)
        let headline = "\(w) × \(set.reps)"
        func inUnit(_ kg: Double) -> String { UnitMath.format(UnitMath.convert(kg, from: .kg, to: unit).rounded()) }
        let newE1 = set.e1RMKg.map { inUnit($0) + " " + unit.symbol }
        let why: String
        switch kind {
        case .heaviestWeight:
            let delta = UnitMath.convert(set.weightKg - book.heaviestKg, from: .kg, to: unit)
            var s = "Heaviest yet, up \(UnitMath.format((delta * 2).rounded() / 2)) \(unit.symbol) from \(inUnit(book.heaviestKg))."
            if let newE1 { s += " Estimated max is now \(newE1)." }
            why = s
        case .bestE1RM:
            let delta = UnitMath.convert((set.e1RMKg ?? 0) - book.bestE1RMKg, from: .kg, to: unit)
            why = "Your estimated max is now \(newE1 ?? ""), up \(UnitMath.format(delta.rounded()))."
        case .mostReps:
            let prev = book.mostReps(atOrAboveKg: set.weightKg) ?? 0
            let d = set.reps - prev
            why = "\(set.reps) reps at \(w), \(d) more than ever."
        case .bestVolume:
            why = "Your biggest set of \(exercise), \(UnitMath.format(UnitMath.convert(set.volumeKg, from: .kg, to: unit).rounded())) \(unit.symbol)."
        }
        return PRBannerContent(kind: kind, exercise: exercise, headline: headline, why: why,
                               accessibility: "New best, \(exercise), \(w) by \(set.reps)")
    }
}

/// Date-based rest countdown, correct after backgrounding.
public struct RestCountdown: Equatable, Sendable {
    public var endsAt: Date
    public var total: TimeInterval
    public var setID: UUID?

    public init(seconds: Int, from now: Date = Date(), setID: UUID? = nil) {
        total = TimeInterval(max(seconds, 0))
        endsAt = now.addingTimeInterval(total)
        self.setID = setID
    }

    public func remaining(at date: Date) -> TimeInterval { max(endsAt.timeIntervalSince(date), 0) }
    /// 1 → 0 as rest drains (the draining line).
    public func progress(at date: Date) -> Double { total > 0 ? remaining(at: date) / total : 0 }

    public mutating func adjust(by seconds: Int, now: Date = Date()) {
        endsAt = endsAt.addingTimeInterval(TimeInterval(seconds))
        total = max(total + TimeInterval(seconds), 1)
        if endsAt < now { endsAt = now }
    }

    public static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

public enum Week {
    /// Monday-start week containing `date`.
    public static func start(of date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    public static func count(_ dates: [Date], inWeekOf date: Date, calendar: Calendar = .current) -> Int {
        let s = start(of: date, calendar: calendar)
        let e = s.addingTimeInterval(7 * 86_400)
        return dates.filter { $0 >= s && $0 < e }.count
    }

    public static func ordinal(_ n: Int) -> String {
        let words = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
        return n >= 1 && n <= words.count ? words[n - 1] : "\(n)th"
    }
}
