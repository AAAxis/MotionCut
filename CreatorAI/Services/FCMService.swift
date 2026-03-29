import Foundation
import UIKit
import FirebaseMessaging
import UserNotifications

/// Handles FCM token registration and push notification display.
/// Mirrors Android FCMService — saves token to Supabase app_users table.
final class FCMService: NSObject, MessagingDelegate, UNUserNotificationCenterDelegate {
    static let shared = FCMService()

    private override init() {
        super.init()
    }

    /// Call once at app launch (after Firebase.configure).
    func configure() {
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("[FCM] Notification permission granted: \(granted)")
            if let error { print("[FCM] Permission error: \(error)") }
        }

        // Register for remote notifications
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Register current FCM token for a user. Call after successful sign-in.
    func registerTokenForUser(userId: String) {
        Messaging.messaging().token { token, error in
            guard let token else {
                print("[FCM] Failed to get token: \(error?.localizedDescription ?? "unknown")")
                return
            }
            print("[FCM] Token: \(token)")
            Task {
                await SupabaseService.shared.saveFCMToken(userId: userId, token: token)
            }
        }
    }

    // MARK: - MessagingDelegate

    /// Called when FCM token is refreshed.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        print("[FCM] Token refreshed: \(fcmToken)")

        // Get cached userId and update Supabase
        if let userId = UserDefaults.standard.string(forKey: "cached_user_id") {
            Task {
                await SupabaseService.shared.saveFCMToken(userId: userId, token: fcmToken)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show push notifications while app is in foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("[FCM] Notification tapped: \(userInfo)")
        completionHandler()
    }
}
