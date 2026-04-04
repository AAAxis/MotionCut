import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @State private var navigationPath = NavigationPath()
    @State private var selectedTab = 2

    var body: some View {
        NavigationStack(path: $navigationPath) {
            mainContent
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .videoEditor(let params):
                        #if os(macOS)
                        // macOS: editor is inline in workspace, don't push
                        EmptyView()
                        #else
                        VideoEditorView(params: params)
                        #endif
                    case .generationStatus(let id, let title, let isLocalExport):
                        GenerationStatusView(generationId: id, title: title, isLocalExport: isLocalExport)
                    case .settings:
                        SettingsView(showCloseButton: true, userId: appState.userId ?? "demo-user")
                    }
                }
                #if os(iOS)
                .toolbarBackground(theme.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToVideoEditor)) { notification in
            if let params = notification.object as? VideoEditorParams {
                navigationPath.append(Route.videoEditor(params))
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .navigateToGenerationStatus)) { notification in
            if let result = notification.object as? (id: String, title: String, isLocalExport: Bool, isReel: Bool) {
                navigationPath.append(Route.generationStatus(id: result.id, title: result.title, isLocalExport: result.isLocalExport))
            } else if let result = notification.object as? (id: String, title: String, isLocalExport: Bool) {
                navigationPath.append(Route.generationStatus(id: result.id, title: result.title, isLocalExport: result.isLocalExport))
            } else if let result = notification.object as? (id: String, title: String) {
                navigationPath.append(Route.generationStatus(id: result.id, title: result.title))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToLibraryTab)) { _ in
            navigationPath = NavigationPath()
            selectedTab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .catalogUsePrompt)) { notification in
            if let prompt = notification.object as? String {
                navigationPath = NavigationPath()
                selectedTab = 2
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .prefillPrompt, object: prompt)
                }
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .togglePlayback)) { _ in
            // Forward to video editor if active
        }
        .onReceive(NotificationCenter.default.publisher(for: .splitClip)) { _ in
            // Forward to video editor if active
        }
        #endif
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
                selectedTab = 3
            }
        }
    }

    // MARK: - Platform-specific main content

    @ViewBuilder
    private var mainContent: some View {
        #if os(macOS)
        // macOS: Final Cut Pro-style workspace
        MacWorkspaceView()
        #else
        // iOS: bottom tab bar
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem {
                    Image(systemName: "play.rectangle.fill")
                    Text("Library")
                }
                .tag(0)

            CatalogView()
                .tabItem {
                    Image(systemName: "rectangle.grid.2x2")
                    Text("Catalog")
                }
                .tag(1)

            CreateView()
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("Create")
                }
                .tag(2)

            SettingsView(showCloseButton: false, userId: appState.userId ?? "demo-user")
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
                .tag(3)
        }
        .tint(theme.primary)
        #endif
    }

}

enum Route: Hashable {
    case videoEditor(VideoEditorParams)
    case generationStatus(id: String, title: String, isLocalExport: Bool = false)
    case settings

    struct VideoEditorParams: Hashable {
        var generationId: String?
        var videoUri: String?
        var videoName: String?
        var takesJson: String?
        var musicUrl: String?
        var userId: String
    }
}

typealias VideoEditorParams = Route.VideoEditorParams
