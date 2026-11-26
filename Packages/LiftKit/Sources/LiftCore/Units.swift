import Foundation

/// The two units Lift understands. Every set stores the number the user
/// entered plus its unit; comparisons happen in kilograms.
public enum WeightUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case kg
    case lb

    public var id: String { rawValue }
    public var symbol: String { rawValue }
    public var other: WeightUnit { self == .kg ? .lb : .kg }

    /// Default ± step on the weight stepper: one small plate pair.
    public var defaultStep: Double { self == .kg ? 2.5 : 5 }
}

public enum UnitMath {
    public static let poundsPerKilogram = 2.20462

    /// Converts a weight to kilograms, the single internal unit for comparisons.
    public static func kilograms(_ value: Double, _ unit: WeightUnit) -> Double {
        unit == .kg ? value : value / poundsPerKilogram
    }

    public static func convert(_ value: Double, from: WeightUnit, to: WeightUnit) -> Double {
        if from == to { return value }
        return to == .kg ? value / poundsPerKilogram : value * poundsPerKilogram
    }

    /// Rounds to the nearest multiple of `step` (the nearest weight you can load).
    public static func round(_ value: Double, toStep step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    /// Converts and snaps to a loadable increment in the target unit.
    public static func convertLoadable(_ value: Double, from: WeightUnit, to: WeightUnit, step: Double? = nil) -> Double {
        if from == to { return value }
        return round(convert(value, from: from, to: to), toStep: step ?? to.defaultStep)
    }

    /// "100", "102.5", "1.25" – no trailing zeros, at most two decimals.
    public static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var s = String(format: "%.2f", rounded)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }
}
