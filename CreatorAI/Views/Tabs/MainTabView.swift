import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            mainContent
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .videoEditor(let params):
                        #if os(macOS)
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePlayback)) { _ in
            // Forward to video editor if active
        }
        .onReceive(NotificationCenter.default.publisher(for: .splitClip)) { _ in
            // Forward to video editor if active
        }
        .onChange(of: appState.pendingDeeplink) { newValue in
            guard let action = newValue else { return }
            appState.pendingDeeplink = nil
            switch action {
            case .switchTab(let index):
                navigationPath = NavigationPath()
                if index == 1 {
                    navigationPath.append(Route.settings)
                }
            case .generationStatus(let id, let title):
                navigationPath = NavigationPath()
                navigationPath.append(Route.generationStatus(id: id, title: title))
            case .videoEditor(let params):
                if let instruction = params.aiInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !instruction.isEmpty,
                   params.videoUri == nil,
                   params.takesJson == nil {
                    NotificationCenter.default.post(name: .applyEditorAIInstruction, object: instruction)
                } else {
                    navigationPath.append(Route.videoEditor(params))
                }
            case .settings:
                navigationPath = NavigationPath()
                navigationPath.append(Route.settings)
            }
        }
    }

    // MARK: - Platform-specific main content

    @ViewBuilder
    private var mainContent: some View {
        #if os(macOS)
        MacWorkspaceView()
        #else
        ZStack(alignment: .bottom) {
            LibraryView {
                navigationPath.append(Route.settings)
            }
                .padding(.bottom, 98)

            bottomActionSheet
        }
        #endif
    }

    #if os(iOS)
    private var bottomActionSheet: some View {
        HStack(spacing: 12) {
            Button {
                navigationPath.append(Route.videoEditor(VideoEditorParams(
                    videoName: "Editor",
                    userId: appState.userId ?? "demo-user"
                )))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "timeline.selection")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Open Editor")
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(theme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .background(
            Rectangle()
                .fill(theme.background.opacity(0.96))
                .ignoresSafeArea(edges: .bottom)
        )
    }
    #endif

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
        var aiInstruction: String? = nil
    }
}

typealias VideoEditorParams = Route.VideoEditorParams
