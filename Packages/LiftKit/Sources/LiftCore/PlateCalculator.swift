import Foundation

public struct PlateSet: Codable, Equatable, Sendable {
    public var unit: WeightUnit
    public var bar: Double
    /// Plate sizes available, any order. Unlimited pairs of each are assumed.
    public var plates: [Double]

    public init(unit: WeightUnit, bar: Double, plates: [Double]) {
        self.unit = unit
        self.bar = bar
        self.plates = plates
    }

    public static let standardKg = PlateSet(unit: .kg, bar: 20, plates: [25, 20, 15, 10, 5, 2.5, 1.25])
    public static let standardLb = PlateSet(unit: .lb, bar: 45, plates: [45, 35, 25, 10, 5, 2.5])

    public static func standard(for unit: WeightUnit) -> PlateSet {
        unit == .kg ? standardKg : standardLb
    }
}

public struct PlateLoad: Equatable, Sendable {
    /// Plates for ONE side of the bar, heaviest first.
    public var perSide: [Double]
    /// Total weight actually loaded (bar + both sides).
    public var loaded: Double
    /// Target minus loaded; non-zero when the target can't be made exactly.
    public var remainder: Double

    public var isExact: Bool { abs(remainder) < 0.001 }
}

public enum PlateCalculator {
    /// Greedy per-side loading, which is exact for standard plate sets.
    public static func load(target: Double, using set: PlateSet) -> PlateLoad {
        guard target > set.bar else {
            return PlateLoad(perSide: [], loaded: set.bar, remainder: target - set.bar)
        }
        var perSideRemaining = (target - set.bar) / 2
        var perSide: [Double] = []
        for plate in set.plates.filter({ $0 > 0 }).sorted(by: >) {
            while perSideRemaining + 0.0001 >= plate {
                perSide.append(plate)
                perSideRemaining -= plate
            }
        }
        let loaded = set.bar + 2 * perSide.reduce(0, +)
        let remainder = ((target - loaded) * 1000).rounded() / 1000
        return PlateLoad(perSide: perSide, loaded: loaded, remainder: remainder)
    }
}
