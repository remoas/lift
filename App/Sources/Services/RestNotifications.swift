import Foundation
import UserNotifications

/// The local notification that fires when rest ends while Lift is in the background.
enum RestNotifications {
    private static let id = "lift.rest"

    static func requestPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// "Rest's up. Bench Press, 185 × 6."
    static func schedule(at date: Date, exercise: String?, next: String?) {
        cancel()
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        if let exercise, let next {
            content.body = "Rest's up. \(exercise), \(next)."
        } else {
            content.body = "Rest's up."
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
