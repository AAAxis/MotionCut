import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @State private var navigationPath = NavigationPath()
    @State private var selectedTab = 1

    var body: some View {
        NavigationStack(path: $navigationPath) {
            TabView(selection: $selectedTab) {
                LibraryView()
                    .tabItem {
                        Image(systemName: "play.rectangle.fill")
                        Text("Library")
                    }
                    .tag(0)

                CreateView()
                    .tabItem {
                        Image(systemName: "plus.circle.fill")
                        Text("Create")
                    }
                    .tag(1)

                SettingsView(showCloseButton: false, userId: appState.userId ?? "demo-user")
                    .tabItem {
                        Image(systemName: "person.fill")
                        Text("Profile")
                    }
                    .tag(2)
            }
            .tint(theme.primary)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .videoEditor(let params):
                    VideoEditorView(params: params)
                case .generationStatus(let id, let title, let isLocalExport):
                    GenerationStatusView(generationId: id, title: title, isLocalExport: isLocalExport)
                case .settings:
                    SettingsView(showCloseButton: true, userId: appState.userId ?? "demo-user")
                }
            }
            .toolbarBackground(theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToVideoEditor)) { notification in
            if let params = notification.object as? VideoEditorParams {
                navigationPath.append(Route.videoEditor(params))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToGenerationStatus)) { notification in
            if let result = notification.object as? (id: String, title: String, isLocalExport: Bool) {
                navigationPath.append(Route.generationStatus(id: result.id, title: result.title, isLocalExport: result.isLocalExport))
            } else if let result = notification.object as? (id: String, title: String) {
                navigationPath.append(Route.generationStatus(id: result.id, title: result.title))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToLibraryTab)) { _ in
            navigationPath = NavigationPath()
            selectedTab = 0
        }
        .onChange(of: appState.pendingDeeplink) { newValue in
            guard let action = newValue else { return }
            appState.pendingDeeplink = nil
            switch action {
            case .switchTab(let index):
                navigationPath = NavigationPath()
                selectedTab = index
            case .generationStatus(let id, let title):
                navigationPath = NavigationPath()
                selectedTab = 0
                navigationPath.append(Route.generationStatus(id: id, title: title))
            case .videoEditor(let params):
                navigationPath.append(Route.videoEditor(params))
            case .settings:
                navigationPath = NavigationPath()
                selectedTab = 2
            }
        }
    }
}

enum Route: Hashable {
    case videoEditor(VideoEditorParams)
    case generationStatus(id: String, title: String, isLocalExport: Bool = false)
    case settings

    struct VideoEditorParams: Hashable {
        var videoUri: String?
        var videoName: String?
        var takesJson: String?
        var musicUrl: String?
        var userId: String
    }
}

// Alias for convenience
typealias VideoEditorParams = Route.VideoEditorParams
