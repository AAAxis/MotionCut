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

    // Music
    @Published var selectedMusic: MusicTrack?
    @Published var musicVolume: Double = 0.5
    @Published var musicLibrary = MusicTrack.library
    /// True when we tried to load music (from params) but playback failed (download or init).
    @Published var musicLoadFailed = false

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
    private let musicUrl: String?
    private let userId: String

    private var playlistItems: [(clip: Clip, startOffset: Double)] = []
    private var currentQueueItems: [AVPlayerItem] = []
    private var isReelMode: Bool { clips.contains { $0.beatDuration != nil } && clips.count > 1 }

    // MARK: - Init

    init(params: VideoEditorParams) {
        self.videoName = params.videoName ?? "Video"
        self.musicUrl = params.musicUrl
        self.userId = params.userId

        // Parse takes JSON or single video
        if let takesJson = params.takesJson,
           let data = takesJson.data(using: .utf8),
           let takes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            self.clips = takes.enumerated().map { (i, t) in
                Clip(
                    id: (t["id"] as? Int) ?? (Int(Date().timeIntervalSince1970 * 1000) + i),
                    uri: t["uri"] as? String ?? "",
                    name: t["name"] as? String ?? "Take \(i + 1)",
                    mimeType: t["mimeType"] as? String ?? "video/mp4",
                    trimStart: t["trimStart"] as? Double ?? 0,
                    trimEnd: t["trimEnd"] as? Double ?? 100,
                    beatDuration: t["beatDuration"] as? Double,
                    sourceDuration: t["sourceDuration"] as? Double,
                    text: t["text"] as? String ?? ""
                )
            }
        } else if let videoUri = params.videoUri {
            self.clips = [Clip(id: 1, uri: videoUri, name: videoName)]
        }

        setupPlayer()
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        guard let firstClip = clips.first else { return }
        let urlString = firstClip.localUri ?? firstClip.uri
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

    // MARK: - Music

    func configureAudioSessionForMusic() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[Music] Audio session setup failed: \(error)")
        }
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

        let localURL = await AudioMixerService.shared.downloadAndSaveAudio(from: track.file, audioId: track.id)

        guard let localURL = localURL else {
            print("[Music] Download failed for: \(track.name)")
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

        let hasRemote = clips.contains { isRemoteURL($0.uri) && $0.localUri == nil }
        guard hasRemote else {
            clipsCached = true
            return
        }

        let storage = FileStorageService.shared

        for i in 0..<clips.count {
            guard isRemoteURL(clips[i].uri), clips[i].localUri == nil else { continue }

            let localPath = storage.clipCacheDirectory.appendingPathComponent("take_\(clips[i].id)_\(i).mp4")
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
        rebuildPlaylistIfNeeded()
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
            addCaptionsViaCloud: addCaptionsViaCloud
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
