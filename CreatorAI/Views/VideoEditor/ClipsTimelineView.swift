import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#endif

// MARK: - CapCut-style Multi-track Timeline

struct ClipsTimelineView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme
    @State private var draggedClipIndex: Int? = nil
    @State private var musicTrimBases: [String: (start: Double, end: Double)] = [:]
    @State private var musicMoveBases: [String: (start: Double, end: Double)] = [:]
    @State private var textTrimBases: [Int: (start: Double, end: Double)] = [:]
    @State private var textMoveBases: [Int: (start: Double, end: Double)] = [:]
    @State private var activeItemDrag = false

    private let thumbHeight: CGFloat = 52
    private let attachedTextHeight: CGFloat = 24
    private let videoLaneSpacing: CGFloat = 6
    private let musicRowHeight: CGFloat = 36
    private let textRowHeight: CGFloat = 28
    private let timeRulerHeight: CGFloat = 22
    private let minClipWidth: CGFloat = 60
    private let basePixelsPerSecond: CGFloat = 50
    private let minZoomScale: CGFloat = 0.45
    private let maxZoomScale: CGFloat = 4.0
    @State private var zoomScale: CGFloat = 1.0
    @State private var zoomGestureBaseScale: CGFloat?
    private var pixelsPerSecond: CGFloat { basePixelsPerSecond * zoomScale }
    private let screenPadding: CGFloat = ScreenSize.width / 2

    private var totalDuration: Double {
        max(0.1, viewModel.timelineDisplayDuration)
    }

    private var timelineContentWidth: CGFloat {
        let clipsWidth = timelineClips.reduce(CGFloat(0)) { partial, item in
            max(partial, item.x + clipWidth(for: item.clip))
        }
        let pendingWidth = pendingVideoItems.reduce(CGFloat(0)) { partial, item in
            max(partial, item.x + item.width)
        }
        let durationWidth = totalDuration * pixelsPerSecond
        return max(clipsWidth, pendingWidth, durationWidth)
    }

    private var videoLaneCount: Int {
        min(2, max(1, viewModel.clips.count))
    }

    private var videoRowsHeight: CGFloat {
        CGFloat(videoLaneCount) * videoClipBlockHeight + CGFloat(max(0, videoLaneCount - 1)) * videoLaneSpacing
    }

    private var videoClipBlockHeight: CGFloat {
        thumbHeight + attachedTextHeight
    }

    private var timelineClips: [(index: Int, clip: Clip, x: CGFloat, lane: Int)] {
        var x: CGFloat = 0
        return viewModel.clips.enumerated().map { index, clip in
            defer {
                x += clipWidth(for: clip) + 2
            }
            return (index: index, clip: clip, x: x, lane: index % videoLaneCount)
        }
    }

    private var pendingVideoItems: [(slot: Int, x: CGFloat, width: CGFloat, lane: Int)] {
        guard viewModel.pendingVideoSlots > 0 else { return [] }
        let startX = timelineClips.reduce(CGFloat(0)) { partial, item in
            max(partial, item.x + clipWidth(for: item.clip) + 2)
        }
        let pendingWidth = max(minClipWidth, CGFloat(1.6) * pixelsPerSecond)
        return (0..<min(1, viewModel.pendingVideoSlots)).map { slot in
            (
                slot: slot,
                x: startX + CGFloat(slot) * (pendingWidth + 2),
                width: pendingWidth,
                lane: (viewModel.clips.count + slot) % videoLaneCount
            )
        }
    }

    @State private var lastAutoScrollTime: Int = -1
    @State private var userIsDragging = false
    @State private var scrollOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let sidePadding = geo.size.width / 2
            let playbackOffset = clampedTimelineOffset(CGFloat(currentTimelineTime) * pixelsPerSecond)
            let effectiveOffset = userIsDragging ? scrollOffset : playbackOffset

            ZStack {
                timelineContent
                    .padding(.leading, sidePadding)
                    .padding(.trailing, sidePadding)
                    .padding(.vertical, 6)
                    .offset(x: -effectiveOffset)
                    .animation(viewModel.isPlaying && !userIsDragging ? .linear(duration: 0.24) : nil, value: currentTimelineTime)

                playhead
                    .frame(height: geo.size.height)
                    .position(x: sidePadding, y: geo.size.height / 2)

                VStack {
                    HStack {
                        undoHistoryControl
                            .padding(.top, 5)
                            .padding(.leading, 8)
                        Spacer()
                        zoomControls
                            .padding(.top, 5)
                            .padding(.trailing, 8)
                    }
                    Spacer()
                }

                #if os(macOS)
                MacTimelineTrackpadBridge(
                    onScroll: { deltaX, deltaY in
                        handleMacTrackpadScroll(deltaX: deltaX, deltaY: deltaY)
                    },
                    onMagnify: { magnification in
                        handleMacTrackpadMagnify(magnification)
                    }
                )
                .allowsHitTesting(false)
                #endif
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(scrubGesture)
            .simultaneousGesture(zoomGesture)
            .onAppear {
                scrollOffset = playbackOffset
            }
            .onChange(of: viewModel.isPlaying) { playing in
                if playing {
                    userIsDragging = false
                    scrollOffset = playbackOffset
                }
            }
            .onChange(of: viewModel.currentTime) { _ in
                guard viewModel.isPlaying, !userIsDragging else { return }
                scrollOffset = playbackOffset
            }
            .onChange(of: zoomScale) { _ in
                guard viewModel.isPlaying, !userIsDragging else { return }
                scrollOffset = playbackOffset
            }
        }
        .coordinateSpace(name: "timeline")
        .background(theme.isDark ? theme.surface : theme.borderLight)
        .padding(.vertical, 4)
    }

    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            timeRuler
            videoClipsRow
            musicWaveformRows
            voiceoverWaveformRow
        }
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !activeItemDrag else { return }
                if !userIsDragging {
                    userIsDragging = true
                    dragStartOffset = scrollOffset
                    viewModel.pauseForScrub()
                }
                let nextOffset = clampedTimelineOffset(dragStartOffset - value.translation.width)
                scrollOffset = nextOffset
                viewModel.seekToTime(Double(nextOffset / max(1, pixelsPerSecond)))
            }
            .onEnded { _ in
                guard !activeItemDrag else { return }
                dragStartOffset = scrollOffset
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { magnification in
                guard !activeItemDrag else { return }
                let base = zoomGestureBaseScale ?? zoomScale
                zoomGestureBaseScale = base
                setTimelineZoom(base * magnification)
            }
            .onEnded { _ in
                zoomGestureBaseScale = nil
                dragStartOffset = scrollOffset
            }
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button {
                stepTimelineZoom(multiplier: 0.8)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 28)
            }
            .disabled(zoomScale <= minZoomScale + 0.01)

            Button {
                stepTimelineZoom(multiplier: 1.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 28)
            }
            .disabled(zoomScale >= maxZoomScale - 0.01)
        }
        .foregroundColor(theme.text)
        .background(
            Capsule()
                .fill(theme.surfaceElevated.opacity(0.94))
                .overlay(Capsule().stroke(theme.border, lineWidth: 0.7))
                .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
        )
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    private var undoHistoryControl: some View {
        Button {
            viewModel.undoLastEdit()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 28)
        }
        .foregroundColor(theme.text)
        .background(
            Capsule()
                .fill(theme.surfaceElevated.opacity(0.94))
                .overlay(Capsule().stroke(theme.border, lineWidth: 0.7))
                .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
        )
        .disabled(!viewModel.canUndoEdit)
        .opacity(viewModel.canUndoEdit ? 1 : 0.45)
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel("Undo last edit")
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
        ZStack(alignment: .topLeading) {
            if viewModel.clips.isEmpty && viewModel.pendingVideoSlots == 0 {
                videoTrackPlaceholder
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                ForEach(timelineClips, id: \.clip.id) { item in
                    let index = item.index
                    let clip = item.clip
                    let y = CGFloat(item.lane) * (videoClipBlockHeight + videoLaneSpacing)
                    let clipW = clipWidth(for: clip)
                    FilmstripClip(
                        clip: clip,
                        index: index,
                        isSelected: viewModel.isVideoSelected(index),
                        isTextSelected: viewModel.isTextSelected(index),
                        thumbHeight: thumbHeight,
                        attachedTextHeight: attachedTextHeight,
                        clipWidth: clipW,
                        onTap: {
                            viewModel.selectClip(at: index)
                        },
                        onTextTap: {
                            viewModel.selectText(at: index)
                            viewModel.showSubtitlesFromTimeline = true
                        },
                        onTrimStartChanged: { delta in
                            handleTrimDrag(index: index, isStart: true, delta: delta, clip: clip)
                        },
                        onTrimEndChanged: { delta in
                            handleTrimDrag(index: index, isStart: false, delta: delta, clip: clip)
                        }
                    )
                    .id(clip.id)
                    .offset(x: item.x, y: y)
                    .scaleEffect(draggedClipIndex == index ? 1.04 : 1.0)
                    .shadow(color: .black.opacity(draggedClipIndex == index ? 0.28 : 0), radius: draggedClipIndex == index ? 12 : 0, y: draggedClipIndex == index ? 8 : 0)
                    .zIndex(draggedClipIndex == index ? 5 : 0)
                    .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.78), value: draggedClipIndex == index)
                    .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.82), value: item.x)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .onDrag {
                        activeItemDrag = true
                        draggedClipIndex = index
                        return NSItemProvider(object: String(index) as NSString)
                    }
                    .onDrop(of: [.text], delegate: ClipDropDelegate(
                        targetIndex: index,
                        draggedIndex: $draggedClipIndex,
                        activeItemDrag: $activeItemDrag,
                        viewModel: viewModel
                    ))

                    if index < viewModel.clips.count - 1 && clip.transitionName != "None" {
                        TransitionTimelineBadge(
                            transitionName: clip.transitionName,
                            isSelected: true
                        )
                        .offset(x: item.x + clipW - 15, y: y + (thumbHeight / 2) - 15)
                        .zIndex(8)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }

                ForEach(pendingVideoItems, id: \.slot) { item in
                    let y = CGFloat(item.lane) * (videoClipBlockHeight + videoLaneSpacing)
                    VStack(spacing: 2) {
                        PendingTimelineBlock(
                            title: "",
                            icon: "film",
                            color: theme.primary,
                            height: thumbHeight,
                            width: item.width
                        )
                        PendingTimelineBlock(
                            title: "Text",
                            icon: "text.bubble",
                            color: theme.primary,
                            height: attachedTextHeight,
                            width: item.width
                        )
                    }
                    .offset(x: item.x, y: y)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
        }
        .frame(width: timelineContentWidth, height: videoRowsHeight, alignment: .topLeading)
        .padding(.bottom, 6)
    }

    private var videoTrackPlaceholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "film.fill")
                .font(.system(size: 12, weight: .medium))
            Text("Video track")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundColor(theme.textTertiary)
        .padding(.horizontal, 12)
        .frame(width: max(220, timelineContentWidth), height: thumbHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.surfaceElevated.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.border.opacity(0.7), lineWidth: 1)
                )
        )
    }

    // MARK: - Music Waveform Row

    private var musicWaveformRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selected = viewModel.selectedMusic {
                audioWaveformRow(
                    title: selected.name,
                    icon: "music.note",
                    color: theme.foxBlue,
                    trackId: selected.id,
                    timelineStart: selected.timelineStart,
                    timelineEnd: selected.timelineEnd,
                    isSelected: viewModel.isMusicSelected(selected.id),
                    onSelect: { viewModel.selectMusicTrack(id: selected.id) },
                    trailingAction: {
                        EmptyView()
                    }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))

                ForEach(viewModel.additionalMusicTracks) { track in
                    audioWaveformRow(
                        title: track.name,
                        icon: "waveform",
                        color: theme.foxBlue,
                        trackId: track.id,
                        timelineStart: track.timelineStart,
                        timelineEnd: track.timelineEnd,
                        isSelected: viewModel.isMusicSelected(track.id),
                        onSelect: { viewModel.selectMusicTrack(id: track.id) },
                        trailingAction: {
                            EmptyView()
                        }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            } else {
                EmptyView()
            }
        }
    }

    private func audioWaveformRow<Trailing: View>(
        title: String,
        icon: String,
        color: Color,
        trackId: String? = nil,
        timelineStart: Double = 0,
        timelineEnd: Double? = nil,
        isSelected: Bool = false,
        onSelect: (() -> Void)? = nil,
        onTimingChange: ((Double?, Double?) -> Void)? = nil,
        @ViewBuilder trailingAction: () -> Trailing
    ) -> some View {
        let barWidth = max(60, totalDuration * pixelsPerSecond)
        let clampedStart = max(0, min(timelineStart, totalDuration))
        let clampedEnd = max(clampedStart + 0.1, min(timelineEnd ?? totalDuration, totalDuration))
        let blockX = CGFloat(clampedStart) * pixelsPerSecond
        let blockWidth = max(44, CGFloat(clampedEnd - clampedStart) * pixelsPerSecond)
        let isMoving = trackId.flatMap { musicMoveBases[$0] } != nil

        return HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.08))
                    .frame(width: barWidth, height: musicRowHeight)

                ZStack(alignment: .leading) {
                    AudioWaveformView(width: blockWidth, height: musicRowHeight, color: color)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? color : color.opacity(0.55), lineWidth: isSelected ? 2 : 1)
                        .frame(width: blockWidth, height: musicRowHeight)

                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 10))
                        Text(title)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(color)
                    .padding(.horizontal, 8)

                    if let trackId {
                        Color.clear
                            .contentShape(Rectangle())
                            .padding(.horizontal, 12)
                            .gesture(
                                DragGesture(minimumDistance: 3)
                                    .onChanged { value in
                                        activeItemDrag = true
                                        let base = musicMoveBases[trackId] ?? (clampedStart, clampedEnd)
                                        musicMoveBases[trackId] = base
                                        let delta = Double(value.translation.width / pixelsPerSecond)
                                        let length = max(0.1, base.end - base.start)
                                        let maxStart = max(0, totalDuration - length)
                                        let nextStart = max(0, min(base.start + delta, maxStart))
                                        if let onTimingChange {
                                            onTimingChange(nextStart, nextStart + length)
                                        } else {
                                            viewModel.updateMusicTrackTiming(id: trackId, start: nextStart, end: nextStart + length)
                                        }
                                    }
                                    .onEnded { _ in
                                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.78)) {
                                            musicMoveBases[trackId] = nil
                                            activeItemDrag = false
                                        }
                                    }
                            )
                    }

                    if let trackId {
                        HStack(spacing: 0) {
                            TimelineMiniTrimHandle(edge: .leading, color: color)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            activeItemDrag = true
                                            let base = musicTrimBases[trackId] ?? (clampedStart, clampedEnd)
                                            musicTrimBases[trackId] = base
                                            let delta = Double(value.translation.width / pixelsPerSecond)
                                            if let onTimingChange {
                                                onTimingChange(base.start + delta, nil)
                                            } else {
                                                viewModel.updateMusicTrackTiming(id: trackId, start: base.start + delta)
                                            }
                                        }
                                        .onEnded { _ in
                                            musicTrimBases[trackId] = nil
                                            activeItemDrag = false
                                        }
                                )
                            Spacer()
                            TimelineMiniTrimHandle(edge: .trailing, color: color)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            activeItemDrag = true
                                            let base = musicTrimBases[trackId] ?? (clampedStart, clampedEnd)
                                            musicTrimBases[trackId] = base
                                            let delta = Double(value.translation.width / pixelsPerSecond)
                                            if let onTimingChange {
                                                onTimingChange(nil, base.end + delta)
                                            } else {
                                                viewModel.updateMusicTrackTiming(id: trackId, end: base.end + delta)
                                            }
                                        }
                                        .onEnded { _ in
                                            musicTrimBases[trackId] = nil
                                            activeItemDrag = false
                                        }
                                )
                        }
                        .frame(width: blockWidth, height: musicRowHeight)
                    }

                }
                .frame(width: blockWidth, height: musicRowHeight)
                .offset(x: blockX)
                .scaleEffect(isMoving ? 1.035 : 1.0)
                .shadow(color: .black.opacity(isMoving ? 0.24 : 0), radius: isMoving ? 10 : 0, y: isMoving ? 6 : 0)
                .zIndex(isMoving ? 4 : 0)
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.8), value: isMoving)
                .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.86), value: blockX)
                .onTapGesture {
                    onSelect?()
                }

                HStack {
                    Spacer()
                    trailingAction()
                }
                .padding(.trailing, 8)
            }
            .frame(width: barWidth, height: musicRowHeight)

            Spacer(minLength: 0)
        }
        .frame(height: musicRowHeight)
        .padding(.bottom, 6)
    }

    // MARK: - Voiceover Waveform Row

    private var voiceoverWaveformRow: some View {
        if viewModel.voiceoverFileURL != nil {
            return AnyView(
                audioWaveformRow(
                    title: "Voiceover",
                    icon: "mic.fill",
                    color: theme.success,
                    trackId: "voiceover",
                    timelineStart: viewModel.voiceoverTimelineStart,
                    timelineEnd: viewModel.voiceoverTimelineEnd,
                    isSelected: viewModel.isVoiceoverSelected,
                    onSelect: { viewModel.selectVoiceover() },
                    onTimingChange: { start, end in
                        viewModel.updateVoiceoverTiming(start: start, end: end)
                    }
                ) {
                    EmptyView()
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            )
        } else if viewModel.pendingVoiceoverProcessing {
            return AnyView(
                PendingTimelineBlock(
                    title: "Voice loading",
                    icon: "mic.fill",
                    color: theme.success,
                    height: musicRowHeight,
                    width: max(180, min(timelineContentWidth, totalDuration * pixelsPerSecond))
                )
                .padding(.bottom, 6)
                .transition(.move(edge: .leading).combined(with: .opacity))
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    // MARK: - Text Track Row

    private var textTrackRow: some View {
        let hasText = viewModel.clips.contains { ($0.text ?? "").isEmpty == false }
        if !hasText && viewModel.pendingTextSlots == 0 {
            return AnyView(EmptyView())
        }

        return AnyView(
            ZStack(alignment: .leading) {
                ForEach(timelineClips, id: \.clip.id) { item in
                    let clip = item.clip
                    let w = clipWidth(for: clip)
                    let txt = clip.text ?? ""
                    let hasContent = !txt.isEmpty
                    let textStart = max(0, min(clip.textStart, 100))
                    let textEnd = max(textStart + 1, min(clip.textEnd, 100))
                    let textX = w * CGFloat(textStart / 100)
                    let textWidth = max(36, w * CGFloat((textEnd - textStart) / 100))
                    let textIsMoving = textMoveBases[item.index] != nil

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.primary.opacity(0.06))
                            .frame(width: w, height: textRowHeight)

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(hasContent ? theme.primary.opacity(0.2) : theme.primary.opacity(0.08))
                                .frame(width: textWidth, height: textRowHeight)
                                .overlay(
                                    Group {
                                        if hasContent {
                                            Text("Text")
                                                .font(.system(size: 8, weight: .medium))
                                                .foregroundColor(theme.primary)
                                                .lineLimit(1)
                                                .padding(.horizontal, 10)
                                        } else {
                                            Image(systemName: "text.bubble")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(theme.primary.opacity(0.7))
                                        }
                                    }
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(viewModel.isTextSelected(item.index) ? theme.primary : theme.primary.opacity(hasContent ? 0.4 : 0.25), lineWidth: viewModel.isTextSelected(item.index) ? 2 : 0.5)
                                )

                            Color.clear
                                .contentShape(Rectangle())
                                .padding(.horizontal, 12)
                                .gesture(
                                    DragGesture(minimumDistance: 3)
                                        .onChanged { value in
                                            activeItemDrag = true
                                            viewModel.selectText(at: item.index)
                                            let base = textMoveBases[item.index] ?? (textStart, textEnd)
                                            textMoveBases[item.index] = base
                                            let delta = Double(value.translation.width / max(1, w)) * 100
                                            let length = max(1, base.end - base.start)
                                            let maxStart = max(0, 100 - length)
                                            let nextStart = max(0, min(base.start + delta, maxStart))
                                            viewModel.updateTextTiming(for: item.index, start: nextStart, end: nextStart + length)
                                        }
                                        .onEnded { _ in
                                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.78)) {
                                                textMoveBases[item.index] = nil
                                                activeItemDrag = false
                                            }
                                        }
                                )

                            HStack(spacing: 0) {
                                TimelineMiniTrimHandle(edge: .leading, color: theme.primary)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                activeItemDrag = true
                                                let base = textTrimBases[item.index] ?? (textStart, textEnd)
                                                textTrimBases[item.index] = base
                                                let delta = Double(value.translation.width / max(1, w)) * 100
                                                viewModel.updateTextTiming(for: item.index, start: base.start + delta)
                                            }
                                            .onEnded { _ in
                                                textTrimBases[item.index] = nil
                                                activeItemDrag = false
                                            }
                                    )
                                Spacer()
                                TimelineMiniTrimHandle(edge: .trailing, color: theme.primary)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                activeItemDrag = true
                                                let base = textTrimBases[item.index] ?? (textStart, textEnd)
                                                textTrimBases[item.index] = base
                                                let delta = Double(value.translation.width / max(1, w)) * 100
                                                viewModel.updateTextTiming(for: item.index, end: base.end + delta)
                                            }
                                            .onEnded { _ in
                                                textTrimBases[item.index] = nil
                                                activeItemDrag = false
                                            }
                                    )
                            }
                            .frame(width: textWidth, height: textRowHeight)
                        }
                        .offset(x: textX)
                        .scaleEffect(textIsMoving ? 1.04 : 1.0)
                        .shadow(color: .black.opacity(textIsMoving ? 0.24 : 0), radius: textIsMoving ? 9 : 0, y: textIsMoving ? 5 : 0)
                        .zIndex(textIsMoving ? 4 : 0)
                        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.8), value: textIsMoving)
                        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.86), value: textX)
                        .onTapGesture {
                            viewModel.selectText(at: item.index)
                            viewModel.showSubtitlesFromTimeline = true
                        }
                    }
                    .frame(width: w, height: textRowHeight, alignment: .leading)
                    .offset(x: item.x)
                }

                if viewModel.pendingTextSlots > 0 {
                    let startX = timelineClips.reduce(CGFloat(0)) { partial, item in
                        max(partial, item.x + clipWidth(for: item.clip) + 2)
                    }
                    let pendingWidth = max(64, CGFloat(1.3) * pixelsPerSecond)
                    ForEach(0..<min(1, viewModel.pendingTextSlots), id: \.self) { slot in
                        PendingTimelineBlock(
                            title: slot == 0 ? "Text" : "Caption",
                            icon: "text.bubble",
                            color: theme.primary,
                            height: textRowHeight,
                            width: pendingWidth
                        )
                        .offset(x: startX + CGFloat(slot) * (pendingWidth + 2))
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                }
            }
            .frame(width: timelineContentWidth, height: textRowHeight, alignment: .leading)
            .transition(.move(edge: .leading).combined(with: .opacity))
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

    private var currentTimelineTime: Double {
        if isReelTimeline {
            return max(0, min(viewModel.currentTime, totalDuration))
        }

        guard viewModel.clips.indices.contains(viewModel.activeClipIndex) else {
            return max(0, min(viewModel.currentTime, totalDuration))
        }

        let start = viewModel.clips.prefix(viewModel.activeClipIndex).reduce(0) { $0 + timelineDuration(for: $1) }
        return max(0, min(start + viewModel.currentTime, totalDuration))
    }

    private var isReelTimeline: Bool {
        viewModel.clips.count > 1 && viewModel.clips.contains { $0.beatDuration != nil }
    }

    private func clampedTimelineOffset(_ offset: CGFloat) -> CGFloat {
        max(0, min(offset, max(0, timelineContentWidth)))
    }

    private func stepTimelineZoom(multiplier: CGFloat) {
        setTimelineZoom(zoomScale * multiplier)
    }

    private func setTimelineZoom(_ scale: CGFloat) {
        let previousPixelsPerSecond = max(1, pixelsPerSecond)
        let focusedTime = userIsDragging
            ? Double(scrollOffset / previousPixelsPerSecond)
            : currentTimelineTime
        let nextScale = max(minZoomScale, min(maxZoomScale, scale))
        zoomScale = nextScale
        let nextOffset = CGFloat(max(0, min(focusedTime, totalDuration))) * (basePixelsPerSecond * nextScale)
        scrollOffset = clampedTimelineOffset(nextOffset)
        dragStartOffset = scrollOffset
    }

    #if os(macOS)
    private func handleMacTrackpadScroll(deltaX: CGFloat, deltaY: CGFloat) {
        guard !activeItemDrag else { return }
        let dominantDelta = abs(deltaX) >= abs(deltaY) ? deltaX : deltaY
        guard abs(dominantDelta) > 0.1 else { return }
        if !userIsDragging {
            userIsDragging = true
            dragStartOffset = scrollOffset
            viewModel.pauseForScrub()
        }
        let nextOffset = clampedTimelineOffset(scrollOffset + dominantDelta)
        scrollOffset = nextOffset
        dragStartOffset = nextOffset
        viewModel.seekToTime(Double(nextOffset / max(1, pixelsPerSecond)))
    }

    private func handleMacTrackpadMagnify(_ magnification: CGFloat) {
        guard !activeItemDrag else { return }
        guard abs(magnification) > 0.001 else { return }
        let multiplier = max(0.75, min(1.35, 1 + magnification))
        setTimelineZoom(zoomScale * multiplier)
    }
    #endif

    private func clipWidth(for clip: Clip) -> CGFloat {
        let trimmedDur = timelineDuration(for: clip)
        return max(minClipWidth, trimmedDur * pixelsPerSecond)
    }

    private func timelineDuration(for clip: Clip) -> Double {
        let dur = clip.beatDuration ?? clip.sourceDuration ?? 3.0
        return dur * (clip.trimEnd - clip.trimStart) / 100.0
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

struct PendingTimelineBlock: View {
    let title: String
    let icon: String
    let color: Color
    let height: CGFloat
    let width: CGFloat

    @Environment(\.theme) var theme
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: max(9, height * 0.28), weight: .semibold))
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: max(8, min(11, height * 0.28)), weight: .semibold))
                    .lineLimit(1)
            }
            ProgressView()
                .scaleEffect(0.55)
                .tint(color)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .frame(width: width, height: height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(color.opacity(isPulsing ? 0.2 : 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundColor(color.opacity(isPulsing ? 0.75 : 0.42))
                )
        )
        .scaleEffect(isPulsing ? 1.015 : 1.0)
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
    }
}

struct TransitionTimelineBadge: View {
    let transitionName: String
    let isSelected: Bool
    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            if isSelected {
                Text(shortName)
                    .font(.system(size: 8, weight: .bold))
                    .lineLimit(1)
            }
        }
        .foregroundColor(isSelected ? .white : theme.primary)
        .padding(.horizontal, isSelected ? 6 : 0)
        .frame(minWidth: 30, minHeight: 30)
        .background(
            Capsule()
                .fill(isSelected ? theme.primary : theme.surfaceElevated)
                .overlay(Capsule().stroke(theme.primary.opacity(isSelected ? 0.95 : 0.55), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
    }

    private var shortName: String {
        switch transitionName {
        case "Fade": return "Fade"
        case "Dip": return "Dip"
        default: return ""
        }
    }

    private var icon: String {
        switch transitionName {
        case "Fade": return "circle.lefthalf.filled"
        case "Dip": return "moonphase.new.moon"
        default: return "plus"
        }
    }
}

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
    let isTextSelected: Bool
    let thumbHeight: CGFloat
    let attachedTextHeight: CGFloat
    let clipWidth: CGFloat
    let onTap: () -> Void
    let onTextTap: () -> Void
    let onTrimStartChanged: (CGFloat) -> Void
    let onTrimEndChanged: (CGFloat) -> Void

    @Environment(\.theme) var theme
    @State private var thumbnailFrames: [PlatformImage] = []
    @State private var isLoadingThumbs = true

    private let handleWidth: CGFloat = 14

    var body: some View {
        ZStack(alignment: .center) {
            VStack(spacing: 2) {
                filmstripBody
                    .onTapGesture {
                        onTap()
                    }
                attachedTextStrip
            }

            if isSelected {
                trimHandles
                    .offset(y: -(attachedTextHeight + 2) / 2)
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
                                Image(platformImage: img)
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
            .timelineClipFilter(clip.filterName)
            .overlay(filterTintOverlay(for: clip.filterName).clipShape(RoundedRectangle(cornerRadius: 4)))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? theme.text : theme.border, lineWidth: isSelected ? 2 : 0.5)
            )

            if clip.videoLayoutMode == "PiP" {
                HStack(spacing: 4) {
                    Image(systemName: "pip.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("PiP")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.58)))
                .frame(width: clipWidth - 6, height: thumbHeight - 6, alignment: .topTrailing)
            }

        }
        .frame(width: clipWidth, height: thumbHeight)
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

    private var attachedTextStrip: some View {
        let text = (clip.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !text.isEmpty
        let textStart = max(0, min(clip.textStart, 100))
        let textEnd = max(textStart + 1, min(clip.textEnd, 100))
        let x = clipWidth * CGFloat(textStart / 100)
        let width = max(34, clipWidth * CGFloat((textEnd - textStart) / 100))

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.primary.opacity(isTextSelected ? 0.12 : 0.06))
                .frame(width: clipWidth, height: attachedTextHeight)

            HStack(spacing: 4) {
                Image(systemName: hasText ? "text.bubble.fill" : "plus")
                    .font(.system(size: 8, weight: .bold))
                Text("Text")
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(theme.primary)
            .padding(.horizontal, 7)
            .frame(width: width, height: attachedTextHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hasText ? theme.primary.opacity(0.2) : theme.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isTextSelected ? theme.primary : theme.primary.opacity(hasText ? 0.42 : 0.22), lineWidth: isTextSelected ? 1.5 : 0.7)
            )
            .offset(x: x)
        }
        .frame(width: clipWidth, height: attachedTextHeight, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            onTextTap()
        }
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

        var images: [PlatformImage] = []
        for i in 0..<frameCount {
            let time = CMTime(seconds: (Double(i) / Double(frameCount)) * dur, preferredTimescale: 600)
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                images.append(PlatformImage.from(cgImage: cgImage))
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
    @Binding var activeItemDrag: Bool
    let viewModel: VideoEditorViewModel

    func performDrop(info: DropInfo) -> Bool {
        draggedIndex = nil
        activeItemDrag = false
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let from = draggedIndex, from != targetIndex else { return }
        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.78)) {
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

struct TimelineMiniTrimHandle: View {
    let edge: HorizontalEdge
    let color: Color
    @Environment(\.theme) var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 10, height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.isDark ? Color.black.opacity(0.4) : Color.white.opacity(0.65))
                    .frame(width: 2, height: 10)
            )
            .contentShape(Rectangle().inset(by: -8))
    }
}

#if os(macOS)
private struct MacTimelineTrackpadBridge: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat) -> Void
    let onMagnify: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll, onMagnify: onMagnify)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.postsFrameChangedNotifications = true
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.onMagnify = onMagnify
        context.coordinator.attach(to: nsView)
    }

    final class Coordinator {
        var onScroll: (CGFloat, CGFloat) -> Void
        var onMagnify: (CGFloat) -> Void
        private weak var view: NSView?
        private var scrollMonitor: Any?
        private var magnifyMonitor: Any?

        init(onScroll: @escaping (CGFloat, CGFloat) -> Void, onMagnify: @escaping (CGFloat) -> Void) {
            self.onScroll = onScroll
            self.onMagnify = onMagnify
        }

        deinit {
            if let scrollMonitor {
                NSEvent.removeMonitor(scrollMonitor)
            }
            if let magnifyMonitor {
                NSEvent.removeMonitor(magnifyMonitor)
            }
        }

        func attach(to view: NSView) {
            self.view = view
            guard scrollMonitor == nil else { return }

            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.eventIsInsideTimeline(event) else { return event }
                self.onScroll(CGFloat(event.scrollingDeltaX), CGFloat(event.scrollingDeltaY))
                return nil
            }

            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self, self.eventIsInsideTimeline(event) else { return event }
                self.onMagnify(CGFloat(event.magnification))
                return nil
            }
        }

        private func eventIsInsideTimeline(_ event: NSEvent) -> Bool {
            guard let view, let window = view.window, event.window === window else { return false }
            let pointInView = view.convert(event.locationInWindow, from: nil)
            return view.bounds.contains(pointInView)
        }
    }
}
#endif

private extension View {
    @ViewBuilder
    func timelineClipFilter(_ name: String) -> some View {
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

// MARK: - Scroll offset tracking

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
