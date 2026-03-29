import SwiftUI
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        // Configure Google Sign-In
        // iOS client ID from GoogleService-Info.plist
        if let clientID = FirebaseApp.app()?.options.clientID {
            // Server client ID (client_type: 3) from google-services.json — needed for Firebase Auth
            let serverClientID = "918788275830-d98he7rtcdo4s3pgcfbjr9bf9thh2n1g.apps.googleusercontent.com"
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
                clientID: clientID,
                serverClientID: serverClientID
            )
        }

        FCMService.shared.configure()
        AppsFlyerService.shared.configure()
        return true
    }

    // Forward remote notification token to Firebase
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // Handle Google Sign-In redirect
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

@main
struct CreatorAIApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup {
            ZStack {
                // Fill entire window (including status bar area) so no black bar appears
                Color(UIColor.systemBackground)
                    .ignoresSafeArea(.all)
                ContentView()
                    .environmentObject(appState)
                    .environment(\.theme, AppColors(isDark: true))
                    .preferredColorScheme(.dark)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                AppsFlyerService.shared.start()
                AppsFlyerService.shared.requestTrackingAuthorization()
                Task { await PurchaseService.shared.loadOfferings() }
            }
            .onOpenURL { url in
                // Let Google Sign-In handle its callback
                GIDSignIn.sharedInstance.handle(url)

                if let action = DeeplinkService.parse(url) {
                    appState.pendingDeeplink = action
                }
            }
        }
    }
}
