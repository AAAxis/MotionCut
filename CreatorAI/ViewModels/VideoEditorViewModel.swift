import SwiftUI
import AVFoundation
import AVKit
import Photos

@MainActor
class VideoEditorViewModel: ObservableObject {
    // Clips
    @Published var clips: [Clip] = []
    @Published var activeClipIndex: Int = 0
    @Published var clipsCached = false

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
    @Published var addCaptionsViaCloud = false

    /// Trigger gallery picker for adding a clip (set from timeline "+" button)
    @Published var showAddClipPicker = false

    // Music
    @Published var selectedMusic: MusicTrack?
    @Published var musicVolume: Double = 0.5
    @Published var musicLibrary = MusicTrack.library
    /// True when we tried to load music (from params) but playback failed (download or init).
    @Published var musicLoadFailed = false

    // Voiceover
    @Published var voiceoverFileURL: URL?
    @Published var voiceoverVolume: Double = 1.0
    @Published var showVoiceoverSheet = false

    func setVoiceover(url: URL) {
        voiceoverFileURL = url
    }

    func removeVoiceover() {
        if let url = voiceoverFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        voiceoverFileURL = nil
    }

    // Speed
    @Published var showSpeedSheet = false

    // Aspect Ratio
    @Published var showAspectRatioSheet = false

    func setClipSpeed(_ speed: Double) {
        guard clips.indices.contains(activeClipIndex) else { return }
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

    // Editor
    @Published var activeTab = "edit"

    private var timeObserver: Any?
    private var boundaryObserver: Any?
    private var endObserver: NSObjectProtocol?
    /// Music played with AVPlayer so it mixes reliably with video (same as RN/expo-av behavior).
    private var musicAVPlayer: AVPlayer?
    private var musicEndObserver: NSObjectProtocol?
    let videoName: String
    private let generationId: String?
    private let musicUrl: String?
    private let userId: String

    private var playlistItems: [(clip: Clip, startOffset: Double)] = []
    private var currentQueueItems: [AVPlayerItem] = []
    private var isReelMode: Bool { clips.contains { $0.beatDuration != nil } && clips.count > 1 }

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
            self.clips = takes.enumerated().map { (i, t) in
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
                    localUri: isLocal ? resolvedUri : nil
                )
            }
        } else if let videoUri = params.videoUri {
            let resolved = Self.resolveClipPath(videoUri)
            let isLocal = !resolved.hasPrefix("http://") && !resolved.hasPrefix("https://")
            self.clips = [Clip(id: 1, uri: resolved, name: videoName, localUri: isLocal ? resolved : nil)]
        }

        setupPlayer()
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        guard let firstClip = clips.first else { return }
        let urlString = firstClip.localUri ?? firstClip.uri

        // Skip setup if the clip is a remote URL that hasn't been cached yet
        // preCacheClips() will call rebuildPlaylistIfNeeded() after caching
        if isRemoteURL(urlString) && firstClip.localUri == nil {
            return
        }

        guard let url = createURL(from: urlString) else { return }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.isMuted = isMuted

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
            let maxStart = max(0, srcDur - beatDur - 0.5)
            let startOffset = Double.random(in: 0...max(0.01, maxStart))

            let start = CMTime(seconds: startOffset, preferredTimescale: 600)
            let end = CMTime(seconds: startOffset + beatDur, preferredTimescale: 600)
            let item = AVPlayerItem(asset: asset)
            item.forwardPlaybackEndTime = end
            item.seek(to: start, completionHandler: nil)

            items.append(item)
            playlistItems.append((clip: clip, startOffset: startOffset))
        }

        guard !items.isEmpty else { return }

        currentQueueItems = items
        let queuePlayer = AVQueuePlayer(items: items)
        queuePlayer.isMuted = isMuted
        player = queuePlayer

        activeClipIndex = selectFirst ? 0 : -1
        duration = clips.reduce(0) { $0 + ($1.beatDuration ?? 1.5) }
        currentTime = 0

        startTimeObserver()
        observeQueueAdvance(queuePlayer: queuePlayer, allItems: items)

        if isPlaying {
            queuePlayer.play()
        }
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
        musicAVPlayer?.seek(to: .zero)
        musicAVPlayer?.play()
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
                    }
                } else {
                    self.currentTime = CMTimeGetSeconds(time)
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
            player?.play()
            // Apply per-clip speed
            let speed = activeClipSpeed
            if abs(speed - 1.0) > 0.01 {
                player?.rate = Float(speed)
            }
            musicAVPlayer?.play()
        } else {
            player?.pause()
            musicAVPlayer?.pause()
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    func seekToTime(_ seconds: Double) {
        guard duration > 0 else { return }
        let clamped = max(0, min(seconds, duration))
        let pct = (clamped / duration) * 100
        seek(to: pct)
    }

    func pauseForScrub() {
        if isPlaying {
            player?.pause()
            musicAVPlayer?.pause()
            isPlaying = false
        }
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
                    return
                }
                accumulated += beatDur
            }
        } else {
            let time = CMTime(seconds: (percentage / 100) * duration, preferredTimescale: 600)
            player.seek(to: time)
            currentTime = CMTimeGetSeconds(time)
        }
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
            let maxStart = max(0, srcDur - beatDur - 0.5)
            let startOffset = Double.random(in: 0...max(0.01, maxStart))

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

        startTimeObserver()
        observeQueueAdvance(queuePlayer: queuePlayer, allItems: items)

        if isPlaying {
            queuePlayer.play()
        }
    }

    // MARK: - Clip Management

    func selectClip(at index: Int) {
        guard index >= 0, index < clips.count else { return }
        activeClipIndex = index
        let clip = clips[index]
        let urlString = clip.localUri ?? clip.uri
        guard let url = createURL(from: urlString) else { return }

        removeAllObservers()
        playlistItems.removeAll()
        currentQueueItems = []

        let item = AVPlayerItem(url: url)

        if let beatDur = clip.beatDuration {
            let srcDur = clip.sourceDuration ?? 10.0
            let maxStart = max(0, srcDur - beatDur - 0.5)
            let startOffset = (clip.trimStart / 100.0) * srcDur
            let end = CMTime(seconds: startOffset + beatDur, preferredTimescale: 600)
            item.forwardPlaybackEndTime = end
            item.seek(to: CMTime(seconds: startOffset, preferredTimescale: 600), completionHandler: nil)
            duration = beatDur
        } else {
            duration = 0
        }

        let singlePlayer = AVPlayer(playerItem: item)
        singlePlayer.isMuted = isMuted
        player = singlePlayer
        currentTime = 0

        observeEndForLoop(item: item)
        startTimeObserver()

        if isPlaying {
            singlePlayer.play()
        }
    }

    func updateClipTrimStart(_ index: Int, _ value: Double) {
        guard index >= 0, index < clips.count else { return }
        clips[index].trimStart = value
    }

    func updateClipTrimEnd(_ index: Int, _ value: Double) {
        guard index >= 0, index < clips.count else { return }
        clips[index].trimEnd = value
    }

    func addClip(uri: String, name: String) {
        let clip = Clip(id: Int(Date().timeIntervalSince1970 * 1000), uri: uri, name: name)
        clips.append(clip)
    }

    func removeClip(at index: Int) {
        guard index >= 0 && index < clips.count else { return }
        clips.remove(at: index)
        if activeClipIndex >= clips.count {
            activeClipIndex = max(0, clips.count - 1)
        }
        if clips.count > 1 && isReelMode {
            rebuildPlaylistIfNeeded()
        } else if !clips.isEmpty {
            selectClip(at: activeClipIndex)
        }
    }

    func reorderClips(from: Int, to: Int) {
        guard from != to, from >= 0, to >= 0, from < clips.count, to < clips.count else { return }
        let clip = clips.remove(at: from)
        clips.insert(clip, at: to)
        activeClipIndex = to
    }

    private var nextClipId: Int {
        return (clips.map(\.id).max() ?? 0) + 1
    }

    func duplicateClip(at index: Int) {
        guard index >= 0 && index < clips.count else { return }
        var copy = clips[index]
        copy.id = nextClipId
        clips.insert(copy, at: index + 1)
        activeClipIndex = index + 1
    }

    func splitClipAtPlayhead() {
        guard activeClipIndex >= 0 && activeClipIndex < clips.count else { return }
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
        guard selectedMusic != nil, let p = musicAVPlayer else { return }
        configureAudioSessionForMusic()
        p.seek(to: .zero)
        p.volume = Float(musicVolume)
        p.play()
    }

    func restartMusicIfNeeded() {
        guard musicAVPlayer != nil else { return }
        ensureMusicPlaying()
    }

    /// Download and start playing the given track. Uses AVPlayer so music mixes with video (like RN/expo-av).
    func selectMusic(_ track: MusicTrack) async {
        selectedMusic = track
        musicLoadFailed = false

        if let obs = musicEndObserver {
            NotificationCenter.default.removeObserver(obs)
            musicEndObserver = nil
        }
        musicAVPlayer?.pause()
        musicAVPlayer = nil

        configureAudioSessionForMusic()

        // For local files, play directly with AVPlayer (no transcoding needed)
        let localURL: URL?
        let filePath = track.file.replacingOccurrences(of: "file://", with: "")
        if filePath.hasPrefix("/"), FileManager.default.fileExists(atPath: filePath) {
            localURL = URL(fileURLWithPath: filePath)
            print("[Music] Using local file: \(filePath)")
        } else {
            localURL = await AudioMixerService.shared.downloadAndSaveAudio(from: track.file, audioId: track.id)
        }

        guard let localURL = localURL else {
            print("[Music] Failed to load: \(track.name)")
            musicLoadFailed = true
            return
        }

        let item = AVPlayerItem(url: localURL)
        let avp = AVPlayer(playerItem: item)
        avp.volume = Float(musicVolume)
        musicAVPlayer = avp

        musicEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.musicAVPlayer?.seek(to: .zero)
            self?.musicAVPlayer?.play()
        }

        configureAudioSessionForMusic()
        avp.play()
    }

    func clearMusic() {
        selectedMusic = nil
        musicLoadFailed = false
        if let obs = musicEndObserver {
            NotificationCenter.default.removeObserver(obs)
            musicEndObserver = nil
        }
        musicAVPlayer?.pause()
        musicAVPlayer = nil
    }

    func updateMusicVolume(_ volume: Double) {
        musicVolume = volume
        musicAVPlayer?.volume = Float(volume)
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
            let c = clips[i]

            if storage.fileExists(at: localPath), let size = storage.fileSize(at: localPath), size > 0 {
                var updated = clips
                updated[i] = Clip(id: c.id, uri: c.uri, name: c.name, mimeType: c.mimeType, trimStart: c.trimStart, trimEnd: c.trimEnd, beatDuration: c.beatDuration, sourceDuration: c.sourceDuration, text: c.text, localUri: localPath.path)
                clips = updated
                continue
            }

            do {
                try await storage.downloadFile(from: clips[i].uri, to: localPath)
                var updated = clips
                let clip = clips[i]
                updated[i] = Clip(id: clip.id, uri: clip.uri, name: clip.name, mimeType: clip.mimeType, trimStart: clip.trimStart, trimEnd: clip.trimEnd, beatDuration: clip.beatDuration, sourceDuration: clip.sourceDuration, text: clip.text, localUri: localPath.path)
                clips = updated
                print("[Cache] Clip \(i) cached")
            } catch {
                print("[Cache] Clip \(i) download failed: \(error)")
            }
        }

        clipsCached = true

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

    func generateAiClip() async {
        let prompt = aiPrompt.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty else { return }
        aiGenerating = true
        aiStatus = "Starting AI generation..."
        showAiPrompt = false

        do {
            let response = try await GenerationService.shared.startAICreate(
                modelId: "fal-ai/pixverse/v4/text-to-video",
                prompt: prompt,
                imageUrl: nil,
                duration: 5,
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
                        sourceDuration: 5.0,
                        localUri: clipFile.path
                    )
                    clips.append(clip)
                    activeClipIndex = clips.count - 1
                    if isReelMode { rebuildPlaylistIfNeeded() } else { selectClip(at: activeClipIndex) }

                    aiStatus = ""
                    aiPrompt = ""
                    aiGenerating = false
                    return
                } else if status.status == "failed" || status.status == "canceled" {
                    aiStatus = "Generation failed"
                    aiGenerating = false
                    return
                }
            }
            aiStatus = "Timed out"
            aiGenerating = false
        } catch {
            aiStatus = "Error: \(error.localizedDescription)"
            aiGenerating = false
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
                localUri: clipFile.path
            )
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
            clips[activeClipIndex].uri = clipFile.path
            clips[activeClipIndex].localUri = clipFile.path
            clips[activeClipIndex].sourceDuration = Double(video.duration)
            showPexelsSheet = false
            if isReelMode { rebuildPlaylistIfNeeded() } else { selectClip(at: activeClipIndex) }
        } catch {
            print("[Pexels] Download failed: \(error)")
        }
    }

    func addClipFromGallery(url: URL) {
        let id = nextClipId
        let dest = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try? FileStorageService.shared.copyFile(from: url, to: dest)
        let clip = Clip(
            id: id,
            uri: dest.path,
            name: "Imported \(id)",
            localUri: dest.path
        )
        clips.append(clip)
        activeClipIndex = clips.count - 1
        if isReelMode { rebuildPlaylistIfNeeded() } else { selectClip(at: activeClipIndex) }
    }

    // MARK: - Generate / Export

    func handleGenerate() async {
        guard !isGenerating else { return }
        isGenerating = true
        processingError = nil
        processingMessage = nil
        processingStatus = "processing"
        isProcessingModalVisible = true

        let renderClips = clips.map { c in
            Clip(
                id: c.id,
                uri: c.localUri ?? c.uri,
                trimStart: c.trimStart,
                trimEnd: c.trimEnd,
                beatDuration: c.beatDuration,
                sourceDuration: c.sourceDuration,
                text: c.text
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
                volume: musicVolume,
                quality: exportQuality,
                resolvedPath: localPath
            )
        }

        let result = await VideoRenderService.shared.renderVideo(
            clips: renderClips,
            music: musicOptions,
            aspectRatio: aspectRatio,
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

            // Upload to Supabase Storage for cloud persistence
            Task {
                if let remoteUrl = await SupabaseService.shared.uploadVideo(fileURL: persistentURL, generationId: id) {
                    await GenerationService.shared.updateGeneration(id: id, remoteVideoUrl: remoteUrl)
                }
            }

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

    @Published var isSaved = false
    /// Set after export starts; holds the generation ID so the UI can navigate to the status screen.
    @Published var exportGenerationId: String?

    /// Start export in background and navigate to rendering status screen.
    func saveVideo() async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }

        NotificationService.shared.requestPermissionIfNeeded()

        let renderClips = clips.map { c in
            Clip(
                id: c.id,
                uri: c.localUri ?? c.uri,
                name: c.name,
                mimeType: c.mimeType,
                trimStart: c.trimStart,
                trimEnd: c.trimEnd,
                beatDuration: c.beatDuration,
                sourceDuration: c.sourceDuration,
                text: c.text,
                localUri: c.localUri ?? c.uri
            )
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
            takesJson: serializeClipsToTakesJson(clips),
            addCaptionsViaCloud: addCaptionsViaCloud,
            voiceoverFileURL: voiceoverFileURL,
            voiceoverVolume: voiceoverVolume
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

        // Return original as fallback
        return cleanPath
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

    private func serializeClipsToTakesJson(_ clips: [Clip]) -> String? {
        let arr = clips.map { c -> [String: Any] in
            var d: [String: Any] = [
                "id": c.id,
                "uri": c.localUri ?? c.uri,
                "name": c.name,
                "mimeType": c.mimeType,
                "trimStart": c.trimStart,
                "trimEnd": c.trimEnd,
                "text": c.text ?? "",
            ]
            if let b = c.beatDuration { d["beatDuration"] = b }
            if let s = c.sourceDuration { d["sourceDuration"] = s }
            return d
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arr) else { return nil }
        return String(data: data, encoding: .utf8)
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
    }

    deinit {}
}
