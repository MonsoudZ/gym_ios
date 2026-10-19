import Foundation
import UserNotifications

/// Fires a local notification when a rest ends, so the countdown survives the phone locking.
/// In the foreground nothing is presented (no notification delegate), so the in-app bar and
/// haptic remain the only signal there.
enum RestNotifier {
    static let identifier = "rest-timer"

    static func schedule(endsAt: Date, exerciseName: String) async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        cancel()
        let seconds = endsAt.timeIntervalSinceNow
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest done"
        content.body = "Next set of \(exerciseName)."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
