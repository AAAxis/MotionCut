import SwiftUI
import AVFoundation

// MARK: - CapCut-style Multi-track Timeline

struct ClipsTimelineView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme
    @State private var draggedClipIndex: Int? = nil

    private let thumbHeight: CGFloat = 52
    private let musicRowHeight: CGFloat = 36
    private let textRowHeight: CGFloat = 28
    private let timeRulerHeight: CGFloat = 22
    private let minClipWidth: CGFloat = 60
    private let pixelsPerSecond: CGFloat = 50
    private let screenPadding: CGFloat = UIScreen.main.bounds.width / 2

    private var totalDuration: Double {
        if viewModel.clips.count > 1 {
            return viewModel.clips.reduce(0) { $0 + ($1.beatDuration ?? $1.sourceDuration ?? 3.0) }
        }
        // For single clip, prefer the player's reported duration (most accurate)
        if viewModel.duration > 0 { return viewModel.duration }
        return viewModel.clips.first.flatMap { $0.sourceDuration ?? $0.beatDuration } ?? 10.0
    }

    private var timelineContentWidth: CGFloat {
        let clipsWidth = viewModel.clips.reduce(CGFloat(0)) { $0 + clipWidth(for: $1) } + CGFloat(max(0, viewModel.clips.count - 1)) * 2
        let durationWidth = totalDuration * pixelsPerSecond
        return max(clipsWidth, durationWidth)
    }

    @State private var lastAutoScrollTime: Int = -1
    @State private var userIsDragging = false

    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 0) {
                            timeRuler
                            videoClipsRow
                            if viewModel.selectedMusic != nil { musicWaveformRow }
                            textTrackRow
                        }

                        // Time markers for auto-scroll (every 0.5s)
                        let markerCount = max(1, Int(totalDuration * 2) + 1)
                        ForEach(0..<markerCount, id: \.self) { tick in
                            Color.clear
                                .frame(width: 1, height: 1)
                                .id("time_\(tick)")
                                .offset(x: CGFloat(Double(tick) * 0.5) * pixelsPerSecond)
                        }
                    }
                    .padding(.leading, screenPadding)
                    .padding(.trailing, screenPadding)
                    .padding(.vertical, 6)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { _ in userIsDragging = true }
                        .onEnded { _ in userIsDragging = true }
                )
                .onChange(of: viewModel.isPlaying) { playing in
                    // Reset manual scroll when user taps play
                    if playing { userIsDragging = false }
                }
                .onChange(of: viewModel.currentTime) { newTime in
                    guard viewModel.isPlaying, !userIsDragging else { return }
                    let tick = Int(newTime * 2)
                    guard tick != lastAutoScrollTime else { return }
                    lastAutoScrollTime = tick
                    withAnimation(.linear(duration: 0.5)) {
                        proxy.scrollTo("time_\(tick)", anchor: .center)
                    }
                }
            }

            playhead
        }
        .background(theme.isDark ? theme.surface : theme.borderLight)
        .padding(.vertical, 4)
    }

    // MARK: - Time Ruler

    private var timeRuler: some View {
        let totalW = timelineContentWidth
        let interval: Double = totalDuration < 10 ? 1.0 : 2.0
        let tickCount = Int(totalDuration / interval) + 1

        return HStack(spacing: 0) {
            ForEach(0..<tickCount, id: \.self) { i in
                let sec = Double(i) * interval
                let isMain = i % 2 == 0 || interval >= 2
                VStack(spacing: 2) {
                    Text(formatRulerTime(sec))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(theme.textTertiary.opacity(isMain ? 0.8 : 0.5))
                }
                .frame(width: interval * pixelsPerSecond, alignment: .leading)
            }
        }
        .frame(width: totalW, height: timeRulerHeight, alignment: .leading)
        .padding(.bottom, 4)
    }

    // MARK: - Video Clips Row

    private var videoClipsRow: some View {
        HStack(spacing: 2) {
            ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                FilmstripClip(
                    clip: clip,
                    index: index,
                    isSelected: index == viewModel.activeClipIndex,
                    thumbHeight: thumbHeight,
                    clipWidth: clipWidth(for: clip),
                    onTap: {
                        if index == viewModel.activeClipIndex {
                            viewModel.playAllClips()
                        } else {
                            viewModel.selectClip(at: index)
                        }
                    },
                    onRemove: viewModel.clips.count > 1 ? { viewModel.removeClip(at: index) } : nil,
                    onTrimStartChanged: { delta in
                        handleTrimDrag(index: index, isStart: true, delta: delta, clip: clip)
                    },
                    onTrimEndChanged: { delta in
                        handleTrimDrag(index: index, isStart: false, delta: delta, clip: clip)
                    }
                )
                .id(clip.id)
                .onDrag {
                    draggedClipIndex = index
                    return NSItemProvider(object: String(index) as NSString)
                }
                .onDrop(of: [.text], delegate: ClipDropDelegate(
                    targetIndex: index,
                    draggedIndex: $draggedClipIndex,
                    viewModel: viewModel
                ))
            }

            // Add clip button at end of timeline
            Button {
                viewModel.showAddClipPicker = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(theme.border, lineWidth: 1)
                        )
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(theme.primary)
                }
                .frame(width: 44, height: thumbHeight)
            }
        }
        .frame(height: thumbHeight)
        .padding(.bottom, 6)
    }

    // MARK: - Music Waveform Row

    private var musicWaveformRow: some View {
        let barWidth = max(60, totalDuration * pixelsPerSecond)

        return HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.foxBlue.opacity(0.2))
                    .frame(width: barWidth, height: musicRowHeight)

                AudioWaveformView(width: barWidth, height: musicRowHeight, color: theme.foxBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                RoundedRectangle(cornerRadius: 4)
                    .stroke(theme.foxBlue.opacity(0.5), lineWidth: 1)
                    .frame(width: barWidth, height: musicRowHeight)

                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                    Text(viewModel.selectedMusic?.name ?? "Music")
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(theme.foxBlue)
                .padding(.horizontal, 8)
            }
            .frame(width: barWidth, height: musicRowHeight)

            Spacer(minLength: 0)
        }
        .frame(height: musicRowHeight)
        .padding(.bottom, 6)
    }

    // MARK: - Text Track Row

    private var textTrackRow: some View {
        let hasText = viewModel.clips.contains { ($0.text ?? "").isEmpty == false }
        guard hasText else { return AnyView(EmptyView()) }

        return AnyView(
            HStack(spacing: 2) {
                ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                    let w = clipWidth(for: clip)
                    let txt = clip.text ?? ""
                    let hasContent = !txt.isEmpty

                    RoundedRectangle(cornerRadius: 4)
                        .fill(hasContent ? theme.primary.opacity(0.2) : Color.clear)
                        .frame(width: w, height: textRowHeight)
                        .overlay(
                            Group {
                                if hasContent {
                                    Text(txt)
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(theme.primary)
                                        .lineLimit(1)
                                        .padding(.horizontal, 6)
                                }
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(hasContent ? theme.primary.opacity(0.4) : Color.clear, lineWidth: 0.5)
                        )
                }
            }
            .frame(height: textRowHeight)
        )
    }

    // MARK: - Center Playhead

    private var playhead: some View {
        let headColor = theme.text
        return VStack(spacing: 0) {
            Triangle()
                .fill(headColor)
                .frame(width: 12, height: 7)

            Rectangle()
                .fill(headColor)
                .frame(width: 1.5)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func clipWidth(for clip: Clip) -> CGFloat {
        let dur = clip.beatDuration ?? clip.sourceDuration ?? 3.0
        let trimmedDur = dur * (clip.trimEnd - clip.trimStart) / 100.0
        return max(minClipWidth, trimmedDur * pixelsPerSecond)
    }

    private func handleTrimDrag(index: Int, isStart: Bool, delta: CGFloat, clip: Clip) {
        let dur = clip.beatDuration ?? clip.sourceDuration ?? 3.0
        let totalWidth = dur * pixelsPerSecond
        let pctChange = Double(delta / totalWidth) * 100.0
        if isStart {
            let newVal = max(0, min(clip.trimEnd - 5, clip.trimStart + pctChange))
            viewModel.updateClipTrimStart(index, newVal)
        } else {
            let newVal = max(clip.trimStart + 5, min(100, clip.trimEnd + pctChange))
            viewModel.updateClipTrimEnd(index, newVal)
        }
    }

    private func formatRulerTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        if m > 0 { return String(format: "%02d:%02d", m, s) }
        return String(format: "00:%02d.%d", s, ms)
    }
}

// MARK: - Audio Waveform Visualization

struct AudioWaveformView: View {
    let width: CGFloat
    let height: CGFloat
    let color: Color

    @State private var bars: [CGFloat] = []

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, barH in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(color.opacity(0.6))
                    .frame(width: 2, height: barH)
            }
        }
        .frame(width: width, height: height)
        .onAppear { generateWaveform() }
    }

    private func generateWaveform() {
        let count = max(1, Int(width / 3))
        var rng = SystemRandomNumberGenerator()
        bars = (0..<count).map { i in
            let phase = Double(i) / Double(count)
            let envelope = sin(phase * .pi) * 0.6 + 0.2
            let noise = Double.random(in: 0.4...1.0, using: &rng)
            return height * CGFloat(envelope * noise)
        }
    }
}

// MARK: - Triangle Shape (Playhead indicator)

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Individual Filmstrip Clip

struct FilmstripClip: View {
    let clip: Clip
    let index: Int
    let isSelected: Bool
    let thumbHeight: CGFloat
    let clipWidth: CGFloat
    let onTap: () -> Void
    let onRemove: (() -> Void)?
    let onTrimStartChanged: (CGFloat) -> Void
    let onTrimEndChanged: (CGFloat) -> Void

    @Environment(\.theme) var theme
    @State private var thumbnailFrames: [UIImage] = []
    @State private var isLoadingThumbs = true
    @State private var showRemoveButton = false

    private let handleWidth: CGFloat = 14

    var body: some View {
        ZStack(alignment: .center) {
            filmstripBody
                .onTapGesture {
                    if showRemoveButton {
                        showRemoveButton = false
                    } else {
                        onTap()
                    }
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    if onRemove != nil {
                        showRemoveButton = true
                    }
                }

            if isSelected {
                trimHandles
            }
        }
        .frame(width: clipWidth + (isSelected ? handleWidth * 2 : 0))
        .task(id: clip.localUri ?? clip.uri) { await loadThumbnails() }
    }

    private var filmstripBody: some View {
        ZStack {
            HStack(spacing: 0) {
                if thumbnailFrames.isEmpty {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.surfaceElevated)
                        .frame(width: clipWidth, height: thumbHeight)
                        .overlay(ProgressView().scaleEffect(0.6))
                } else {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(Array(thumbnailFrames.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width / CGFloat(max(1, thumbnailFrames.count)),
                                           height: thumbHeight)
                                    .clipped()
                            }
                        }
                    }
                    .frame(width: clipWidth, height: thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? theme.text : theme.border, lineWidth: isSelected ? 2 : 0.5)
            )

            if showRemoveButton, let onRemove {
                Color.black.opacity(0.5)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .onTapGesture { showRemoveButton = false }

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showRemoveButton = false
                            onRemove()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white, Color.red)
                        }
                        .offset(x: 6, y: -6)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: clipWidth, height: thumbHeight)
    }

    private var trimHandles: some View {
        HStack(spacing: 0) {
            TrimHandle(edge: .leading, color: theme.text)
                .gesture(DragGesture().onChanged { value in onTrimStartChanged(value.translation.width) })
            Spacer()
            TrimHandle(edge: .trailing, color: theme.text)
                .gesture(DragGesture().onChanged { value in onTrimEndChanged(value.translation.width) })
        }
        .frame(width: clipWidth + handleWidth * 2, height: thumbHeight)
    }

    private func loadThumbnails() async {
        let urlString = clip.localUri ?? clip.uri
        let url: URL? = (urlString.hasPrefix("http") || urlString.hasPrefix("file://")) ? URL(string: urlString) : URL(fileURLWithPath: urlString)
        guard let videoURL = url else { return }

        await MainActor.run { thumbnailFrames = []; isLoadingThumbs = true }

        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 120)

        let frameCount = max(2, Int(clipWidth / 30))
        let dur = clip.sourceDuration ?? (clip.beatDuration ?? 3.0)
        guard dur > 0 else { return }

        var images: [UIImage] = []
        for i in 0..<frameCount {
            let time = CMTime(seconds: (Double(i) / Double(frameCount)) * dur, preferredTimescale: 600)
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                images.append(UIImage(cgImage: cgImage))
            } catch { break }
        }

        await MainActor.run {
            thumbnailFrames = images.isEmpty ? [] : images
            isLoadingThumbs = false
        }
    }
}

// MARK: - Drag & Drop Reorder

struct ClipDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var draggedIndex: Int?
    let viewModel: VideoEditorViewModel

    func performDrop(info: DropInfo) -> Bool {
        draggedIndex = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let from = draggedIndex, from != targetIndex else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.reorderClips(from: from, to: targetIndex)
        }
        draggedIndex = targetIndex
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        return draggedIndex != nil
    }
}

// MARK: - Trim Handle

struct TrimHandle: View {
    let edge: HorizontalEdge
    let color: Color
    @Environment(\.theme) var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: 14, height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.isDark ? Color.black.opacity(0.4) : Color.white.opacity(0.6))
                    .frame(width: 3, height: 18)
            )
            .contentShape(Rectangle().inset(by: -8))
    }
}
