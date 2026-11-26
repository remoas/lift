import Foundation
import Observation
import LiftCore

/// App-wide preferences, stored on device.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var unit: WeightUnit { didSet { defaults.set(unit.rawValue, forKey: Keys.unit) } }
    var showOtherUnit: Bool { didSet { defaults.set(showOtherUnit, forKey: Keys.secondary) } }
    var autoStartRest: Bool { didSet { defaults.set(autoStartRest, forKey: Keys.autoRest) } }
    var workingRestSeconds: Int { didSet { defaults.set(workingRestSeconds, forKey: Keys.workingRest) } }
    var warmupRestSeconds: Int { didSet { defaults.set(warmupRestSeconds, forKey: Keys.warmupRest) } }
    var celebrateBanner: Bool { didSet { defaults.set(celebrateBanner, forKey: Keys.banner) } }
    var celebrateHaptic: Bool { didSet { defaults.set(celebrateHaptic, forKey: Keys.haptic) } }
    var plateSetKg: PlateSet { didSet { save(plateSetKg, Keys.platesKg) } }
    var plateSetLb: PlateSet { didSet { save(plateSetLb, Keys.platesLb) } }
    /// nil = never asked; true = asked and the user chose to save.
    var healthEnabled: Bool? {
        didSet { if let healthEnabled { defaults.set(healthEnabled, forKey: Keys.health) } else { defaults.removeObject(forKey: Keys.health) } }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Ben's Bermuda gym is in pounds, so lb is the default.
        unit = WeightUnit(rawValue: defaults.string(forKey: Keys.unit) ?? "") ?? .lb
        showOtherUnit = defaults.object(forKey: Keys.secondary) as? Bool ?? false
        autoStartRest = defaults.object(forKey: Keys.autoRest) as? Bool ?? true
        workingRestSeconds = defaults.object(forKey: Keys.workingRest) as? Int ?? 120
        warmupRestSeconds = defaults.object(forKey: Keys.warmupRest) as? Int ?? 60
        celebrateBanner = defaults.object(forKey: Keys.banner) as? Bool ?? true
        celebrateHaptic = defaults.object(forKey: Keys.haptic) as? Bool ?? true
        healthEnabled = defaults.object(forKey: Keys.health) as? Bool
        plateSetKg = Self.load(defaults, Keys.platesKg) ?? .standardKg
        plateSetLb = Self.load(defaults, Keys.platesLb) ?? .standardLb
    }

    func plates(for unit: WeightUnit) -> PlateSet { unit == .kg ? plateSetKg : plateSetLb }

    func setPlates(_ set: PlateSet) {
        if set.unit == .kg { plateSetKg = set } else { plateSetLb = set }
    }

    private func save(_ set: PlateSet, _ key: String) {
        defaults.set(try? JSONEncoder().encode(set), forKey: key)
    }

    private static func load(_ d: UserDefaults, _ key: String) -> PlateSet? {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(PlateSet.self, from: $0) }
    }

    private enum Keys {
        static let unit = "lift.unit"
        static let secondary = "lift.showOtherUnit"
        static let autoRest = "lift.autoRest"
        static let workingRest = "lift.workingRest"
        static let warmupRest = "lift.warmupRest"
        static let banner = "lift.celebrate.banner"
        static let haptic = "lift.celebrate.haptic"
        static let platesKg = "lift.plates.kg"
        static let platesLb = "lift.plates.lb"
        static let health = "lift.health"
    }
}
