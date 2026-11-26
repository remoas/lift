import Foundation
import UserNotifications

/// The local notification that fires when rest ends while Lift is in the
/// background. PhoneSync decides whether the phone or the watch alerts.
enum RestNotifications {
    private static let id = "lift.rest"

    static func requestPermissionIfNeeded() {
        #if DEBUG
        // Screenshot fixtures and UI tests: never raise the system prompt over a frame.
        if Fixtures.requested != nil { return }
        #endif
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// "Rest over. Barbell Bench Press, 185 lb × 9." Only when no Live Activity can alert.
    static func schedule(at date: Date, body: String) {
        cancel()
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
