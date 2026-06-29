import SwiftUI
import AVKit
#if os(iOS)
import PhotosUI
#endif
import UniformTypeIdentifiers

struct VideoEditorView: View {
    let params: VideoEditorParams
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: VideoEditorViewModel

    @State private var showSubsSheet = false
    @State private var showMusicSheet = false
    @State private var showMusicFilePicker = false
    @State private var showAgentContext = false
    @State private var showGalleryPicker = false
    @State private var activeToolSubmenu: ToolSubmenu?
    @State private var transitionBoundaryIndex = 0
    #if os(iOS)
    @State private var selectedFileItem: PhotosPickerItem?
    #endif
    @State private var isImportingClip = false

    init(params: VideoEditorParams) {
        self.params = params
        self._viewModel = StateObject(wrappedValue: VideoEditorViewModel(params: params))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: Close | Title | Export
            HStack {
                Button(action: {
                    viewModel.autosave()
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(theme.text)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(theme.surfaceElevated))
                }

                Spacer()

                Text(viewModel.videoName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineLimit(1)

                Spacer()

                Button {
                    Task { await viewModel.saveVideo() }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isGenerating {
                            Image(systemName: "film.stack")
                                .font(.system(size: 14, weight: .semibold))
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text("Export")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(viewModel.canExport && !viewModel.isGenerating ? theme.primary : theme.textTertiary.opacity(0.45))
                    .clipShape(Capsule())
                }
                .disabled(viewModel.isGenerating || !viewModel.canExport)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Video preview — fills height, cropped to selected aspect ratio
                    GeometryReader { geo in
                        let h = geo.size.height
                        let w = h * previewAspectRatio
                        VideoPreviewView(viewModel: viewModel)
                            .frame(width: w, height: h)
                            .clipped()
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: ScreenSize.height * 0.42)

                    // Timeline + tracks
                    ClipsTimelineView(viewModel: viewModel)
                        .frame(height: 220)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom action bar
            bottomActionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea(.all))
        .overlay {
            if isImportingClip || viewModel.isPexelsDownloading || (viewModel.aiGenerating && !viewModel.aiAgentActive) {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 14) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                        Text(loadingMessage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(theme.surfaceElevated)
                    )
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.aiAgentActive {
                AiAgentBulbView(
                    status: viewModel.aiStatus,
                    note: viewModel.aiAgentNote,
                    canStop: true,
                    onOpen: { showAgentContext = true },
                    onStop: { viewModel.stopAiAgent() }
                )
                    .padding(.top, 58)
                    .padding(.trailing, 16)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
        .onDisappear {
            viewModel.cleanup()
        }
        .onChange(of: viewModel.exportGenerationId) { generationId in
            if let generationId = generationId {
                NotificationCenter.default.post(
                    name: .navigateToGenerationStatus,
                    object: (id: generationId, title: viewModel.videoName, isLocalExport: true)
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .applyEditorAIInstruction)) { notification in
            guard let instruction = notification.object as? String else { return }
            applyIncomingEditorInstruction(instruction)
        }
        .sheet(isPresented: $viewModel.showAiPrompt) {
            SheetWrapper(title: "Ad maker", isPresented: $viewModel.showAiPrompt) {
                AiClipSheet(viewModel: viewModel)
            }
        }
        .fileImporter(
            isPresented: $showMusicFilePicker,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                let destURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("user-music-\(UUID().uuidString)")
                    .appendingPathExtension(url.pathExtension)
                try? FileManager.default.copyItem(at: url, to: destURL)
                let trackName = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                let track = MusicTrack(
                    id: "user-\(UUID().uuidString)",
                    name: trackName,
                    file: destURL.absoluteString
                )
                Task { await viewModel.addMusicTrack(track) }
            }
        }
        .sheet(isPresented: $showSubsSheet) {
            SheetWrapper(title: "Subtitles", isPresented: $showSubsSheet) {
                SubtitlesTabView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showMusicSheet) {
            SheetWrapper(title: "Music", isPresented: $showMusicSheet) {
                MusicTabView(viewModel: viewModel) {
                    showMusicSheet = false
                }
            }
        }
        .sheet(isPresented: $viewModel.showSpeedSheet) {
            SheetWrapper(title: "Speed", isPresented: $viewModel.showSpeedSheet) {
                SpeedControlView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.showVolumeSheet) {
            SheetWrapper(title: "Volume", isPresented: $viewModel.showVolumeSheet) {
                VolumeControlView(viewModel: viewModel)
            }
        }
        
        .sheet(isPresented: $viewModel.showLayoutSheet) {
            SheetWrapper(title: "Layout", isPresented: $viewModel.showLayoutSheet) {
                ClipLayoutView(viewModel: viewModel)
            }
        }
        
        .sheet(isPresented: $viewModel.showAspectRatioSheet) {
            SheetWrapper(title: "Aspect Ratio", isPresented: $viewModel.showAspectRatioSheet) {
                AspectRatioView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.showVoiceoverSheet) {
            SheetWrapper(title: "Voiceover", isPresented: $viewModel.showVoiceoverSheet) {
                VoiceoverRecordView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.showPexelsSheet) {
            PexelsSearchSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showAgentContext) {
            SheetWrapper(title: "Agent context", isPresented: $showAgentContext) {
                AgentContextView(viewModel: viewModel)
            }
        }
        #if os(iOS)
        .photosPicker(isPresented: $showGalleryPicker, selection: $selectedFileItem, matching: .any(of: [.videos, .images]))
        #endif
        .onChange(of: viewModel.showAddClipPicker) { show in
            if show {
                showGalleryPicker = true
                viewModel.showAddClipPicker = false
            }
        }
        .onChange(of: viewModel.showMusicPickerFromTimeline) { show in
            if show {
                showMusicSheet = true
                viewModel.showMusicPickerFromTimeline = false
            }
        }
        .onChange(of: viewModel.showSubtitlesFromTimeline) { show in
            if show {
                showSubsSheet = true
                viewModel.showSubtitlesFromTimeline = false
            }
        }
        #if os(iOS)
        .onChange(of: selectedFileItem) { newItem in
            guard let newItem else { return }
            selectedFileItem = nil
            isImportingClip = true
            Task {
                defer { isImportingClip = false }
                guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                let type = newItem.supportedContentTypes.first { $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .image) }
                let isImage = type?.conforms(to: .image) == true
                let ext = type?.preferredFilenameExtension ?? (isImage ? "jpg" : "mp4")
                let dest = FileStorageService.shared.clipCacheDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
                try? data.write(to: dest)
                viewModel.addClipFromGallery(url: dest, mimeType: type?.preferredMIMEType ?? (isImage ? "image/jpeg" : "video/mp4"))
            }
        }
        #endif
        .task {
            viewModel.configureAudioSessionForMusic()
            viewModel.rebuildPlaylistIfNeeded()
            await viewModel.preCacheClips()

            if let rawMusicUrl = params.musicUrl, !rawMusicUrl.isEmpty {
                // Resolve music path (container UUID may have changed between launches)
                let resolvedMusic: String
                let cleanPath = rawMusicUrl.replacingOccurrences(of: "file://", with: "")
                if FileManager.default.fileExists(atPath: cleanPath) {
                    resolvedMusic = cleanPath
                } else {
                    let filename = (cleanPath as NSString).lastPathComponent
                    let resolved = FileStorageService.shared.savedVideosDirectory.appendingPathComponent(filename)
                    resolvedMusic = FileManager.default.fileExists(atPath: resolved.path) ? resolved.path : rawMusicUrl
                }

                let track = MusicTrack(id: "reel-music", name: "Reel Music", file: resolvedMusic)
                viewModel.musicVolume = 0.75
                await viewModel.selectMusic(track)

                if viewModel.musicLoadFailed {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await viewModel.selectMusic(track)
                }

                viewModel.ensureMusicPlaying()
                try? await Task.sleep(nanoseconds: 400_000_000)
                viewModel.ensureMusicPlaying()
                try? await Task.sleep(nanoseconds: 800_000_000)
                viewModel.ensureMusicPlaying()
            }

            let instruction = params.aiInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !instruction.isEmpty else { return }
            await applyEditorInstruction(instruction)
        }
    }

    private func applyIncomingEditorInstruction(_ instruction: String) {
        Task { await applyEditorInstruction(instruction) }
    }

    @MainActor
    private func applyEditorInstruction(_ instruction: String) async {
        let request = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        if applyDirectEditorCommand(request) {
            return
        }
        if viewModel.clips.isEmpty {
            viewModel.aiPrompt = request
            viewModel.showAiPrompt = true
        } else {
            await viewModel.interruptAndApplyAgentInstruction(request)
        }
    }

    @MainActor
    private func applyDirectEditorCommand(_ command: String) -> Bool {
        switch command {
        case "__creatorai_skip_current_scene":
            if viewModel.canDeleteSelectedTimelineItem {
                viewModel.deleteSelectedTimelineItem()
            } else if viewModel.clips.indices.contains(viewModel.activeClipIndex) {
                viewModel.removeClip(at: viewModel.activeClipIndex)
            }
            return true
        case "__creatorai_cut_current_clip":
            viewModel.splitClipAtPlayhead()
            return true
        default:
            return false
        }
    }

    private var previewAspectRatio: CGFloat {
        switch viewModel.aspectRatio {
        case "9:16": return 9.0 / 16.0
        case "16:9": return 16.0 / 9.0
        case "4:5": return 4.0 / 5.0
        default: return 1.0 // 1:1
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                if let activeToolSubmenu {
                    submenuButtons(activeToolSubmenu)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    switch viewModel.timelineSelection {
                    case .none:
                        mainActionButtons
                    default:
                        selectedActionButtons
                    }
                }
            }
            .padding(.horizontal, 4)
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.82), value: activeToolSubmenu != nil)
        }
        .padding(.vertical, 8)
        .background(theme.surfaceElevated.shadow(color: .black.opacity(0.1), radius: 8, y: -2))
    }

    @ViewBuilder
    private func submenuButtons(_ submenu: ToolSubmenu) -> some View {
        bottomBarButton(icon: "chevron.left", label: "Back") {
            activeToolSubmenu = nil
        }

        switch submenu {
        case .filters:
            filterSubmenuButtons
        case .transitions:
            transitionSubmenuButtons
        }
    }

    @ViewBuilder
    private var mainActionButtons: some View {
        bottomBarButton(icon: "music.note", label: "Music") {
            showMusicSheet = true
        }

        bottomBarButton(
            icon: viewModel.voiceoverFileURL != nil ? "mic.fill" : "mic",
            label: "Voice",
            color: viewModel.voiceoverFileURL != nil ? theme.primary : nil
        ) {
            if viewModel.voiceoverFileURL != nil {
                viewModel.selectVoiceover()
            }
            viewModel.showVoiceoverSheet = true
        }

        bottomBarButton(icon: "sparkles", label: "AI") {
            viewModel.showAiPrompt = true
        }

        bottomBarButton(icon: "folder", label: "File") {
            showGalleryPicker = true
        }

        bottomBarButton(icon: "photo.on.rectangle.angled", label: "Pexels") {
            viewModel.pexelsReplaceMode = true
            viewModel.showPexelsSheet = true
        }

        bottomBarButton(icon: "rectangle.2.swap", label: "Trans") {
            transitionBoundaryIndex = min(max(0, viewModel.activeClipIndex), max(0, viewModel.clips.count - 2))
            activeToolSubmenu = .transitions
        }

        bottomBarButton(icon: "captions.bubble", label: "Subs") {
            showSubsSheet = true
        }
    }

    @ViewBuilder
    private var selectedActionButtons: some View {
        bottomBarButton(icon: "chevron.left", label: "Back") {
            viewModel.clearTimelineSelection()
        }

        switch viewModel.timelineSelection {
        case .video:
            videoSelectedActionButtons
        case .text:
            textSelectedActionButtons
        case .music, .voiceover:
            audioSelectedActionButtons
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var videoSelectedActionButtons: some View {
        bottomBarButton(
            icon: "gauge.with.dots.needle.33percent",
            label: "Speed",
            color: viewModel.activeClipSpeed != 1.0 ? theme.primary : nil
        ) {
            viewModel.showSpeedSheet = true
        }

        bottomBarButton(icon: "camera.filters", label: "Filter") {
            activeToolSubmenu = .filters
        }

        bottomBarButton(icon: "pip", label: "Layout") {
            viewModel.showLayoutSheet = true
        }

        bottomBarButton(icon: "rectangle.2.swap", label: "Trans", color: viewModel.clips.indices.contains((selectedVideoIndexForTools ?? 0)) && (selectedVideoIndexForTools ?? 0) < viewModel.clips.count - 1 ? nil : theme.textTertiary) {
            if let index = selectedVideoIndexForTools, viewModel.clips.count >= 2 {
                transitionBoundaryIndex = min(index, max(0, viewModel.clips.count - 2))
                activeToolSubmenu = .transitions
            }
        }

        bottomBarButton(icon: "scissors", label: "Cut") {
            viewModel.splitClipAtPlayhead()
        }

        bottomBarButton(icon: "trash", label: "Delete", color: viewModel.canDeleteSelectedTimelineItem ? .red : theme.textTertiary) {
            if viewModel.canDeleteSelectedTimelineItem {
                viewModel.deleteSelectedTimelineItem()
            }
        }

        bottomBarButton(icon: "rectangle.portrait", label: "4:5") {
            viewModel.setAspectRatio("4:5")
        }

        bottomBarButton(
            icon: "slider.horizontal.3",
            label: "Volume",
            color: viewModel.canAdjustSelectedTimelineVolume ? nil : theme.textTertiary
        ) {
            if viewModel.canAdjustSelectedTimelineVolume {
                viewModel.showVolumeSheet = true
            }
        }
    }

    private var selectedVideoIndexForTools: Int? {
        if case .video(let index) = viewModel.timelineSelection, viewModel.clips.indices.contains(index) {
            return index
        }
        return viewModel.clips.indices.contains(viewModel.activeClipIndex) ? viewModel.activeClipIndex : nil
    }

    @ViewBuilder
    private var filterSubmenuButtons: some View {
        if let index = selectedVideoIndexForTools {
            ForEach(["None", "Warm", "Cool", "Punch", "Mono", "Fade"], id: \.self) { filter in
                bottomBarButton(
                    icon: filter == "None" ? "circle.slash" : "camera.filters",
                    label: filter,
                    color: viewModel.clips[index].filterName == filter ? theme.primary : nil
                ) {
                    viewModel.updateClipFilter(at: index, filterName: filter)
                }
            }
        } else {
            bottomBarButton(icon: "video.slash", label: "No clip", color: theme.textTertiary) {}
        }
    }

    @ViewBuilder
    private var transitionSubmenuButtons: some View {
        if viewModel.clips.count >= 2 {
            let boundaryIndex = safeTransitionBoundaryIndex

            bottomBarButton(icon: "chevron.left.2", label: "Prev", color: boundaryIndex > 0 ? nil : theme.textTertiary) {
                transitionBoundaryIndex = max(0, boundaryIndex - 1)
            }

            bottomBarButton(icon: "chevron.right.2", label: "Next", color: boundaryIndex < viewModel.clips.count - 2 ? nil : theme.textTertiary) {
                transitionBoundaryIndex = min(max(0, viewModel.clips.count - 2), boundaryIndex + 1)
            }

            ForEach(["None", "Fade", "Dip"], id: \.self) { transition in
                bottomBarButton(
                    icon: transitionIcon(for: transition),
                    label: transition,
                    color: viewModel.clips[boundaryIndex].transitionName == transition ? theme.primary : nil
                ) {
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.82)) {
                        viewModel.updateClipTransition(at: boundaryIndex, transitionName: transition)
                    }
                }
            }
        } else {
            bottomBarButton(icon: "rectangle.2.swap", label: "Need 2", color: theme.textTertiary) {}
        }
    }

    private var safeTransitionBoundaryIndex: Int {
        min(max(0, transitionBoundaryIndex), max(0, viewModel.clips.count - 2))
    }

    private func transitionIcon(for transition: String) -> String {
        switch transition {
        case "Fade": return "circle.lefthalf.filled"
        case "Dip": return "moonphase.new.moon"
        default: return "circle.slash"
        }
    }

    @ViewBuilder
    private var textSelectedActionButtons: some View {
        bottomBarButton(icon: "captions.bubble", label: "Edit") {
            showSubsSheet = true
        }

        bottomBarButton(icon: "trash", label: "Delete", color: viewModel.canDeleteSelectedTimelineItem ? .red : theme.textTertiary) {
            if viewModel.canDeleteSelectedTimelineItem {
                viewModel.deleteSelectedTimelineItem()
            }
        }
    }

    @ViewBuilder
    private var audioSelectedActionButtons: some View {
        bottomBarButton(
            icon: "slider.horizontal.3",
            label: "Volume",
            color: viewModel.canAdjustSelectedTimelineVolume ? nil : theme.textTertiary
        ) {
            if viewModel.canAdjustSelectedTimelineVolume {
                viewModel.showVolumeSheet = true
            }
        }

        bottomBarButton(icon: "trash", label: "Delete", color: viewModel.canDeleteSelectedTimelineItem ? .red : theme.textTertiary) {
            if viewModel.canDeleteSelectedTimelineItem {
                viewModel.deleteSelectedTimelineItem()
            }
        }
    }

    private var legacyBottomActionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                bottomBarButton(icon: "sparkles", label: "AI") {
                    viewModel.showAiPrompt = true
                }

                bottomBarButton(icon: "folder", label: "File") {
                    showGalleryPicker = true
                }

                bottomBarButton(icon: "scissors", label: "Cut") {
                    viewModel.splitClipAtPlayhead()
                }

                bottomBarButton(
                    icon: "gauge.with.dots.needle.33percent",
                    label: "Speed",
                    color: viewModel.activeClipSpeed != 1.0 ? theme.primary : nil
                ) {
                    viewModel.showSpeedSheet = true
                }

                bottomBarButton(icon: "photo.on.rectangle.angled", label: "Pexels") {
                    viewModel.pexelsReplaceMode = true
                    viewModel.showPexelsSheet = true
                }

                bottomBarButton(icon: "trash", label: "Delete", color: viewModel.canDeleteSelectedTimelineItem ? .red : theme.textTertiary) {
                    if viewModel.canDeleteSelectedTimelineItem {
                        viewModel.deleteSelectedTimelineItem()
                    }
                }

                bottomBarButton(
                    icon: "slider.horizontal.3",
                    label: "Volume",
                    color: viewModel.canAdjustSelectedTimelineVolume ? nil : theme.textTertiary
                ) {
                    if viewModel.canAdjustSelectedTimelineVolume {
                        viewModel.showVolumeSheet = true
                    }
                }

                bottomBarButton(
                    icon: viewModel.voiceoverFileURL != nil ? "mic.fill" : "mic",
                    label: "Voice",
                    color: viewModel.voiceoverFileURL != nil ? theme.primary : nil
                ) {
                    if viewModel.voiceoverFileURL != nil {
                        viewModel.selectVoiceover()
                    }
                    viewModel.showVoiceoverSheet = true
                }

                bottomBarButton(icon: "music.note", label: "Music") {
                    showMusicSheet = true
                }

                bottomBarButton(icon: "aspectratio", label: viewModel.aspectRatio) {
                    viewModel.showAspectRatioSheet = true
                }

                bottomBarButton(icon: "captions.bubble", label: "Subs") {
                    showSubsSheet = true
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 8)
        .background(theme.surfaceElevated.shadow(color: .black.opacity(0.1), radius: 8, y: -2))
    }

    private var loadingMessage: String {
        if isImportingClip { return "Importing video" }
        if viewModel.isPexelsDownloading { return "Downloading clip" }
        if viewModel.aiGenerating { return viewModel.aiStatus.isEmpty ? "Generating" : viewModel.aiStatus.replacingOccurrences(of: "...", with: "") }
        return "Loading"
    }

    private func bottomBarButton(icon: String, label: String, color: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(color ?? theme.text)
            .frame(width: 64)
            .padding(.vertical, 6)
        }
    }
}

private enum ToolSubmenu {
    case filters
    case transitions
}

struct ClipLayoutView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    private var selectedIndex: Int? {
        if case .video(let index) = viewModel.timelineSelection, viewModel.clips.indices.contains(index) {
            return index
        }
        return viewModel.clips.indices.contains(viewModel.activeClipIndex) ? viewModel.activeClipIndex : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let index = selectedIndex {
                HStack(spacing: 8) {
                    layoutButton("Full", icon: "rectangle.fill", index: index)
                    layoutButton("PiP", icon: "pip.fill", index: index)
                }

                if viewModel.clips[index].videoLayoutMode == "PiP" {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Size")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(theme.text)
                            Spacer()
                            Text(String(format: "%.0f%%", viewModel.clips[index].videoScale * 100))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(theme.textSecondary)
                        }
                        Slider(
                            value: Binding(
                                get: { viewModel.clips[index].videoScale },
                                set: { viewModel.updateClipLayout(at: index, scale: $0) }
                            ),
                            in: 0.18...0.85
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Position")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(theme.text)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            positionButton("Top left", index: index, x: 0.24, y: 0.24)
                            positionButton("Top right", index: index, x: 0.76, y: 0.24)
                            positionButton("Bottom left", index: index, x: 0.24, y: 0.76)
                            positionButton("Bottom right", index: index, x: 0.76, y: 0.76)
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private func layoutButton(_ title: String, icon: String, index: Int) -> some View {
        let selected = viewModel.clips[index].videoLayoutMode == title
        return Button {
            viewModel.updateClipLayout(at: index, mode: title)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(selected ? .white : theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? theme.primary : theme.surfaceElevated)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    private func positionButton(_ title: String, index: Int, x: Double, y: Double) -> some View {
        Button {
            viewModel.updateClipLayout(at: index, x: x, y: y)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.surfaceElevated)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct AiAgentBulbView: View {
    @Environment(\.theme) var theme
    let status: String
    let note: String
    let canStop: Bool
    let onOpen: () -> Void
    let onStop: () -> Void
    @State private var isPulsing = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.yellow)
                    .scaleEffect(isPulsing ? 1.12 : 0.92)
                    .rotationEffect(.degrees(isPulsing ? 8 : -8))
                    .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: isPulsing)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(status.isEmpty ? "Editing timeline..." : status)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineLimit(1)

                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if canStop {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(theme.error))
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
                .accessibilityLabel("Stop AI editor")
            }
        }
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 310, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.surfaceElevated)
                .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
        )
        .onAppear { isPulsing = true }
    }
}

private extension View {
    @ViewBuilder
    func clipFilter(_ name: String) -> some View {
        switch name {
        case "Warm":
            self.saturation(1.45).contrast(1.14).brightness(0.06).colorMultiply(Color(red: 1.0, green: 0.82, blue: 0.62))
        case "Cool":
            self.saturation(0.82).contrast(1.2).brightness(-0.03).colorMultiply(Color(red: 0.68, green: 0.86, blue: 1.0))
        case "Punch":
            self.saturation(1.75).contrast(1.38).brightness(0.02)
        case "Mono":
            self.saturation(0).contrast(1.35).brightness(0.02)
        case "Fade":
            self.saturation(0.55).contrast(0.78).brightness(0.12).colorMultiply(Color(red: 1.0, green: 0.94, blue: 0.86))
        default:
            self
        }
    }
}

private struct AgentContextView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme
    @State private var instruction = ""
    @State private var isSending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                statusBadge
                Spacer()
                Button {
                    viewModel.stopAiAgent()
                } label: {
                    Label("Interrupt", systemImage: "stop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(theme.error))
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            }

            TextEditor(text: $instruction)
                .frame(height: 72)
                .font(.system(size: 14))
                .foregroundColor(theme.text)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.surfaceElevated)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
                )
                .overlay(alignment: .topLeading) {
                    if instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add instruction while agent is working...")
                            .font(.system(size: 14))
                            .foregroundColor(theme.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                let request = instruction
                instruction = ""
                isSending = true
                Task {
                    await viewModel.interruptAndApplyAgentInstruction(request)
                    isSending = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.turn.down.right")
                    }
                    Text("Interrupt and apply")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.primary))
            }
            .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .opacity(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)

            if !viewModel.aiRawScenario.isEmpty {
                Text("Raw scenario")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textSecondary)

                ScrollView {
                    Text(viewModel.aiRawScenario)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(minHeight: 180, maxHeight: 280)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.surfaceElevated))
            }

            Text("Model and tool log")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textSecondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if viewModel.aiAgentLogs.isEmpty {
                        Text("No agent messages yet.")
                            .font(.system(size: 13))
                            .foregroundColor(theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(viewModel.aiAgentLogs.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(theme.text)
                                if !entry.detail.isEmpty {
                                    Text(entry.detail)
                                        .font(.system(size: 12))
                                        .foregroundColor(theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(theme.surfaceElevated))
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private var statusBadge: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(viewModel.aiStatus.isEmpty ? "Agent idle" : viewModel.aiStatus)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(theme.text)
                .lineLimit(1)
            if !viewModel.aiAgentNote.isEmpty {
                Text(viewModel.aiAgentNote)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}

struct VolumeControlView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { viewModel.selectedTimelineItemVolume },
            set: { viewModel.setSelectedTimelineItemVolume($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: volumeBinding.wrappedValue <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(theme.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(theme.primary.opacity(0.12)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.selectedTimelineVolumeTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(theme.text)
                        .lineLimit(1)
                    Text("\(Int(volumeBinding.wrappedValue * 100))%")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(theme.textSecondary)
                }
            }

            Slider(value: volumeBinding, in: 0...1)
                .tint(theme.primary)

            HStack(spacing: 10) {
                Button {
                    viewModel.setSelectedTimelineItemVolume(0)
                } label: {
                    Label("Mute", systemImage: "speaker.slash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.surfaceElevated))
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif

                Button {
                    viewModel.setSelectedTimelineItemVolume(1)
                } label: {
                    Label("100%", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.primary))
                        .foregroundColor(.white)
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            }
        }
        .padding(20)
    }
}
