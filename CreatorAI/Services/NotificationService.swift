import Foundation
import UserNotifications

/// Requests permission and sends local notifications (e.g. when export is ready).
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    /// Call before starting export so the user can allow notifications. Completion runs on main queue.
    func requestPermissionIfNeeded(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                completion?(granted)
            }
        }
    }

    /// Send a local notification when the video is ready. Call from background when render completes.
    func notifyVideoReady(videoName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Video ready"
        content.body = "\"\(videoName)\" is ready to view in Library."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "video-ready-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Notification] Failed to schedule: \(error)")
            }
        }
    }

    /// Send a local notification when export failed.
    func notifyVideoFailed(videoName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Export failed"
        content.body = "\"\(videoName)\" could not be exported."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "video-failed-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Notification] Failed to schedule: \(error)")
            }
        }
    }
}
