import SwiftUI
import AVKit
#if os(iOS)
import PhotosUI
#endif

struct VideoEditorView: View {
    let params: VideoEditorParams
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: VideoEditorViewModel

    @State private var showSubsSheet = false
    @State private var showMusicFilePicker = false
    @State private var showGalleryPicker = false
    #if os(iOS)
    @State private var selectedVideoItem: PhotosPickerItem?
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
                            ProgressView().scaleEffect(0.7).tint(.white)
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
                    .background(theme.primary)
                    .clipShape(Capsule())
                }
                .disabled(viewModel.isGenerating)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

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
                .frame(height: 130)

            Spacer(minLength: 0)

            // Bottom action bar
            bottomActionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea(.all))
        .overlay {
            if isImportingClip || viewModel.isPexelsDownloading || viewModel.aiGenerating {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.white)
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
        .sheet(isPresented: $viewModel.showAiPrompt) {
            SheetWrapper(title: "AI Clip", isPresented: $viewModel.showAiPrompt) {
                AiClipSheet(viewModel: viewModel)
            }
        }
        .fileImporter(
            isPresented: $showMusicFilePicker,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff],
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
                Task { await viewModel.selectMusic(track) }
            }
        }
        .sheet(isPresented: $showSubsSheet) {
            SheetWrapper(title: "Subtitles", isPresented: $showSubsSheet) {
                SubtitlesTabView(viewModel: viewModel)
            }
        }
        .sheet(isPresented: $viewModel.showSpeedSheet) {
            SheetWrapper(title: "Speed", isPresented: $viewModel.showSpeedSheet) {
                SpeedControlView(viewModel: viewModel)
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
        #if os(iOS)
        .photosPicker(isPresented: $showGalleryPicker, selection: $selectedVideoItem, matching: .videos)
        #endif
        .onChange(of: viewModel.showAddClipPicker) { show in
            if show {
                showGalleryPicker = true
                viewModel.showAddClipPicker = false
            }
        }
        #if os(iOS)
        .onChange(of: selectedVideoItem) { newItem in
            guard let newItem else { return }
            selectedVideoItem = nil
            isImportingClip = true
            Task {
                defer { isImportingClip = false }
                guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                let dest = FileStorageService.shared.clipCacheDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
                try? data.write(to: dest)
                viewModel.addClipFromGallery(url: dest)
            }
        }
        #endif
        .task {
            viewModel.configureAudioSessionForMusic()
            viewModel.rebuildPlaylistIfNeeded()
            await viewModel.preCacheClips()

            guard let rawMusicUrl = params.musicUrl, !rawMusicUrl.isEmpty else { return }

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
                bottomBarButton(icon: "sparkles", label: "AI") {
                    viewModel.showAiPrompt = true
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

                bottomBarButton(icon: "arrow.triangle.2.circlepath", label: "Change") {
                    viewModel.pexelsReplaceMode = true
                    viewModel.showPexelsSheet = true
                }

                bottomBarButton(icon: "trash", label: "Delete", color: viewModel.clips.count > 1 ? .red : theme.textTertiary) {
                    if viewModel.clips.count > 1 {
                        viewModel.removeClip(at: viewModel.activeClipIndex)
                    }
                }

                bottomBarButton(
                    icon: viewModel.voiceoverFileURL != nil ? "mic.fill" : "mic",
                    label: "Voice",
                    color: viewModel.voiceoverFileURL != nil ? theme.primary : nil
                ) {
                    viewModel.showVoiceoverSheet = true
                }

                bottomBarButton(icon: "music.note", label: "Music") {
                    showMusicFilePicker = true
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
        if isImportingClip { return "Importing video..." }
        if viewModel.isPexelsDownloading { return "Downloading clip..." }
        if viewModel.aiGenerating { return viewModel.aiStatus.isEmpty ? "Generating..." : viewModel.aiStatus }
        return "Loading..."
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
