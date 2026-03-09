import SwiftUI
import AVKit

struct VideoEditorView: View {
    let params: VideoEditorParams
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: VideoEditorViewModel

    init(params: VideoEditorParams) {
        self.params = params
        self._viewModel = StateObject(wrappedValue: VideoEditorViewModel(params: params))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        VideoPreviewView(viewModel: viewModel)

                        ClipsTimelineView(viewModel: viewModel)
                    }
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                GenerateButtonView(
                    label: "Export",
                    isGenerating: viewModel.isGenerating,
                    isSaved: viewModel.isSaved
                ) {
                    Task { await viewModel.saveVideo() }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 20)
                .background(theme.background.shadow(color: .black.opacity(0.05), radius: 8, y: -4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background.ignoresSafeArea(.all))

            // Minimal close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(theme.text)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(theme.surfaceElevated))
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 12)
                }
                Spacer()
            }
            .allowsHitTesting(true)

        }
        .navigationBarHidden(true)
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
        .task {
            viewModel.configureAudioSessionForMusic()
            viewModel.rebuildPlaylistIfNeeded()
            await viewModel.preCacheClips()

            guard let musicUrl = params.musicUrl, !musicUrl.isEmpty else { return }

            let track = MusicTrack(id: "reel-music", name: "Reel Music", file: musicUrl)
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
}
