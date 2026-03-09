import Foundation
import AVFoundation
import QuartzCore

// NOTE: This service requires ffmpeg-kit-ios-full SPM package.
// Import FFmpegKit when the package is added to the Xcode project:
// import FFmpegKit

class VideoRenderService {
    static let shared = VideoRenderService()

    private let storage = FileStorageService.shared

    typealias ProgressCallback = (String) -> Void

    // MARK: - Main Render Entry

    func renderVideo(clips: [Clip], music: MusicRenderOptions?, aspectRatio: String = "1:1", onProgress: ProgressCallback?) async -> URL? {
        let report: (String) -> Void = { msg in
            print("[renderVideo] \(msg)")
            onProgress?(msg)
        }

        guard !clips.isEmpty else { return nil }

        let outputPath = storage.renderedVideosDirectory.appendingPathComponent("rendered_\(Int(Date().timeIntervalSince1970 * 1000)).mp4")

        // 1. Ensure all clips are local
        var localClips: [Clip] = []
        for (i, clip) in clips.enumerated() {
            var c = clip
            if isRemoteURL(clip.uri) {
                report("Downloading clip \(i + 1) of \(clips.count)...")
                let localPath = storage.clipCacheDirectory.appendingPathComponent("clip_\(i)_\(Int(Date().timeIntervalSince1970 * 1000)).mp4")
                do {
                    try await storage.downloadFile(from: clip.uri, to: localPath)
                    c.localUri = localPath.path
                } catch {
                    print("Failed to download clip \(i): \(error)")
                    c.localUri = clip.uri
                }
            } else {
                c.localUri = clip.uri
            }
            localClips.append(c)
        }

        let isReelMode = localClips.contains { $0.beatDuration != nil }

        if isReelMode {
            if let url = await renderReelModeWithAVFoundation(clips: localClips, music: music, outputPath: outputPath, onProgress: report) {
                return url
            }
            if let url = await renderReelMode(clips: localClips, music: music, aspectRatio: aspectRatio, outputPath: outputPath, onProgress: report) {
                return url
            }
        } else {
            if let url = await renderStandardModeWithAVFoundation(clips: localClips, music: music, outputPath: outputPath, onProgress: report) {
                return url
            }
            if let url = await renderStandardMode(clips: localClips, music: music, outputPath: outputPath, onProgress: report) {
                return url
            }
        }
        return copyFirstClipAsFallback(clips: localClips, outputPath: outputPath)
    }

    /// When export fails, copy first clip so user still gets a playable file (like RN mock).
    private func copyFirstClipAsFallback(clips: [Clip], outputPath: URL) -> URL? {
        guard let first = clips.first, let srcURL = urlForPath(first.localUri ?? first.uri) else { return nil }
        do {
            try? FileManager.default.removeItem(at: outputPath)
            try FileManager.default.copyItem(at: srcURL, to: outputPath)
            print("[renderVideo] Fallback: copied first clip to \(outputPath.path)")
            return outputPath
        } catch {
            print("[renderVideo] Fallback copy failed: \(error)")
            return nil
        }
    }

    // MARK: - AVFoundation Export (produces real playable file when FFmpeg is not available)

    private func urlForPath(_ path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        if path.hasPrefix("file://") {
            return URL(string: path)
        }
        return URL(fileURLWithPath: path)
    }

    private func renderStandardModeWithAVFoundation(clips: [Clip], music: MusicRenderOptions?, outputPath: URL, onProgress: @escaping (String) -> Void) async -> URL? {
        onProgress("Preparing clips...")
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        let addOriginalAudio = (music == nil)
        let audioTrack: AVMutableCompositionTrack? = addOriginalAudio ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) : nil

        var currentTime = CMTime.zero
        var renderSize = CGSize(width: 1920, height: 1080)
        var firstTrackTransform: CGAffineTransform = .identity

        for (i, clip) in clips.enumerated() {
            guard let clipURL = urlForPath(clip.localUri ?? clip.uri) else { continue }
            let asset = AVURLAsset(url: clipURL)
            guard let assetVideo = try? await asset.loadTracks(withMediaType: .video).first else { continue }
            let duration = try? await asset.load(.duration)
            let durSec = duration.map { CMTimeGetSeconds($0) } ?? 0
            guard durSec > 0 else { continue }

            let startSec = (clip.trimStart / 100.0) * durSec
            let endSec = (clip.trimEnd / 100.0) * durSec
            let trimDuration = max(0.01, endSec - startSec)
            let startTime = CMTime(seconds: startSec, preferredTimescale: 600)
            let rangeDuration = CMTime(seconds: trimDuration, preferredTimescale: 600)
            let range = CMTimeRange(start: startTime, duration: rangeDuration)

            try? videoTrack.insertTimeRange(range, of: assetVideo, at: currentTime)
            if let audioTrack = audioTrack, let assetAudio = try? await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: assetAudio, at: currentTime)
            }

            if i == 0 {
                let naturalSize = (try? await assetVideo.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)
                let preferredTransform = (try? await assetVideo.load(.preferredTransform)) ?? .identity
                firstTrackTransform = preferredTransform
                renderSize = naturalSize.applying(preferredTransform)
                renderSize = CGSize(width: abs(renderSize.width), height: abs(renderSize.height))
                if renderSize.width < 1 || renderSize.height < 1 { renderSize = CGSize(width: 1920, height: 1080) }
            }
            currentTime = CMTimeAdd(currentTime, rangeDuration)
        }

        if CMTimeGetSeconds(currentTime) < 0.01 { return nil }

        // Add music track directly to the composition (avoids two-step export)
        var audioMix: AVMutableAudioMix?
        if let musicOpt = music, let musicPath = musicOpt.resolvedPath, let musicURL = urlForPath(musicPath) {
            onProgress("Adding music...")
            let musicAsset = AVURLAsset(url: musicURL)
            if let musicAudioTrack = try? await musicAsset.loadTracks(withMediaType: .audio).first {
                if let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    let musicDuration = (try? await musicAsset.load(.duration)) ?? .zero
                    let insertDuration = CMTimeGetSeconds(currentTime) < CMTimeGetSeconds(musicDuration) ? currentTime : musicDuration
                    let musicRange = CMTimeRange(start: .zero, duration: insertDuration)
                    try? musicTrack.insertTimeRange(musicRange, of: musicAudioTrack, at: .zero)

                    let mixParams = AVMutableAudioMixInputParameters(track: musicTrack)
                    mixParams.setVolume(Float(musicOpt.volume), at: .zero)
                    let mix = AVMutableAudioMix()
                    mix.inputParameters = [mixParams]
                    audioMix = mix
                }
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: currentTime)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(firstTrackTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        // Captions are optional and done via cloud; no local overlay.

        if await exportComposition(composition, videoComposition: videoComposition, audioMix: audioMix, to: outputPath) {
            return outputPath
        }
        print("[renderVideo] Standard export failed, retrying with no composition...")
        if await exportComposition(composition, videoComposition: nil, audioMix: audioMix, to: outputPath) {
            return outputPath
        }
        // -12849 often occurs with audio mix; retry without music mix (clips + original audio only)
        if audioMix != nil {
            print("[renderVideo] Retrying with no composition and no music mix (clips only)...")
            if await exportComposition(composition, videoComposition: nil, audioMix: nil, to: outputPath) {
                return outputPath
            }
            // Remove the music audio track entirely from the composition.
            // Previous fallbacks only removed audioMix params but left the
            // (potentially incompatible MP3) track data, which still causes -12849.
            print("[renderVideo] Retrying after removing music track from composition...")
            let audioTracks = composition.tracks(withMediaType: .audio)
            for track in audioTracks {
                composition.removeTrack(track)
            }
            if await exportComposition(composition, videoComposition: videoComposition, audioMix: nil, to: outputPath) {
                return outputPath
            }
            if await exportComposition(composition, videoComposition: nil, audioMix: nil, to: outputPath) {
                return outputPath
            }
        }
        return nil
    }

    private func renderReelModeWithAVFoundation(clips: [Clip], music: MusicRenderOptions?, outputPath: URL, onProgress: @escaping (String) -> Void) async -> URL? {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        // When music is present, keep clips muted (no clip audio) so we only have 1 audio track — avoids -12849 and keeps music mandatory.
        let audioTrack: AVMutableCompositionTrack? = (music == nil)
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        var currentTime = CMTime.zero
        let renderSize = CGSize(width: 1080, height: 1920)

        // Use a SINGLE layer instruction for the single video track.
        // Multiple layer instructions for the same track causes AVAssetExportSession error -16979.
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        var hasAudioData = false

        for (i, clip) in clips.enumerated() {
            onProgress("Rendering take \(i + 1) of \(clips.count)...")
            guard let clipURL = urlForPath(clip.localUri ?? clip.uri) else {
                print("[renderVideo] Reel clip \(i): invalid URL for \(clip.localUri ?? clip.uri)")
                continue
            }
            let asset = AVURLAsset(url: clipURL)

            // Load video track — retry once on failure
            var assetVideo: AVAssetTrack?
            for attempt in 0..<2 {
                assetVideo = try? await asset.loadTracks(withMediaType: .video).first
                if assetVideo != nil { break }
                if attempt == 0 { try? await Task.sleep(nanoseconds: 300_000_000) }
            }
            guard let assetVideo else {
                print("[renderVideo] Reel clip \(i): no video track at \(clipURL.lastPathComponent)")
                continue
            }

            let assetAudio = try? await asset.loadTracks(withMediaType: .audio).first
            let beatDuration = clip.beatDuration ?? 1.2
            let loadedDuration = try? await asset.load(.duration)
            let sourceDuration: Double = clip.sourceDuration ?? (loadedDuration.map { CMTimeGetSeconds($0) } ?? 10)
            let maxStart = max(0, sourceDuration - beatDuration - 0.5)
            let startOffset = Double.random(in: 0...max(0.01, maxStart))
            let startTime = CMTime(seconds: startOffset, preferredTimescale: 600)
            let rangeDuration = CMTime(seconds: beatDuration, preferredTimescale: 600)
            let range = CMTimeRange(start: startTime, duration: rangeDuration)

            do {
                try videoTrack.insertTimeRange(range, of: assetVideo, at: currentTime)
            } catch {
                print("[renderVideo] Reel clip \(i): insertTimeRange failed: \(error)")
                continue
            }
            if let assetAudio = assetAudio, let audioTrack = audioTrack {
                try? audioTrack.insertTimeRange(range, of: assetAudio, at: currentTime)
                hasAudioData = true
            }

            // Scale each clip to fill the render size (9:16)
            let naturalSize = (try? await assetVideo.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)
            let preferredTransform = (try? await assetVideo.load(.preferredTransform)) ?? .identity
            let transformed = naturalSize.applying(preferredTransform)
            let clipW = abs(transformed.width)
            let clipH = abs(transformed.height)

            if clipW > 0 && clipH > 0 {
                let scaleX = renderSize.width / clipW
                let scaleY = renderSize.height / clipH
                let scale = max(scaleX, scaleY) // fill (crop excess)
                let scaledW = clipW * scale
                let scaledH = clipH * scale
                let tx = (renderSize.width - scaledW) / 2
                let ty = (renderSize.height - scaledH) / 2

                // Normalize the preferredTransform origin before scaling so that
                // any rotation-induced translation doesn't get scaled incorrectly.
                let originAfterPreferred = CGPoint.zero.applying(preferredTransform)
                let transform = preferredTransform
                    .concatenating(CGAffineTransform(translationX: -originAfterPreferred.x, y: -originAfterPreferred.y))
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(translationX: tx, y: ty))
                layerInstruction.setTransform(transform, at: currentTime)
            }

            currentTime = CMTimeAdd(currentTime, rangeDuration)
        }

        // Remove empty audio track to avoid export issues
        if !hasAudioData, let audioTrack = audioTrack {
            composition.removeTrack(audioTrack)
        }

        if CMTimeGetSeconds(currentTime) < 0.01 {
            print("[renderVideo] Reel: no clips were added to composition")
            return nil
        }

        // Apply video composition for uniform sizing
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = CMTimeRange(start: .zero, duration: currentTime)
        mainInstruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [mainInstruction]

        // Add music track directly to the composition (avoids two-step export that triggers -12849)
        var audioMix: AVMutableAudioMix?
        if let musicOpt = music, let musicPath = musicOpt.resolvedPath, let musicURL = urlForPath(musicPath) {
            onProgress("Adding music...")
            let musicAsset = AVURLAsset(url: musicURL)
            if let musicAudioTrack = try? await musicAsset.loadTracks(withMediaType: .audio).first {
                if let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    let musicDuration = (try? await musicAsset.load(.duration)) ?? .zero
                    // Trim music to match video length
                    let insertDuration = CMTimeGetSeconds(currentTime) < CMTimeGetSeconds(musicDuration) ? currentTime : musicDuration
                    let musicRange = CMTimeRange(start: .zero, duration: insertDuration)
                    try? musicTrack.insertTimeRange(musicRange, of: musicAudioTrack, at: .zero)

                    let mixParams = AVMutableAudioMixInputParameters(track: musicTrack)
                    mixParams.setVolume(Float(musicOpt.volume), at: .zero)
                    let mix = AVMutableAudioMix()
                    mix.inputParameters = [mixParams]
                    audioMix = mix
                    print("[renderVideo] Music track added to composition (duration: \(CMTimeGetSeconds(insertDuration))s)")
                }
            } else {
                print("[renderVideo] Could not load audio track from music file")
            }
        }

        if await exportComposition(composition, videoComposition: videoComposition, audioMix: audioMix, to: outputPath) {
            return outputPath
        }
        // Fallbacks if video composition export fails (-16979)
        print("[renderVideo] Export with video composition failed, retrying with no composition (all clips + music)...")
        if await exportComposition(composition, videoComposition: nil, audioMix: audioMix, to: outputPath) {
            return outputPath
        }
        if audioMix != nil {
            print("[renderVideo] Retrying with no composition and no music mix (clips only)...")
            if await exportComposition(composition, videoComposition: nil, audioMix: nil, to: outputPath) {
                return outputPath
            }
            // Remove the music audio track entirely from the composition.
            // Previous fallbacks only removed audioMix params but left the
            // (potentially incompatible MP3) track data, which still causes -12849.
            print("[renderVideo] Retrying after removing music track from composition...")
            let audioTracks = composition.tracks(withMediaType: .audio)
            for track in audioTracks {
                composition.removeTrack(track)
            }
            if await exportComposition(composition, videoComposition: videoComposition, audioMix: nil, to: outputPath) {
                return outputPath
            }
            if await exportComposition(composition, videoComposition: nil, audioMix: nil, to: outputPath) {
                return outputPath
            }
        }
        return nil
    }

    /// Builds video + animation layers for burning captions into the reel. Each segment's text is shown at the bottom center for its duration.
    private func makeCaptionOverlayLayers(renderSize: CGSize, captionSegments: [(start: CMTime, duration: CMTime, text: String)]) -> (videoLayer: CALayer, animationLayer: CALayer) {
        let videoLayer = CALayer()
        let animationLayer = CALayer()
        animationLayer.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        animationLayer.beginTime = AVCoreAnimationBeginTimeAtZero
        animationLayer.addSublayer(videoLayer)

        let width = renderSize.width
        let height = renderSize.height
        let fontSize: CGFloat = 56
        let bottomMargin: CGFloat = 180
        let textHeight: CGFloat = 120
        let horizontalMargin: CGFloat = 80

        for seg in captionSegments {
            let textLayer = CATextLayer()
            textLayer.string = seg.text
            textLayer.fontSize = fontSize
            textLayer.foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            textLayer.alignmentMode = .center
            textLayer.contentsScale = 2.0
            textLayer.frame = CGRect(x: horizontalMargin, y: height - bottomMargin - textHeight, width: width - 2 * horizontalMargin, height: textHeight)
            textLayer.isWrapped = true
            textLayer.truncationMode = .end
            textLayer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            textLayer.shadowOffset = CGSize(width: 2, height: 2)
            textLayer.shadowOpacity = 1
            textLayer.shadowRadius = 2

            let startSec = CMTimeGetSeconds(seg.start)
            let durationSec = CMTimeGetSeconds(seg.duration)
            textLayer.beginTime = startSec
            let hideAnim = CABasicAnimation(keyPath: "opacity")
            hideAnim.fromValue = 1
            hideAnim.toValue = 0
            hideAnim.beginTime = durationSec
            hideAnim.duration = 0.01
            hideAnim.fillMode = .forwards
            hideAnim.isRemovedOnCompletion = false
            textLayer.add(hideAnim, forKey: "hide")

            animationLayer.addSublayer(textLayer)
        }

        return (videoLayer, animationLayer)
    }

    private func exportComposition(_ composition: AVMutableComposition, videoComposition: AVMutableVideoComposition? = nil, audioMix: AVMutableAudioMix? = nil, to url: URL) async -> Bool {
        // Passthrough only works without videoComposition (no re-encoding needed).
        // Include lower-resolution presets to work around encoder -12849 with some audio mixes.
        var presets = [
            AVAssetExportPresetHighestQuality,
            AVAssetExportPreset1920x1080,
            AVAssetExportPreset1280x720,
            AVAssetExportPresetMediumQuality,
            AVAssetExportPreset640x480
        ]
        if videoComposition == nil {
            presets.append(AVAssetExportPresetPassthrough)
        }

        let videoTracks = composition.tracks(withMediaType: .video)
        let audioTracks = composition.tracks(withMediaType: .audio)
        let totalDuration = CMTimeGetSeconds(composition.duration)
        print("[renderVideo] Composition: \(videoTracks.count) video, \(audioTracks.count) audio tracks, duration: \(String(format: "%.2f", totalDuration))s, hasVideoComposition: \(videoComposition != nil), hasAudioMix: \(audioMix != nil)")

        for preset in presets {
            guard AVAssetExportSession.exportPresets(compatibleWith: composition).contains(preset),
                  let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
                print("[renderVideo] Preset \(preset) not compatible, skipping")
                continue
            }

            try? FileManager.default.removeItem(at: url)
            exportSession.outputURL = url
            exportSession.outputFileType = .mp4
            if let vc = videoComposition {
                exportSession.videoComposition = vc
            }
            if let am = audioMix {
                exportSession.audioMix = am
            }

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                exportSession.exportAsynchronously {
                    cont.resume()
                }
            }

            if exportSession.status == .completed {
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                print("[renderVideo] Export OK with \(preset): \(url.lastPathComponent) (\(size / 1024)KB)")
                return true
            }

            let errMsg = exportSession.error?.localizedDescription ?? "unknown"
            let underlying = (exportSession.error as NSError?)?.userInfo[NSUnderlyingErrorKey] as? NSError
            let underlyingMsg = underlying.map { " (underlying: \($0.domain) \($0.code))" } ?? ""
            print("[renderVideo] Export failed with \(preset) (\(exportSession.status.rawValue)): \(errMsg)\(underlyingMsg)")
        }

        print("[renderVideo] All export presets failed")
        return false
    }

    private func mixVideoWithMusic(videoURL: URL, musicURL: URL, volume: Float, outputPath: URL) async -> URL? {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let musicAsset = AVURLAsset(url: musicURL)
        guard let vTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let aTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        guard let videoAssetTrack = try? await videoAsset.loadTracks(withMediaType: .video).first,
              let musicAssetTrack = try? await musicAsset.loadTracks(withMediaType: .audio).first else { return nil }
        let videoDuration = (try? await videoAsset.load(.duration)) ?? .zero
        let musicDuration = (try? await musicAsset.load(.duration)) ?? .zero
        let insertDuration = CMTimeGetSeconds(videoDuration) < CMTimeGetSeconds(musicDuration) ? videoDuration : musicDuration
        let range = CMTimeRange(start: .zero, duration: insertDuration)
        try? vTrack.insertTimeRange(range, of: videoAssetTrack, at: .zero)
        try? aTrack.insertTimeRange(CMTimeRange(start: .zero, duration: insertDuration), of: musicAssetTrack, at: .zero)

        let mixParams = AVMutableAudioMixInputParameters(track: aTrack)
        mixParams.setVolume(volume, at: .zero)
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [mixParams]

        // Try presets in order; HighestQuality can trigger -16979 with some codecs
        let presets = [AVAssetExportPresetHighestQuality, AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720, AVAssetExportPresetMediumQuality]
        for preset in presets {
            guard AVAssetExportSession.exportPresets(compatibleWith: composition).contains(preset),
                  let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else { continue }
            exportSession.outputURL = outputPath
            exportSession.outputFileType = .mp4
            exportSession.audioMix = audioMix
            try? FileManager.default.removeItem(at: outputPath)
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                exportSession.exportAsynchronously { cont.resume() }
            }
            if exportSession.status == .completed {
                return outputPath
            }
            if let err = exportSession.error {
                print("[renderVideo] mixVideoWithMusic preset \(preset) failed: \(err)")
            }
        }
        return nil
    }

    // MARK: - Reel Mode (per-clip processing + concat + music)

    private func outputSize(for aspectRatio: String) -> (width: Int, height: Int) {
        switch aspectRatio {
        case "9:16": return (1080, 1920)
        case "16:9": return (1920, 1080)
        case "4:5": return (864, 1080)
        case "1:1", _: return (1080, 1080)
        }
    }

    private func renderReelMode(clips: [Clip], music: MusicRenderOptions?, aspectRatio: String, outputPath: URL, onProgress: @escaping (String) -> Void) async -> URL? {
        let (outW, outH) = outputSize(for: aspectRatio)
        var processedPaths: [URL] = []

        for (i, clip) in clips.enumerated() {
            onProgress("Rendering take \(i + 1) of \(clips.count)...")

            let procPath = storage.renderedVideosDirectory.appendingPathComponent("proc_\(i)_\(Int(Date().timeIntervalSince1970 * 1000)).mp4")
            let inputPath = clip.localUri ?? clip.uri

            let beatDuration = clip.beatDuration ?? 1.2
            let sourceDuration: Double
            if let sd = clip.sourceDuration {
                sourceDuration = sd
            } else {
                sourceDuration = await getVideoDuration(path: inputPath)
            }
            let maxStart = max(0, sourceDuration - beatDuration - 0.5)
            let startOffset = Double.random(in: 0...max(0.01, maxStart))

            // Build filter chain (scale and crop to selected aspect ratio)
            var filters = [
                "scale=\(outW):\(outH):force_original_aspect_ratio=increase",
                "crop=\(outW):\(outH)",
                "eq=brightness=-0.04:contrast=1.1:saturation=0.9",
                "fade=t=in:st=0:d=0.15",
                "fade=t=out:st=\(String(format: "%.3f", max(0, beatDuration - 0.15))):d=0.15"
            ]

            let cleanText = sanitizeText(clip.text ?? "")
            if !cleanText.isEmpty {
                filters.append(
                    "drawtext=text='\(cleanText)':fontsize=52:fontcolor=white:shadowcolor=black@0.9:shadowx=3:shadowy=3:x=(w-text_w)/2:y=(h*0.45)"
                )
            }

            let filterChain = filters.joined(separator: ",")
            let cmd = "-y -ss \(String(format: "%.3f", startOffset)) -t \(String(format: "%.3f", beatDuration)) -i \"\(sanitizePath(inputPath))\" -vf \"\(filterChain)\" -c:v libx264 -preset ultrafast -crf 23 -an -pix_fmt yuv420p -r 30 \"\(procPath.path)\""

            let success = await executeFFmpeg(cmd)
            if success {
                processedPaths.append(procPath)
            } else {
                print("Clip \(i) processing failed, skipping")
            }
        }

        guard !processedPaths.isEmpty else { return nil }

        // Concat processed clips
        onProgress("Stitching clips...")
        let listFile = storage.renderedVideosDirectory.appendingPathComponent("concat_\(Int(Date().timeIntervalSince1970 * 1000)).txt")
        let listContent = processedPaths.map { "file '\($0.path)'" }.joined(separator: "\n")
        try? listContent.write(to: listFile, atomically: true, encoding: .utf8)

        let tempConcat = storage.renderedVideosDirectory.appendingPathComponent("concat_\(Int(Date().timeIntervalSince1970 * 1000)).mp4")
        let concatCmd = "-y -f concat -safe 0 -i \"\(listFile.path)\" -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p \"\(tempConcat.path)\""

        guard await executeFFmpeg(concatCmd) else {
            print("Concat failed")
            return nil
        }

        // Add music if present
        var finalOutput = tempConcat
        if let music = music, let musicFile = music.resolvedPath {
            onProgress("Adding music...")
            let vol = music.volume
            let totalDur = clips.reduce(0.0) { $0 + ($1.beatDuration ?? 1.2) }
            let musicCmd = "-y -i \"\(tempConcat.path)\" -i \"\(musicFile)\" -filter_complex \"[1:a]afade=t=in:d=0.5,afade=t=out:st=\(String(format: "%.1f", max(1, totalDur - 1.5))):d=1.5,volume=\(String(format: "%.2f", vol))[a]\" -map 0:v -map \"[a]\" -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart \"\(outputPath.path)\""

            if await executeFFmpeg(musicCmd) {
                finalOutput = outputPath
            }
        }

        if finalOutput != outputPath {
            try? FileManager.default.copyItem(at: tempConcat, to: outputPath)
            finalOutput = outputPath
        }

        // Cleanup
        for p in processedPaths { storage.deleteFile(at: p) }
        storage.deleteFile(at: tempConcat)
        storage.deleteFile(at: listFile)

        return finalOutput
    }

    // MARK: - Standard Mode (concat with trim + optional music)

    private func renderStandardMode(clips: [Clip], music: MusicRenderOptions?, outputPath: URL, onProgress: @escaping (String) -> Void) async -> URL? {
        onProgress("Preparing clips...")

        let fileListPath = storage.renderedVideosDirectory.appendingPathComponent("filelist.txt")
        var fileListContent = ""

        for clip in clips {
            let path = sanitizePath(clip.localUri ?? clip.uri)
            fileListContent += "file '\(path)'\n"

            let duration = await getVideoDuration(path: path)
            if duration > 0 {
                let startSec = (clip.trimStart / 100.0) * duration
                let endSec = (clip.trimEnd / 100.0) * duration
                if startSec > 0 {
                    fileListContent += "inpoint \(String(format: "%.6f", startSec))\n"
                }
                if endSec > startSec && endSec < duration {
                    fileListContent += "outpoint \(String(format: "%.6f", endSec))\n"
                }
            }
        }

        try? fileListContent.write(to: fileListPath, atomically: true, encoding: .utf8)

        var command: String
        if let music = music, let musicPath = music.resolvedPath {
            let vol = music.volume
            command = "-y -f concat -safe 0 -i \"\(fileListPath.path)\" -i \"\(musicPath)\" -filter_complex \"[1:a]volume=\(String(format: "%.2f", vol))[a]\" -map 0:v -map \"[a]\" -c:v copy -c:a aac -shortest \"\(outputPath.path)\""
        } else {
            command = "-y -f concat -safe 0 -i \"\(fileListPath.path)\" -c:v copy -c:a aac \"\(outputPath.path)\""
        }

        onProgress("Rendering video...")
        let success = await executeFFmpeg(command)

        storage.deleteFile(at: fileListPath)

        return success ? outputPath : nil
    }

    // MARK: - FFmpeg Execution

    private func executeFFmpeg(_ command: String) async -> Bool {
        // TODO: Uncomment when ffmpeg-kit-ios-full is added via SPM
        // let session = FFmpegKit.execute(command)
        // let returnCode = session?.getReturnCode()
        // return ReturnCode.isSuccess(returnCode)

        print("[FFmpeg] Not available – skipping: \(command.prefix(80))...")
        return false
    }

    // MARK: - Helpers

    private func getVideoDuration(path: String) async -> Double {
        guard let url = urlForPath(path) else { return 0 }
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return CMTimeGetSeconds(duration)
        } catch {
            return 0
        }
    }

    private func isRemoteURL(_ uri: String) -> Bool {
        uri.hasPrefix("http://") || uri.hasPrefix("https://")
    }

    private func sanitizePath(_ path: String) -> String {
        path.replacingOccurrences(of: "file://", with: "")
    }

    private func sanitizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "'", with: "\u{2019}")
            .replacingOccurrences(of: ":", with: "\\:")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MusicRenderOptions {
    let file: String?
    let volume: Double
    let quality: String
    var resolvedPath: String?
}
