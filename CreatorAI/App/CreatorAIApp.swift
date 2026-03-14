import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppsFlyerService.shared.configure()
        return true
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
                if let action = DeeplinkService.parse(url) {
                    appState.pendingDeeplink = action
                }
            }
        }
    }
}
