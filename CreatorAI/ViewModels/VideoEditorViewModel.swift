import SwiftUI
import AVFoundation
import AVKit
import Photos
#if os(macOS)
import AppKit
#endif

enum TimelineSelection: Equatable {
    case none
    case video(Int)
    case text(Int)
    case voiceover
    case music(String)
}

struct AiAgentLogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let title: String
    let detail: String
}

@MainActor
class VideoEditorViewModel: ObservableObject {
    private struct EditHistorySnapshot: Equatable {
        var clips: [Clip]
        var activeClipIndex: Int
        var timelineSelection: TimelineSelection
        var selectedMusic: MusicTrack?
        var additionalMusicTracks: [MusicTrack]
        var musicVolume: Double
        var voiceoverFileURL: URL?
        var voiceoverVolume: Double
        var voiceoverTimelineStart: Double
        var voiceoverTimelineEnd: Double?
        var voiceoverMuted: Bool
        var aspectRatio: String
        var addCaptionsViaCloud: Bool
    }

    @Published private(set) var canUndoEdit = false
    @Published private(set) var lastEditHistoryLabel: String?
    private var editHistory: [EditHistorySnapshot] = []
    private var editHistoryLabels: [String] = []
    private let maxEditHistoryCount = 80
    private var isRestoringEditHistory = false
    private var isCoalescingAiEditHistory = false

    // Clips
    @Published var clips: [Clip] = [] {
        didSet {
            guard !isRestoringEditHistory else { return }
            guard clipTimelineSignature(clips) != clipTimelineSignature(oldValue) else { return }
            resetAudioRowsToFullTimeline()
        }
    }
    @Published var activeClipIndex: Int = 0
    @Published var timelineSelection: TimelineSelection = .none
    @Published var clipsCached = false
    @Published var isPreparingSelectedClip = false

    // Playback
    @Published var isPlaying = true
    @Published var isMuted = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var player: AVPlayer?

    // Trim
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double = 100

    // Quality
    @Published var aspectRatio = "1:1"
    @Published var exportQuality = "original"

    /// When true, captions will be added via cloud function after export (no local caption rendering).
    @Published var addCaptionsViaCloud = true
    @Published var showVolumeSheet = false
    @Published var showLayoutSheet = false

    /// Trigger gallery picker for adding a clip (set from timeline "+" button)
    @Published var showAddClipPicker = false

    // Music
    @Published var selectedMusic: MusicTrack?
    @Published var additionalMusicTracks: [MusicTrack] = []
    @Published var musicVolume: Double = 0.5
    @Published var musicLibrary = MusicTrack.library
    @Published var showMusicPickerFromTimeline = false
    @Published var showSubtitlesFromTimeline = false
    /// True when we tried to load music (from params) but playback failed (download or init).
    @Published var musicLoadFailed = false

    // Voiceover
    @Published var voiceoverFileURL: URL?
    @Published var voiceoverVolume: Double = 1.0
    @Published var voiceoverTimelineStart: Double = 0
    @Published var voiceoverTimelineEnd: Double?
    @Published var voiceoverMuted = false
    @Published var showVoiceoverSheet = false
    private var voiceoverAVPlayer: AVPlayer?
    private var voiceoverEndObserver: NSObjectProtocol?

    func setVoiceover(url: URL, timelineEnd: Double? = nil) {
        rememberEditHistory("voiceover")
        voiceoverFileURL = url
        configureAudioSessionForMusic()
        let end = timelineTotalDuration
        voiceoverTimelineStart = min(voiceoverTimelineStart, max(0, end - 0.1))
        let requestedEnd = timelineEnd ?? end
        voiceoverTimelineEnd = abs(requestedEnd - end) < 0.05 ? nil : max(voiceoverTimelineStart + 0.1, min(requestedEnd, end))
        prepareVoiceoverPlayer(seekTime: currentTime)
        if isPlaying {
            playMusicIfAudible(at: currentTime)
            playVoiceoverIfAudible(at: currentTime)
        }
    }

    func removeVoiceover() {
        rememberEditHistory("voiceover delete")
        voiceoverFileURL = nil
        voiceoverTimelineStart = 0
        voiceoverTimelineEnd = nil
        if timelineSelection == .voiceover {
            timelineSelection = clips.indices.contains(activeClipIndex) ? .video(activeClipIndex) : .none
        }
        clearVoiceoverPlayer()
    }

    // Speed
    @Published var showSpeedSheet = false

    // Aspect Ratio
    @Published var showAspectRatioSheet = false

    func setClipSpeed(_ speed: Double) {
        guard clips.indices.contains(activeClipIndex) else { return }
        rememberEditHistory("speed")
        clips[activeClipIndex].speed = max(0.1, min(5.0, speed))
        // Apply rate to player only during preview — export uses scaleTimeRange per clip
        if isPlaying {
            player?.rate = Float(clips[activeClipIndex].speed)
        }
    }

    var activeClipSpeed: Double {
        guard clips.indices.contains(activeClipIndex) else { return 1.0 }
        return clips[activeClipIndex].speed
    }

    // Processing
    @Published var isGenerating = false
    @Published var processingStatus = "idle"
    @Published var processingError: String?
    @Published var processingMessage: String?
    @Published var isProcessingModalVisible = false
    @Published var generatedVideoUri: URL?
    #if os(macOS)
    private var activeSharingPicker: NSSharingServicePicker?
    #endif

    // Editor
    @Published var activeTab = "edit"

    private var timeObserver: Any?
    private var boundaryObserver: Any?
    private var endObserver: NSObjectProtocol?
    /// Music played with AVPlayer so it mixes reliably with video (same as RN/expo-av behavior).
    private var musicAVPlayer: AVPlayer?
    private var musicEndObserver: NSObjectProtocol?
    private var additionalMusicPlayers: [String: AVPlayer] = [:]
    private var additionalMusicEndObservers: [String: NSObjectProtocol] = [:]
    @Published var videoName: String
    private let generationId: String?
    private let musicUrl: String?
    private let userId: String

    private var playlistItems: [(clip: Clip, startOffset: Double)] = []
    private var currentQueueItems: [AVPlayerItem] = []
    private var isReelMode: Bool { clips.contains { $0.beatDuration != nil } && clips.count > 1 }

    func isImageClip(_ clip: Clip) -> Bool {
        clip.mimeType.hasPrefix("image/")
    }

    private var currentEditHistorySnapshot: EditHistorySnapshot {
        EditHistorySnapshot(
            clips: clips,
            activeClipIndex: activeClipIndex,
            timelineSelection: timelineSelection,
            selectedMusic: selectedMusic,
            additionalMusicTracks: additionalMusicTracks,
            musicVolume: musicVolume,
            voiceoverFileURL: voiceoverFileURL,
            voiceoverVolume: voiceoverVolume,
            voiceoverTimelineStart: voiceoverTimelineStart,
            voiceoverTimelineEnd: voiceoverTimelineEnd,
            voiceoverMuted: voiceoverMuted,
            aspectRatio: aspectRatio,
            addCaptionsViaCloud: addCaptionsViaCloud
        )
    }

    func rememberEditHistory(_ label: String) {
        guard !isRestoringEditHistory else { return }
        if isCoalescingAiEditHistory, editHistoryLabels.last == "AI edit" {
            return
        }
        let snapshot = currentEditHistorySnapshot
        guard editHistory.last != snapshot else { return }
        editHistory.append(snapshot)
        editHistoryLabels.append(label)
        if editHistory.count > maxEditHistoryCount {
            editHistory.removeFirst()
            editHistoryLabels.removeFirst()
        }
        canUndoEdit = true
        lastEditHistoryLabel = label
    }

    func undoLastEdit() {
        guard let snapshot = editHistory.popLast() else { return }
        let label = editHistoryLabels.popLast()
        isRestoringEditHistory = true
        clips = snapshot.clips
        activeClipIndex = snapshot.activeClipIndex
        timelineSelection = snapshot.timelineSelection
        selectedMusic = snapshot.selectedMusic
        additionalMusicTracks = snapshot.additionalMusicTracks
        musicVolume = snapshot.musicVolume
        voiceoverFileURL = snapshot.voiceoverFileURL
        voiceoverVolume = snapshot.voiceoverVolume
        voiceoverTimelineStart = snapshot.voiceoverTimelineStart
        voiceoverTimelineEnd = snapshot.voiceoverTimelineEnd
        voiceoverMuted = snapshot.voiceoverMuted
        aspectRatio = snapshot.aspectRatio
        addCaptionsViaCloud = snapshot.addCaptionsViaCloud
        isRestoringEditHistory = false

        canUndoEdit = !editHistory.isEmpty
        lastEditHistoryLabel = editHistoryLabels.last
        processingMessage = label.map { "Undid \($0)" } ?? "Undid edit"

        rebuildPlaylistIfNeeded()
        reconcileRestoredAudioPlayers()
        prepareVoiceoverPlayer(seekTime: currentTime)
        syncMusic(to: currentTime)
        syncVoiceover(to: currentTime)
        autosave()
    }

    private func reconcileRestoredAudioPlayers() {
        if selectedMusic == nil {
            if let obs = musicEndObserver {
                NotificationCenter.default.removeObserver(obs)
                musicEndObserver = nil
            }
            musicAVPlayer?.pause()
            musicAVPlayer = nil
        }

        let restoredAdditionalIds = Set(additionalMusicTracks.map(\.id))
        for (id, player) in additionalMusicPlayers where !restoredAdditionalIds.contains(id) {
            player.pause()
            additionalMusicPlayers[id] = nil
        }
        for (id, observer) in additionalMusicEndObservers where !restoredAdditionalIds.contains(id) {
            NotificationCenter.default.removeObserver(observer)
            additionalMusicEndObservers[id] = nil
        }

        if voiceoverFileURL == nil {
            clearVoiceoverPlayer()
        }
    }

    // MARK: - Init

    init(params: VideoEditorParams) {
        self.videoName = params.videoName ?? "Video"
        self.generationId = params.generationId
        self.musicUrl = params.musicUrl
        self.userId = params.userId

        // Parse takes JSON or single video
        if let takesJson = params.takesJson,
           let data = takesJson.data(using: .utf8),
           let takes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let parsedClips = takes.enumerated().map { (i, t) in
                let rawUri = t["uri"] as? String ?? ""
                let resolvedUri = Self.resolveClipPath(rawUri)
                let isLocal = !resolvedUri.hasPrefix("http://") && !resolvedUri.hasPrefix("https://")
                return Clip(
                    id: (t["id"] as? Int) ?? (Int(Date().timeIntervalSince1970 * 1000) + i),
                    uri: resolvedUri,
                    name: t["name"] as? String ?? "Take \(i + 1)",
                    mimeType: t["mimeType"] as? String ?? "video/mp4",
                    trimStart: t["trimStart"] as? Double ?? 0,
                    trimEnd: t["trimEnd"] as? Double ?? 100,
                    beatDuration: t["beatDuration"] as? Double,
                    sourceDuration: t["sourceDuration"] as? Double,
                    text: t["text"] as? String ?? "",
                    textStart: t["textStart"] as? Double ?? 0,
                    textEnd: t["textEnd"] as? Double ?? 100,
                    textX: t["textX"] as? Double ?? 0.5,
                    textY: t["textY"] as? Double ?? 0.82,
                    textFontName: t["textFontName"] as? String ?? "System",
                    localUri: isLocal ? resolvedUri : nil,
                    audioVolume: t["audioVolume"] as? Double ?? 1.0,
                    isMuted: t["isMuted"] as? Bool ?? false,
                    filterName: t["filterName"] as? String ?? "None",
                    overlayImageUri: t["overlayImageUri"] as? String,
                    overlayX: t["overlayX"] as? Double ?? 0.82,
                    overlayY: t["overlayY"] as? Double ?? 0.18,
                    overlayScale: t["overlayScale"] as? Double ?? 0.22,
                    transitionName: t["transitionName"] as? String ?? "None",
                    transitionDuration: t["transitionDuration"] as? Double ?? 0.35,
                    videoLayoutMode: t["videoLayoutMode"] as? String ?? "Full",
                    videoScale: t["videoScale"] as? Double ?? 1.0,
                    videoX: t["videoX"] as? Double ?? 0.5,
                    videoY: t["videoY"] as? Double ?? 0.5
                )
            }
            if parsedClips.allSatisfy(Self.clipHasPlayableSource(_:)) {
                self.clips = parsedClips
            } else if let videoUri = params.videoUri {
                let resolved = Self.resolveClipPath(videoUri)
                let isLocal = !resolved.hasPrefix("http://") && !resolved.hasPrefix("https://")
                self.clips = [Clip(id: 1, uri: resolved, name: videoName, localUri: isLocal ? resolved : nil)]
            } else {
                self.clips = parsedClips
            }
        } else if let videoUri = params.videoUri {
            let resolved = Self.resolveClipPath(videoUri)
            let isLocal = !resolved.hasPrefix("http://") && !resolved.hasPrefix("https://")
            self.clips = [Clip(id: 1, uri: resolved, name: videoName, localUri: isLocal ? resolved : nil)]
        }

        setupPlayer()
        Task { await hydrateMissingClipDurations() }
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        guard let firstClip = clips.first else { return }
        let urlString = firstClip.localUri ?? firstClip.uri

        // Skip setup if the clip is a remote URL that hasn't been cached yet
        // preCacheClips() will call rebuildPlaylistIfNeeded() after caching
        if isRemoteURL(urlString) && firstClip.localUri == nil {
            isPreparingSelectedClip = true
            return
        }

        guard let url = createURL(from: urlString) else { return }
        isPreparingSelectedClip = false

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.isMuted = isMuted || (clips.indices.contains(activeClipIndex) && clips[activeClipIndex].isMuted)

        startTimeObserver()

        if isPlaying {
            player?.play()
        }

        if !isReelMode {
            observeEndForLoop(item: playerItem)
        }
    }

    /// Rebuild the player as a sequential reel playlist (1s cuts). Uses remote URLs if not cached yet so playback starts immediately.
    func rebuildPlaylistIfNeeded() {
        guard isReelMode, generatedVideoUri == nil else { return }
        buildReelPlaylist(selectFirst: true)
    }

    /// Switch to "play all clips" mode: no clip selected, full sequence plays.
    func playAllClips() {
        guard isReelMode, generatedVideoUri == nil else { return }
        buildReelPlaylist(selectFirst: false)
        if isPlaying {
            player?.play()
        }
    }

    private func buildReelPlaylist(selectFirst: Bool = true) {
        removeAllObservers()

        playlistItems.removeAll()
        var items: [AVPlayerItem] = []

        for clip in clips {
            let urlString = clip.localUri ?? clip.uri
            guard let url = createURL(from: urlString) else { continue }

            let asset = AVURLAsset(url: url)
            let beatDur = clip.beatDuration ?? 1.5
            let srcDur = clip.sourceDuration ?? 10.0
            let maxStart = max(0, srcDur - beatDur)
            let startOffset = min(maxStart, max(0, (clip.trimStart / 100.0) * srcDur))

            let start = CMTime(seconds: startOffset, preferredTimescale: 600)
            let end = CMTime(seconds: startOffset + beatDur, preferredTimescale: 600)
            let item = AVPlayerItem(asset: asset)
            item.forwardPlaybackEndTime = end
            item.seek(to: start, completionHandler: nil)
            applyClipAudioSettings(clip, to: item)

            items.append(item)
            playlistItems.append((clip: clip, startOffset: startOffset))
        }

        guard !items.isEmpty else { return }

        currentQueueItems = items
        let queuePlayer = AVQueuePlayer(items: items)
        queuePlayer.isMuted = isMuted
        player = queuePlayer

        activeClipIndex = selectFirst ? 0 : -1
        timelineSelection = selectFirst ? .video(0) : .none
        duration = clips.reduce(0) { $0 + ($1.beatDuration ?? 1.5) }
        currentTime = 0

        startTimeObserver()
        observeQueueAdvance(queuePlayer: queuePlayer, allItems: items)

        syncMusic(to: 0)
        syncVoiceover(to: 0)
        if isPlaying {
            queuePlayer.play()
            playMusicIfAudible(at: 0)
            playVoiceoverIfAudible(at: 0)
        }
    }

    private func applyClipAudioSettings(_ clip: Clip, to item: AVPlayerItem) {
        let volume = clip.isMuted ? 0 : max(0, min(1, clip.audioVolume))
        guard volume < 0.999 else {
            item.audioMix = nil
            return
        }
        let params = AVMutableAudioMixInputParameters()
        params.setVolume(Float(volume), at: .zero)
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
    }

    /// Observe when the last item finishes to loop the whole playlist.
    private func observeQueueAdvance(queuePlayer: AVQueuePlayer, allItems: [AVPlayerItem]) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let finishedItem = notification.object as? AVPlayerItem else { return }
            guard queuePlayer === self.player else { return }

            if let idx = allItems.firstIndex(where: { $0 === finishedItem }) {
                let next = idx + 1
                if next < self.clips.count {
                    if self.activeClipIndex >= 0 { self.activeClipIndex = next }
                    // Apply per-clip speed for the new clip
                    let clipSpeed = self.clips[next].speed
                    if abs(clipSpeed - 1.0) > 0.01 {
                        self.player?.rate = Float(clipSpeed)
                    } else if self.player?.rate != 1.0 {
                        self.player?.rate = 1.0
                    }
                } else {
                    self.rebuildAndLoop()
                }
            }
        }
    }

    private func rebuildAndLoop() {
        guard isPlaying else { return }
        let wasPlayAll = (activeClipIndex == -1)
        buildReelPlaylist(selectFirst: !wasPlayAll)
        syncMusic(to: 0)
        playMusicIfAudible(at: 0)
        syncVoiceover(to: 0)
        playVoiceoverIfAudible(at: 0)
    }

    private func observeEndForLoop(item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            if self?.isPlaying == true {
                self?.player?.play()
            }
        }
    }

    private func startTimeObserver() {
        if let observer = timeObserver, let p = player {
            p.removeTimeObserver(observer)
        }
        timeObserver = nil

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if self.isReelMode && !self.playlistItems.isEmpty {
                    if self.activeClipIndex == -1, let cur = self.player?.currentItem,
                       let idx = self.currentQueueItems.firstIndex(where: { $0 === cur }) {
                        var elapsed: Double = 0
                        for i in 0..<idx { elapsed += self.clips[i].beatDuration ?? 1.5 }
                        let clipTime = CMTimeGetSeconds(time)
                        let offset = self.playlistItems.indices.contains(idx) ? self.playlistItems[idx].startOffset : 0
                        elapsed += max(0, clipTime - offset)
                        self.currentTime = min(elapsed, self.duration)
                        self.playMusicIfAudible(at: self.currentTime)
                        self.playVoiceoverIfAudible(at: self.currentTime)
                    } else if self.activeClipIndex >= 0 {
                        var elapsed: Double = 0
                        for i in 0..<self.activeClipIndex {
                            elapsed += self.clips[i].beatDuration ?? 1.5
                        }
                        let clipTime = CMTimeGetSeconds(time)
                        let offset = self.playlistItems.indices.contains(self.activeClipIndex)
                            ? self.playlistItems[self.activeClipIndex].startOffset : 0
                        elapsed += max(0, clipTime - offset)
                        self.currentTime = min(elapsed, self.duration)
                        self.playMusicIfAudible(at: self.currentTime)
                        self.playVoiceoverIfAudible(at: self.currentTime)
                    }
                } else {
                    self.currentTime = CMTimeGetSeconds(time)
                    self.playMusicIfAudible(at: self.currentTime)
                    self.playVoiceoverIfAudible(at: self.currentTime)
                    if let item = self.player?.currentItem {
                        let dur = CMTimeGetSeconds(item.duration)
                        if dur.isFinite && dur > 0 {
                            self.duration = dur
                            // Update clip sourceDuration so timeline width is correct
                            if self.activeClipIndex >= 0, self.activeClipIndex < self.clips.count,
                               self.clips[self.activeClipIndex].sourceDuration == nil {
                                self.clips[self.activeClipIndex].sourceDuration = dur
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying {
            if isReelMode, generatedVideoUri == nil, activeClipIndex >= 0 {
                playAllClips()
            }
            player?.play()
            if !isReelMode {
                // Apply per-clip speed only when previewing a single non-reel clip.
                let speed = activeClipSpeed
                if abs(speed - 1.0) > 0.01 {
                    player?.rate = Float(speed)
                }
            }
            syncMusic(to: currentTime)
            playMusicIfAudible(at: currentTime)
            syncVoiceover(to: currentTime)
            playVoiceoverIfAudible(at: currentTime)
        } else {
            player?.pause()
            musicAVPlayer?.pause()
            for player in additionalMusicPlayers.values {
                player.pause()
            }
            voiceoverAVPlayer?.pause()
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted || (clips.indices.contains(activeClipIndex) && clips[activeClipIndex].isMuted)
        musicAVPlayer?.isMuted = isMuted
        for player in additionalMusicPlayers.values {
            player.isMuted = isMuted
        }
        voiceoverAVPlayer?.isMuted = isMuted || voiceoverMuted
    }

    func seekToTime(_ seconds: Double) {
        guard duration > 0 else { return }
        let clamped = max(0, min(seconds, duration))
        let pct = (clamped / duration) * 100
        seek(to: pct)
    }

    func seekTimeline(to seconds: Double) {
        guard !clips.isEmpty else { return }
        let total = max(0.1, clips.reduce(0) { $0 + timelineClipDuration(for: $1) })
        let target = max(0, min(seconds, total))

        var elapsed: Double = 0
        for (index, clip) in clips.enumerated() {
            let clipDuration = max(0.1, timelineClipDuration(for: clip))
            if target <= elapsed + clipDuration || index == clips.count - 1 {
                let localTime = max(0, min(clipDuration, target - elapsed))
                seekClipPreview(index: index, localTimelineTime: localTime, globalTimelineTime: elapsed + localTime)
                return
            }
            elapsed += clipDuration
        }
    }

    func pauseForScrub() {
        if isPlaying {
            player?.pause()
            musicAVPlayer?.pause()
            for player in additionalMusicPlayers.values {
                player.pause()
            }
            voiceoverAVPlayer?.pause()
            isPlaying = false
        }
    }

    private func pausePlaybackForGeneration() {
        isPlaying = false
        player?.pause()
        musicAVPlayer?.pause()
        for player in additionalMusicPlayers.values {
            player.pause()
        }
        voiceoverAVPlayer?.pause()
    }

    func seek(to percentage: Double) {
        guard let player = player, duration > 0 else { return }

        if isReelMode && !playlistItems.isEmpty {
            let targetTime = (percentage / 100) * duration
            var accumulated: Double = 0
            for (i, clip) in clips.enumerated() {
                let beatDur = clip.beatDuration ?? 1.5
                if accumulated + beatDur >= targetTime || i == clips.count - 1 {
                    let withinClip = targetTime - accumulated
                    rebuildPlaylistFrom(index: i, seekOffset: withinClip)
                    currentTime = targetTime
                    syncMusic(to: targetTime)
                    syncVoiceover(to: targetTime)
                    return
                }
                accumulated += beatDur
            }
        } else {
            let time = CMTime(seconds: (percentage / 100) * duration, preferredTimescale: 600)
            player.seek(to: time)
            currentTime = CMTimeGetSeconds(time)
            syncMusic(to: currentTime)
            syncVoiceover(to: currentTime)
        }
    }

    private func seekClipPreview(index: Int, localTimelineTime: Double, globalTimelineTime: Double) {
        guard clips.indices.contains(index) else { return }

        if isReelMode && generatedVideoUri == nil {
            rebuildPlaylistFrom(index: index, seekOffset: localTimelineTime)
            currentTime = globalTimelineTime
            syncMusic(to: globalTimelineTime)
            syncVoiceover(to: globalTimelineTime)
            return
        }

        let clip = clips[index]
        guard !isImageClip(clip) else {
            activeClipIndex = index
            timelineSelection = .video(index)
            player?.pause()
            removeAllObservers()
            playlistItems.removeAll()
            currentQueueItems = []
            player = nil
            currentTime = localTimelineTime
            syncMusic(to: globalTimelineTime)
            syncVoiceover(to: globalTimelineTime)
            return
        }

        let urlString = clip.localUri ?? clip.uri
        if isRemoteURL(urlString) && clip.localUri == nil {
            isPreparingSelectedClip = true
            currentTime = localTimelineTime
            return
        }
        guard let url = createURL(from: urlString) else { return }
        isPreparingSelectedClip = false

        let sourceTime = sourceTime(for: clip, localTimelineTime: localTimelineTime)
        if activeClipIndex == index,
           let existingPlayer = player,
           currentQueueItems.isEmpty,
           playlistItems.isEmpty {
            currentTime = localTimelineTime
            existingPlayer.seek(
                to: CMTime(seconds: sourceTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: CMTime(seconds: 0.03, preferredTimescale: 600)
            )
            syncMusic(to: globalTimelineTime)
            syncVoiceover(to: globalTimelineTime)
            return
        }

        activeClipIndex = index
        timelineSelection = .video(index)

        removeAllObservers()
        playlistItems.removeAll()
        currentQueueItems = []

        let item = AVPlayerItem(url: url)
        applyClipAudioSettings(clip, to: item)
        if let sourceDuration = clip.sourceDuration ?? clip.beatDuration {
            let end = max(sourceTime + 0.05, min(sourceDuration, sourceTime + max(0.1, timelineClipDuration(for: clip) - localTimelineTime)))
            item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        }
        item.seek(to: CMTime(seconds: sourceTime, preferredTimescale: 600), completionHandler: nil)

        let wasPlaying = isPlaying
        let singlePlayer = AVPlayer(playerItem: item)
        singlePlayer.isMuted = isMuted || clip.isMuted
        player = singlePlayer
        duration = timelineClipDuration(for: clip)
        currentTime = localTimelineTime
        observeEndForLoop(item: item)
        startTimeObserver()
        syncMusic(to: globalTimelineTime)
        syncVoiceover(to: globalTimelineTime)
        if wasPlaying {
            singlePlayer.play()
            playMusicIfAudible(at: globalTimelineTime)
            playVoiceoverIfAudible(at: globalTimelineTime)
        }
    }

    private func sourceTime(for clip: Clip, localTimelineTime: Double) -> Double {
        let sourceDuration = max(0.1, clip.sourceDuration ?? clip.beatDuration ?? localTimelineTime)
        let trimStartTime = max(0, min(sourceDuration, (clip.trimStart / 100.0) * sourceDuration))
        let trimEndTime = max(trimStartTime + 0.1, min(sourceDuration, (clip.trimEnd / 100.0) * sourceDuration))
        let speed = max(0.1, min(5.0, clip.speed))
        return max(trimStartTime, min(trimEndTime, trimStartTime + localTimelineTime * speed))
    }

    private func rebuildPlaylistFrom(index: Int, seekOffset: Double) {
        removeAllObservers()

        playlistItems.removeAll()
        var items: [AVPlayerItem] = []

        for i in index..<clips.count {
            let clip = clips[i]
            let urlString = clip.localUri ?? clip.uri
            guard let url = createURL(from: urlString) else { continue }

            let asset = AVURLAsset(url: url)
            let beatDur = clip.beatDuration ?? 1.5
            let srcDur = clip.sourceDuration ?? 10.0
            let maxStart = max(0, srcDur - beatDur)
            let startOffset = min(maxStart, max(0, (clip.trimStart / 100.0) * srcDur))

            let effectiveStart: Double
            if i == index {
                effectiveStart = startOffset + seekOffset
            } else {
                effectiveStart = startOffset
            }

            let end = CMTime(seconds: startOffset + beatDur, preferredTimescale: 600)
            let item = AVPlayerItem(asset: asset)
            item.forwardPlaybackEndTime = end
            item.seek(to: CMTime(seconds: effectiveStart, preferredTimescale: 600), completionHandler: nil)

            items.append(item)
            playlistItems.append((clip: clip, startOffset: startOffset))
        }

        guard !items.isEmpty else { return }

        let queuePlayer = AVQueuePlayer(items: items)
        queuePlayer.isMuted = isMuted
        player = queuePlayer
        activeClipIndex = index
        timelineSelection = .video(index)
        currentQueueItems = items

        startTimeObserver()
        observeQueueAdvance(queuePlayer: queuePlayer, allItems: items)

        let targetTime = clips.prefix(index).reduce(0) { $0 + ($1.beatDuration ?? 1.5) } + seekOffset
        syncVoiceover(to: targetTime)
        if isPlaying {
            queuePlayer.play()
            playVoiceoverIfAudible(at: targetTime)
        }
    }

    // MARK: - Clip Management

    func selectClip(at index: Int) {
        guard index >= 0, index < clips.count else { return }
        activeClipIndex = index
        timelineSelection = .video(index)
        Task { await hydrateMissingClipDurations() }
        if isImageClip(clips[index]) {
            player?.pause()
            removeAllObservers()
            playlistItems.removeAll()
            currentQueueItems = []
            player = nil
            isPreparingSelectedClip = false
            duration = clips[index].beatDuration ?? clips[index].sourceDuration ?? 3.0
            currentTime = 0
            return
        }

        if isReelMode, generatedVideoUri == nil {
            duration = clips.reduce(0) { $0 + ($1.beatDuration ?? 1.5) }
            if player == nil || playlistItems.isEmpty {
                buildReelPlaylist(selectFirst: false)
            }
            return
        }

        let clip = clips[index]
        let urlString = clip.localUri ?? clip.uri
        if isRemoteURL(urlString) && clip.localUri == nil {
            player?.pause()
            removeAllObservers()
            playlistItems.removeAll()
            currentQueueItems = []
            player = nil
            currentTime = 0
            isPreparingSelectedClip = true
            return
        }
        guard let url = createURL(from: urlString) else { return }
        isPreparingSelectedClip = false

        removeAllObservers()
        playlistItems.removeAll()
        currentQueueItems = []

        let item = AVPlayerItem(url: url)
        applyClipAudioSettings(clip, to: item)

        if let beatDur = clip.beatDuration {
            let srcDur = clip.sourceDuration ?? 10.0
            let maxStart = max(0, srcDur - beatDur - 0.5)
            let startOffset = (clip.trimStart / 100.0) * srcDur
            let end = CMTime(seconds: startOffset + beatDur, preferredTimescale: 600)
            item.forwardPlaybackEndTime = end
            item.seek(to: CMTime(seconds: startOffset, preferredTimescale: 600), completionHandler: nil)
            duration = beatDur
        } else {
            duration = timelineClipDuration(for: clip)
        }

        let singlePlayer = AVPlayer(playerItem: item)
        singlePlayer.isMuted = isMuted || clip.isMuted
        player = singlePlayer
        currentTime = 0

        observeEndForLoop(item: item)
        startTimeObserver()

        syncVoiceover(to: timelineStartTime(for: index))
        if isPlaying {
            singlePlayer.play()
            playVoiceoverIfAudible(at: timelineStartTime(for: index))
        }
    }

    func updateClipTrimStart(_ index: Int, _ value: Double) {
        guard index >= 0, index < clips.count else { return }
        rememberEditHistory("trim")
        clips[index].trimStart = value
        clampAudioRowsToEditedTimeline()
    }

    func updateClipTrimEnd(_ index: Int, _ value: Double) {
        guard index >= 0, index < clips.count else { return }
        rememberEditHistory("trim")
        clips[index].trimEnd = value
        clampAudioRowsToEditedTimeline()
    }

    func addClip(uri: String, name: String) {
        rememberEditHistory("add clip")
        let clip = Clip(id: Int(Date().timeIntervalSince1970 * 1000), uri: uri, name: name)
        clips.append(clip)
    }

    func removeClip(at index: Int) {
        guard index >= 0 && index < clips.count else { return }
        rememberEditHistory("delete clip")
        clips.remove(at: index)
        duration = clips.reduce(0) { $0 + ($1.beatDuration ?? $1.sourceDuration ?? 3.0) }

        if clips.isEmpty {
            player?.pause()
            removeAllObservers()
            playlistItems.removeAll()
            currentQueueItems = []
            player = nil
            activeClipIndex = -1
            currentTime = 0
            timelineSelection = .none
            generatedVideoUri = nil
            syncMusic(to: currentTime)
            syncVoiceover(to: currentTime)
            return
        }

        resetAudioRowsToFullTimeline()
        if activeClipIndex >= clips.count {
            activeClipIndex = max(0, clips.count - 1)
        }
        timelineSelection = clips.indices.contains(activeClipIndex) ? .video(activeClipIndex) : .none
        if clips.count > 1 && isReelMode {
            rebuildPlaylistIfNeeded()
        } else if !clips.isEmpty {
            selectClip(at: activeClipIndex)
        }
    }

    func reorderClips(from: Int, to: Int) {
        guard from != to, from >= 0, to >= 0, from < clips.count, to < clips.count else { return }
        rememberEditHistory("move clip")
        let clip = clips.remove(at: from)
        clips.insert(clip, at: to)
        activeClipIndex = to
        timelineSelection = .video(to)
        if clips.count > 1 && isReelMode {
            rebuildPlaylistFrom(index: to, seekOffset: 0)
        } else {
            selectClip(at: to)
        }
    }

    private var nextClipId: Int {
        return (clips.map(\.id).max() ?? 0) + 1
    }

    func duplicateClip(at index: Int) {
        guard index >= 0 && index < clips.count else { return }
        rememberEditHistory("duplicate clip")
        var copy = clips[index]
        copy.id = nextClipId
        clips.insert(copy, at: index + 1)
        activeClipIndex = index + 1
        clampAudioRowsToEditedTimeline()
    }

    func splitClipAtPlayhead() {
        guard activeClipIndex >= 0 && activeClipIndex < clips.count else { return }
        rememberEditHistory("cut")
        let clip = clips[activeClipIndex]

        // Split at 50% of the visible trim range
        let splitPct = (clip.trimStart + clip.trimEnd) / 2.0

        var firstHalf = clip
        firstHalf.trimEnd = splitPct

        var secondHalf = clip
        secondHalf.id = nextClipId
        secondHalf.trimStart = splitPct

        clips[activeClipIndex] = firstHalf
        clips.insert(secondHalf, at: activeClipIndex + 1)
        activeClipIndex = activeClipIndex + 1
        clampAudioRowsToEditedTimeline()

        if isReelMode { rebuildPlaylistIfNeeded() }
    }

    // MARK: - Music

    func configureAudioSessionForMusic() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[Music] Audio session setup failed: \(error)")
        }
        #endif
        // macOS: audio routing is automatic
    }

    /// Call after video player is ready to (re)claim session and start music.
    func ensureMusicPlaying() {
        configureAudioSessionForMusic()
        syncMusic(to: currentTime)
    }

    func restartMusicIfNeeded() {
        guard musicAVPlayer != nil || !additionalMusicPlayers.isEmpty else { return }
        ensureMusicPlaying()
    }

    private func startTimelinePlaybackAfterAddingMusic() {
        guard !aiGenerating else {
            syncMusic(to: currentTime)
            return
        }

        isPlaying = true
        configureAudioSessionForMusic()
        if isReelMode, generatedVideoUri == nil, activeClipIndex >= 0 {
            playAllClips()
        } else {
            player?.play()
            syncMusic(to: currentTime)
            playMusicIfAudible(at: currentTime)
            playVoiceoverIfAudible(at: currentTime)
        }
    }

    /// Download and start playing the given track. Uses AVPlayer so music mixes with video (like RN/expo-av).
    func selectMusic(_ track: MusicTrack) async {
        rememberEditHistory("music")
        var timelineTrack = track
        timelineTrack.timelineStart = 0
        timelineTrack.timelineEnd = nil
        selectedMusic = timelineTrack
        musicLoadFailed = false

        if let obs = musicEndObserver {
            NotificationCenter.default.removeObserver(obs)
            musicEndObserver = nil
        }
        musicAVPlayer?.pause()
        musicAVPlayer = nil

        configureAudioSessionForMusic()

        guard let playbackURL = await musicPlaybackURL(for: timelineTrack) else {
            print("[Music] Failed to load: \(timelineTrack.name)")
            musicLoadFailed = true
            return
        }

        let item = AVPlayerItem(url: playbackURL)
        item.preferredForwardBufferDuration = 1
        let avp = AVPlayer(playerItem: item)
        avp.automaticallyWaitsToMinimizeStalling = false
        avp.volume = Float(effectiveMusicVolume(for: timelineTrack))
        musicAVPlayer = avp

        musicEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.syncMusic(to: self.currentTime)
            }
        }

        configureAudioSessionForMusic()
        startTimelinePlaybackAfterAddingMusic()
    }

    func addMusicTrack(_ track: MusicTrack) async {
        rememberEditHistory("music")
        if selectedMusic == nil {
            await selectMusic(track)
            return
        }

        if selectedMusic?.id == track.id {
            selectMusicTrack(id: track.id)
            return
        }

        if additionalMusicTracks.contains(where: { $0.id == track.id }) {
            selectMusicTrack(id: track.id)
            return
        }

        var timelineTrack = track
        timelineTrack.timelineStart = 0
        timelineTrack.timelineEnd = nil
        additionalMusicTracks.append(timelineTrack)
        await prepareAdditionalMusicPlayer(for: timelineTrack)
    }

    private func prepareAdditionalMusicPlayer(for track: MusicTrack) async {
        if let obs = additionalMusicEndObservers[track.id] {
            NotificationCenter.default.removeObserver(obs)
            additionalMusicEndObservers[track.id] = nil
        }
        additionalMusicPlayers[track.id]?.pause()
        additionalMusicPlayers[track.id] = nil

        configureAudioSessionForMusic()

        guard let playbackURL = await musicPlaybackURL(for: track) else {
            musicLoadFailed = true
            return
        }
        let item = AVPlayerItem(url: playbackURL)
        item.preferredForwardBufferDuration = 1
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.volume = Float(effectiveMusicVolume(for: track))
        additionalMusicPlayers[track.id] = player
        additionalMusicEndObservers[track.id] = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.syncMusic(to: self.currentTime)
            }
        }

        startTimelinePlaybackAfterAddingMusic()
    }

    private func musicPlaybackURL(for track: MusicTrack) async -> URL? {
        let filePath = track.file.replacingOccurrences(of: "file://", with: "")
        if filePath.hasPrefix("/"), FileManager.default.fileExists(atPath: filePath) {
            print("[Music] Using local file: \(filePath)")
            return URL(fileURLWithPath: filePath)
        }

        if let localURL = await AudioMixerService.shared.downloadAndSaveAudio(from: track.file, audioId: track.id) {
            return localURL
        }

        if let remoteURL = URL(string: track.file), remoteURL.scheme?.hasPrefix("http") == true {
            print("[Music] Streaming remote fallback: \(track.file)")
            return remoteURL
        }

        if track.file.hasPrefix("file://"), let url = URL(string: track.file) {
            return url
        }

        return nil
    }

    func removeAdditionalMusicTrack(id: String) {
        rememberEditHistory("music delete")
        additionalMusicTracks.removeAll { $0.id == id }
        if let obs = additionalMusicEndObservers[id] {
            NotificationCenter.default.removeObserver(obs)
            additionalMusicEndObservers[id] = nil
        }
        additionalMusicPlayers[id]?.pause()
        additionalMusicPlayers[id] = nil
    }

    func removeMusicTrack(id: String) {
        rememberEditHistory("music delete")
        if selectedMusic?.id == id {
            selectedMusic = nil
            musicLoadFailed = false
            if let obs = musicEndObserver {
                NotificationCenter.default.removeObserver(obs)
                musicEndObserver = nil
            }
            musicAVPlayer?.pause()
            musicAVPlayer = nil
        } else {
            removeAdditionalMusicTrack(id: id)
        }
        if timelineSelection == .music(id) {
            timelineSelection = clips.indices.contains(activeClipIndex) ? .video(activeClipIndex) : .none
        }
    }

    func selectMusicTrack(id: String) {
        timelineSelection = .music(id)
    }

    private var timelineTotalDuration: Double {
        let editedDuration = clips.reduce(0) { $0 + timelineClipDuration(for: $1) }
        if editedDuration > 0 {
            return max(0.1, editedDuration)
        }
        return max(0.1, duration)
    }

    var timelineDisplayDuration: Double {
        let editedDuration = clips.reduce(0) { $0 + timelineClipDuration(for: $1) }
        let musicEnd = max(
            selectedMusic?.timelineEnd ?? 0,
            additionalMusicTracks.map { $0.timelineEnd ?? 0 }.max() ?? 0
        )
        let voiceoverEnd = voiceoverTimelineEnd ?? 0
        return max(0.1, duration, editedDuration, musicEnd, voiceoverEnd)
    }

    private func clampAudioRowsToEditedTimeline() {
        let end = timelineTotalDuration

        if voiceoverFileURL != nil {
            voiceoverTimelineStart = min(voiceoverTimelineStart, max(0, end - 0.1))
            if let currentEnd = voiceoverTimelineEnd {
                voiceoverTimelineEnd = max(voiceoverTimelineStart + 0.1, min(currentEnd, end))
            }
        }

        if var music = selectedMusic {
            music.timelineStart = min(music.timelineStart, max(0, end - 0.1))
            if let timelineEnd = music.timelineEnd, timelineEnd > end {
                music.timelineEnd = end
            }
            selectedMusic = music
        }

        additionalMusicTracks = additionalMusicTracks.map { track in
            var next = track
            next.timelineStart = min(next.timelineStart, max(0, end - 0.1))
            if let timelineEnd = next.timelineEnd, timelineEnd > end {
                next.timelineEnd = end
            }
            return next
        }
    }

    private func resetAudioRowsToFullTimeline() {
        if voiceoverFileURL != nil {
            voiceoverTimelineStart = 0
            voiceoverTimelineEnd = nil
        }

        if var music = selectedMusic {
            music.timelineStart = 0
            music.timelineEnd = nil
            selectedMusic = music
        }

        additionalMusicTracks = additionalMusicTracks.map { track in
            var next = track
            next.timelineStart = 0
            next.timelineEnd = nil
            return next
        }

        syncMusic(to: currentTime)
        syncVoiceover(to: currentTime)
    }

    private func clipTimelineSignature(_ clips: [Clip]) -> String {
        clips.map { clip in
            [
                "\(clip.id)",
                String(format: "%.3f", clip.trimStart),
                String(format: "%.3f", clip.trimEnd),
                String(format: "%.3f", clip.beatDuration ?? -1),
                String(format: "%.3f", clip.sourceDuration ?? -1),
                String(format: "%.3f", clip.speed)
            ].joined(separator: ":")
        }
        .joined(separator: "|")
    }

    private func audioDuration(for url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite && seconds > 0 ? seconds : nil
        } catch {
            return nil
        }
    }

    private func mediaDuration(for url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite && seconds > 0 ? seconds : nil
        } catch {
            return nil
        }
    }

    private func hydrateMissingClipDurations() async {
        guard !clips.isEmpty else { return }
        var updated = clips
        var changed = false

        for index in updated.indices {
            let clip = updated[index]
            guard clip.beatDuration == nil else { continue }
            guard clip.sourceDuration == nil || (clip.sourceDuration ?? 0) <= 0 else { continue }
            guard !isImageClip(clip) else {
                updated[index].sourceDuration = 3.0
                changed = true
                continue
            }

            let urlString = clip.localUri ?? clip.uri
            guard let url = createURL(from: urlString),
                  let seconds = await mediaDuration(for: url) else { continue }

            updated[index].sourceDuration = seconds
            changed = true
        }

        guard changed else { return }
        clips = updated
        duration = clips.indices.contains(activeClipIndex)
            ? timelineClipDuration(for: clips[activeClipIndex])
            : timelineTotalDuration
    }

    func updateMusicTrackTiming(id: String, start: Double? = nil, end: Double? = nil) {
        rememberEditHistory("music trim")
        let duration = timelineTotalDuration

        func clampedTiming(for track: MusicTrack) -> (Double, Double) {
            let currentStart = max(0, min(track.timelineStart, duration - 0.1))
            let currentEnd = max(currentStart + 0.1, min(track.timelineEnd ?? duration, duration))
            let nextStart = max(0, min(start ?? currentStart, currentEnd - 0.1))
            let nextEnd = max(nextStart + 0.1, min(end ?? currentEnd, duration))
            return (nextStart, nextEnd)
        }

        if selectedMusic?.id == id, var track = selectedMusic {
            let next = clampedTiming(for: track)
            track.timelineStart = next.0
            track.timelineEnd = next.1
            selectedMusic = track
        } else if let index = additionalMusicTracks.firstIndex(where: { $0.id == id }) {
            var track = additionalMusicTracks[index]
            let next = clampedTiming(for: track)
            track.timelineStart = next.0
            track.timelineEnd = next.1
            additionalMusicTracks[index] = track
        }
        syncMusic(to: currentTime)
    }

    func updateVoiceoverTiming(start: Double? = nil, end: Double? = nil) {
        rememberEditHistory("voiceover trim")
        let duration = timelineTotalDuration
        let currentStart = max(0, min(voiceoverTimelineStart, duration - 0.1))
        let currentEnd = max(currentStart + 0.1, min(voiceoverTimelineEnd ?? duration, duration))
        let nextStart = max(0, min(start ?? currentStart, currentEnd - 0.1))
        let nextEnd = max(nextStart + 0.1, min(end ?? currentEnd, duration))
        voiceoverTimelineStart = nextStart
        voiceoverTimelineEnd = nextEnd
        if timelineSelection == .voiceover {
            syncVoiceover(to: currentTime)
        }
    }

    func updateTextTiming(for index: Int, start: Double? = nil, end: Double? = nil) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("text trim")
        let currentStart = max(0, min(clips[index].textStart, clips[index].textEnd - 1))
        let currentEnd = max(currentStart + 1, min(clips[index].textEnd, 100))
        clips[index].textStart = max(0, min(start ?? currentStart, currentEnd - 1))
        clips[index].textEnd = max(clips[index].textStart + 1, min(end ?? currentEnd, 100))
    }

    func updateTextPosition(for index: Int, x: Double, y: Double) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("text move")
        clips[index].textX = max(0.08, min(0.92, x))
        clips[index].textY = max(0.08, min(0.92, y))
    }

    func updateTextFont(for index: Int, fontName: String) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("font")
        var next = clips
        next[index].textFontName = fontName
        clips = next
    }

    func updateText(for index: Int, text: String) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("text")
        var next = clips
        next[index].text = text
        clips = next
    }

    func updateClipFilter(at index: Int, filterName: String) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("filter")
        var next = clips
        next[index].filterName = filterName
        clips = next
        activeClipIndex = index
        timelineSelection = .video(index)
    }

    func updateClipTransition(at index: Int, transitionName: String, duration: Double? = nil) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("transition")
        var next = clips
        next[index].transitionName = transitionName
        if let duration {
            next[index].transitionDuration = max(0.1, min(1.2, duration))
        }
        clips = next
    }

    func updateClipLayout(at index: Int, mode: String? = nil, scale: Double? = nil, x: Double? = nil, y: Double? = nil) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("layout")
        if let mode {
            clips[index].videoLayoutMode = mode
            if mode == "PiP", clips[index].videoScale > 0.85 {
                clips[index].videoScale = 0.36
                clips[index].videoX = 0.78
                clips[index].videoY = 0.24
            } else if mode == "Full" {
                clips[index].videoScale = 1.0
                clips[index].videoX = 0.5
                clips[index].videoY = 0.5
            }
        }
        if let scale {
            guard clips[index].videoLayoutMode == "PiP" else {
                clips[index].videoScale = 1.0
                return
            }
            let upper = clips[index].videoLayoutMode == "PiP" ? 0.85 : 3.0
            let lower = clips[index].videoLayoutMode == "PiP" ? 0.18 : 1.0
            clips[index].videoScale = max(lower, min(upper, scale))
        }
        if let x {
            clips[index].videoX = max(0.08, min(0.92, x))
        }
        if let y {
            clips[index].videoY = max(0.08, min(0.92, y))
        }
    }

    func setOverlayImage(for index: Int, url: URL) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("overlay")
        clips[index].overlayImageUri = url.path
        clips[index].overlayX = 0.82
        clips[index].overlayY = 0.18
        clips[index].overlayScale = 0.22
    }

    func updateOverlayPosition(for index: Int, x: Double, y: Double) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("overlay move")
        clips[index].overlayX = max(0.08, min(0.92, x))
        clips[index].overlayY = max(0.08, min(0.92, y))
    }

    func updateOverlayScale(for index: Int, scale: Double) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("overlay scale")
        clips[index].overlayScale = max(0.08, min(0.65, scale))
    }

    func removeOverlayImage(for index: Int) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("overlay delete")
        clips[index].overlayImageUri = nil
        clips[index].overlayScale = 0.22
    }

    func removeText(for index: Int) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("text delete")
        clips[index].text = ""
        clips[index].textStart = 0
        clips[index].textEnd = 100
        clips[index].textX = 0.5
        clips[index].textY = 0.82
        clips[index].textFontName = "System"
        if timelineSelection == .text(index) {
            timelineSelection = clips.indices.contains(activeClipIndex) ? .video(activeClipIndex) : .none
        }
    }

    func selectText(at index: Int) {
        guard clips.indices.contains(index) else { return }
        activeClipIndex = index
        timelineSelection = .text(index)
    }

    func selectVoiceover() {
        guard voiceoverFileURL != nil else { return }
        activeClipIndex = -1
        timelineSelection = .voiceover
    }

    func clearTimelineSelection() {
        timelineSelection = .none
    }

    var canDeleteSelectedTimelineItem: Bool {
        switch timelineSelection {
        case .video(let index):
            return clips.indices.contains(index)
        case .text(let index):
            return clips.indices.contains(index) && (clips[index].text ?? "").isEmpty == false
        case .voiceover:
            return voiceoverFileURL != nil
        case .music(let id):
            return selectedMusic?.id == id || additionalMusicTracks.contains { $0.id == id }
        case .none:
            return clips.indices.contains(activeClipIndex)
        }
    }

    var canMuteSelectedTimelineItem: Bool {
        switch timelineSelection {
        case .video(let index):
            return clips.indices.contains(index)
        case .voiceover:
            return voiceoverFileURL != nil
        case .music(let id):
            return selectedMusic?.id == id || additionalMusicTracks.contains { $0.id == id }
        case .text, .none:
            return false
        }
    }

    var canAdjustSelectedTimelineVolume: Bool {
        canMuteSelectedTimelineItem
    }

    var canExport: Bool {
        !clips.isEmpty
    }

    func setAspectRatio(_ ratio: String) {
        guard aspectRatio != ratio else { return }
        rememberEditHistory("canvas")
        aspectRatio = ratio
    }

    func setCaptionsViaCloud(_ enabled: Bool) {
        guard addCaptionsViaCloud != enabled else { return }
        rememberEditHistory("captions")
        addCaptionsViaCloud = enabled
    }

    var selectedTimelineItemVolume: Double {
        switch timelineSelection {
        case .video(let index):
            guard clips.indices.contains(index) else { return 0 }
            return clips[index].isMuted ? 0 : max(0, min(1, clips[index].audioVolume))
        case .voiceover:
            return voiceoverMuted ? 0 : max(0, min(1, voiceoverVolume))
        case .music(let id):
            if let music = selectedMusic, music.id == id {
                return music.isMuted ? 0 : max(0, min(1, music.volume))
            }
            if let track = additionalMusicTracks.first(where: { $0.id == id }) {
                return track.isMuted ? 0 : max(0, min(1, track.volume))
            }
            return 0
        case .text, .none:
            return 0
        }
    }

    var selectedTimelineVolumeTitle: String {
        switch timelineSelection {
        case .video(let index):
            return clips.indices.contains(index) ? "Take \(index + 1)" : "Volume"
        case .voiceover:
            return "Voiceover"
        case .music(let id):
            if let music = selectedMusic, music.id == id { return music.name }
            return additionalMusicTracks.first { $0.id == id }?.name ?? "Music"
        case .text, .none:
            return "Volume"
        }
    }

    func setSelectedTimelineItemVolume(_ value: Double) {
        rememberEditHistory("volume")
        let clamped = max(0, min(1, value))
        switch timelineSelection {
        case .video(let index):
            setClipVolume(at: index, volume: clamped)
        case .voiceover:
            voiceoverVolume = clamped
            voiceoverMuted = clamped <= 0.001
            voiceoverAVPlayer?.volume = Float(clamped)
            voiceoverAVPlayer?.isMuted = isMuted || voiceoverMuted
        case .music(let id):
            setMusicTrackVolume(id: id, volume: clamped)
        case .text, .none:
            break
        }
    }

    var selectedTimelineItemIsMuted: Bool {
        switch timelineSelection {
        case .video(let index):
            return clips.indices.contains(index) ? clips[index].isMuted : false
        case .voiceover:
            return voiceoverMuted
        case .music(let id):
            if selectedMusic?.id == id { return selectedMusic?.isMuted == true }
            return additionalMusicTracks.first { $0.id == id }?.isMuted == true
        case .text, .none:
            return false
        }
    }

    func toggleSelectedTimelineMute() {
        rememberEditHistory("mute")
        switch timelineSelection {
        case .video(let index):
            toggleClipMute(at: index)
        case .voiceover:
            voiceoverMuted.toggle()
            voiceoverAVPlayer?.isMuted = isMuted || voiceoverMuted
        case .music(let id):
            toggleMusicMute(id: id)
        case .text, .none:
            break
        }
    }

    func toggleClipMute(at index: Int) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("mute")
        clips[index].isMuted.toggle()
        if index == activeClipIndex {
            player?.isMuted = isMuted || clips[index].isMuted
            player?.currentItem.map { applyClipAudioSettings(clips[index], to: $0) }
        }
        if isReelMode {
            buildReelPlaylist(selectFirst: activeClipIndex >= 0)
        }
    }

    func setClipVolume(at index: Int, volume: Double) {
        guard clips.indices.contains(index) else { return }
        rememberEditHistory("volume")
        clips[index].audioVolume = max(0, min(1, volume))
        clips[index].isMuted = clips[index].audioVolume <= 0.001
        if index == activeClipIndex {
            player?.isMuted = isMuted || clips[index].isMuted
            player?.currentItem.map { applyClipAudioSettings(clips[index], to: $0) }
        }
        if isReelMode {
            buildReelPlaylist(selectFirst: activeClipIndex >= 0)
        }
    }

    func toggleMusicMute(id: String) {
        rememberEditHistory("mute")
        if selectedMusic?.id == id, var track = selectedMusic {
            track.isMuted.toggle()
            selectedMusic = track
        } else if let index = additionalMusicTracks.firstIndex(where: { $0.id == id }) {
            additionalMusicTracks[index].isMuted.toggle()
        }
        syncMusic(to: currentTime)
    }

    func setMusicTrackVolume(id: String, volume: Double) {
        rememberEditHistory("volume")
        let clamped = max(0, min(1, volume))
        if selectedMusic?.id == id, var track = selectedMusic {
            track.volume = clamped
            track.isMuted = clamped <= 0.001
            selectedMusic = track
            musicAVPlayer?.volume = Float(effectiveMusicVolume(for: track))
        } else if let index = additionalMusicTracks.firstIndex(where: { $0.id == id }) {
            additionalMusicTracks[index].volume = clamped
            additionalMusicTracks[index].isMuted = clamped <= 0.001
            let track = additionalMusicTracks[index]
            additionalMusicPlayers[id]?.volume = Float(effectiveMusicVolume(for: track))
        }
        syncMusic(to: currentTime)
    }

    func deleteSelectedTimelineItem() {
        switch timelineSelection {
        case .video(let index):
            if clips.indices.contains(index) {
                removeClip(at: index)
            }
        case .text(let index):
            removeText(for: index)
        case .voiceover:
            removeVoiceover()
        case .music(let id):
            removeMusicTrack(id: id)
        case .none:
            if clips.indices.contains(activeClipIndex) {
                removeClip(at: activeClipIndex)
            }
        }
    }

    func isVideoSelected(_ index: Int) -> Bool {
        timelineSelection == .video(index)
    }

    func isTextSelected(_ index: Int) -> Bool {
        timelineSelection == .text(index)
    }

    var isVoiceoverSelected: Bool {
        timelineSelection == .voiceover
    }

    func isMusicSelected(_ id: String) -> Bool {
        timelineSelection == .music(id)
    }

    func clearMusic() {
        rememberEditHistory("music delete")
        selectedMusic = nil
        musicLoadFailed = false
        if let obs = musicEndObserver {
            NotificationCenter.default.removeObserver(obs)
            musicEndObserver = nil
        }
        musicAVPlayer?.pause()
        musicAVPlayer = nil
        for obs in additionalMusicEndObservers.values {
            NotificationCenter.default.removeObserver(obs)
        }
        additionalMusicEndObservers.removeAll()
        for player in additionalMusicPlayers.values {
            player.pause()
        }
        additionalMusicPlayers.removeAll()
    }

    func updateMusicVolume(_ volume: Double) {
        rememberEditHistory("music volume")
        musicVolume = volume
        if let track = selectedMusic {
            musicAVPlayer?.volume = Float(effectiveMusicVolume(for: track))
        }
        for track in additionalMusicTracks {
            additionalMusicPlayers[track.id]?.volume = Float(effectiveMusicVolume(for: track))
        }
    }

    // MARK: - Voiceover Preview

    private func prepareVoiceoverPlayer(seekTime: Double = 0) {
        guard let voiceoverFileURL else { return }

        if voiceoverAVPlayer?.currentItem == nil {
            let item = AVPlayerItem(url: voiceoverFileURL)
            let player = AVPlayer(playerItem: item)
            player.volume = Float(voiceoverVolume)
            player.isMuted = isMuted || voiceoverMuted
            voiceoverAVPlayer = player

            if let obs = voiceoverEndObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            voiceoverEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.voiceoverAVPlayer?.seek(to: .zero)
                if self.isPlaying {
                    self.playVoiceoverIfAudible(at: self.currentTime)
                }
            }
        }

        syncVoiceover(to: seekTime)
    }

    private func playMusicIfAudible(at seconds: Double) {
        guard isPlaying else {
            musicAVPlayer?.pause()
            for player in additionalMusicPlayers.values {
                player.pause()
            }
            return
        }

        if let track = selectedMusic, let player = musicAVPlayer {
            playMusicPlayer(player, for: track, at: seconds)
        }

        for track in additionalMusicTracks {
            guard let player = additionalMusicPlayers[track.id] else { continue }
            playMusicPlayer(player, for: track, at: seconds)
        }
    }

    private func playMusicPlayer(_ player: AVPlayer, for track: MusicTrack, at seconds: Double) {
        let start = max(0, track.timelineStart)
        let end = max(start + 0.1, track.timelineEnd ?? timelineTotalDuration)
        player.volume = Float(effectiveMusicVolume(for: track))
        if seconds >= start && seconds < end {
            player.play()
        } else {
            player.pause()
        }
    }

    private func syncMusic(to seconds: Double) {
        if let track = selectedMusic, let player = musicAVPlayer {
            syncMusicPlayer(player, for: track, to: seconds)
        }

        for track in additionalMusicTracks {
            guard let player = additionalMusicPlayers[track.id] else { continue }
            syncMusicPlayer(player, for: track, to: seconds)
        }
    }

    private func syncMusicPlayer(_ player: AVPlayer, for track: MusicTrack, to seconds: Double) {
        let start = max(0, track.timelineStart)
        let end = max(start + 0.1, track.timelineEnd ?? timelineTotalDuration)
        let localSeconds = loopedMusicLocalSeconds(for: player, localSeconds: max(0, seconds - start))
        let target = CMTime(seconds: localSeconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 0.08, preferredTimescale: 600))
        player.volume = Float(effectiveMusicVolume(for: track))
        if isPlaying, seconds >= start, seconds < end {
            player.play()
        } else {
            player.pause()
        }
    }

    private func loopedMusicLocalSeconds(for player: AVPlayer, localSeconds: Double) -> Double {
        guard let item = player.currentItem else { return localSeconds }
        let duration = CMTimeGetSeconds(item.duration)
        guard duration.isFinite, duration > 0.05 else { return localSeconds }
        return localSeconds.truncatingRemainder(dividingBy: duration)
    }

    private func effectiveMusicVolume(for track: MusicTrack) -> Double {
        track.isMuted ? 0 : max(0, min(1, musicVolume)) * max(0, min(1, track.volume))
    }

    private func playVoiceoverIfAudible(at seconds: Double) {
        guard voiceoverFileURL != nil else { return }
        guard isPlaying else {
            voiceoverAVPlayer?.pause()
            return
        }
        let windowStart = max(0, voiceoverTimelineStart)
        let windowEnd = max(windowStart + 0.1, voiceoverTimelineEnd ?? timelineTotalDuration)
        if seconds >= windowStart && seconds < windowEnd {
            voiceoverAVPlayer?.play()
        } else {
            voiceoverAVPlayer?.pause()
        }
    }

    private func syncVoiceover(to seconds: Double) {
        guard voiceoverFileURL != nil else { return }
        if voiceoverAVPlayer == nil {
            prepareVoiceoverPlayer(seekTime: seconds)
            return
        }

        let windowStart = max(0, voiceoverTimelineStart)
        let windowEnd = max(windowStart + 0.1, voiceoverTimelineEnd ?? timelineTotalDuration)
        let localSeconds = max(0, min(seconds - windowStart, windowEnd - windowStart))
        let target = CMTime(seconds: localSeconds, preferredTimescale: 600)
        voiceoverAVPlayer?.seek(to: target, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600))
        voiceoverAVPlayer?.volume = Float(voiceoverVolume)
        voiceoverAVPlayer?.isMuted = isMuted || voiceoverMuted
        if isPlaying {
            if seconds >= windowStart && seconds < windowEnd {
                voiceoverAVPlayer?.play()
            } else {
                voiceoverAVPlayer?.pause()
            }
        }
    }

    private func clearVoiceoverPlayer() {
        if let obs = voiceoverEndObserver {
            NotificationCenter.default.removeObserver(obs)
            voiceoverEndObserver = nil
        }
        voiceoverAVPlayer?.pause()
        voiceoverAVPlayer = nil
    }

    private func timelineStartTime(for index: Int) -> Double {
        guard index > 0 else { return 0 }
        return clips.prefix(index).reduce(0) { $0 + ($1.beatDuration ?? 1.5) }
    }

    // MARK: - Pre-cache Remote Clips

    func preCacheClips() async {
        guard !clipsCached else { return }

        // Check if any clips actually need downloading
        let hasRemote = clips.contains { clip in
            let uri = clip.localUri ?? clip.uri
            return isRemoteURL(uri) && !FileManager.default.fileExists(atPath: uri.replacingOccurrences(of: "file://", with: ""))
        }
        guard hasRemote else {
            clipsCached = true
            isPreparingSelectedClip = false
            return
        }

        let storage = FileStorageService.shared

        for i in 0..<clips.count {
            let clipUri = clips[i].localUri ?? clips[i].uri
            // Skip if already local
            guard isRemoteURL(clipUri) else { continue }
            // Skip if local file already exists at localUri path
            if let localUri = clips[i].localUri, FileManager.default.fileExists(atPath: localUri.replacingOccurrences(of: "file://", with: "")) { continue }

            let localPath = storage.savedVideosDirectory.appendingPathComponent("take_\(clips[i].id)_\(i).mp4")

            if storage.fileExists(at: localPath), let size = storage.fileSize(at: localPath), size > 0 {
                var updated = clips
                updated[i].localUri = localPath.path
                clips = updated
                if i == activeClipIndex { isPreparingSelectedClip = false }
                continue
            }

            do {
                try await storage.downloadFile(from: clips[i].uri, to: localPath)
                var updated = clips
                updated[i].localUri = localPath.path
                clips = updated
                if i == activeClipIndex { isPreparingSelectedClip = false }
                print("[Cache] Clip \(i) cached")
            } catch {
                print("[Cache] Clip \(i) download failed: \(error)")
            }
        }

        clipsCached = true
        isPreparingSelectedClip = false
        await hydrateMissingClipDurations()

        // Update generation's takesJson with local paths so next open doesn't re-download
        if let json = serializeClipsToTakesJson(clips) {
            // Find generation by video name and update
            Task {
                let gens = try? await GenerationService.shared.fetchGenerations(userId: userId)
                if let gen = gens?.first(where: { $0.videoName == videoName }) {
                    await GenerationService.shared.updateGeneration(id: gen.id, videoUri: clips.first?.localUri)
                }
            }
        }

        if isReelMode {
            rebuildPlaylistIfNeeded()
        } else if player == nil {
            setupPlayer()
        }
    }

    // MARK: - AI Clip Generation

    @Published var showAiPrompt = false
    @Published var aiPrompt = ""
    @Published var aiGenerating = false
    @Published var aiStatus = ""
    @Published var aiAgentActive = false
    @Published var aiAgentNote = ""
    @Published var aiAgentCanStop = false
    @Published var aiAgentLogs: [AiAgentLogEntry] = []
    @Published var aiRawScenario = ""
    @Published var pendingVideoSlots = 0
    @Published var pendingVoiceoverProcessing = false
    @Published var pendingTextSlots = 0
    private var aiAgentStopRequested = false
    private var aiGeneratedStreamStartIndex = 0
    private var aiGeneratedStreamCount = 0

    private func appendAgentLog(_ title: String, detail: String = "") {
        aiAgentLogs.append(AiAgentLogEntry(date: Date(), title: title, detail: detail))
        if aiAgentLogs.count > 80 {
            aiAgentLogs.removeFirst(aiAgentLogs.count - 80)
        }
    }

    private func handlePlannerRateLimit(_ update: OpenRouterScenarioGenerator.RateLimitUpdate) async {
        if update.maxAttempts <= 1 {
            aiStatus = "Switching models..."
            aiAgentNote = "\(update.modelName) is rate limited. Trying another available free model."
        } else {
            aiStatus = "Pending..."
            aiAgentNote = "\(update.modelName) is rate limited. Retrying in \(update.retryInSeconds)s (\(update.attempt)/\(update.maxAttempts))."
        }
        appendAgentLog(aiStatus, detail: aiAgentNote)
        NotificationService.shared.requestPermissionIfNeeded()
    }

    func generateAiAd(
        aiModelId: String = "wan-video/wan-2.2-turbo",
        sourceMode: String = "smart",
        scenarioMode: String,
        voiceoverMode: String,
        elevenLabsVoiceId: String? = nil,
        referenceImageUrl: String? = nil,
        referenceVideoUrl: String? = nil,
        referencePromptNote: String? = nil,
        language: String = "en",
        clipCount: Int = 6
    ) async -> Bool {
        let basePrompt = aiPrompt.trimmingCharacters(in: .whitespaces)
        let prompt = [basePrompt, referencePromptNote]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !prompt.isEmpty else { return false }
        videoName = Self.promptTitle(from: basePrompt.isEmpty ? prompt : basePrompt)

        guard scenarioMode == "openrouter" || scenarioMode == "apple" else {
            aiStatus = "Use \(OpenRouterScenarioGenerator.displayName) or Apple Intelligence for scenarios."
            return false
        }

        guard ["none", "elevenlabs", "music"].contains(voiceoverMode) else {
            aiStatus = "Choose an audio mode."
            return false
        }

        let usesNoAIVideoMode = aiModelId == "noai" || sourceMode == "stock"

        pausePlaybackForGeneration()
        NotificationService.shared.requestPermissionIfNeeded()
        aiGenerating = true
        aiAgentActive = true
        aiAgentCanStop = true
        aiAgentStopRequested = false
        aiAgentLogs.removeAll()
        aiRawScenario = ""
        showAiPrompt = false
        aiStatus = usesNoAIVideoMode ? "Planning Pexels edit..." : "Planning AI ad..."
        aiAgentNote = usesNoAIVideoMode
            ? "Pexels mode uses the brain for script and edit planning, then only stock footage. No video model is called."
            : "Writing the scenario and preparing source tools."
        appendAgentLog(aiStatus, detail: aiAgentNote)

        let effectiveScenarioMode = scenarioMode == "apple" && AppleIntelligenceScenarioGenerator.isAvailable
            ? "apple"
            : "openrouter"
        if scenarioMode == "apple", effectiveScenarioMode != "apple" {
            aiStatus = "Starting \(OpenRouterScenarioGenerator.displayName)..."
            aiAgentNote = "Apple Intelligence is not available in this runtime, so the scenario will use \(OpenRouterScenarioGenerator.displayName)."
            appendAgentLog(aiStatus, detail: aiAgentNote)
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        let scriptOverride: LocalScriptGenerator.GeneratedScript
        var scriptProviderName = effectiveScenarioMode == "apple" ? "Apple Intelligence" : OpenRouterScenarioGenerator.displayName
        do {
            if effectiveScenarioMode == "apple" {
                aiStatus = "Writing scenario with Apple Intelligence..."
                aiAgentNote = usesNoAIVideoMode
                    ? "Pexels mode still allows AI planning. Only video generation models are disabled."
                    : "Building the scene plan with Apple Intelligence."
                appendAgentLog(aiStatus, detail: aiAgentNote)
                do {
                    scriptOverride = try await AppleIntelligenceScenarioGenerator.generateScript(
                        topic: prompt,
                        language: language,
                        clipCount: clipCount
                    )
                } catch {
                    aiStatus = "Using local scene plan..."
                    aiAgentNote = "Apple Intelligence did not return a usable script. Staying on-device and continuing with a local plan."
                    appendAgentLog(aiStatus, detail: error.localizedDescription)
                    scriptOverride = LocalScriptGenerator.generateScript(
                        topic: prompt,
                        language: language,
                        clipCount: clipCount,
                        durationPerClip: 2.5
                    )
                    scriptProviderName = "Apple Intelligence / local"
                }
            } else {
                aiStatus = "Writing scenario with \(OpenRouterScenarioGenerator.displayName)..."
                aiAgentNote = usesNoAIVideoMode
                    ? "Pexels mode still uses \(OpenRouterScenarioGenerator.displayName) for planning. Only video generation models are disabled."
                    : "Building the scene plan with \(OpenRouterScenarioGenerator.displayName)."
                appendAgentLog(aiStatus, detail: aiAgentNote)
                scriptOverride = try await OpenRouterScenarioGenerator.generateScript(
                    topic: prompt,
                    language: language,
                    clipCount: clipCount,
                    onRateLimit: { [weak self] update in
                        await self?.handlePlannerRateLimit(update)
                    }
                )
                scriptProviderName = OpenRouterScenarioGenerator.lastUsedModelName
            }
        } catch {
            if usesNoAIVideoMode {
                aiStatus = error.localizedDescription
                aiAgentNote = "The ad planner stopped before it could create the scene list."
                appendAgentLog(aiStatus, detail: aiAgentNote)
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                aiGenerating = false
                aiAgentActive = false
                aiAgentCanStop = false
                aiAgentStopRequested = false
                aiAgentNote = ""
                NotificationService.shared.notifyAgentFailed(
                    title: "Ad maker stopped",
                    body: "The planner could not finish after retrying."
                )
                return false
            }

            aiStatus = "Starting fal.ai with local scene plan..."
            aiAgentNote = "The planner failed, so I am using a local 4-scene plan and sending videos to fal.ai one by one."
            appendAgentLog(aiStatus, detail: error.localizedDescription)
            scriptOverride = LocalScriptGenerator.generateScript(
                topic: prompt,
                language: language,
                clipCount: clipCount,
                durationPerClip: 2.5
            )
            scriptProviderName = "Local fallback"
        }

        aiRawScenario = rawScenarioText(for: scriptOverride, provider: scriptProviderName)
        appendAgentLog("Raw scenario", detail: aiRawScenario)

        let reusableTimelineClips = clips
        let finalScript = scriptOverride
        let sourcePlan: [Int: LocalReelGenerator.SceneSource]
        if usesNoAIVideoMode {
            sourcePlan = Dictionary(
                uniqueKeysWithValues: finalScript.scenes.indices.map { index in
                    (index, .stock(reason: "Pexels mode uses stock/timeline sources and does not call paid video generation."))
                }
            )
        } else if sourceMode == "ai" || aiModelId != "noai" {
            sourcePlan = Dictionary(
                uniqueKeysWithValues: finalScript.scenes.indices.map { index in
                    (index, .aiVideo(reason: "Generate this scene with the selected API video model."))
                }
            )
        } else {
            sourcePlan = buildSourceToolPlan(for: finalScript, prompt: prompt, reusableClipCount: reusableTimelineClips.count)
        }
        aiAgentActive = true
        aiAgentCanStop = true
        aiStatus = usesNoAIVideoMode ? "Sourcing free stock clips..." : "Planning source tools..."
        aiAgentNote = usesNoAIVideoMode
            ? "\(sourceToolSummary(sourcePlan)) No video model call will run."
            : sourceToolSummary(sourcePlan)
        appendAgentLog(aiStatus, detail: aiAgentNote)
        try? await Task.sleep(nanoseconds: 800_000_000)
        pendingVideoSlots = finalScript.scenes.isEmpty ? 0 : 1
        pendingTextSlots = 0
        pendingVoiceoverProcessing = voiceoverMode != "none" && voiceoverMode != "music"
        await prepareGeneratedTimelineStream(preserveExistingClips: !clips.isEmpty)

        let result = await LocalReelGenerator.generate(
            topic: prompt,
            language: language,
            clipCount: clipCount,
            scriptOverride: finalScript,
            sourcePlan: sourcePlan,
            reusableClips: reusableTimelineClips,
            aiModelId: aiModelId,
            referenceImageUrl: referenceImageUrl,
            referenceVideoUrl: referenceVideoUrl,
            voiceoverMode: "none",
            elevenLabsVoiceId: elevenLabsVoiceId,
            userId: userId,
            onClipReady: { [weak self] clip, index, total in
            await self?.spawnGeneratedTimelineClip(clip, index: index, total: total)
            },
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    self?.aiStatus = progress.step
                    self?.appendAgentLog(progress.step, detail: "Progress \(Int(progress.progress * 100))%")
                }
            }
        )

        guard result.success else {
            aiStatus = result.error ?? "Ad maker failed"
            appendAgentLog(aiStatus, detail: "Generation stopped before a finished timeline was produced.")
            pendingVideoSlots = 0
            pendingTextSlots = 0
            pendingVoiceoverProcessing = false
            aiGenerating = false
            aiAgentActive = false
            aiAgentCanStop = false
            aiAgentStopRequested = false
            aiAgentNote = ""
            NotificationService.shared.notifyAgentFailed(
                title: "Ad maker stopped",
                body: "The timeline could not be generated."
            )
            return false
        }

        if let takesJson = result.takesJson,
           let data = takesJson.data(using: .utf8),
           let generatedClips = try? JSONDecoder().decode([Clip].self, from: data),
           !generatedClips.isEmpty,
           aiGeneratedStreamCount == 0 {
            await spawnGeneratedTimeline(generatedClips, preserveExistingClips: !clips.isEmpty)
        }

        await performVisibleAdPolishPass()
        await regenerateFinalTextAndVoiceover(
            script: finalScript,
            voiceoverMode: voiceoverMode,
            elevenLabsVoiceId: elevenLabsVoiceId,
            language: language
        )

        if isReelMode {
            buildReelPlaylist(selectFirst: false)
        } else if !clips.isEmpty {
            selectClip(at: 0)
        }

        aiStatus = ""
        aiPrompt = ""
        pendingVideoSlots = 0
        pendingTextSlots = 0
        pendingVoiceoverProcessing = false
        aiGenerating = false
        aiAgentActive = false
        aiAgentCanStop = false
        aiAgentStopRequested = false
        aiAgentNote = ""
        NotificationService.shared.notifyAgentDone(
            title: "Ad maker done",
            body: clips.isEmpty ? "The agent finished." : "Your ad timeline is ready to preview."
        )
        return true
    }

    private func rawScenarioText(for script: LocalScriptGenerator.GeneratedScript, provider: String) -> String {
        var lines: [String] = [
            "Provider: \(provider)",
            "Topic: \(script.topic)",
            "Total duration: \(String(format: "%.1f", script.totalDuration))s",
            "",
            "Full voiceover:",
            script.fullVoiceover,
            "",
            "Scenes:"
        ]

        for (index, scene) in script.scenes.enumerated() {
            lines.append("""
            \(index + 1). Search: \(scene.searchQuery)
               Caption: \(scene.subtitleText)
               Voiceover: \(scene.voiceoverText)
               Duration: \(String(format: "%.1f", scene.durationSeconds))s
            """)
        }

        return lines.joined(separator: "\n")
    }

    private func rawTimelinePlanText(_ plan: [TimelineEditInstruction], provider: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = (try? encoder.encode(plan))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """
        Provider: \(provider)
        Type: timeline edit plan

        \(json)
        """
    }

    private func buildSourceToolPlan(
        for script: LocalScriptGenerator.GeneratedScript,
        prompt: String,
        reusableClipCount: Int
    ) -> [Int: LocalReelGenerator.SceneSource] {
        let lower = prompt.lowercased()
        let asksForStock = lower.contains("stock") || lower.contains("b-roll") || lower.contains("b roll") || lower.contains("real footage") || lower.contains("pexels")
        let asksToReuse = lower.contains("timeline") || lower.contains("existing") || lower.contains("my footage") || lower.contains("use clips")
        let usableTimelineCount = max(0, reusableClipCount)

        var plan: [Int: LocalReelGenerator.SceneSource] = [:]
        for index in script.scenes.indices {
            let isClosingScene = index == script.scenes.count - 1

            if usableTimelineCount > 0, (asksToReuse || (isClosingScene && lower.contains("reuse"))) {
                plan[index] = .timeline(reason: "Use footage already in the timeline when it can carry this scene.")
            } else if asksForStock {
                plan[index] = .stock(reason: "Use stock footage because the request explicitly asked for stock or real b-roll.")
            } else {
                plan[index] = .aiVideo(reason: "Generate this scene with the selected API video model.")
            }
        }
        return plan
    }

    private func sourceToolSummary(_ plan: [Int: LocalReelGenerator.SceneSource]) -> String {
        let timelineCount = plan.values.filter {
            if case .timeline = $0 { return true }
            return false
        }.count
        let aiCount = plan.values.filter {
            if case .aiVideo = $0 { return true }
            return false
        }.count
        let stockCount = plan.values.filter {
            if case .stock = $0 { return true }
            return false
        }.count

        var parts: [String] = []
        if timelineCount > 0 { parts.append("reuse \(timelineCount) timeline") }
        if aiCount > 0 { parts.append("generate \(aiCount) AI") }
        if stockCount > 0 { parts.append("search \(stockCount) stock") }
        return "Tool plan: " + (parts.isEmpty ? "build scenes from the best available source." : parts.joined(separator: ", ")) + "."
    }

    private func prepareGeneratedTimelineStream(preserveExistingClips: Bool) async {
        aiAgentActive = true
        aiAgentCanStop = true
        aiGeneratedStreamStartIndex = preserveExistingClips ? clips.count : 0
        aiGeneratedStreamCount = 0
        aiStatus = "Preparing timeline..."
        aiAgentNote = preserveExistingClips
            ? "Keeping your imported video and adding generated scenes as they become ready."
            : "Generated scenes will appear as soon as each video is ready."
        appendAgentLog(aiStatus, detail: aiAgentNote)
        withAnimation(.easeInOut(duration: 0.25)) {
            if !preserveExistingClips {
                clips.removeAll()
                activeClipIndex = -1
                timelineSelection = .none
                playlistItems.removeAll()
                currentQueueItems.removeAll()
                player?.pause()
                player = nil
                currentTime = 0
                duration = 0
            }
            voiceoverFileURL = nil
            clearVoiceoverPlayer()
        }
        try? await Task.sleep(nanoseconds: 220_000_000)
    }

    private func spawnGeneratedTimelineClip(_ clip: Clip, index: Int, total: Int) async {
        guard !aiAgentStopRequested else { return }
        aiStatus = "Spawning video \(index + 1)/\(total)..."
        aiAgentNote = "Adding scene \(index + 1) to the video row."
        appendAgentLog(aiStatus, detail: clip.name)
        var visibleClip = clip
        let pendingCaption = visibleClip.text
        visibleClip.text = nil
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            clips.append(visibleClip)
            pendingVideoSlots = index + 1 < total ? 1 : 0
            aiGeneratedStreamCount += 1
            activeClipIndex = clips.count - 1
            timelineSelection = .video(activeClipIndex)
            duration = clips.reduce(0) { $0 + ($1.beatDuration ?? $1.sourceDuration ?? 3.0) }
        }
        let spawnedIndex = activeClipIndex
        if isReelMode, generatedVideoUri == nil {
            rebuildPlaylistFrom(index: spawnedIndex, seekOffset: 0)
        } else {
            selectClip(at: spawnedIndex)
        }
        try? await Task.sleep(nanoseconds: 260_000_000)

        if let text = pendingCaption, !text.isEmpty {
            aiStatus = "Spawning text \(index + 1)/\(total)..."
            aiAgentNote = "Placing the caption on the text row and on the video preview."
            appendAgentLog(aiStatus, detail: text)
            withAnimation(.easeInOut(duration: 0.16)) {
                pendingTextSlots = 1
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                if clips.indices.contains(activeClipIndex) {
                    clips[activeClipIndex].text = text
                }
                pendingTextSlots = 0
                timelineSelection = .text(activeClipIndex)
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
        }
    }

    private func spawnGeneratedTimeline(_ generatedClips: [Clip], preserveExistingClips: Bool = false) async {
        await prepareGeneratedTimelineStream(preserveExistingClips: preserveExistingClips)

        for (index, clip) in generatedClips.enumerated() {
            if aiAgentStopRequested { break }
            await spawnGeneratedTimelineClip(clip, index: index, total: generatedClips.count)
        }

        aiStatus = "Positioning clips..."
        aiAgentNote = "Locking the generated scenes into the timeline order."
        appendAgentLog(aiStatus, detail: aiAgentNote)
        withAnimation(.easeInOut(duration: 0.25)) {
            let preferredIndex = clips.indices.contains(aiGeneratedStreamStartIndex) ? aiGeneratedStreamStartIndex : (clips.indices.first ?? -1)
            activeClipIndex = preferredIndex
            timelineSelection = clips.indices.contains(activeClipIndex) ? .video(activeClipIndex) : .none
        }
        try? await Task.sleep(nanoseconds: 260_000_000)
    }

    private func performVisibleAdPolishPass() async {
        guard !clips.isEmpty else { return }

        aiAgentActive = true
        aiAgentCanStop = true
        aiStatus = "Finding pacing..."
        aiAgentNote = "Scanning clip timing and adjusting scene duration without cutting clips apart."
        appendAgentLog(aiStatus, detail: aiAgentNote)
        try? await Task.sleep(nanoseconds: 520_000_000)

        var changedCount = 0
        for index in clips.indices {
            guard !aiAgentStopRequested else { break }

            let sourceDuration = max(0.1, clips[index].sourceDuration ?? clips[index].beatDuration ?? 3.0)
            let currentBeat = clips[index].beatDuration ?? min(sourceDuration, 2.0)
            let targetBeat = max(0.7, min(2.0, currentBeat))

            aiStatus = "Setting duration \(index + 1)/\(clips.count)..."
            aiAgentNote = "Changing scene \(index + 1) duration only. No clip split."
            appendAgentLog(aiStatus, detail: clips[index].name)

            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                activeClipIndex = index
                timelineSelection = .video(index)

                if abs((clips[index].beatDuration ?? sourceDuration) - targetBeat) > 0.01 {
                    clips[index].beatDuration = targetBeat
                    changedCount += 1
                }
            }

            duration = clips.reduce(0) { $0 + ($1.beatDuration ?? $1.sourceDuration ?? 3.0) }
            try? await Task.sleep(nanoseconds: 430_000_000)
        }

        await performMandatoryFinalCutPass()

        aiStatus = "Editing done"
        aiAgentNote = changedCount > 0
            ? "Adjusted scene durations into short ad beats without splitting clips."
            : "The timeline already matched the short ad pacing."
        appendAgentLog(aiStatus, detail: aiAgentNote)
        withAnimation(.easeInOut(duration: 0.22)) {
            if clips.indices.contains(0) {
                activeClipIndex = 0
                timelineSelection = .video(0)
            }
        }
        try? await Task.sleep(nanoseconds: 900_000_000)
    }

    private func performMandatoryFinalCutPass() async {
        guard !clips.isEmpty else { return }

        aiStatus = "Locking final durations..."
        aiAgentNote = "Final pass changes clip duration only. It does not split or remove clip parts."
        appendAgentLog(aiStatus, detail: aiAgentNote)
        try? await Task.sleep(nanoseconds: 520_000_000)

        var durationsChanged = 0

        for index in clips.indices {
            guard !aiAgentStopRequested else { break }

            let visibleDuration = max(0.1, timelineClipDuration(for: clips[index]))
            let targetDuration: Double
            if clips.count >= 8 {
                targetDuration = 1.15
            } else if clips.count >= 5 {
                targetDuration = 1.35
            } else {
                targetDuration = 1.6
            }
            let nextDuration = max(0.7, min(2.0, min(visibleDuration, targetDuration)))

            aiStatus = "Duration pass \(index + 1)/\(clips.count)..."
            aiAgentNote = "Setting scene \(index + 1) to \(String(format: "%.1f", nextDuration))s."
            appendAgentLog(aiStatus, detail: clips[index].name)

            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                activeClipIndex = index
                timelineSelection = .video(index)
                if abs((clips[index].beatDuration ?? visibleDuration) - nextDuration) > 0.01 {
                    clips[index].beatDuration = nextDuration
                    durationsChanged += 1
                    duration = clips.reduce(0) { $0 + ($1.beatDuration ?? $1.sourceDuration ?? 3.0) }
                    clampAudioRowsToEditedTimeline()
                }
            }

            try? await Task.sleep(nanoseconds: 220_000_000)
        }

        aiStatus = "Final durations locked"
        clampAudioRowsToEditedTimeline()
        aiAgentNote = durationsChanged > 0
            ? "Adjusted \(durationsChanged) clip duration\(durationsChanged == 1 ? "" : "s") as the final edit step."
            : "No duration changes were needed."
        appendAgentLog(aiStatus, detail: aiAgentNote)
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    private func regenerateFinalTextAndVoiceover(
        script: LocalScriptGenerator.GeneratedScript,
        voiceoverMode: String,
        elevenLabsVoiceId: String?,
        language: String
    ) async {
        guard !clips.isEmpty else {
            pendingVoiceoverProcessing = false
            return
        }

        aiStatus = "Writing final captions..."
        aiAgentNote = "Rebuilding text after cuts so captions match the edited timeline."
        appendAgentLog(aiStatus, detail: aiAgentNote)
        pendingTextSlots = 1
        try? await Task.sleep(nanoseconds: 320_000_000)

        withAnimation(.easeInOut(duration: 0.24)) {
            for index in clips.indices {
                let scriptText = finalScriptScene(forClipAt: index, totalClips: clips.count, script: script)?.subtitleText
                    ?? clips[index].text
                    ?? script.scenes.last?.subtitleText
                    ?? script.topic
                let readable = scriptText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !readable.isEmpty {
                    clips[index].text = readable
                }
                clips[index].textStart = 0
                clips[index].textEnd = 100
            }
            pendingTextSlots = 0
            timelineSelection = clips.indices.contains(activeClipIndex) ? .text(max(0, activeClipIndex)) : .none
        }

        guard voiceoverMode == "elevenlabs" else {
            pendingVoiceoverProcessing = false
            return
        }

        let usePremiumVoice = ElevenLabsTTSService.shared.isConfigured
            && !(elevenLabsVoiceId ?? "").isEmpty
            && PremiumVoiceQuota.consumeIfAvailable()

        aiStatus = "Generating final voice..."
        aiAgentNote = usePremiumVoice
            ? "Creating voice after cuts so audio follows the final edit."
            : "Daily premium voice limit reached. Using built-in voice for this edit."
        appendAgentLog(aiStatus, detail: aiAgentNote)
        pendingVoiceoverProcessing = true

        let outputDir = FileStorageService.shared.cacheDirectory.appendingPathComponent("final_voiceover_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        var files: [URL] = []
        var voiceoverStartTimes: [Double] = []
        var voiceoverCursor: Double = 0
        do {
            for (index, clip) in clips.enumerated() {
                let text = finalVoiceoverText(forClipAt: index, clip: clip, totalClips: clips.count, script: script)
                guard !text.isEmpty else { continue }
                let file: URL
                if usePremiumVoice {
                    file = try await ElevenLabsTTSService.shared.synthesizeToFile(
                        text: text,
                        voiceId: elevenLabsVoiceId ?? "",
                        outputDir: outputDir,
                        filename: "final_voice_\(index).mp3"
                    )
                } else {
                    file = try await SystemTTSService.shared.synthesizeToFile(
                        text: text,
                        outputDir: outputDir,
                        filename: "final_voice_\(index).caf",
                        language: language
                    )
                }
                files.append(file)
                voiceoverStartTimes.append(voiceoverCursor)
                voiceoverCursor += timelineClipDuration(for: clip)
            }

            if !files.isEmpty {
                let mergedOutput = outputDir.appendingPathComponent("voiceover_final.m4a")
                if let merged = await composeVoiceoverFiles(files, startTimes: voiceoverStartTimes, output: mergedOutput, totalDuration: timelineTotalDuration) {
                    let dest = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(UUID().uuidString)_voiceover_final.m4a")
                    try? FileManager.default.removeItem(at: dest)
                    try? FileManager.default.copyItem(at: merged, to: dest)

                    aiStatus = "Spawning final voice..."
                    aiAgentNote = "Generated voice for \(files.count) of \(clips.count) final clips and aligned it to the edited timeline."
                    appendAgentLog(aiStatus, detail: aiAgentNote)
                    setVoiceover(url: dest, timelineEnd: timelineTotalDuration)
                    timelineSelection = .voiceover
                }
            }
        } catch {
            aiStatus = "Voice failed"
            aiAgentNote = error.localizedDescription
            appendAgentLog(aiStatus, detail: aiAgentNote)
        }

        pendingVoiceoverProcessing = false
        if isReelMode {
            buildReelPlaylist(selectFirst: false)
        }
    }

    private func finalScriptScene(
        forClipAt index: Int,
        totalClips: Int,
        script: LocalScriptGenerator.GeneratedScript
    ) -> LocalScriptGenerator.SceneScript? {
        guard !script.scenes.isEmpty else { return nil }
        guard totalClips > 0 else { return script.scenes.first }
        let proportionalIndex = Int((Double(index) / Double(max(1, totalClips))) * Double(script.scenes.count))
        let clampedIndex = max(0, min(script.scenes.count - 1, proportionalIndex))
        return script.scenes[clampedIndex]
    }

    private func finalVoiceoverText(
        forClipAt index: Int,
        clip: Clip,
        totalClips: Int,
        script: LocalScriptGenerator.GeneratedScript
    ) -> String {
        let scene = finalScriptScene(forClipAt: index, totalClips: totalClips, script: script)
        let candidates = [
            scene?.voiceoverText,
            scene?.subtitleText,
            clip.text,
            script.scenes.last?.voiceoverText,
            script.topic
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func composeVoiceoverFiles(
        _ files: [URL],
        startTimes: [Double],
        output: URL,
        totalDuration: Double
    ) async -> URL? {
        guard !files.isEmpty else { return nil }

        let composition = AVMutableComposition()
        guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return files.first
        }

        for (index, file) in files.enumerated() {
            let asset = AVURLAsset(url: file)
            guard let sourceTrack = try? await asset.loadTracks(withMediaType: .audio).first,
                  let duration = try? await asset.load(.duration)
            else { continue }

            let startSeconds = startTimes.indices.contains(index) ? startTimes[index] : 0
            let insertAt = CMTime(seconds: max(0, startSeconds), preferredTimescale: 600)
            try? audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack, at: insertAt)
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            return files.first
        }

        try? FileManager.default.removeItem(at: output)
        exportSession.outputURL = output
        exportSession.outputFileType = .m4a
        await exportSession.export()

        if exportSession.status == .completed {
            return output
        }
        return await AudioMergeService.shared.mergeAudioFiles(files, output: output)
    }

    func runAiTimelineEdit(
        scenarioMode: String,
        language: String = "en",
        requestOverride: String? = nil
    ) async {
        let prompt = (requestOverride ?? aiPrompt).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        guard scenarioMode == "openrouter" || scenarioMode == "apple" else {
            aiStatus = "Use \(OpenRouterScenarioGenerator.displayName) or Apple Intelligence for timeline tools."
            return
        }

        rememberEditHistory("AI edit")
        isCoalescingAiEditHistory = true
        defer { isCoalescingAiEditHistory = false }
        aiGenerating = true
        NotificationService.shared.requestPermissionIfNeeded()
        aiAgentActive = true
        aiAgentCanStop = true
        aiAgentStopRequested = false
        showAiPrompt = false
        aiRawScenario = ""
        aiStatus = "Reading timeline..."
        aiAgentNote = "Looking at the scenes, captions, timing, and current canvas."
        appendAgentLog(aiStatus, detail: aiAgentNote)

        let plan: [TimelineEditInstruction]
        do {
            if scenarioMode == "apple" {
                aiStatus = "Planning edits with Apple Intelligence..."
                aiAgentNote = "Building a visible edit plan from your request."
                appendAgentLog(aiStatus, detail: requestOverride ?? aiPrompt)
                plan = try await AppleIntelligenceScenarioGenerator.generateTimelineEditPlan(
                    request: prompt,
                    timelineSummary: timelineSummaryForAgent(),
                    language: language
                )
            } else {
                aiStatus = "Planning edits with \(OpenRouterScenarioGenerator.displayName)..."
                aiAgentNote = "Asking the model for concrete cut, caption, speed, and canvas operations."
                appendAgentLog(aiStatus, detail: requestOverride ?? aiPrompt)
                plan = try await OpenRouterScenarioGenerator.generateTimelineEditPlan(
                    request: prompt,
                    timelineSummary: timelineSummaryForAgent(),
                    language: language,
                    onRateLimit: { [weak self] update in
                        await self?.handlePlannerRateLimit(update)
                    }
                )
            }
        } catch {
            if scenarioMode == "apple" {
                aiStatus = "Using local edit plan..."
                aiAgentNote = "Apple Intelligence did not return a usable edit plan. Staying on-device and applying local edit tools."
                appendAgentLog(aiStatus, detail: error.localizedDescription)
                plan = localTimelineEditPlan(for: prompt)
            } else {
                aiStatus = error.localizedDescription
                aiAgentNote = "Timeline edit planning failed. Check network or model availability."
                appendAgentLog(aiStatus, detail: aiAgentNote)
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                aiGenerating = false
                aiAgentActive = false
                aiAgentCanStop = false
                aiAgentNote = ""
                NotificationService.shared.notifyAgentFailed(
                    title: "Timeline agent stopped",
                    body: "The edit plan could not finish after retrying."
                )
                return
            }
        }

        guard !plan.isEmpty else {
            aiStatus = "Tell me what to change in the timeline."
            aiAgentNote = "No timeline action matched your request."
            appendAgentLog(aiStatus, detail: aiAgentNote)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            aiPrompt = ""
            aiGenerating = false
            aiAgentActive = false
            aiAgentCanStop = false
            aiStatus = ""
            aiAgentNote = ""
            return
        }

        aiRawScenario = rawTimelinePlanText(plan, provider: scenarioMode == "apple" ? "Apple Intelligence / model fallback" : OpenRouterScenarioGenerator.displayName)
        appendAgentLog("Timeline edit plan", detail: aiRawScenario)

        for instruction in plan.prefix(12) {
            if aiAgentStopRequested {
                aiStatus = "Stopped"
                aiAgentNote = "I stopped before the next edit. You can adjust the timeline now."
                appendAgentLog(aiStatus, detail: aiAgentNote)
                try? await Task.sleep(nanoseconds: 900_000_000)
                break
            }
            aiStatus = timelineStatus(for: instruction)
            aiAgentNote = timelineNote(for: instruction)
            appendAgentLog(aiStatus, detail: aiAgentNote)
            await applyTimelineInstruction(instruction)
            try? await Task.sleep(nanoseconds: 650_000_000)
        }

        if isReelMode {
            rebuildPlaylistIfNeeded()
        } else if clips.indices.contains(activeClipIndex) {
            selectClip(at: activeClipIndex)
        }

        aiPrompt = ""
        aiStatus = ""
        aiGenerating = false
        aiAgentActive = false
        aiAgentCanStop = false
        aiAgentStopRequested = false
        aiAgentNote = ""
        NotificationService.shared.notifyAgentDone(
            title: "Timeline agent done",
            body: "Your timeline edits are ready to preview."
        )
    }

    func stopAiAgent() {
        guard aiAgentActive else { return }
        aiAgentStopRequested = true
        aiAgentCanStop = false
        aiStatus = "Stopping..."
        aiAgentNote = "Finishing the current small edit, then handing control back to you."
        appendAgentLog(aiStatus, detail: aiAgentNote)
    }

    func interruptAndApplyAgentInstruction(_ instruction: String) async {
        let request = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        appendAgentLog("User interrupt", detail: request)
        if aiAgentActive {
            stopAiAgent()
            try? await Task.sleep(nanoseconds: 550_000_000)
        }
        let savedMode = UserDefaults.standard.string(forKey: "AI_SCENARIO_MODE") ?? "apple"
        let scenarioMode = savedMode == "apple" && AppleIntelligenceScenarioGenerator.isAvailable ? "apple" : "openrouter"
        await runAiTimelineEdit(
            scenarioMode: scenarioMode,
            language: "en",
            requestOverride: request
        )
    }

    private func timelineSummaryForAgent() -> String {
        let clipSummary = clips.enumerated().map { index, clip in
            let duration = clip.beatDuration ?? clip.sourceDuration ?? 3.0
            let caption = clip.text?.isEmpty == false ? clip.text! : "none"
            return """
            \(index): name=\(clip.name), beatDuration=\(String(format: "%.2f", duration))s, visibleDuration=\(String(format: "%.2f", timelineClipDuration(for: clip)))s, trimPercent=\(String(format: "%.1f", clip.trimStart))-\(String(format: "%.1f", clip.trimEnd)), speed=\(String(format: "%.2f", clip.speed)), caption=\(caption)
            """
        }
        .joined(separator: "\n")
        let musicSummary: String
        if let selectedMusic {
            musicSummary = "music=\(selectedMusic.name), volume=\(String(format: "%.2f", musicVolume)), start=\(String(format: "%.1f", selectedMusic.timelineStart)), end=\(selectedMusic.timelineEnd.map { String(format: "%.1f", $0) } ?? "full")"
        } else {
            musicSummary = "music=none"
        }
        return """
        Rules: make pacing match the ad scenario and voiceover beats. Prefer 0.1s precision. Keep each scene beatDuration <= 2.0s unless user asks slow cinematic. Prefer setBeatDuration and syncBeatCuts. Do not split clips unless the user explicitly asks to split. Use setMusic to duck or place music. Use muteClip, muteMusic, muteVoiceover, unmuteClip, unmuteMusic, or unmuteVoiceover when audio should be silenced/restored.
        \(musicSummary)
        Clips:
        \(clipSummary)
        """
    }

    private func localTimelineEditPlan(for prompt: String) -> [TimelineEditInstruction] {
        let lower = prompt.lowercased()
        var plan: [TimelineEditInstruction] = []

        if lower.contains("caption") || lower.contains("subtitle") {
            plan.append(TimelineEditInstruction(action: "setCaptionsEnabled", clipIndex: nil, fromIndex: nil, toIndex: nil, trimStart: nil, trimEnd: nil, speed: nil, text: nil, enabled: !lower.contains("off"), aspectRatio: nil))
        }

        if lower.contains("vertical") || lower.contains("reel") || lower.contains("tiktok") || lower.contains("short") {
            plan.append(TimelineEditInstruction(action: "setAspectRatio", clipIndex: nil, fromIndex: nil, toIndex: nil, trimStart: nil, trimEnd: nil, speed: nil, text: nil, enabled: nil, aspectRatio: "9:16"))
        } else if lower.contains("wide") || lower.contains("youtube") || lower.contains("landscape") {
            plan.append(TimelineEditInstruction(action: "setAspectRatio", clipIndex: nil, fromIndex: nil, toIndex: nil, trimStart: nil, trimEnd: nil, speed: nil, text: nil, enabled: nil, aspectRatio: "16:9"))
        } else if lower.contains("square") {
            plan.append(TimelineEditInstruction(action: "setAspectRatio", clipIndex: nil, fromIndex: nil, toIndex: nil, trimStart: nil, trimEnd: nil, speed: nil, text: nil, enabled: nil, aspectRatio: "1:1"))
        }

        let asksAllClips = lower.contains("every clip") || lower.contains("all clips") || lower.contains("whole timeline") || lower.contains("all video")
        if lower.contains("faster") || lower.contains("speed up") {
            plan.append(TimelineEditInstruction(action: "setSpeed", clipIndex: asksAllClips ? nil : activeClipIndexForAgent, allClips: asksAllClips, speed: 1.5))
        } else if lower.contains("slower") || lower.contains("slow down") {
            plan.append(TimelineEditInstruction(action: "setSpeed", clipIndex: asksAllClips ? nil : activeClipIndexForAgent, allClips: asksAllClips, speed: 0.75))
        }

        if lower.contains("duplicate") || lower.contains("copy clip") {
            plan.append(TimelineEditInstruction(action: "duplicateClip", clipIndex: activeClipIndexForAgent, fromIndex: nil, toIndex: nil, trimStart: nil, trimEnd: nil, speed: nil, text: nil, enabled: nil, aspectRatio: nil))
        }

        if lower.contains("split") || lower.contains("cut") || lower.contains("scissor") || lower.contains("slice") {
            plan.append(TimelineEditInstruction(action: "splitClip", clipIndex: activeClipIndexForAgent, fromIndex: nil, toIndex: nil, trimStart: nil, trimEnd: nil, speed: nil, text: nil, enabled: nil, aspectRatio: nil))
        }

        if lower.contains("bad take") || lower.contains("bad takes") || lower.contains("remove bad") || lower.contains("delete bad") || lower.contains("clean takes") {
            plan.append(TimelineEditInstruction(action: "removeBadTakes", clipIndex: nil, fromIndex: nil, toIndex: nil, trimStart: nil, trimEnd: nil, speed: nil, text: nil, enabled: nil, aspectRatio: nil))
        } else if lower.contains("delete") || lower.contains("remove") {
            plan.append(TimelineEditInstruction(action: "deleteClip", clipIndex: activeClipIndexForAgent, fromIndex: nil, toIndex: nil, trimStart: nil, trimEnd: nil, speed: nil, text: nil, enabled: nil, aspectRatio: nil))
        }

        if lower.contains("mute") {
            if lower.contains("voice") || lower.contains("voiceover") {
                plan.append(TimelineEditInstruction(action: lower.contains("unmute") ? "unmuteVoiceover" : "muteVoiceover"))
            } else if lower.contains("music") || lower.contains("audio") {
                plan.append(TimelineEditInstruction(action: lower.contains("unmute") ? "unmuteMusic" : "muteMusic"))
            } else {
                plan.append(TimelineEditInstruction(action: lower.contains("unmute") ? "unmuteClip" : "muteClip", clipIndex: activeClipIndexForAgent))
            }
        }

        if plan.isEmpty, !clips.isEmpty {
            plan.append(TimelineEditInstruction(action: "selectClip", clipIndex: activeClipIndexForAgent, fromIndex: nil, toIndex: nil, trimStart: nil, trimEnd: nil, speed: nil, text: nil, enabled: nil, aspectRatio: nil))
        }

        return plan
    }

    private var activeClipIndexForAgent: Int? {
        clips.indices.contains(activeClipIndex) ? activeClipIndex : clips.indices.first
    }

    private func removeLikelyBadTakes() {
        guard clips.count > 1 else { return }

        let badMarkers = [
            "bad", "failed", "fail", "mistake", "retake", "test",
            "blurry", "blur", "shaky", "unusable", "trash", "delete", "remove"
        ]

        let removableIndexes = clips.indices.filter { index in
            let clip = clips[index]
            let searchable = [clip.name, clip.text ?? "", clip.uri]
                .joined(separator: " ")
                .lowercased()
            let hasBadMarker = badMarkers.contains { searchable.contains($0) }
            let duration = timelineClipDuration(for: clip)
            let trimRange = clip.trimEnd - clip.trimStart
            return hasBadMarker || duration < 0.45 || trimRange < 5
        }

        guard !removableIndexes.isEmpty else {
            aiAgentNote = "I did not find clips clearly marked as bad, failed, blurry, shaky, test, or too short."
            return
        }

        for index in removableIndexes.reversed() where clips.count > 1 {
            clips.remove(at: index)
        }

        activeClipIndex = min(activeClipIndex, max(0, clips.count - 1))
        resetAudioRowsToFullTimeline()
    }

    private func timelineClipDuration(for clip: Clip) -> Double {
        let base = clipDisplayDuration(for: clip)
        return max(0, base * (clip.trimEnd - clip.trimStart) / 100.0)
    }

    private func clipDisplayDuration(for clip: Clip) -> Double {
        if let beatDuration = clip.beatDuration, beatDuration > 0 { return beatDuration }
        if let sourceDuration = clip.sourceDuration, sourceDuration > 0 { return sourceDuration }
        if clips.count == 1, duration > 0 { return duration }
        return isImageClip(clip) ? 3.0 : 3.0
    }

    private func setBeatDuration(for index: Int, seconds: Double) {
        guard clips.indices.contains(index) else { return }
        clips[index].beatDuration = max(0.1, min(2.0, seconds))
        duration = clips.reduce(0) { $0 + ($1.beatDuration ?? $1.sourceDuration ?? 3.0) }
        clampAudioRowsToEditedTimeline()
    }

    private func syncBeatCuts(seconds: Double?) {
        guard !clips.isEmpty else { return }
        let defaultBeat = clips.count >= 8 ? 1.25 : 1.5
        let beat = max(0.1, min(2.0, seconds ?? defaultBeat))
        for index in clips.indices {
            clips[index].beatDuration = beat
        }
        duration = clips.reduce(0) { $0 + ($1.beatDuration ?? $1.sourceDuration ?? 3.0) }
        clampAudioRowsToEditedTimeline()
    }

    private func setTimelineSpeed(_ speed: Double, clipIndex: Int?, allClips: Bool) {
        let clamped = max(0.1, min(5.0, speed))
        if allClips {
            for index in clips.indices {
                clips[index].speed = clamped
            }
            activeClipIndex = clips.indices.contains(activeClipIndex) ? activeClipIndex : (clips.indices.first ?? -1)
        } else if let index = clipIndex, clips.indices.contains(index) {
            clips[index].speed = clamped
            activeClipIndex = index
        } else if clips.indices.contains(activeClipIndex) {
            clips[activeClipIndex].speed = clamped
        }

        if isReelMode {
            rebuildPlaylistIfNeeded()
        } else if let player, isPlaying {
            player.rate = Float(clamped)
        }
    }

    private func splitClip(at index: Int, localSeconds: Double) {
        guard clips.indices.contains(index) else { return }
        let clip = clips[index]
        let visibleDuration = max(0.1, timelineClipDuration(for: clip))
        let sourceDuration = max(0.1, clip.sourceDuration ?? clip.beatDuration ?? visibleDuration)
        let splitRatio = max(0.05, min(0.95, localSeconds / visibleDuration))
        let splitPct = clip.trimStart + ((clip.trimEnd - clip.trimStart) * splitRatio)
        let minimumPct = (0.1 / sourceDuration) * 100.0
        let clampedSplit = max(clip.trimStart + minimumPct, min(clip.trimEnd - minimumPct, splitPct))
        guard clampedSplit > clip.trimStart, clampedSplit < clip.trimEnd else { return }

        var firstHalf = clip
        firstHalf.trimEnd = clampedSplit
        firstHalf.beatDuration = max(0.1, min(2.0, localSeconds))

        var secondHalf = clip
        secondHalf.id = nextClipId
        secondHalf.trimStart = clampedSplit
        secondHalf.beatDuration = max(0.1, min(2.0, visibleDuration - localSeconds))

        clips[index] = firstHalf
        clips.insert(secondHalf, at: index + 1)
        activeClipIndex = index + 1
        duration = clips.reduce(0) { $0 + ($1.beatDuration ?? $1.sourceDuration ?? 3.0) }
        clampAudioRowsToEditedTimeline()
        if isReelMode {
            buildReelPlaylist(selectFirst: false)
        }
    }

    private func applyMusicDecision(_ instruction: TimelineEditInstruction) {
        if let volume = instruction.musicVolume {
            updateMusicVolume(max(0, min(1, volume)))
        } else if voiceoverFileURL != nil {
            updateMusicVolume(0.22)
        }

        if selectedMusic == nil, let track = musicTrack(matching: instruction.musicMood) {
            Task { @MainActor in
                await selectMusic(track)
                if var current = selectedMusic {
                    current.timelineStart = max(0, instruction.musicStart ?? 0)
                    current.timelineEnd = nil
                    selectedMusic = current
                    timelineSelection = .music(current.id)
                }
            }
        } else if var current = selectedMusic {
            current.timelineStart = max(0, instruction.musicStart ?? current.timelineStart)
            current.timelineEnd = nil
            selectedMusic = current
            timelineSelection = .music(current.id)
        } else {
            showMusicPickerFromTimeline = true
        }
    }

    private func musicTrack(matching mood: String?) -> MusicTrack? {
        guard !musicLibrary.isEmpty else { return nil }
        let lower = (mood ?? "").lowercased()
        if lower.contains("tech") || lower.contains("club") || lower.contains("house") {
            return musicLibrary.first { $0.id.contains("tech") }
        }
        if lower.contains("chill") || lower.contains("calm") || lower.contains("night") {
            return musicLibrary.first { $0.id.contains("hazy") }
        }
        if lower.contains("warm") || lower.contains("emotional") || lower.contains("story") {
            return musicLibrary.first { $0.id.contains("sun") }
        }
        if lower.contains("drive") || lower.contains("momentum") || lower.contains("cinematic") {
            return musicLibrary.first { $0.id.contains("driving") }
        }
        return musicLibrary.first
    }

    private func timelineStatus(for instruction: TimelineEditInstruction) -> String {
        switch instruction.action {
        case "moveClip": return "Moving clips..."
        case "trimClip": return "Trimming clip..."
        case "setBeatDuration", "syncBeatCuts": return "Matching beat cuts..."
        case "splitClip": return "Cutting clip..."
        case "removeBadTakes": return "Removing bad takes..."
        case "duplicateClip": return "Duplicating clip..."
        case "deleteClip": return "Removing clip..."
        case "setSpeed": return "Changing speed..."
        case "muteClip", "unmuteClip", "muteMusic", "unmuteMusic", "muteVoiceover", "unmuteVoiceover": return "Updating mute..."
        case "setCaption", "setCaptionsEnabled": return "Updating captions..."
        case "setAspectRatio": return "Changing canvas..."
        case "setMusic": return "Choosing music..."
        case "playAll": return "Previewing timeline..."
        default: return "Editing timeline..."
        }
    }

    private func timelineNote(for instruction: TimelineEditInstruction) -> String {
        switch instruction.action {
        case "moveClip":
            let from = (instruction.fromIndex ?? 0) + 1
            let to = (instruction.toIndex ?? 0) + 1
            return "Moving scene \(from) closer to position \(to) so the story order matches the ad."
        case "trimClip":
            return "Tightening a scene so the pacing feels faster."
        case "setBeatDuration":
            return "Setting this scene length so the cut lands on the beat."
        case "syncBeatCuts":
            return "Making all scene cuts short and rhythmic for the ad."
        case "splitClip":
            return "Shortening the selected scene duration without splitting it apart."
        case "removeBadTakes":
            return "Scanning the timeline for clips marked as bad, failed, test, blurry, shaky, or too short."
        case "duplicateClip":
            return "Duplicating the selected scene to reuse the strongest visual beat."
        case "deleteClip":
            return "Removing a scene that seems unnecessary for the current direction."
        case "setSpeed":
            return "Changing speed to better match the voiceover and scene energy."
        case "muteClip":
            return "Muting the selected clip audio."
        case "unmuteClip":
            return "Restoring the selected clip audio."
        case "muteMusic":
            return "Muting the selected music row."
        case "unmuteMusic":
            return "Restoring the selected music row."
        case "muteVoiceover":
            return "Muting the voiceover row."
        case "unmuteVoiceover":
            return "Restoring the voiceover row."
        case "setCaption":
            return "Updating on-screen text so the caption reads cleaner."
        case "setCaptionsEnabled":
            return "Toggling caption export for this project."
        case "setAspectRatio":
            return "Adjusting the canvas for the target platform."
        case "setMusic":
            return "Choosing a music bed and ducking it under the voiceover."
        case "playAll":
            return "Previewing the full sequence so timing is visible."
        default:
            return "Applying one small timeline edit."
        }
    }

    private func applyTimelineInstruction(_ instruction: TimelineEditInstruction) async {
        switch instruction.action {
        case "selectClip":
            if let index = instruction.clipIndex, clips.indices.contains(index) {
                selectClip(at: index)
            }
        case "moveClip":
            if let from = instruction.fromIndex,
               let to = instruction.toIndex,
               clips.indices.contains(from),
               clips.indices.contains(to) {
                reorderClips(from: from, to: to)
            }
        case "trimClip":
            if let index = instruction.clipIndex, clips.indices.contains(index) {
                if let trimStart = instruction.trimStart {
                    updateClipTrimStart(index, max(0, min(clips[index].trimEnd - 1, trimStart)))
                }
                if let trimEnd = instruction.trimEnd {
                    updateClipTrimEnd(index, min(100, max(clips[index].trimStart + 1, trimEnd)))
                }
                activeClipIndex = index
            }
        case "setBeatDuration":
            if let index = instruction.clipIndex, clips.indices.contains(index) {
                setBeatDuration(for: index, seconds: instruction.beatDuration ?? 1.5)
            }
        case "syncBeatCuts":
            syncBeatCuts(seconds: instruction.beatDuration)
        case "splitClip":
            if let index = instruction.clipIndex, clips.indices.contains(index) {
                activeClipIndex = index
                let visibleDuration = max(0.1, timelineClipDuration(for: clips[index]))
                setBeatDuration(for: index, seconds: instruction.splitAt ?? min(visibleDuration, 1.3))
            }
        case "duplicateClip":
            if let index = instruction.clipIndex, clips.indices.contains(index) {
                duplicateClip(at: index)
            }
        case "deleteClip":
            if let index = instruction.clipIndex, clips.indices.contains(index) {
                removeClip(at: index)
            }
        case "removeBadTakes":
            removeLikelyBadTakes()
        case "setSpeed":
            if let speed = instruction.speed {
                setTimelineSpeed(speed, clipIndex: instruction.clipIndex, allClips: instruction.allClips == true)
            }
        case "muteClip", "unmuteClip":
            if let index = instruction.clipIndex ?? activeClipIndexForAgent, clips.indices.contains(index) {
                clips[index].isMuted = instruction.action == "muteClip"
                if index == activeClipIndex {
                    player?.isMuted = isMuted || clips[index].isMuted
                    player?.currentItem.map { applyClipAudioSettings(clips[index], to: $0) }
                }
                if isReelMode {
                    buildReelPlaylist(selectFirst: activeClipIndex >= 0)
                }
            }
        case "muteMusic", "unmuteMusic":
            let muted = instruction.action == "muteMusic"
            if var music = selectedMusic {
                music.isMuted = muted
                selectedMusic = music
                timelineSelection = .music(music.id)
            }
            additionalMusicTracks = additionalMusicTracks.map { track in
                var next = track
                next.isMuted = muted
                return next
            }
            syncMusic(to: currentTime)
        case "muteVoiceover", "unmuteVoiceover":
            voiceoverMuted = instruction.action == "muteVoiceover"
            voiceoverAVPlayer?.isMuted = isMuted || voiceoverMuted
            if voiceoverFileURL != nil {
                timelineSelection = .voiceover
            }
        case "setCaption":
            if let index = instruction.clipIndex, clips.indices.contains(index) {
                clips[index].text = instruction.text ?? clips[index].text
                activeClipIndex = index
            }
        case "setCaptionsEnabled":
            setCaptionsViaCloud(instruction.enabled ?? true)
        case "setAspectRatio":
            if let ratio = instruction.aspectRatio, ["9:16", "16:9", "4:5", "1:1"].contains(ratio) {
                setAspectRatio(ratio)
            }
        case "setMusic":
            applyMusicDecision(instruction)
        case "playAll":
            playAllClips()
        default:
            break
        }
    }

    func generateAiClip(
        modelId: String = "wan-video/wan-2.2-turbo",
        duration: Int = 5,
        scenarioMode: String = "openrouter",
        language: String = "en"
    ) async {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty else { return }

        guard scenarioMode == "openrouter" || scenarioMode == "apple" else {
            aiStatus = "Use \(OpenRouterScenarioGenerator.displayName) or Apple Intelligence for prompts."
            return
        }

        pausePlaybackForGeneration()
        NotificationService.shared.requestPermissionIfNeeded()
        aiGenerating = true
        aiStatus = "Starting AI generation..."
        showAiPrompt = false

        do {
            let generationPrompt: String
            if scenarioMode == "apple" {
                aiStatus = "Writing prompt with Apple Intelligence..."
                generationPrompt = try await AppleIntelligenceScenarioGenerator.generateSingleClipPrompt(
                    topic: prompt,
                    language: language,
                    duration: duration
                )
            } else {
                aiStatus = "Writing prompt with \(OpenRouterScenarioGenerator.displayName)..."
                generationPrompt = try await OpenRouterScenarioGenerator.generateSingleClipPrompt(
                    topic: prompt,
                    language: language,
                    duration: duration,
                    onRateLimit: { [weak self] update in
                        await self?.handlePlannerRateLimit(update)
                    }
                )
            }

            let response = try await GenerationService.shared.startAICreate(
                modelId: modelId,
                prompt: generationPrompt,
                imageUrl: nil,
                duration: duration,
                userId: userId
            )

            guard let genId = response.id, response.error == nil else {
                aiStatus = response.error ?? "Failed to start"
                aiGenerating = false
                return
            }

            aiStatus = "Generating video..."
            let deadline = Date().addingTimeInterval(300)
            while Date() < deadline {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                let status = try await GenerationService.shared.pollAICreate(id: genId)
                if status.status == "succeeded", let outputUrl = status.outputUrl {
                    aiStatus = "Downloading clip..."
                    let clipFile = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("ai_clip_\(UUID().uuidString).mp4")
                    try await FileStorageService.shared.downloadFile(from: outputUrl, to: clipFile)

                    let clip = Clip(
                        id: nextClipId,
                        uri: clipFile.path,
                        name: "AI Clip",
                        sourceDuration: Double(duration),
                        localUri: clipFile.path
                    )
                    rememberEditHistory("AI clip")
                    clips.append(clip)
                    activeClipIndex = clips.count - 1
                    if isReelMode { rebuildPlaylistIfNeeded() } else { selectClip(at: activeClipIndex) }

                    aiStatus = ""
                    aiPrompt = ""
                    aiGenerating = false
                    NotificationService.shared.notifyAgentDone(
                        title: "Generated clip ready",
                        body: "Your generated clip is ready in the timeline."
                    )
                    return
                } else if status.status == "failed" || status.status == "canceled" {
                    aiStatus = "Generation failed"
                    aiGenerating = false
                    NotificationService.shared.notifyAgentFailed(
                        title: "Video generation stopped",
                        body: "The generated clip could not finish."
                    )
                    return
                }
            }
            aiStatus = "Timed out"
            aiGenerating = false
            NotificationService.shared.notifyAgentFailed(
                title: "Video generation timed out",
                body: "The generated clip did not finish in time."
            )
        } catch {
            aiStatus = "Error: \(error.localizedDescription)"
            aiGenerating = false
            NotificationService.shared.notifyAgentFailed(
                title: "Video generation stopped",
                body: "The prompt or video generation failed after retrying."
            )
        }
    }

    // MARK: - Pexels Search & Clip Add/Replace

    @Published var pexelsQuery = ""
    @Published var pexelsResults: [PexelsVideoResult] = []
    @Published var isPexelsSearching = false
    @Published var showPexelsSheet = false
    @Published var pexelsReplaceMode = false  // true = replace current clip, false = add new
    @Published var isPexelsDownloading = false
    @Published var pexelsDownloadingId: Int?  // id of the video being downloaded

    func searchPexels() async {
        let query = pexelsQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isPexelsSearching = true
        pexelsResults = await PexelsService.shared.searchVideos(query: query, perPage: 10, orientation: "portrait")
        isPexelsSearching = false
    }

    func addClipFromPexels(_ video: PexelsVideoResult) async {
        isPexelsDownloading = true
        pexelsDownloadingId = video.id
        defer { isPexelsDownloading = false; pexelsDownloadingId = nil }

        let clipFile = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("pexels_\(video.id).mp4")
        do {
            try await FileStorageService.shared.downloadFile(from: video.videoUrl, to: clipFile)
            let clip = Clip(
                id: nextClipId,
                uri: clipFile.path,
                name: "Stock \(video.id)",
                beatDuration: clips.first?.beatDuration,
                sourceDuration: Double(video.duration),
                localUri: clipFile.path,
                isMuted: true
            )
            rememberEditHistory("Pexels clip")
            clips.append(clip)
            activeClipIndex = clips.count - 1
            showPexelsSheet = false
            if isReelMode { rebuildPlaylistIfNeeded() } else { selectClip(at: activeClipIndex) }
        } catch {
            print("[Pexels] Download failed: \(error)")
        }
    }

    func replaceClipFromPexels(_ video: PexelsVideoResult) async {
        guard activeClipIndex >= 0, activeClipIndex < clips.count else { return }
        isPexelsDownloading = true
        pexelsDownloadingId = video.id
        defer { isPexelsDownloading = false; pexelsDownloadingId = nil }

        let clipFile = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("pexels_\(video.id).mp4")
        do {
            try await FileStorageService.shared.downloadFile(from: video.videoUrl, to: clipFile)
            rememberEditHistory("Pexels replace")
            clips[activeClipIndex].uri = clipFile.path
            clips[activeClipIndex].localUri = clipFile.path
            clips[activeClipIndex].sourceDuration = Double(video.duration)
            clips[activeClipIndex].isMuted = true
            showPexelsSheet = false
            if isReelMode { rebuildPlaylistIfNeeded() } else { selectClip(at: activeClipIndex) }
        } catch {
            print("[Pexels] Download failed: \(error)")
        }
    }

    func addClipFromGallery(url: URL, mimeType: String = "video/mp4") {
        rememberEditHistory("add file")
        let id = nextClipId
        let fileExtension = url.pathExtension.isEmpty ? (mimeType.hasPrefix("image/") ? "jpg" : "mp4") : url.pathExtension
        let isImage = mimeType.hasPrefix("image/")
        let importedURL: URL
        let importedMimeType: String
        if isImage {
            let imageCopy = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
            try? FileStorageService.shared.copyFile(from: url, to: imageCopy)
            let videoURL = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(UUID().uuidString)_still.mp4")
            importedURL = makeStillVideo(from: imageCopy, outputURL: videoURL, duration: 3.0) ? videoURL : imageCopy
            importedMimeType = importedURL.pathExtension.lowercased() == "mp4" ? "video/mp4" : mimeType
        } else {
            let dest = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
            try? FileStorageService.shared.copyFile(from: url, to: dest)
            importedURL = dest
            importedMimeType = mimeType
        }
        let clip = Clip(
            id: id,
            uri: importedURL.path,
            name: "Imported \(id)",
            mimeType: importedMimeType,
            beatDuration: isImage ? 3.0 : nil,
            sourceDuration: isImage ? 3.0 : nil,
            localUri: importedURL.path,
            isMuted: isImage
        )
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.82)) {
            clips.append(clip)
            activeClipIndex = clips.count - 1
            timelineSelection = .video(activeClipIndex)
            duration = clips.reduce(0) { $0 + ($1.beatDuration ?? $1.sourceDuration ?? 3.0) }
        }
        if isReelMode { rebuildPlaylistIfNeeded() } else { selectClip(at: activeClipIndex) }
    }

    private func makeStillVideo(from imageURL: URL, outputURL: URL, duration: Double) -> Bool {
        guard let data = try? Data(contentsOf: imageURL),
              let image = PlatformImage.from(data: data),
              let cgImage = image.platformCGImage
        else { return false }

        try? FileManager.default.removeItem(at: outputURL)
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else { return false }
        let width = 1080
        let height = 1920
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(2, Int(duration * 30))
        for frame in 0...frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.002)
            }
            guard let buffer = makePixelBuffer(from: cgImage, width: width, height: height, pool: adaptor.pixelBufferPool) else { continue }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()
        return writer.status == .completed
    }

    private func makePixelBuffer(from image: CGImage, width: Int, height: Int, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32ARGB, nil, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = max(CGFloat(width) / imageSize.width, CGFloat(height) / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: (CGFloat(width) - drawSize.width) / 2,
            y: (CGFloat(height) - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.draw(image, in: drawRect)
        return buffer
    }

    // MARK: - Generate / Export

    func handleGenerate() async {
        guard !isGenerating else { return }
        isGenerating = true
        processingError = nil
        processingMessage = nil
        processingStatus = "processing"
        isProcessingModalVisible = true

        await preCacheClips()

        let renderClips: [Clip] = clips.map { c in
            let resolvedSource = Self.resolveClipPath(c.localUri ?? c.uri)
            return Clip(
                id: c.id,
                uri: resolvedSource,
                name: c.name,
                mimeType: c.mimeType,
                trimStart: c.trimStart,
                trimEnd: c.trimEnd,
                beatDuration: c.beatDuration,
                sourceDuration: c.sourceDuration,
                text: c.text,
                textStart: c.textStart,
                textEnd: c.textEnd,
                textX: c.textX,
                textY: c.textY,
                textFontName: c.textFontName,
                localUri: resolvedSource,
                speed: c.speed,
                audioVolume: c.audioVolume,
                isMuted: c.isMuted,
                filterName: c.filterName,
                overlayImageUri: c.overlayImageUri,
                overlayX: c.overlayX,
                overlayY: c.overlayY,
                overlayScale: c.overlayScale,
                transitionName: c.transitionName,
                transitionDuration: c.transitionDuration,
                videoLayoutMode: c.videoLayoutMode,
                videoScale: c.videoScale,
                videoX: c.videoX,
                videoY: c.videoY
            )
        }

        // Prepare music options
        var musicOptions: MusicRenderOptions?
        if let music = selectedMusic {
            var localPath: String?
            let localURL = await AudioMixerService.shared.downloadAndSaveAudio(from: music.file, audioId: music.id)
            localPath = localURL?.path

            processingMessage = "Downloading music..."

            musicOptions = MusicRenderOptions(
                file: music.file,
                volume: musicVolume * music.volume,
                quality: exportQuality,
                timelineStart: music.timelineStart,
                timelineEnd: music.timelineEnd,
                resolvedPath: localPath,
                isMuted: music.isMuted
            )
        }
        var additionalMusicOptions: [MusicRenderOptions] = []
        for track in additionalMusicTracks {
            let localURL = await AudioMixerService.shared.downloadAndSaveAudio(from: track.file, audioId: track.id)
            additionalMusicOptions.append(MusicRenderOptions(
                file: track.file,
                volume: musicVolume * track.volume,
                quality: exportQuality,
                timelineStart: track.timelineStart,
                timelineEnd: track.timelineEnd,
                resolvedPath: localURL?.path,
                isMuted: track.isMuted
            ))
        }
        let voiceoverOptions = voiceoverFileURL.map {
            VoiceoverRenderOptions(
                fileURL: $0,
                volume: voiceoverVolume,
                timelineStart: voiceoverTimelineStart,
                timelineEnd: voiceoverTimelineEnd,
                isMuted: voiceoverMuted
            )
        }

        let result = await VideoRenderService.shared.renderVideo(
            clips: renderClips,
            music: musicOptions,
            additionalMusic: additionalMusicOptions,
            voiceover: voiceoverOptions,
            aspectRatio: aspectRatio,
            includeBranding: !CreatorSubscriptionPlan.current.isActive,
            onProgress: { [weak self] msg in
                Task { @MainActor in
                    self?.processingMessage = msg
                }
            }
        )

        // Verify the rendered file actually exists and has content
        if let resultURL = result,
           FileStorageService.shared.fileExists(at: resultURL),
           (FileStorageService.shared.fileSize(at: resultURL) ?? 0) > 1000 {
            let id = UUID().uuidString
            let persistentURL: URL
            do {
                persistentURL = try FileStorageService.shared.copyToSavedVideos(sourceURL: resultURL, id: id)
            } catch {
                print("Copy to saved videos failed: \(error), using render URL")
                persistentURL = resultURL
            }

            let generation = Generation(
                id: id,
                videoName: videoName,
                videoUri: persistentURL.absoluteString,
                status: .saved,
                userId: userId,
                musicId: selectedMusic?.id,
                musicName: selectedMusic?.name
            )
            await GenerationService.shared.saveGeneration(generation)

            generatedVideoUri = persistentURL
            processingStatus = "completed"

            // Switch to single-video player for the rendered result
            removeAllObservers()
            playlistItems.removeAll()
            let playerItem = AVPlayerItem(url: persistentURL)
            let singlePlayer = AVPlayer(playerItem: playerItem)
            singlePlayer.isMuted = isMuted
            player = singlePlayer
            observeEndForLoop(item: playerItem)
            startTimeObserver()
            if isPlaying { singlePlayer.play() }
        } else {
            processingStatus = "failed"
            processingError = "Video render failed. Please try again."
        }

        isGenerating = false
    }

    func saveToGallery() async -> Bool {
        guard let videoURL = generatedVideoUri else { return false }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized else {
                    continuation.resume(returning: false)
                    return
                }

                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                } completionHandler: { success, error in
                    if let error = error {
                        print("Save to gallery failed: \(error)")
                    }
                    continuation.resume(returning: success)
                }
            }
        }
    }

    #if os(macOS)
    func exportAndShare() async {
        guard !isGenerating else { return }

        if generatedVideoUri == nil {
            await handleGenerate()
        }

        guard let url = generatedVideoUri,
              url.isFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            processingError = "Export finished, but no local video file was found to share."
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let picker = NSSharingServicePicker(items: [url])
        activeSharingPicker = picker

        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
        guard let view = window?.contentView else {
            if let service = NSSharingService(named: .sendViaAirDrop) {
                service.perform(withItems: [url])
            }
            return
        }

        let anchor = NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        DispatchQueue.main.async {
            picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
        }
    }
    #endif

    @Published var isSaved = false
    /// Set after export starts; holds the generation ID so the UI can navigate to the status screen.
    @Published var exportGenerationId: String?

    /// Start export in background and navigate to rendering status screen.
    func saveVideo() async {
        guard !isGenerating else { return }
        guard canExport else {
            processingError = "Add a video before exporting."
            return
        }
        isGenerating = true
        defer { isGenerating = false }

        NotificationService.shared.requestPermissionIfNeeded()
        processingError = nil

        await preCacheClips()

        let renderClips: [Clip] = clips.map { c in
            let resolvedSource = Self.resolveClipPath(c.localUri ?? c.uri)
            return Clip(
                id: c.id,
                uri: resolvedSource,
                name: c.name,
                mimeType: c.mimeType,
                trimStart: c.trimStart,
                trimEnd: c.trimEnd,
                beatDuration: c.beatDuration,
                sourceDuration: c.sourceDuration,
                text: c.text,
                textStart: c.textStart,
                textEnd: c.textEnd,
                textX: c.textX,
                textY: c.textY,
                textFontName: c.textFontName,
                localUri: resolvedSource,
                speed: c.speed,
                audioVolume: c.audioVolume,
                isMuted: c.isMuted,
                filterName: c.filterName,
                overlayImageUri: c.overlayImageUri,
                overlayX: c.overlayX,
                overlayY: c.overlayY,
                overlayScale: c.overlayScale,
                transitionName: c.transitionName,
                transitionDuration: c.transitionDuration,
                videoLayoutMode: c.videoLayoutMode,
                videoScale: c.videoScale,
                videoX: c.videoX,
                videoY: c.videoY
            )
        }

        guard renderClips.allSatisfy(Self.clipHasPlayableSource(_:)) else {
            processingError = "Video source file is missing. Re-import the video."
            return
        }

        let params = ExportParams(
            existingGenerationId: generationId,
            videoName: videoName,
            clips: renderClips,
            aspectRatio: aspectRatio,
            exportQuality: exportQuality,
            userId: userId,
            musicId: selectedMusic?.id,
            musicName: selectedMusic?.name,
            musicFileUrl: selectedMusic?.file,
            musicVolume: musicVolume,
            musicTrackVolume: selectedMusic?.volume ?? 1.0,
            musicMuted: selectedMusic?.isMuted == true,
            musicTimelineStart: selectedMusic?.timelineStart ?? 0,
            musicTimelineEnd: selectedMusic?.timelineEnd,
            additionalMusic: additionalMusicTracks,
            takesJson: serializeClipsToTakesJson(clips),
            addCaptionsViaCloud: addCaptionsViaCloud,
            voiceoverFileURL: voiceoverFileURL,
            voiceoverVolume: voiceoverVolume,
            voiceoverMuted: voiceoverMuted,
            voiceoverTimelineStart: voiceoverTimelineStart,
            voiceoverTimelineEnd: voiceoverTimelineEnd,
            includeBranding: !CreatorSubscriptionPlan.current.isActive
        )

        let generationId = await BackgroundRenderService.shared.startExport(params: params)
        exportGenerationId = generationId
    }

    // MARK: - Helpers

    var generateLabel: String { "Save" }

    var videoDimensions: CGSize {
        let maxDim: CGFloat = 280
        switch aspectRatio {
        case "9:16":
            return CGSize(width: maxDim * 9 / 16, height: maxDim)
        case "16:9":
            return CGSize(width: maxDim, height: maxDim * 9 / 16)
        case "4:5":
            return CGSize(width: maxDim * 4 / 5, height: maxDim)
        case "1:1", _:
            return CGSize(width: maxDim, height: maxDim)
        }
    }

    /// Resolve a clip path that may contain a stale container UUID.
    /// Extracts the filename and looks for it in savedVideosDirectory.
    private static func resolveClipPath(_ path: String) -> String {
        // Remote URLs pass through
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }

        // If the file exists at the stored path, use it
        let cleanPath = path.replacingOccurrences(of: "file://", with: "")
        if FileManager.default.fileExists(atPath: cleanPath) { return cleanPath }

        // Extract filename and look in savedVideosDirectory
        let filename = (cleanPath as NSString).lastPathComponent
        let resolved = FileStorageService.shared.savedVideosDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: resolved.path) {
            return resolved.path
        }

        let cached = FileStorageService.shared.clipCacheDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached.path
        }

        let rendered = FileStorageService.shared.renderedVideosDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: rendered.path) {
            return rendered.path
        }

        // Return original as fallback
        return cleanPath
    }

    private static func clipHasPlayableSource(_ clip: Clip) -> Bool {
        let source = clip.localUri ?? clip.uri
        if source.hasPrefix("http://") || source.hasPrefix("https://") { return true }
        let resolved = resolveClipPath(source)
        return FileManager.default.fileExists(atPath: resolved)
    }

    private func isRemoteURL(_ uri: String) -> Bool {
        uri.hasPrefix("http://") || uri.hasPrefix("https://")
    }

    private func createURL(from string: String) -> URL? {
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            return URL(string: string)
        }
        if string.hasPrefix("file://") {
            return URL(string: string)
        }
        return URL(fileURLWithPath: string)
    }

    static func serializeClipsForStorage(_ clips: [Clip]) -> String? {
        let arr = clips.map { c -> [String: Any] in
            var d: [String: Any] = [
                "id": c.id,
                "uri": c.localUri ?? c.uri,
                "name": c.name,
                "mimeType": c.mimeType,
                "trimStart": c.trimStart,
                "trimEnd": c.trimEnd,
                "text": c.text ?? "",
                "textStart": c.textStart,
                "textEnd": c.textEnd,
                "textX": c.textX,
                "textY": c.textY,
                "textFontName": c.textFontName,
                "audioVolume": c.audioVolume,
                "isMuted": c.isMuted,
                "filterName": c.filterName,
                "overlayX": c.overlayX,
                "overlayY": c.overlayY,
                "overlayScale": c.overlayScale,
                "transitionName": c.transitionName,
                "transitionDuration": c.transitionDuration,
                "videoLayoutMode": c.videoLayoutMode,
                "videoScale": c.videoScale,
                "videoX": c.videoX,
                "videoY": c.videoY,
            ]
            if let overlay = c.overlayImageUri { d["overlayImageUri"] = overlay }
            if let b = c.beatDuration { d["beatDuration"] = b }
            if let s = c.sourceDuration { d["sourceDuration"] = s }
            return d
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arr) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func serializeClipsToTakesJson(_ clips: [Clip]) -> String? {
        Self.serializeClipsForStorage(clips)
    }

    private static func promptTitle(from prompt: String) -> String {
        let collapsed = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "Video" }
        if collapsed.count <= 42 { return collapsed }
        let prefix = collapsed.prefix(42)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace])
        }
        return String(prefix)
    }

    private func removeAllObservers() {
        if let observer = timeObserver, let p = player {
            p.removeTimeObserver(observer)
        }
        timeObserver = nil

        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        endObserver = nil

        if let obs = boundaryObserver, let p = player {
            p.removeTimeObserver(obs)
        }
        boundaryObserver = nil
    }

    /// Save current clip state back to the generation (autosave on dismiss)
    func autosave() {
        guard let genId = generationId else { return }
        let takesJson = serializeClipsToTakesJson(clips)
        let musicFile = selectedMusic?.file
        Task {
            await GenerationService.shared.updateGeneration(
                id: genId,
                videoUri: clips.first?.localUri ?? clips.first?.uri,
                takesJson: takesJson,
                musicFile: musicFile
            )
            print("[Editor] Autosaved generation \(genId)")
        }
    }

    func cleanup() {
        removeAllObservers()
        player?.pause()
        if let obs = musicEndObserver {
            NotificationCenter.default.removeObserver(obs)
            musicEndObserver = nil
        }
        musicAVPlayer?.pause()
        musicAVPlayer = nil
        clearVoiceoverPlayer()
    }

    deinit {}
}
