import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme

    var body: some View {
        Group {
            if !appState.hasSeenOnboarding {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea(.all))
        .animation(.easeInOut, value: appState.hasSeenOnboarding)
    }
}
