import SwiftUI
import AVKit
import UniformTypeIdentifiers

// MARK: - Final Cut Pro-style Desktop Workspace

struct MacWorkspaceView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @StateObject private var libraryVM = LibraryViewModel()
    @State private var editorVM: VideoEditorViewModel?
    @State private var editorId = UUID() // Forces view recreation when project changes

    @State private var showBrowser = true
    @State private var showInspector = true
    @State private var showProfile = false

    private var activeEditor: VideoEditorViewModel {
        editorVM ?? VideoEditorViewModel(params: VideoEditorParams(userId: "demo-user"))
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Top: Browser | Preview | Inspector ──
            HStack(spacing: 0) {
                // Left: Media Browser
                if showBrowser {
                    MediaBrowserPanel(libraryVM: libraryVM, onSelect: loadGeneration, onImport: loadParams)
                        .frame(width: 280)
                }

                // Center: Video Preview
                VideoPreviewPanel(viewModel: activeEditor)
                    .id(editorId)
                    .frame(maxWidth: .infinity)

                // Right: Inspector
                if showInspector {
                    InspectorPanel(viewModel: activeEditor)
                        .id(editorId)
                        .frame(width: 300)
                }
            }
            .frame(maxHeight: .infinity)

            // ── Bottom: Timeline ──
            MacTimelinePanel(viewModel: activeEditor, onVideoDropped: { fileURL in
                let params = VideoEditorParams(
                    videoUri: fileURL.absoluteString,
                    videoName: fileURL.deletingPathExtension().lastPathComponent,
                    userId: appState.userId ?? "demo-user"
                )
                loadParams(params)
            })
                .id(editorId)
                .frame(height: 250)
        }
        .background(theme.background)
        .overlay(alignment: .bottom) {
            // Floating generation status toast
            if activeEditor.aiGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                    Text(activeEditor.aiStatus.isEmpty ? "Generating..." : activeEditor.aiStatus)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.primary.opacity(0.9)))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: activeEditor.aiGenerating)
            }

            // Error toast
            if let error = activeEditor.processingError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.white)
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Dismiss")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .onTapGesture { activeEditor.processingError = nil }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.error.opacity(0.9)))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .toolbar(id: "workspace") {
            ToolbarItem(id: "browser", placement: .navigation) {
                Button { showBrowser.toggle() } label: {
                    Image(systemName: "sidebar.left")
                        .symbolVariant(showBrowser ? .fill : .none)
                }
                .help("Toggle Media Browser")
            }

            ToolbarItem(id: "inspector", placement: .navigation) {
                Button { showInspector.toggle() } label: {
                    Image(systemName: "sidebar.right")
                        .symbolVariant(showInspector ? .fill : .none)
                }
                .help("Toggle Inspector")
            }

            ToolbarItem(id: "catalog", placement: .primaryAction) {
                Button {
                    if let url = URL(string: "https://www.creatorai.art/en/catalog") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                } label: {
                    Label("Catalog", systemImage: "rectangle.grid.2x2")
                }
                .help("Open Catalog in Browser")
            }

            ToolbarItem(id: "profile", placement: .primaryAction) {
                Button {
                    showProfile = true
                } label: {
                    Image(systemName: "person.circle")
                        .font(.system(size: 16))
                }
                .help("Profile & Settings")
            }

            ToolbarItem(id: "export", placement: .primaryAction) {
                Button {
                    Task { await editorVM?.saveVideo() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export Video")
            }
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack {
                SettingsView(showCloseButton: false, userId: appState.userId ?? "demo-user")
                    .environmentObject(appState)
                    .environment(\.theme, AppColors(isDark: true))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showProfile = false }
                        }
                    }
            }
            .frame(minWidth: 500, minHeight: 400)
        }
        .onChange(of: activeEditor.aiGenerating) { generating in
            if !generating && activeEditor.aiStatus.isEmpty {
                // AI generation completed — refresh library
                Task { await libraryVM.loadGenerations() }
            }
        }
        .onAppear {
            Task {
                await appState.fetchCredits()
                await libraryVM.loadGenerations()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToVideoEditor)) { notification in
            if let params = notification.object as? VideoEditorParams {
                loadParams(params)
            }
        }
    }

    private func loadParams(_ params: VideoEditorParams) {
        editorVM?.cleanup()
        let vm = VideoEditorViewModel(params: params)
        vm.configureAudioSessionForMusic()
        vm.rebuildPlaylistIfNeeded()
        editorVM = vm
        editorId = UUID()
        Task {
            await vm.preCacheClips()
            // Wait for player to be ready, then show first frame
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if vm.player != nil { break }
            }
            await MainActor.run {
                vm.player?.seek(to: .zero)
                vm.player?.pause()
                vm.isPlaying = false
            }
        }
    }

    private func loadGeneration(_ generation: Generation) {
        guard let fileURL = generation.videoFileURL else { return }
        let params = VideoEditorParams(
            generationId: generation.id,
            videoUri: fileURL.isFileURL ? fileURL.path : fileURL.absoluteString,
            videoName: generation.videoName,
            takesJson: generation.takesJson,
            musicUrl: generation.resolvedMusicFile,
            userId: generation.userId ?? appState.userId ?? "demo-user"
        )
        loadParams(params)
    }
}

// MARK: - Media Browser Panel (Library grid + Import)

struct MediaBrowserPanel: View {
    @ObservedObject var libraryVM: LibraryViewModel
    let onSelect: (Generation) -> Void
    var onImport: ((VideoEditorParams) -> Void)?
    @Environment(\.theme) var theme
    @State private var showFileImporter = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Media")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.text)
                Spacer()
                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.surfaceElevated)

            Divider()

            // Grid
            if libraryVM.generations.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "film.stack")
                        .font(.system(size: 32))
                        .foregroundColor(theme.textTertiary)
                    Text("No media")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textTertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(libraryVM.generations) { gen in
                            MediaBrowserItem(generation: gen, thumbnail: libraryVM.thumbnails[gen.id], onDelete: {
                                Task { await libraryVM.deleteGeneration(gen) }
                            })
                                .contentShape(Rectangle())
                                .gesture(TapGesture().onEnded { onSelect(gen) })
                                .contextMenu {
                                    Button {
                                        onSelect(gen)
                                    } label: {
                                        Label("Open in Editor", systemImage: "play.rectangle")
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        Task { await libraryVM.deleteGeneration(gen) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(theme.background)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            let videoExts = ["mp4", "mov", "m4v", "avi", "mkv"]
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, videoExts.contains(url.pathExtension.lowercased()) else { return }
                    let _ = url.startAccessingSecurityScopedResource()
                    DispatchQueue.main.async {
                        importFile(url)
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            }
            return true
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                importFile(url)
            }
        }
    }

    private func importFile(_ url: URL) {
        let id = UUID().uuidString
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let dest = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(id).\(ext)")
        try? FileManager.default.copyItem(at: url, to: dest)

        let videoName = url.deletingPathExtension().lastPathComponent

        // Save as a Generation so it appears in the Media Browser
        let generation = Generation(
            id: id,
            videoName: videoName,
            videoUri: dest.path,
            resultVideoUrl: nil,
            status: .saved,
            createdAt: Date(),
            userId: nil
        )
        Task {
            await GenerationService.shared.saveGeneration(generation)
            await libraryVM.loadGenerations()
        }

        let params = VideoEditorParams(
            generationId: id,
            videoUri: dest.absoluteString,
            videoName: videoName,
            userId: "demo-user"
        )
        onImport?(params)
    }
}

struct MediaBrowserItem: View {
    let generation: Generation
    let thumbnail: PlatformImage?
    var onDelete: (() -> Void)?
    @Environment(\.theme) var theme
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if let thumbnail {
                        Image(platformImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(theme.surfaceElevated)
                        Image(systemName: "film")
                            .font(.system(size: 20))
                            .foregroundColor(theme.textTertiary)
                    }
                }
                .frame(height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Delete X button — visible on hover
                if isHovering, let onDelete {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .padding(4)
                        .onTapGesture { onDelete() }
                }
            }

            Text(generation.videoName)
                .font(.system(size: 10))
                .foregroundColor(theme.textSecondary)
                .lineLimit(1)
        }
        .onHover { isHovering = $0 }
    }
}

// MARK: - Video Preview Panel

struct VideoPreviewPanel: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    private var aspectRatio: CGFloat {
        switch viewModel.aspectRatio {
        case "9:16": return 9.0 / 16.0
        case "16:9": return 16.0 / 9.0
        case "4:5": return 4.0 / 5.0
        default: return 1.0
        }
    }

    var body: some View {
        ZStack {
            Color.black

            if let player = viewModel.player {
                PlatformVideoPlayerView(player: player, videoGravity: .resizeAspectFill)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .clipped()
                    .onTapGesture {
                        viewModel.togglePlayPause()
                    }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("Select a video from the media browser")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
            }

            // Play/pause overlay
            if !viewModel.isPlaying, viewModel.player != nil {
                Image(systemName: "play.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.white.opacity(0.7))
                    .shadow(radius: 4)
                    .allowsHitTesting(false)
            }

            // Time display
            if viewModel.player != nil {
                VStack {
                    Spacer()
                    HStack {
                        Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.4)))
                        Spacer()
                    }
                    .padding(8)
                }
            }
        }
    }

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite && s >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}

// MARK: - Inspector Panel

struct InspectorPanel: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    private var activeClip: Clip? {
        viewModel.clips.indices.contains(viewModel.activeClipIndex)
            ? viewModel.clips[viewModel.activeClipIndex] : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Clip Info
                sectionHeader("Clip Info")
                if let clip = activeClip {
                    infoRow("Name", clip.name)
                    if let dur = clip.sourceDuration {
                        infoRow("Duration", String(format: "%.1fs", dur))
                    }
                    infoRow("Mode", viewModel.clips.count > 1 ? "Multi-clip" : "Single")
                } else {
                    Text("No clip selected")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                }

                Divider()

                // Speed
                sectionHeader("Speed")
                HStack {
                    Text("\(String(format: "%.2g", viewModel.activeClipSpeed))x")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.text)
                    Spacer()
                }
                Slider(value: Binding(
                    get: { viewModel.activeClipSpeed },
                    set: { viewModel.setClipSpeed($0) }
                ), in: 0.1...5.0, step: 0.05)

                HStack(spacing: 4) {
                    ForEach([0.5, 1.0, 1.5, 2.0, 3.0], id: \.self) { speed in
                        Button("\(String(format: "%.2g", speed))x") {
                            viewModel.setClipSpeed(speed)
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 10))
                        .tint(abs(viewModel.activeClipSpeed - speed) < 0.01 ? theme.primary : .gray)
                    }
                }

                Divider()

                // Aspect Ratio
                sectionHeader("Aspect Ratio")
                Picker("", selection: $viewModel.aspectRatio) {
                    Text("9:16").tag("9:16")
                    Text("16:9").tag("16:9")
                    Text("1:1").tag("1:1")
                    Text("4:5").tag("4:5")
                }
                .pickerStyle(.segmented)

                Divider()

                // Music
                sectionHeader("Music")
                if let music = viewModel.selectedMusic {
                    HStack {
                        Image(systemName: "music.note")
                        Text(music.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Button { viewModel.clearMusic() } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    Slider(value: $viewModel.musicVolume, in: 0...1)
                    Text("Volume: \(Int(viewModel.musicVolume * 100))%")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                } else {
                    Text("No music")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                }

                Spacer()
            }
            .padding(12)
        }
        .background(theme.background)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(theme.textTertiary)
            .textCase(.uppercase)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(theme.text)
        }
    }
}

// MARK: - Timeline Panel (wraps existing ClipsTimelineView + toolbar)

struct MacTimelinePanel: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    var onVideoDropped: ((URL) -> Void)?
    @Environment(\.theme) var theme
    @State private var showMusicPicker = false
    @State private var showClipPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar strip
            HStack(spacing: 12) {
                // Play/Pause
                Button { viewModel.togglePlayPause() } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])

                Divider().frame(height: 16)

                toolbarButton("sparkles", "AI") { viewModel.showAiPrompt = true }
                toolbarButton("scissors", "Cut") { viewModel.splitClipAtPlayhead() }
                toolbarButton("arrow.triangle.2.circlepath", "Change") {
                    viewModel.pexelsReplaceMode = true
                    viewModel.showPexelsSheet = true
                }
                toolbarButton("trash", "Delete") { viewModel.removeClip(at: viewModel.activeClipIndex) }
                toolbarButton("mic", "Voice") { viewModel.showVoiceoverSheet = true }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.surfaceElevated)

            Divider()

            // Timeline
            ClipsTimelineView(viewModel: viewModel)
        }
        .background(theme.background)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            let audioExts = ["mp3", "m4a", "wav", "aiff", "aac"]
            let videoExts = ["mp4", "mov", "m4v", "avi", "mkv"]
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    let _ = url.startAccessingSecurityScopedResource()
                    let ext = url.pathExtension.lowercased()
                    DispatchQueue.main.async {
                        if audioExts.contains(ext) {
                            let dest = FileManager.default.temporaryDirectory
                                .appendingPathComponent("music-\(UUID().uuidString).\(ext)")
                            try? FileManager.default.copyItem(at: url, to: dest)
                            let name = url.deletingPathExtension().lastPathComponent
                            let track = MusicTrack(id: "drop-\(UUID().uuidString)", name: name, file: dest.absoluteString)
                            Task { await viewModel.selectMusic(track) }
                        } else if videoExts.contains(ext) {
                            let id = UUID().uuidString
                            let dest = FileStorageService.shared.savedVideosDirectory
                                .appendingPathComponent("\(id).\(ext)")
                            try? FileManager.default.copyItem(at: url, to: dest)

                            // Save as Generation so it shows in Media Browser
                            let gen = Generation(
                                id: id,
                                videoName: url.deletingPathExtension().lastPathComponent,
                                videoUri: dest.path,
                                resultVideoUrl: nil,
                                status: .saved,
                                createdAt: Date(),
                                userId: nil
                            )
                            GenerationService.shared.saveGeneration(gen)

                            if viewModel.player == nil {
                                onVideoDropped?(dest)
                            } else {
                                viewModel.addClipFromGallery(url: dest)
                            }
                        }
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            }
            return true
        }
        .fileImporter(
            isPresented: $showMusicPicker,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("user-music-\(UUID().uuidString)")
                    .appendingPathExtension(url.pathExtension)
                try? FileManager.default.copyItem(at: url, to: dest)
                let trackName = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                let track = MusicTrack(id: "user-\(UUID().uuidString)", name: trackName, file: dest.absoluteString)
                Task { await viewModel.selectMusic(track) }
            }
        }
        .sheet(isPresented: $viewModel.showAiPrompt) {
            SheetWrapper(title: "AI Clip", isPresented: $viewModel.showAiPrompt) {
                AiClipSheet(viewModel: viewModel)
            }
            .frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $viewModel.showSpeedSheet) {
            SheetWrapper(title: "Speed", isPresented: $viewModel.showSpeedSheet) {
                SpeedControlView(viewModel: viewModel)
            }
            .frame(minWidth: 400, minHeight: 300)
        }
        .sheet(isPresented: $viewModel.showAspectRatioSheet) {
            SheetWrapper(title: "Aspect Ratio", isPresented: $viewModel.showAspectRatioSheet) {
                AspectRatioView(viewModel: viewModel)
            }
            .frame(minWidth: 400, minHeight: 300)
        }
        .sheet(isPresented: $viewModel.showVoiceoverSheet) {
            SheetWrapper(title: "Voiceover", isPresented: $viewModel.showVoiceoverSheet) {
                VoiceoverRecordView(viewModel: viewModel)
            }
            .frame(minWidth: 400, minHeight: 350)
        }
        .sheet(isPresented: $viewModel.showPexelsSheet) {
            PexelsSearchSheet(viewModel: viewModel)
                .frame(minWidth: 500, minHeight: 400)
        }
        .onChange(of: viewModel.showAddClipPicker) { show in
            if show {
                showClipPicker = true
                viewModel.showAddClipPicker = false
            }
        }
        .fileImporter(
            isPresented: $showClipPicker,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
                let dest = FileStorageService.shared.clipCacheDirectory
                    .appendingPathComponent("\(UUID().uuidString).\(ext)")
                try? FileManager.default.copyItem(at: url, to: dest)
                if viewModel.player == nil {
                    onVideoDropped?(dest)
                } else {
                    viewModel.addClipFromGallery(url: dest)
                }
            }
        }
    }

    private func toolbarButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 9))
            }
            .foregroundColor(theme.text)
        }
        .buttonStyle(.plain)
    }
}
