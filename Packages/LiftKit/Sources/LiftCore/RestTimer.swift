import Foundation

/// Which device started a rest.
public enum LiftDevice: String, Codable, Sendable { case phone, watch }

/// A running rest, shared by the phone and the watch. Times are absolute, so
/// both devices count down to the same moment.
public struct RestState: Codable, Equatable, Sendable {
    public var countdown: RestCountdown
    /// The exercise of the set just logged, and "185 × 9" for the next one.
    public var exercise: String?
    public var next: String?
    public var origin: LiftDevice

    public init(seconds: Int, from now: Date = Date(), setID: UUID? = nil, exercise: String? = nil, next: String? = nil, origin: LiftDevice) {
        countdown = RestCountdown(seconds: seconds, from: now, setID: setID)
        self.exercise = exercise; self.next = next; self.origin = origin
    }

    public init(countdown: RestCountdown, exercise: String?, next: String?, origin: LiftDevice) {
        self.countdown = countdown; self.exercise = exercise; self.next = next; self.origin = origin
    }

    public var endsAt: Date { countdown.endsAt }
    public func remaining(at now: Date) -> TimeInterval { countdown.remaining(at: now) }
    public func isOver(at now: Date) -> Bool { remaining(at: now) <= 0 }

    /// +30 s (or any step); from an already-finished rest it counts from now.
    public func adding(_ seconds: Int, now: Date = Date()) -> RestState {
        var r = self
        if r.isOver(at: now) { r.countdown.endsAt = now }
        r.countdown.adjust(by: seconds, now: now)
        return r
    }

    /// "Rest's up. Bench Press, 185 × 6."
    public var alertBody: String {
        if let exercise, let next { return "Rest's up. \(exercise), \(next)." }
        return "Rest's up."
    }
}

/// Who buzzes when rest ends, so there is exactly one alert.
///
/// - Watch workout running and reachable: the watch alerts (haptic, wrist down
///   too, because the workout session keeps it running); the phone schedules
///   nothing, or iOS would mirror its notification to the wrist as a second buzz.
/// - Otherwise: the phone's local notification, which iOS forwards to the
///   watch when the phone is locked. Phone-only use always works.
public enum RestAlertPolicy {
    public struct Plan: Equatable, Sendable {
        public var phoneNotificationAt: Date?
        public var watchAlertAt: Date?
    }

    /// Notifications under a second away aren't worth scheduling.
    public static let minimumLead: TimeInterval = 1

    public static func plan(rest: RestState?, now: Date, watchSessionActive: Bool, watchReachable: Bool) -> Plan {
        guard let rest, rest.endsAt.timeIntervalSince(now) > minimumLead else { return Plan() }
        if watchSessionActive && watchReachable { return Plan(phoneNotificationAt: nil, watchAlertAt: rest.endsAt) }
        return Plan(phoneNotificationAt: rest.endsAt, watchAlertAt: nil)
    }
}

/// Rest choices (15 s steps to 2 min, then 30 s to 5 min) for phone and watch pickers.
public enum RestChoices {
    public static let base = [30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240, 300]
    public static func all(including current: Int) -> [Int] {
        base.contains(current) ? base : (base + [current]).sorted()
    }
}

/// Health saving, so a workout reaches Apple Health exactly once.
public enum HealthOwnership {
    /// The watch saves a workout it ran a session for (its builder has the heart
    /// rate). The phone saves only when there was no watch session, or the
    /// watch said its save failed.
    public static func phoneShouldSave(healthEnabled: Bool?, watchRanSession: Bool, watchSaveFailed: Bool, alreadySaved: Bool) -> Bool {
        guard healthEnabled == true, !alreadySaved else { return false }
        return !watchRanSession || watchSaveFailed
    }
}
