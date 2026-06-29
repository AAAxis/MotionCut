import Foundation
import AVFoundation

class AudioMixerService {
    static let shared = AudioMixerService()

    private let storage = FileStorageService.shared

    /// Minimum size (bytes) to consider a cached or downloaded file valid music.
    private let minValidMusicSize: Int64 = 50_000

    /// Resolve music to a local file URL: use cache, copy local file, or download.
    /// Returns a local M4A (AAC) file URL for best AVFoundation compatibility, or nil.
    func downloadAndSaveAudio(from urlString: String, audioId: String) async -> URL? {
        guard !urlString.isEmpty else { return nil }

        // Prefer M4A cache (AAC-encoded, AVFoundation-compatible).
        let m4aPath = storage.musicCacheDirectory.appendingPathComponent("audio_\(audioId).m4a")
        if storage.fileExists(at: m4aPath),
           let size = storage.fileSize(at: m4aPath), size >= minValidMusicSize {
            if await isPlayableAudio(at: m4aPath) {
                print("[AudioMixer] Using cached music (m4a): \(m4aPath.path)")
                return m4aPath
            }
            storage.deleteFile(at: m4aPath)
        }

        // Legacy MP3 cache — transcode to M4A if found
        let mp3Path = storage.musicCacheDirectory.appendingPathComponent("audio_\(audioId).mp3")
        if storage.fileExists(at: mp3Path),
           let size = storage.fileSize(at: mp3Path), size >= minValidMusicSize {
            if let transcoded = await transcodeToM4A(source: mp3Path, destination: m4aPath) {
                storage.deleteFile(at: mp3Path)
                print("[AudioMixer] Transcoded cached MP3 to M4A: \(transcoded.path)")
                return transcoded
            }
            storage.deleteFile(at: mp3Path)
        }

        let sourceExtension = audioFileExtension(for: urlString)
        let tempPath = storage.musicCacheDirectory
            .appendingPathComponent("audio_\(audioId)_tmp")
            .appendingPathExtension(sourceExtension)

        // Local file (file:// or absolute path) — copy to cache then transcode
        let sourceURL: URL? = urlString.hasPrefix("file://")
            ? URL(string: urlString)
            : (urlString.hasPrefix("/") || !urlString.contains("://") ? URL(fileURLWithPath: urlString.replacingOccurrences(of: "file://", with: "")) : nil)
        if let local = sourceURL, FileManager.default.fileExists(atPath: local.path) {
            do {
                if storage.fileExists(at: tempPath) { try FileManager.default.removeItem(at: tempPath) }
                try FileManager.default.copyItem(at: local, to: tempPath)
                if let result = await transcodeToM4A(source: tempPath, destination: m4aPath) {
                    storage.deleteFile(at: tempPath)
                    print("[AudioMixer] Local music transcoded to M4A: \(result.path)")
                    return result
                }
                // Transcoding failed — try using the original file directly
                if await isPlayableAudio(at: tempPath) {
                    try? FileManager.default.moveItem(at: tempPath, to: m4aPath)
                    print("[AudioMixer] Local music copied as-is: \(m4aPath.path)")
                    return m4aPath
                }
                storage.deleteFile(at: tempPath)
            } catch {
                print("[AudioMixer] Copy local music failed: \(error)")
            }
            return nil
        }

        // Remote URL — download then transcode
        guard URL(string: urlString) != nil else { return nil }
        if storage.fileExists(at: tempPath) { storage.deleteFile(at: tempPath) }

        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            do {
                try await storage.downloadFile(from: urlString, to: tempPath)
                guard let size = storage.fileSize(at: tempPath), size >= minValidMusicSize else {
                    storage.deleteFile(at: tempPath)
                    if attempt < maxAttempts { continue }
                    return nil
                }
                if let result = await transcodeToM4A(source: tempPath, destination: m4aPath) {
                    storage.deleteFile(at: tempPath)
                    print("[AudioMixer] Music downloaded and transcoded to M4A: \(result.path)")
                    return result
                }
                // Transcoding failed — try using the downloaded file directly
                if await isPlayableAudio(at: tempPath) {
                    try? FileManager.default.moveItem(at: tempPath, to: m4aPath)
                    print("[AudioMixer] Music saved as-is: \(m4aPath.path)")
                    return m4aPath
                }
                storage.deleteFile(at: tempPath)
            } catch {
                print("[AudioMixer] Download attempt \(attempt) failed: \(error)")
            }
            if attempt < maxAttempts { try? await Task.sleep(nanoseconds: 800_000_000) }
        }
        return nil
    }

    private func audioFileExtension(for urlString: String) -> String {
        let clean = urlString.replacingOccurrences(of: "file://", with: "")
        let pathExtension: String
        if let url = URL(string: urlString), let ext = url.path.split(separator: ".").last {
            pathExtension = String(ext)
        } else {
            pathExtension = (clean as NSString).pathExtension
        }
        let normalized = pathExtension.lowercased().split(separator: "?").first.map(String.init) ?? ""
        return normalized.isEmpty ? "mp3" : normalized
    }

    /// Transcode audio to M4A (AAC) using AVAssetReader/Writer for AVFoundation composition compatibility.
    /// MP3 tracks in AVMutableComposition cause AVAssetExportSession error -12849.
    private func transcodeToM4A(source: URL, destination: URL) async -> URL? {
        let asset = AVURLAsset(url: source)

        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            print("[AudioMixer] Transcode: no audio track in source")
            return nil
        }

        // If the source is already AAC/M4A, just copy it
        let formatDescriptions = (try? await audioTrack.load(.formatDescriptions)) ?? []
        if let desc = formatDescriptions.first {
            let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
            // 'aac ' = kAudioFormatMPEG4AAC
            if mediaSubType == kAudioFormatMPEG4AAC {
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: source, to: destination)
                    print("[AudioMixer] Source is already AAC, copied directly")
                    return destination
                } catch {
                    print("[AudioMixer] Copy AAC source failed: \(error)")
                }
            }
        }

        // Set up reader
        guard let reader = try? AVAssetReader(asset: asset) else {
            print("[AudioMixer] Transcode: failed to create AVAssetReader")
            return nil
        }

        let readerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerOutputSettings)
        guard reader.canAdd(readerOutput) else {
            print("[AudioMixer] Transcode: cannot add reader output")
            return nil
        }
        reader.add(readerOutput)

        // Set up writer
        try? FileManager.default.removeItem(at: destination)
        guard let writer = try? AVAssetWriter(outputURL: destination, fileType: .m4a) else {
            print("[AudioMixer] Transcode: failed to create AVAssetWriter")
            return nil
        }

        let writerInputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128_000
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerInputSettings)
        guard writer.canAdd(writerInput) else {
            print("[AudioMixer] Transcode: cannot add writer input")
            return nil
        }
        writer.add(writerInput)

        // Transcode
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.creatorai.transcode")) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        writerInput.markAsFinished()
                        cont.resume()
                        return
                    }
                }
            }
        }

        await writer.finishWriting()

        if writer.status == .completed {
            print("[AudioMixer] Transcode OK: \(destination.lastPathComponent)")
            return destination
        }
        print("[AudioMixer] Transcode failed: \(writer.error?.localizedDescription ?? "unknown")")
        try? FileManager.default.removeItem(at: destination)
        return nil
    }

    /// Quick check that the file is playable (has duration).
    private func isPlayableAudio(at url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return CMTimeGetSeconds(duration) > 0
        } catch {
            return false
        }
    }

    func detachAudio(from sourceURL: URL, audioId: String, startSeconds: Double, durationSeconds: Double, speed: Double = 1.0) async -> URL? {
        let source = AVURLAsset(url: sourceURL)
        guard let sourceAudio = try? await source.loadTracks(withMediaType: .audio).first else {
            print("[AudioMixer] Detach failed: source has no audio track")
            return nil
        }

        let sourceDuration = (try? await source.load(.duration)) ?? .zero
        let sourceSeconds = max(0, CMTimeGetSeconds(sourceDuration))
        let start = max(0, min(startSeconds, max(0, sourceSeconds - 0.01)))
        let length = max(0.05, min(durationSeconds, max(0.05, sourceSeconds - start)))
        let clampedSpeed = max(0.1, min(5.0, speed))
        let outputURL = storage.musicCacheDirectory.appendingPathComponent("detached_\(audioId).m4a")
        let sourceRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: length, preferredTimescale: 600)
        )

        if abs(clampedSpeed - 1.0) <= 0.01,
           let directURL = await exportDetachedAudioDirectly(source: source, timeRange: sourceRange, outputURL: outputURL) {
            return directURL
        }

        let composition = AVMutableComposition()
        guard let outputTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }

        do {
            try outputTrack.insertTimeRange(sourceRange, of: sourceAudio, at: .zero)
            if abs(clampedSpeed - 1.0) > 0.01 {
                outputTrack.scaleTimeRange(
                    CMTimeRange(start: .zero, duration: sourceRange.duration),
                    toDuration: CMTime(seconds: length / clampedSpeed, preferredTimescale: 600)
                )
            }
        } catch {
            print("[AudioMixer] Detach insert failed: \(error)")
            return nil
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            exportSession.exportAsynchronously {
                cont.resume()
            }
        }

        if exportSession.status == .completed,
           storage.fileExists(at: outputURL),
           (storage.fileSize(at: outputURL) ?? 0) > 1000 {
            print("[AudioMixer] Detached audio: \(outputURL.lastPathComponent)")
            return outputURL
        }

        let error = exportSession.error as NSError?
        let underlying = error?.userInfo[NSUnderlyingErrorKey] as? NSError
        let underlyingMessage = underlying.map { " underlying=\($0.domain) \($0.code)" } ?? ""
        print("[AudioMixer] Detach export failed status=\(exportSession.status.rawValue) error=\(exportSession.error?.localizedDescription ?? "unknown")\(underlyingMessage)")
        try? FileManager.default.removeItem(at: outputURL)
        return nil
    }

    private func exportDetachedAudioDirectly(source: AVURLAsset, timeRange: CMTimeRange, outputURL: URL) async -> URL? {
        try? FileManager.default.removeItem(at: outputURL)
        guard let exportSession = AVAssetExportSession(asset: source, presetName: AVAssetExportPresetAppleM4A) else {
            print("[AudioMixer] Direct detach failed: could not create export session")
            return nil
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = timeRange

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            exportSession.exportAsynchronously {
                cont.resume()
            }
        }

        if exportSession.status == .completed,
           storage.fileExists(at: outputURL),
           (storage.fileSize(at: outputURL) ?? 0) > 1000 {
            print("[AudioMixer] Direct detached audio: \(outputURL.lastPathComponent)")
            return outputURL
        }

        let error = exportSession.error as NSError?
        let underlying = error?.userInfo[NSUnderlyingErrorKey] as? NSError
        let underlyingMessage = underlying.map { " underlying=\($0.domain) \($0.code)" } ?? ""
        print("[AudioMixer] Direct detach failed status=\(exportSession.status.rawValue) error=\(exportSession.error?.localizedDescription ?? "unknown")\(underlyingMessage)")
        try? FileManager.default.removeItem(at: outputURL)
        return nil
    }

    func mixAudioWithVideo(videoURL: URL, audioURL: URL, volume: Double = 0.5) async -> URL? {
        let outputPath = storage.renderedVideosDirectory.appendingPathComponent("mixed_\(Int(Date().timeIntervalSince1970 * 1000)).mp4")

        let command = "-y -i \"\(videoURL.path)\" -i \"\(audioURL.path)\" -filter_complex \"[1:a]volume=\(String(format: "%.2f", volume))[a]\" -map 0:v -map \"[a]\" -c:v copy -c:a aac -shortest \"\(outputPath.path)\""

        // TODO: Execute with FFmpegKit when available
        print("[AudioMixer] Would execute: \(command)")

        return outputPath
    }

    func cleanupOldCache() {
        storage.cleanupOldFiles(in: storage.musicCacheDirectory, olderThan: 7)
    }
}
