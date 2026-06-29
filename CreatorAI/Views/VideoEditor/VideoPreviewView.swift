import SwiftUI
import AVKit
import AVFoundation

// MARK: - Compact Video Preview

struct VideoPreviewView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme
    @State private var textDragBase: CGPoint?
    @State private var logoDragBase: CGPoint?
    @State private var posterImage: PlatformImage?
    @State private var overlayImage: PlatformImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                previewPoster
                    .clipFilter(visibleClip?.clip.filterName ?? "None")
                    .clipLayout(visibleClip?.clip, canvasSize: geo.size)

                // Video
                if let player = viewModel.player {
                    PlatformVideoPlayerView(player: player, videoGravity: .resizeAspectFill)
                        .opacity(viewModel.isPlaying ? 1 : 0)
                        .clipFilter(visibleClip?.clip.filterName ?? "None")
                        .clipLayout(visibleClip?.clip, canvasSize: geo.size)
                } else if posterImage == nil {
                    theme.surface
                    VStack(spacing: 14) {
                        if !viewModel.clipsCached {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(theme.textTertiary)
                            Text("Loading video...")
                                .font(.system(size: 14))
                                .foregroundColor(theme.textTertiary)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ], spacing: 10) {
                                emptyAction(icon: "folder", title: "File") {
                                    viewModel.showAddClipPicker = true
                                }
                                emptyAction(icon: "music.note", title: "Music") {
                                    viewModel.showMusicPickerFromTimeline = true
                                }
                                emptyAction(icon: "mic", title: "Voice") {
                                    viewModel.showVoiceoverSheet = true
                                }
                                emptyAction(icon: "text.bubble", title: "Text") {
                                    viewModel.showSubtitlesFromTimeline = true
                                }
                            }
                            .frame(maxWidth: 260)
                        }
                    }
                    .padding(18)
                }

                filterTintOverlay(for: visibleClip?.clip.filterName ?? "None")
                    .allowsHitTesting(false)

                // Subtitle overlay
                if let overlay = visibleTextOverlay,
                   let text = overlay.clip.text,
                   !text.isEmpty {
                    let clip = overlay.clip
                    let clipIndex = overlay.index
                    let size = geo.size
                    let margin: CGFloat = 18
                    let x = max(margin, min(size.width - margin, CGFloat(clip.textX) * size.width))
                    let y = max(margin, min(size.height - margin, CGFloat(clip.textY) * size.height))

                    Text(text)
                        .font(previewFont(for: clip.textFontName))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.95), radius: 3, x: 1, y: 1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.28))
                        )
                        .frame(maxWidth: max(80, size.width - 32))
                        .fixedSize(horizontal: false, vertical: true)
                        .position(x: x, y: y)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let base = textDragBase ?? CGPoint(x: x, y: y)
                                    textDragBase = base
                                    let nextX = max(margin, min(size.width - margin, base.x + value.translation.width))
                                    let nextY = max(margin, min(size.height - margin, base.y + value.translation.height))
                                    viewModel.updateTextPosition(
                                        for: clipIndex,
                                        x: Double(nextX / max(1, size.width)),
                                        y: Double(nextY / max(1, size.height))
                                    )
                                }
                                .onEnded { _ in
                                    textDragBase = nil
                                }
                        )
                        .onTapGesture {
                            viewModel.selectText(at: clipIndex)
                            viewModel.showSubtitlesFromTimeline = true
                        }
                }

                if let overlay = visibleClip,
                   let overlayImage,
                   overlay.clip.overlayImageUri != nil {
                    let clip = overlay.clip
                    let clipIndex = overlay.index
                    let size = geo.size
                    let logoSize = max(28, min(size.width, size.height) * CGFloat(clip.overlayScale))
                    let x = max(logoSize / 2, min(size.width - logoSize / 2, CGFloat(clip.overlayX) * size.width))
                    let y = max(logoSize / 2, min(size.height - logoSize / 2, CGFloat(clip.overlayY) * size.height))

                    Image(platformImage: overlayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: logoSize, height: logoSize)
                        .position(x: x, y: y)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let base = logoDragBase ?? CGPoint(x: x, y: y)
                                    logoDragBase = base
                                    let nextX = max(logoSize / 2, min(size.width - logoSize / 2, base.x + value.translation.width))
                                    let nextY = max(logoSize / 2, min(size.height - logoSize / 2, base.y + value.translation.height))
                                    viewModel.updateOverlayPosition(
                                        for: clipIndex,
                                        x: Double(nextX / max(1, size.width)),
                                        y: Double(nextY / max(1, size.height))
                                    )
                                }
                                .onEnded { _ in logoDragBase = nil }
                        )
                }

                if viewModel.player != nil {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                viewModel.togglePlayPause()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.42))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.95))
                                        .offset(x: viewModel.isPlaying ? 0 : 1.5)
                                }
                            }
                            #if os(macOS)
                            .buttonStyle(.plain)
                            #endif
                        }
                        .padding(14)
                        Spacer()
                    }
                    .zIndex(20)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if viewModel.player != nil {
                    viewModel.togglePlayPause()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .task(id: previewPosterKey) {
            await loadPosterImage()
        }
        .task(id: visibleClip?.clip.overlayImageUri ?? "no-logo") {
            await loadOverlayImage()
        }
    }

    @ViewBuilder
    private var previewPoster: some View {
        if let posterImage {
            Image(platformImage: posterImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(Color.black.opacity(0.08))
        } else {
            theme.surface
        }
    }

    private var previewPosterKey: String {
        previewClipURL?.absoluteString ?? "empty-\(viewModel.clips.count)-\(viewModel.activeClipIndex)"
    }

    private var previewClipURL: URL? {
        guard !viewModel.clips.isEmpty else { return nil }
        let index: Int
        if viewModel.clips.indices.contains(viewModel.activeClipIndex), viewModel.activeClipIndex >= 0 {
            index = viewModel.activeClipIndex
        } else {
            index = 0
        }
        let clip = viewModel.clips[index]
        let urlString = clip.localUri ?? clip.uri
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") || urlString.hasPrefix("file://") {
            return URL(string: urlString)
        }
        return URL(fileURLWithPath: urlString)
    }

    private func loadPosterImage() async {
        guard let url = previewClipURL else {
            await MainActor.run { posterImage = nil }
            return
        }
        if let clip = visibleClip?.clip, viewModel.isImageClip(clip),
           let data = try? Data(contentsOf: url),
           let image = PlatformImage.from(data: data) {
            await MainActor.run { posterImage = image }
            return
        }
        if let image = await ThumbnailService.shared.generateThumbnail(for: url) {
            await MainActor.run { posterImage = image }
        }
    }

    private func loadOverlayImage() async {
        guard let path = visibleClip?.clip.overlayImageUri else {
            await MainActor.run { overlayImage = nil }
            return
        }
        let url = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path)
        guard let url,
              let data = try? Data(contentsOf: url),
              let image = PlatformImage.from(data: data)
        else {
            await MainActor.run { overlayImage = nil }
            return
        }
        await MainActor.run { overlayImage = image }
    }

    private var visibleTextOverlay: (index: Int, clip: Clip)? {
        guard let visibleClip else { return nil }
        let duration = max(0.1, visibleClip.clip.beatDuration ?? visibleClip.clip.sourceDuration ?? viewModel.duration)
        return textIsVisible(for: visibleClip.clip, localTime: visibleClip.localTime, duration: duration)
            ? (visibleClip.index, visibleClip.clip)
            : nil
    }

    private var visibleClip: (index: Int, clip: Clip, localTime: Double)? {
        guard !viewModel.clips.isEmpty else { return nil }

        if !viewModel.isPlaying,
           case .video(let selectedIndex) = viewModel.timelineSelection,
           viewModel.clips.indices.contains(selectedIndex) {
            return (selectedIndex, viewModel.clips[selectedIndex], 0)
        }

        if viewModel.isPlaying, viewModel.clips.count > 1 {
            var elapsed: Double = 0
            let playhead = max(0, viewModel.currentTime)
            for (index, clip) in viewModel.clips.enumerated() {
                let duration = max(0.1, clip.beatDuration ?? clip.sourceDuration ?? 1.5)
                if playhead <= elapsed + duration || index == viewModel.clips.count - 1 {
                    return (index, clip, max(0, playhead - elapsed))
                }
                elapsed += duration
            }
        }

        let fallbackIndex = viewModel.clips.indices.contains(viewModel.activeClipIndex) ? viewModel.activeClipIndex : 0
        let clip = viewModel.clips[fallbackIndex]
        return (fallbackIndex, clip, viewModel.currentTime)
    }

    private func textIsVisible(for clip: Clip, localTime: Double, duration: Double) -> Bool {
        guard let text = clip.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let start = max(0, min(clip.textStart, 100)) / 100.0 * duration
        let end = max(clip.textStart + 1, min(clip.textEnd, 100)) / 100.0 * duration
        let clampedLocalTime = max(0, min(localTime, duration))
        return clampedLocalTime >= start && clampedLocalTime <= end
    }

    private func emptyAction(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.border, lineWidth: 1)
                    )
            )
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    @ViewBuilder
    private func filterTintOverlay(for name: String) -> some View {
        switch name {
        case "Warm":
            Color.orange.opacity(0.18).blendMode(.softLight)
        case "Cool":
            Color.cyan.opacity(0.18).blendMode(.softLight)
        case "Punch":
            Color.black.opacity(0.12).blendMode(.overlay)
            Color.orange.opacity(0.08).blendMode(.colorDodge)
        case "Mono":
            Color.gray.opacity(0.26).blendMode(.saturation)
        case "Fade":
            Color.white.opacity(0.16).blendMode(.screen)
            Color.orange.opacity(0.08).blendMode(.softLight)
        default:
            EmptyView()
        }
    }

    private func previewFont(for name: String) -> Font {
        switch name {
        case "Rounded":
            return .system(size: 16, weight: .semibold, design: .rounded)
        case "Serif":
            return .system(size: 16, weight: .semibold, design: .serif)
        case "Avenir Next":
            return .custom("AvenirNext-DemiBold", size: 16)
        case "Helvetica Neue":
            return .custom("HelveticaNeue-Bold", size: 16)
        case "Georgia":
            return .custom("Georgia-Bold", size: 16)
        default:
            return .system(size: 16, weight: .semibold)
        }
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

    @ViewBuilder
    func clipLayout(_ clip: Clip?, canvasSize: CGSize) -> some View {
        if let clip, clip.videoLayoutMode == "PiP" {
            let side = max(40, min(canvasSize.width, canvasSize.height) * CGFloat(max(0.18, min(0.85, clip.videoScale))))
            self
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.8), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .position(
                    x: canvasSize.width * CGFloat(max(0.08, min(0.92, clip.videoX))),
                    y: canvasSize.height * CGFloat(max(0.08, min(0.92, clip.videoY)))
                )
        } else {
            self
        }
    }
}
