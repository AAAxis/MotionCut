import SwiftUI
import FirebaseCore

#if os(iOS)
import FirebaseMessaging
import GoogleSignIn
#endif

// MARK: - App Delegate

#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        if let clientID = FirebaseApp.app()?.options.clientID {
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

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}
#else
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FirebaseApp.configure()
    }
}
#endif

// MARK: - App

@main
struct CreatorAIApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #else
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ZStack {
                #if os(iOS)
                Color(UIColor.systemBackground)
                    .ignoresSafeArea(.all)
                #else
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea(.all)
                #endif

                ContentView()
                    .environmentObject(appState)
                    .environment(\.theme, AppColors(isDark: true))
                    .preferredColorScheme(.dark)
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                AppsFlyerService.shared.start()
                AppsFlyerService.shared.requestTrackingAuthorization()
                Task { await PurchaseService.shared.loadOfferings() }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
                if let action = DeeplinkService.parse(url) {
                    appState.pendingDeeplink = action
                }
            }
            #else
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await PurchaseService.shared.loadOfferings() }
            }
            .onOpenURL { url in
                if let action = DeeplinkService.parse(url) {
                    appState.pendingDeeplink = action
                }
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1400, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Editor") {
                Button("Play / Pause") {
                    NotificationCenter.default.post(name: .togglePlayback, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Split Clip") {
                    NotificationCenter.default.post(name: .splitClip, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)
            }
        }
        #endif
    }
}

// MARK: - macOS command notification names

extension Notification.Name {
    static let togglePlayback = Notification.Name("togglePlayback")
    static let splitClip = Notification.Name("splitClip")
}
