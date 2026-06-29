import Foundation
import AVFoundation
import CoreText
import QuartzCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// NOTE: This service requires ffmpeg-kit-ios-full SPM package.
// Import FFmpegKit when the package is added to the Xcode project:
// import FFmpegKit

class VideoRenderService {
    static let shared = VideoRenderService()

    private let storage = FileStorageService.shared

    typealias ProgressCallback = (String) -> Void

    // MARK: - Main Render Entry

    func renderVideo(clips: [Clip], music: MusicRenderOptions?, additionalMusic: [MusicRenderOptions] = [], voiceover: VoiceoverRenderOptions? = nil, aspectRatio: String = "1:1", includeBranding: Bool = true, onProgress: ProgressCallback?) async -> URL? {
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

        let requiresExternalAudio = ([music].compactMap { $0 } + additionalMusic).contains { !$0.isMuted } || (voiceover?.isMuted == false)

        if isReelMode {
            if let url = await renderReelModeWithAVFoundation(clips: localClips, music: music, additionalMusic: additionalMusic, voiceover: voiceover, outputPath: outputPath, includeBranding: includeBranding, onProgress: report) {
                return url
            }
            if let url = await renderReelMode(clips: localClips, music: music, aspectRatio: aspectRatio, outputPath: outputPath, includeBranding: includeBranding, onProgress: report) {
                return url
            }
        } else {
            if let url = await renderStandardModeWithAVFoundation(clips: localClips, music: music, additionalMusic: additionalMusic, voiceover: voiceover, outputPath: outputPath, includeBranding: includeBranding, onProgress: report) {
                return url
            }
            if let url = await renderStandardMode(clips: localClips, music: music, voiceover: voiceover, outputPath: outputPath, includeBranding: includeBranding, onProgress: report) {
                return url
            }
        }
        if requiresExternalAudio {
            print("[renderVideo] Export failed with required external audio; refusing silent fallback")
            return nil
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

    private func addMusicTracks(
        _ musicOptions: [MusicRenderOptions],
        to composition: AVMutableComposition,
        videoDuration: CMTime,
        existingAudioMix: AVMutableAudioMix?,
        onProgress: @escaping (String) -> Void
    ) async -> AVMutableAudioMix? {
        var audioMix = existingAudioMix
        var mixParams = audioMix?.inputParameters ?? []

        for (index, musicOpt) in musicOptions.enumerated() {
            guard !musicOpt.isMuted else { continue }
            guard let musicPath = musicOpt.resolvedPath ?? musicOpt.file,
                  let musicURL = urlForPath(musicPath) else { continue }
            onProgress(index == 0 ? "Adding music..." : "Adding audio row \(index + 1)...")
            let musicAsset = AVURLAsset(url: musicURL)
            guard let musicAudioTrack = try? await musicAsset.loadTracks(withMediaType: .audio).first,
                  let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }

            let musicDuration = (try? await musicAsset.load(.duration)) ?? .zero
            let videoSeconds = CMTimeGetSeconds(videoDuration)
            let startSeconds = max(0, min(musicOpt.timelineStart, videoSeconds))
            let endSeconds = max(startSeconds, min(musicOpt.timelineEnd ?? videoSeconds, videoSeconds))
            let timelineDuration = max(0, endSeconds - startSeconds)
            let musicDurationSeconds = max(0, CMTimeGetSeconds(musicDuration))
            guard timelineDuration > 0, musicDurationSeconds > 0 else { continue }

            var insertedSeconds: Double = 0
            while insertedSeconds < timelineDuration - 0.01 {
                let segmentSeconds = min(musicDurationSeconds, timelineDuration - insertedSeconds)
                let insertAt = CMTime(seconds: startSeconds + insertedSeconds, preferredTimescale: 600)
                let segmentDuration = CMTime(seconds: segmentSeconds, preferredTimescale: 600)
                try? musicTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: segmentDuration),
                    of: musicAudioTrack,
                    at: insertAt
                )
                insertedSeconds += segmentSeconds
            }

            let params = AVMutableAudioMixInputParameters(track: musicTrack)
            params.setVolume(Float(musicOpt.volume), at: CMTime(seconds: startSeconds, preferredTimescale: 600))
            mixParams.append(params)
        }

        guard !mixParams.isEmpty else { return audioMix }
        let mix = audioMix ?? AVMutableAudioMix()
        mix.inputParameters = mixParams
        return mix
    }

    private func addVoiceoverTrack(
        _ voiceover: VoiceoverRenderOptions?,
        to composition: AVMutableComposition,
        videoDuration: CMTime,
        existingAudioMix: AVMutableAudioMix?,
        onProgress: @escaping (String) -> Void
    ) async -> AVMutableAudioMix? {
        var audioMix = existingAudioMix
        guard let vo = voiceover, !vo.isMuted else { return audioMix }

        onProgress("Adding voiceover...")
        let voAsset = AVURLAsset(url: vo.fileURL)
        guard let voAudioTrack = try? await voAsset.loadTracks(withMediaType: .audio).first,
              let voTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return audioMix }

        let voDuration = (try? await voAsset.load(.duration)) ?? .zero
        let videoDurationSeconds = max(0, CMTimeGetSeconds(videoDuration))
        let voDurationSeconds = max(0, CMTimeGetSeconds(voDuration))
        let timelineStart = max(0, min(vo.timelineStart, videoDurationSeconds))
        let timelineEnd = max(timelineStart, min(vo.timelineEnd ?? videoDurationSeconds, videoDurationSeconds))
        let requestedDuration = max(0, timelineEnd - timelineStart)
        let insertDurationSeconds = min(requestedDuration, voDurationSeconds)
        guard insertDurationSeconds > 0 else { return audioMix }

        let insertAt = CMTime(seconds: timelineStart, preferredTimescale: 600)
        let insertDuration = CMTime(seconds: insertDurationSeconds, preferredTimescale: 600)
        let voRange = CMTimeRange(start: .zero, duration: insertDuration)
        try? voTrack.insertTimeRange(voRange, of: voAudioTrack, at: insertAt)

        let voMixParams = AVMutableAudioMixInputParameters(track: voTrack)
        voMixParams.setVolume(Float(vo.volume), at: insertAt)

        let mix = audioMix ?? AVMutableAudioMix()
        mix.inputParameters = mix.inputParameters + [voMixParams]
        audioMix = mix
        return audioMix
    }

    private func applyTransitions(
        to layerInstruction: AVMutableVideoCompositionLayerInstruction,
        segments: [(start: CMTime, duration: CMTime, clip: Clip)]
    ) {
        guard segments.count > 1 else { return }

        for index in 0..<(segments.count - 1) {
            let segment = segments[index]
            let next = segments[index + 1]
            let transition = segment.clip.transitionName
            guard transition != "None" else { continue }

            let segmentSeconds = CMTimeGetSeconds(segment.duration)
            let nextSeconds = CMTimeGetSeconds(next.duration)
            guard segmentSeconds > 0.2, nextSeconds > 0.2 else { continue }

            let requested = max(0.1, min(1.2, segment.clip.transitionDuration))
            let durationSeconds = min(requested, segmentSeconds * 0.45, nextSeconds * 0.45)
            guard durationSeconds > 0.05 else { continue }

            let transitionDuration = CMTime(seconds: durationSeconds, preferredTimescale: 600)
            let fadeOutStart = CMTimeSubtract(CMTimeAdd(segment.start, segment.duration), transitionDuration)
            let fadeInStart = next.start

            layerInstruction.setOpacityRamp(
                fromStartOpacity: 1,
                toEndOpacity: 0,
                timeRange: CMTimeRange(start: fadeOutStart, duration: transitionDuration)
            )

            layerInstruction.setOpacityRamp(
                fromStartOpacity: 0,
                toEndOpacity: 1,
                timeRange: CMTimeRange(start: fadeInStart, duration: transitionDuration)
            )

            if transition == "Dip" {
                let holdStart = CMTimeSubtract(CMTimeAdd(segment.start, segment.duration), CMTime(seconds: min(0.08, durationSeconds / 2), preferredTimescale: 600))
                layerInstruction.setOpacity(0, at: holdStart)
            }
        }
    }

    private func adjustedTransform(base: CGAffineTransform, renderSize: CGSize, clip: Clip) -> CGAffineTransform {
        let clampedX = CGFloat(max(0.08, min(0.92, clip.videoX)))
        let clampedY = CGFloat(max(0.08, min(0.92, clip.videoY)))

        if clip.videoLayoutMode == "PiP" {
            let scale = CGFloat(max(0.18, min(0.85, clip.videoScale)))
            let targetW = renderSize.width * scale
            let targetH = renderSize.height * scale
            let x = (renderSize.width * clampedX) - (targetW / 2)
            let y = (renderSize.height * clampedY) - (targetH / 2)
            return base
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: x, y: y))
        }

        return base
    }

    private func renderStandardModeWithAVFoundation(clips: [Clip], music: MusicRenderOptions?, additionalMusic: [MusicRenderOptions] = [], voiceover: VoiceoverRenderOptions? = nil, outputPath: URL, includeBranding: Bool, onProgress: @escaping (String) -> Void) async -> URL? {
        onProgress("Preparing clips...")
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        let addOriginalAudio = music == nil && additionalMusic.isEmpty
        let audioTrack: AVMutableCompositionTrack? = addOriginalAudio ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) : nil

        var currentTime = CMTime.zero
        var renderSize = CGSize(width: 1920, height: 1080)
        var firstTrackTransform: CGAffineTransform = .identity
        var clipSegments: [(start: CMTime, duration: CMTime, clip: Clip)] = []
        var clipAudioMixParams: AVMutableAudioMixInputParameters?
        if let audioTrack {
            clipAudioMixParams = AVMutableAudioMixInputParameters(track: audioTrack)
        }

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
            if !clip.isMuted, let audioTrack = audioTrack, let assetAudio = try? await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: assetAudio, at: currentTime)
                clipAudioMixParams?.setVolume(Float(max(0, min(1, clip.audioVolume))), at: currentTime)
            }

            if i == 0 {
                let naturalSize = (try? await assetVideo.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)
                let preferredTransform = (try? await assetVideo.load(.preferredTransform)) ?? .identity
                firstTrackTransform = preferredTransform
                renderSize = naturalSize.applying(preferredTransform)
                renderSize = CGSize(width: abs(renderSize.width), height: abs(renderSize.height))
                if renderSize.width < 1 || renderSize.height < 1 { renderSize = CGSize(width: 1920, height: 1080) }
            }

            // Apply speed change: scaleTimeRange stretches/compresses the inserted segment
            let speed = max(0.1, min(5.0, clip.speed))
            let insertedRange = CMTimeRange(start: currentTime, duration: rangeDuration)
            let segmentStart = currentTime
            let segmentDuration: CMTime
            if abs(speed - 1.0) > 0.01 {
                let scaledDuration = CMTimeMultiplyByFloat64(rangeDuration, multiplier: 1.0 / speed)
                videoTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                if let audioTrack = audioTrack {
                    audioTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                }
                segmentDuration = scaledDuration
                currentTime = CMTimeAdd(currentTime, scaledDuration)
            } else {
                segmentDuration = rangeDuration
                currentTime = CMTimeAdd(currentTime, rangeDuration)
            }
            clipSegments.append((start: segmentStart, duration: segmentDuration, clip: clip))
        }

        if CMTimeGetSeconds(currentTime) < 0.01 { return nil }

        // Add music track directly to the composition (avoids two-step export)
        var audioMix: AVMutableAudioMix?
        if let clipAudioMixParams {
            let mix = AVMutableAudioMix()
            mix.inputParameters = [clipAudioMixParams]
            audioMix = mix
        }
        let musicOptions = [music].compactMap { $0 } + additionalMusic
        let requiresExternalAudio = musicOptions.contains { !$0.isMuted } || (voiceover?.isMuted == false)
        if !requiresExternalAudio {
            audioMix = await addMusicTracks(musicOptions, to: composition, videoDuration: currentTime, existingAudioMix: audioMix, onProgress: onProgress)
            audioMix = await addVoiceoverTrack(voiceover, to: composition, videoDuration: currentTime, existingAudioMix: audioMix, onProgress: onProgress)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: currentTime)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(firstTrackTransform, at: .zero)
        for segment in clipSegments {
            layerInstruction.setTransform(
                adjustedTransform(base: firstTrackTransform, renderSize: renderSize, clip: segment.clip),
                at: segment.start
            )
        }
        applyTransitions(to: layerInstruction, segments: clipSegments)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Add CreatorAI branding (watermark + outro card)
        var brandedComposition = videoComposition
        if includeBranding {
            addBranding(to: composition, videoComposition: &brandedComposition, videoDuration: currentTime, clips: clips)
        }

        if requiresExternalAudio {
            print("[renderVideo] Required audio present; rendering video first, then muxing audio")
            if let mixed = await renderVideoOnlyThenMixExternalAudio(
                composition: composition,
                videoComposition: brandedComposition,
                musicOptions: musicOptions,
                voiceover: voiceover,
                outputPath: outputPath,
                onProgress: onProgress
            ) {
                return mixed
            }
            print("[renderVideo] Required audio mux failed")
            return nil
        }

        if await exportComposition(composition, videoComposition: brandedComposition, audioMix: audioMix, to: outputPath) {
            return outputPath
        }
        print("[renderVideo] Standard export failed, retrying with no composition...")
        if await exportComposition(composition, videoComposition: nil, audioMix: audioMix, to: outputPath) {
            return outputPath
        }
        if requiresExternalAudio {
            print("[renderVideo] External audio export failed, trying video-only render then audio mux...")
            if let mixed = await renderVideoOnlyThenMixExternalAudio(
                composition: composition,
                videoComposition: brandedComposition,
                musicOptions: musicOptions,
                voiceover: voiceover,
                outputPath: outputPath,
                onProgress: onProgress
            ) {
                return mixed
            }
            print("[renderVideo] External audio fallback failed")
            return nil
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

    private func renderReelModeWithAVFoundation(clips: [Clip], music: MusicRenderOptions?, additionalMusic: [MusicRenderOptions] = [], voiceover: VoiceoverRenderOptions? = nil, outputPath: URL, includeBranding: Bool, onProgress: @escaping (String) -> Void) async -> URL? {
        let hasPerClipBurnIn = clips.contains {
            ($0.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) || $0.overlayImageUri != nil
        }
        if hasPerClipBurnIn {
            return await renderReelModeByBurningClipsThenMerging(
                clips: clips,
                music: music,
                additionalMusic: additionalMusic,
                voiceover: voiceover,
                outputPath: outputPath,
                includeBranding: includeBranding,
                onProgress: onProgress
            )
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        // When music is present, keep clips muted (no clip audio) so we only have 1 audio track — avoids -12849 and keeps music mandatory.
        let audioTrack: AVMutableCompositionTrack? = (music == nil && additionalMusic.isEmpty)
            ? composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        var currentTime = CMTime.zero
        let renderSize = CGSize(width: 1080, height: 1920)
        var clipAudioMixParams: AVMutableAudioMixInputParameters?
        if let audioTrack {
            clipAudioMixParams = AVMutableAudioMixInputParameters(track: audioTrack)
        }

        // Use a SINGLE layer instruction for the single video track.
        // Multiple layer instructions for the same track causes AVAssetExportSession error -16979.
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        var hasAudioData = false
        var clipSegments: [(start: CMTime, duration: CMTime, clip: Clip)] = []

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
            if !clip.isMuted, let assetAudio = assetAudio, let audioTrack = audioTrack {
                try? audioTrack.insertTimeRange(range, of: assetAudio, at: currentTime)
                clipAudioMixParams?.setVolume(Float(max(0, min(1, clip.audioVolume))), at: currentTime)
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
                let baseTransform = preferredTransform
                    .concatenating(CGAffineTransform(translationX: -originAfterPreferred.x, y: -originAfterPreferred.y))
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(translationX: tx, y: ty))
                let transform = adjustedTransform(base: baseTransform, renderSize: renderSize, clip: clip)
                layerInstruction.setTransform(transform, at: currentTime)
            }

            clipSegments.append((start: currentTime, duration: rangeDuration, clip: clip))
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
        var videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = CMTimeRange(start: .zero, duration: currentTime)
        applyTransitions(to: layerInstruction, segments: clipSegments)
        mainInstruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [mainInstruction]
        if includeBranding {
            addBranding(to: composition, videoComposition: &videoComposition, videoDuration: currentTime, segments: clipSegments)
        }

        // Add music track directly to the composition (avoids two-step export that triggers -12849)
        var audioMix: AVMutableAudioMix?
        if let clipAudioMixParams, hasAudioData {
            let mix = AVMutableAudioMix()
            mix.inputParameters = [clipAudioMixParams]
            audioMix = mix
        }
        let musicOptions = [music].compactMap { $0 } + additionalMusic
        let requiresExternalAudio = musicOptions.contains { !$0.isMuted } || (voiceover?.isMuted == false)
        if !requiresExternalAudio {
            audioMix = await addMusicTracks(musicOptions, to: composition, videoDuration: currentTime, existingAudioMix: audioMix, onProgress: onProgress)
            audioMix = await addVoiceoverTrack(voiceover, to: composition, videoDuration: currentTime, existingAudioMix: audioMix, onProgress: onProgress)
        }

        if requiresExternalAudio {
            print("[renderVideo] Required audio present; rendering reel video first, then muxing audio")
            if let mixed = await renderVideoOnlyThenMixExternalAudio(
                composition: composition,
                videoComposition: videoComposition,
                musicOptions: musicOptions,
                voiceover: voiceover,
                outputPath: outputPath,
                onProgress: onProgress
            ) {
                return mixed
            }
            print("[renderVideo] Required audio mux failed")
            return nil
        }

        if await exportComposition(composition, videoComposition: videoComposition, audioMix: audioMix, to: outputPath) {
            return outputPath
        }
        // Fallbacks if video composition export fails (-16979)
        let hasBurnedOverlays = clips.contains {
            ($0.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) || $0.overlayImageUri != nil
        }
        if hasBurnedOverlays {
            print("[renderVideo] Reel export with captions failed; refusing no-composition fallback that would drop subtitles")
            return nil
        }
        print("[renderVideo] Export with video composition failed, retrying with no composition (all clips + music)...")
        if await exportComposition(composition, videoComposition: nil, audioMix: audioMix, to: outputPath) {
            return outputPath
        }
        if requiresExternalAudio {
            print("[renderVideo] External audio export failed, trying video-only render then audio mux...")
            if let mixed = await renderVideoOnlyThenMixExternalAudio(
                composition: composition,
                videoComposition: videoComposition,
                musicOptions: musicOptions,
                voiceover: voiceover,
                outputPath: outputPath,
                onProgress: onProgress
            ) {
                return mixed
            }
            print("[renderVideo] External audio fallback failed")
            return nil
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

    private func renderReelModeByBurningClipsThenMerging(
        clips: [Clip],
        music: MusicRenderOptions?,
        additionalMusic: [MusicRenderOptions],
        voiceover: VoiceoverRenderOptions?,
        outputPath: URL,
        includeBranding: Bool,
        onProgress: @escaping (String) -> Void
    ) async -> URL? {
        let renderSize = CGSize(width: 1080, height: 1920)
        var renderedClipURLs: [URL] = []

        for (index, clip) in clips.enumerated() {
            onProgress("Burning caption \(index + 1) of \(clips.count)...")
            let clipOutput = storage.renderedVideosDirectory
                .appendingPathComponent("burned_clip_\(index)_\(UUID().uuidString).mp4")
            guard let rendered = await renderSingleReelClipWithBurnIn(
                clip: clip,
                index: index,
                outputURL: clipOutput,
                renderSize: renderSize,
                includeBranding: includeBranding
            ) else {
                print("[renderVideo] Per-clip burn failed for clip \(index)")
                continue
            }
            renderedClipURLs.append(rendered)
        }

        guard !renderedClipURLs.isEmpty else { return nil }

        onProgress("Merging rendered clips...")
        let mergedComposition = AVMutableComposition()
        guard let mergedVideoTrack = mergedComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }
        let mergedAudioTrack = mergedComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        var hasMergedAudio = false

        for url in renderedClipURLs {
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)) ?? .zero
            guard CMTimeGetSeconds(duration) > 0,
                  let sourceVideo = try? await asset.loadTracks(withMediaType: .video).first else { continue }

            do {
                try mergedVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: cursor)
                if let sourceAudio = try? await asset.loadTracks(withMediaType: .audio).first,
                   let mergedAudioTrack {
                    try? mergedAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceAudio, at: cursor)
                    hasMergedAudio = true
                }
                cursor = CMTimeAdd(cursor, duration)
            } catch {
                print("[renderVideo] Merge burned clip failed: \(error)")
            }
        }

        if !hasMergedAudio, let mergedAudioTrack {
            mergedComposition.removeTrack(mergedAudioTrack)
        }

        guard CMTimeGetSeconds(cursor) > 0 else { return nil }

        let musicOptions = [music].compactMap { $0 } + additionalMusic
        let requiresExternalAudio = musicOptions.contains { !$0.isMuted } || (voiceover?.isMuted == false)
        if requiresExternalAudio {
            let tempVideo = outputPath
                .deletingLastPathComponent()
                .appendingPathComponent("burned_merged_video_\(UUID().uuidString).mp4")
            guard await exportComposition(mergedComposition, videoComposition: nil, audioMix: nil, to: tempVideo) else {
                return nil
            }
            defer { try? FileManager.default.removeItem(at: tempVideo) }
            guard let mixed = await mixRenderedVideoWithExternalAudio(
                videoURL: tempVideo,
                musicOptions: musicOptions,
                voiceover: voiceover,
                outputPath: outputPath,
                onProgress: onProgress
            ) else {
                return nil
            }
            renderedClipURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            return mixed
        }

        let success = await exportComposition(mergedComposition, videoComposition: nil, audioMix: nil, to: outputPath)
        renderedClipURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        return success ? outputPath : nil
    }

    private func renderSingleReelClipWithBurnIn(
        clip: Clip,
        index: Int,
        outputURL: URL,
        renderSize: CGSize,
        includeBranding: Bool
    ) async -> URL? {
        guard let clipURL = urlForPath(clip.localUri ?? clip.uri) else { return nil }
        let asset = AVURLAsset(url: clipURL)
        guard let assetVideo = try? await asset.loadTracks(withMediaType: .video).first else {
            print("[renderVideo] Burn clip \(index): no video track")
            return nil
        }

        let loadedDuration = try? await asset.load(.duration)
        let sourceDuration = max(0.1, clip.sourceDuration ?? (loadedDuration.map { CMTimeGetSeconds($0) } ?? 10))
        let beatDuration = max(0.1, min(clip.beatDuration ?? sourceDuration, sourceDuration))
        let maxStart = max(0, sourceDuration - beatDuration)
        let startOffset = Double.random(in: 0...max(0.01, maxStart))
        let rangeDuration = CMTime(seconds: beatDuration, preferredTimescale: 600)
        let range = CMTimeRange(
            start: CMTime(seconds: startOffset, preferredTimescale: 600),
            duration: rangeDuration
        )

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }

        do {
            try videoTrack.insertTimeRange(range, of: assetVideo, at: .zero)
        } catch {
            print("[renderVideo] Burn clip \(index): insert video failed \(error)")
            return nil
        }

        if !clip.isMuted,
           let assetAudio = try? await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audioTrack.insertTimeRange(range, of: assetAudio, at: .zero)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: rangeDuration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

        let naturalSize = (try? await assetVideo.load(.naturalSize)) ?? CGSize(width: 1920, height: 1080)
        let preferredTransform = (try? await assetVideo.load(.preferredTransform)) ?? .identity
        let transformed = naturalSize.applying(preferredTransform)
        let clipW = abs(transformed.width)
        let clipH = abs(transformed.height)
        if clipW > 0 && clipH > 0 {
            let scale = max(renderSize.width / clipW, renderSize.height / clipH)
            let scaledW = clipW * scale
            let scaledH = clipH * scale
            let tx = (renderSize.width - scaledW) / 2
            let ty = (renderSize.height - scaledH) / 2
            let originAfterPreferred = CGPoint.zero.applying(preferredTransform)
            let baseTransform = preferredTransform
                .concatenating(CGAffineTransform(translationX: -originAfterPreferred.x, y: -originAfterPreferred.y))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: tx, y: ty))
            layerInstruction.setTransform(adjustedTransform(base: baseTransform, renderSize: renderSize, clip: clip), at: .zero)
        }

        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        var compositionWithOverlay = videoComposition
        if includeBranding {
            addBranding(
                to: composition,
                videoComposition: &compositionWithOverlay,
                videoDuration: rangeDuration,
                segments: [(start: .zero, duration: rangeDuration, clip: clip)]
            )
        }

        guard await exportComposition(composition, videoComposition: compositionWithOverlay, audioMix: nil, to: outputURL),
              storage.fileExists(at: outputURL),
              (storage.fileSize(at: outputURL) ?? 0) > 1000 else {
            return nil
        }

        return outputURL
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

    // MARK: - CreatorAI Branding (watermark + outro)

    /// Adds a small CreatorAI logo watermark (bottom-right) and a 2s outro card.
    private func addBranding(to composition: AVMutableComposition, videoComposition: inout AVMutableVideoComposition, videoDuration: CMTime, clips: [Clip] = []) {
        let segments = timelineSegments(from: clips)
        addBranding(to: composition, videoComposition: &videoComposition, videoDuration: videoDuration, segments: segments)
    }

    private func addBranding(to composition: AVMutableComposition, videoComposition: inout AVMutableVideoComposition, videoDuration: CMTime, segments: [(start: CMTime, duration: CMTime, clip: Clip)]) {
        let renderSize = videoComposition.renderSize
        guard renderSize.width > 0, renderSize.height > 0 else { return }

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)

        let animationLayer = CALayer()
        animationLayer.frame = CGRect(origin: .zero, size: renderSize)
        animationLayer.beginTime = AVCoreAnimationBeginTimeAtZero
        animationLayer.addSublayer(videoLayer)

        for segment in segments {
            let clip = segment.clip
            let clipStart = max(0, CMTimeGetSeconds(segment.start))
            let clipDuration = max(0.05, CMTimeGetSeconds(segment.duration))
            if let text = clip.text?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                let textStart = max(0, min(100, clip.textStart)) / 100.0
                let textEnd = max(textStart + 0.01, min(100, clip.textEnd) / 100.0)
                let begin = clipStart + clipDuration * textStart
                let duration = max(0.05, clipDuration * (textEnd - textStart))
                let textLayer = Self.captionTextLayer(
                    text: text,
                    fontName: clip.textFontName,
                    renderSize: renderSize,
                    x: clip.textX,
                    y: clip.textY,
                    beginTime: begin,
                    duration: duration
                )
                animationLayer.addSublayer(textLayer)
            }

            if let overlayPath = clip.overlayImageUri,
               let image = Self.image(at: overlayPath)?.platformCGImage {
                let size = min(renderSize.width, renderSize.height) * CGFloat(max(0.08, min(0.65, clip.overlayScale)))
                let centerX = renderSize.width * CGFloat(max(0.08, min(0.92, clip.overlayX)))
                let centerYFromTop = renderSize.height * CGFloat(max(0.08, min(0.92, clip.overlayY)))
                let logoLayer = CALayer()
                logoLayer.contents = image
                logoLayer.contentsGravity = .resizeAspect
                logoLayer.frame = CGRect(
                    x: centerX - size / 2,
                    y: renderSize.height - centerYFromTop - size / 2,
                    width: size,
                    height: size
                )
                logoLayer.opacity = 0
                let visibleAnim = CABasicAnimation(keyPath: "opacity")
                visibleAnim.fromValue = 1
                visibleAnim.toValue = 1
                visibleAnim.beginTime = clipStart
                visibleAnim.duration = clipDuration
                visibleAnim.fillMode = .both
                visibleAnim.isRemovedOnCompletion = false
                logoLayer.add(visibleAnim, forKey: "visible-window")
                animationLayer.addSublayer(logoLayer)
            }
        }

        // -- Watermark logo (bottom-right, throughout video) --
        let logoSize: CGFloat = min(renderSize.width, renderSize.height) * 0.06
        let margin: CGFloat = logoSize * 0.5

        if let logoImage = Self.appIconImage()?.cgImage {
            let logoLayer = CALayer()
            logoLayer.contents = logoImage
            logoLayer.contentsGravity = .resizeAspect
            // Core Animation: origin is bottom-left
            logoLayer.frame = CGRect(
                x: renderSize.width - logoSize - margin,
                y: margin,
                width: logoSize,
                height: logoSize
            )
            logoLayer.opacity = 0.6
            logoLayer.cornerRadius = logoSize * 0.2
            logoLayer.masksToBounds = true
            animationLayer.addSublayer(logoLayer)
        }

        // -- "CreatorAI" text next to logo --
        let textLayer = CATextLayer()
        textLayer.string = "CreatorAI"
        textLayer.font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 0, nil)
        textLayer.fontSize = logoSize * 0.45
        textLayer.foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.5)
        textLayer.alignmentMode = .right
        textLayer.contentsScale = 2.0
        let textWidth = logoSize * 3
        textLayer.frame = CGRect(
            x: renderSize.width - logoSize - margin - textWidth - 4,
            y: margin + logoSize * 0.15,
            width: textWidth,
            height: logoSize * 0.6
        )
        textLayer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.8)
        textLayer.shadowOffset = CGSize(width: 1, height: 1)
        textLayer.shadowOpacity = 0.8
        textLayer.shadowRadius = 2
        animationLayer.addSublayer(textLayer)

        // Apply animation tool to video composition
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: animationLayer
        )
    }

    private func timelineSegments(from clips: [Clip]) -> [(start: CMTime, duration: CMTime, clip: Clip)] {
        var cursor = CMTime.zero
        var segments: [(start: CMTime, duration: CMTime, clip: Clip)] = []
        for clip in clips {
            let seconds = max(0.05, ((clip.beatDuration ?? clip.sourceDuration ?? 3.0) * (clip.trimEnd - clip.trimStart) / 100.0) / max(0.1, clip.speed))
            let duration = CMTime(seconds: seconds, preferredTimescale: 600)
            segments.append((start: cursor, duration: duration, clip: clip))
            cursor = CMTimeAdd(cursor, duration)
        }
        return segments
    }

    private static func captionTextLayer(text: String, fontName: String, renderSize: CGSize, x: Double, y: Double, beginTime: Double, duration: Double) -> CATextLayer {
        let fontSize = max(18, min(renderSize.width, renderSize.height) * 0.052)
        let textWidth = renderSize.width * 0.84
        let textHeight = max(fontSize * 2.8, min(renderSize.height * 0.24, fontSize * 5.2))
        let centerX = renderSize.width * CGFloat(max(0.08, min(0.92, x)))
        let centerYFromTop = renderSize.height * CGFloat(max(0.08, min(0.92, y)))

        let layer = CATextLayer()
        layer.string = text
        layer.font = CTFontCreateWithName(captionFontName(for: fontName), 0, nil)
        layer.fontSize = fontSize
        layer.foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        layer.alignmentMode = .center
        layer.contentsScale = 2.0
        layer.frame = CGRect(
            x: max(12, min(renderSize.width - textWidth - 12, centerX - textWidth / 2)),
            y: max(12, min(renderSize.height - textHeight - 12, renderSize.height - centerYFromTop - textHeight / 2)),
            width: textWidth,
            height: textHeight
        )
        layer.isWrapped = true
        layer.truncationMode = .end
        layer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        layer.shadowOffset = CGSize(width: 2, height: 2)
        layer.shadowOpacity = 0.95
        layer.shadowRadius = 3
        layer.opacity = 0

        let visibleAnim = CABasicAnimation(keyPath: "opacity")
        visibleAnim.fromValue = 1
        visibleAnim.toValue = 1
        visibleAnim.beginTime = beginTime
        visibleAnim.duration = duration
        visibleAnim.fillMode = .both
        visibleAnim.isRemovedOnCompletion = false
        layer.add(visibleAnim, forKey: "visible-window")

        return layer
    }

    private static func captionFontName(for name: String) -> CFString {
        switch name {
        case "Rounded":
            return "ArialRoundedMTBold" as CFString
        case "Serif":
            return "TimesNewRomanPS-BoldMT" as CFString
        case "Avenir Next":
            return "AvenirNext-DemiBold" as CFString
        case "Helvetica Neue":
            return "HelveticaNeue-Bold" as CFString
        case "Georgia":
            return "Georgia-Bold" as CFString
        default:
            return "HelveticaNeue-Bold" as CFString
        }
    }

    /// Load the app icon from the bundle.
    private static func appIconImage() -> PlatformImage? {
        #if os(iOS)
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let iconName = files.last {
            return UIImage(named: iconName)
        }
        return UIImage(named: "AppIcon60x60") ?? UIImage(named: "AppIcon")
        #else
        return NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage
        #endif
    }

    private static func image(at path: String) -> PlatformImage? {
        let url = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path)
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return PlatformImage.from(data: data)
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

    private func renderVideoOnlyThenMixExternalAudio(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition?,
        musicOptions: [MusicRenderOptions],
        voiceover: VoiceoverRenderOptions?,
        outputPath: URL,
        onProgress: @escaping (String) -> Void
    ) async -> URL? {
        guard !composition.tracks(withMediaType: .video).isEmpty else { return nil }

        // Keep the original composition because videoComposition layer instructions
        // reference its video tracks. Creating a new composition here can invalidate
        // those instructions and make the fallback fail during export.
        let audioTracks = composition.tracks(withMediaType: .audio)
        audioTracks.forEach { composition.removeTrack($0) }

        let videoOnlyURL = outputPath
            .deletingLastPathComponent()
            .appendingPathComponent("video_only_\(UUID().uuidString).mp4")
        guard await exportComposition(composition, videoComposition: videoComposition, audioMix: nil, to: videoOnlyURL) else {
            return nil
        }

        let mixedURL = outputPath
            .deletingLastPathComponent()
            .appendingPathComponent("mixed_\(UUID().uuidString).mp4")
        guard let mixed = await mixRenderedVideoWithExternalAudio(
            videoURL: videoOnlyURL,
            musicOptions: musicOptions,
            voiceover: voiceover,
            outputPath: mixedURL,
            onProgress: onProgress
        ) else {
            print("[renderVideo] Audio mux failed")
            try? FileManager.default.removeItem(at: videoOnlyURL)
            return nil
        }

        do {
            try? FileManager.default.removeItem(at: outputPath)
            try FileManager.default.moveItem(at: mixed, to: outputPath)
            try? FileManager.default.removeItem(at: videoOnlyURL)
            return outputPath
        } catch {
            print("[renderVideo] Move mixed fallback failed: \(error)")
            try? FileManager.default.removeItem(at: videoOnlyURL)
            return mixed
        }
    }

    private func mixRenderedVideoWithExternalAudio(
        videoURL: URL,
        musicOptions: [MusicRenderOptions],
        voiceover: VoiceoverRenderOptions?,
        outputPath: URL,
        onProgress: @escaping (String) -> Void
    ) async -> URL? {
        onProgress("Mixing audio...")
        let videoAsset = AVURLAsset(url: videoURL)
        let composition = AVMutableComposition()
        guard let sourceVideo = try? await videoAsset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }

        let videoDuration = (try? await videoAsset.load(.duration)) ?? .zero
        guard CMTimeGetSeconds(videoDuration) > 0 else { return nil }
        do {
            try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceVideo, at: .zero)
            videoTrack.preferredTransform = (try? await sourceVideo.load(.preferredTransform)) ?? sourceVideo.preferredTransform
        } catch {
            print("[renderVideo] Audio mux video insert failed: \(error)")
            return nil
        }

        var mixParams: [AVMutableAudioMixInputParameters] = []
        for musicOpt in musicOptions where !musicOpt.isMuted {
            guard let musicPath = musicOpt.resolvedPath ?? musicOpt.file,
                  let musicURL = urlForPath(musicPath) else { continue }
            let musicAsset = AVURLAsset(url: musicURL)
            guard let sourceAudio = try? await musicAsset.loadTracks(withMediaType: .audio).first,
                  let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }

            let sourceDuration = (try? await musicAsset.load(.duration)) ?? .zero
            let sourceSeconds = CMTimeGetSeconds(sourceDuration)
            let videoSeconds = CMTimeGetSeconds(videoDuration)
            let startSeconds = max(0, min(musicOpt.timelineStart, videoSeconds))
            let endSeconds = max(startSeconds, min(musicOpt.timelineEnd ?? videoSeconds, videoSeconds))
            let requestedSeconds = max(0, endSeconds - startSeconds)
            guard sourceSeconds > 0, requestedSeconds > 0 else { continue }

            var insertedSeconds: Double = 0
            while insertedSeconds < requestedSeconds - 0.01 {
                let segmentSeconds = min(sourceSeconds, requestedSeconds - insertedSeconds)
                try? audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: CMTime(seconds: segmentSeconds, preferredTimescale: 600)),
                    of: sourceAudio,
                    at: CMTime(seconds: startSeconds + insertedSeconds, preferredTimescale: 600)
                )
                insertedSeconds += segmentSeconds
            }

            audioTrack.preferredVolume = Float(musicOpt.volume)
            let params = AVMutableAudioMixInputParameters(track: audioTrack)
            params.setVolume(Float(musicOpt.volume), at: CMTime(seconds: startSeconds, preferredTimescale: 600))
            mixParams.append(params)
        }

        if let vo = voiceover, !vo.isMuted {
            let voAsset = AVURLAsset(url: vo.fileURL)
            if let sourceAudio = try? await voAsset.loadTracks(withMediaType: .audio).first,
               let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let voDuration = (try? await voAsset.load(.duration)) ?? .zero
                let videoSeconds = CMTimeGetSeconds(videoDuration)
                let timelineStart = max(0, min(vo.timelineStart, videoSeconds))
                let timelineEnd = max(timelineStart, min(vo.timelineEnd ?? videoSeconds, videoSeconds))
                let insertSeconds = min(max(0, timelineEnd - timelineStart), max(0, CMTimeGetSeconds(voDuration)))
                if insertSeconds > 0 {
                    try? audioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: CMTime(seconds: insertSeconds, preferredTimescale: 600)),
                        of: sourceAudio,
                        at: CMTime(seconds: timelineStart, preferredTimescale: 600)
                    )
                    audioTrack.preferredVolume = Float(vo.volume)
                    let params = AVMutableAudioMixInputParameters(track: audioTrack)
                    params.setVolume(Float(vo.volume), at: CMTime(seconds: timelineStart, preferredTimescale: 600))
                    mixParams.append(params)
                }
            }
        }

        guard !mixParams.isEmpty else { return nil }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixParams
        if await exportComposition(composition, videoComposition: nil, audioMix: audioMix, to: outputPath) {
            return outputPath
        }

        print("[renderVideo] Audio mux with audioMix failed, retrying with track volumes only")
        return await exportComposition(composition, videoComposition: nil, audioMix: nil, to: outputPath) ? outputPath : nil
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

    private func renderReelMode(clips: [Clip], music: MusicRenderOptions?, aspectRatio: String, outputPath: URL, includeBranding: Bool, onProgress: @escaping (String) -> Void) async -> URL? {
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
                let textStart = max(0, min(clip.textStart, 100)) / 100 * beatDuration
                let textEnd = max(textStart + 0.05, min(clip.textEnd, 100) / 100 * beatDuration)
                let textX = max(0.08, min(clip.textX, 0.92))
                let textY = max(0.08, min(clip.textY, 0.92))
                filters.append(
                    "drawtext=text='\(cleanText)':fontsize=52:fontcolor=white:shadowcolor=black@0.9:shadowx=3:shadowy=3:x=(w-text_w)*\(String(format: "%.3f", textX)):y=(h-text_h)*\(String(format: "%.3f", textY)):enable='between(t,\(String(format: "%.3f", textStart)),\(String(format: "%.3f", textEnd)))'"
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

    private func renderStandardMode(clips: [Clip], music: MusicRenderOptions?, voiceover: VoiceoverRenderOptions? = nil, outputPath: URL, includeBranding: Bool, onProgress: @escaping (String) -> Void) async -> URL? {
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
    var timelineStart: Double = 0
    var timelineEnd: Double? = nil
    var resolvedPath: String?
    var isMuted: Bool = false
}

struct VoiceoverRenderOptions {
    let fileURL: URL
    let volume: Double
    var timelineStart: Double = 0
    var timelineEnd: Double? = nil
    var isMuted: Bool = false
}
