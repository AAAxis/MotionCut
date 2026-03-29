import Foundation
import AVFoundation

/// On-device text-to-speech using AVSpeechSynthesizer.
/// Direct port of Android LocalTTSService.
final class LocalTTSService {
    static let shared = LocalTTSService()
    private init() {}

    private let languageMap: [String: String] = [
        "en": "en-US",
        "he": "he-IL",
        "ru": "ru-RU",
        "es": "es-ES",
        "de": "de-DE",
        "fr": "fr-FR",
        "pt": "pt-BR"
    ]

    /// Synthesize text to an audio file. Returns the output file URL.
    @MainActor
    func synthesizeToFile(text: String, language: String = "en", outputDir: URL, filename: String? = nil) async -> URL? {
        let voiceLanguage = languageMap[language] ?? "en-US"
        let outputFile = outputDir.appendingPathComponent(filename ?? "tts_\(UUID().uuidString).caf")

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0

        // AVSpeechSynthesizer must be created fresh for each write() call to avoid hangs
        let synthesizer = AVSpeechSynthesizer()

        let result: URL? = await withCheckedContinuation { continuation in
            var audioBuffers: [AVAudioPCMBuffer] = []
            var resumed = false

            synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    // nil/non-PCM buffer signals completion
                    guard !resumed else { return }
                    resumed = true
                    if audioBuffers.isEmpty {
                        continuation.resume(returning: nil)
                    } else {
                        let success = Self.writeBuffersToFile(audioBuffers, outputFile: outputFile)
                        continuation.resume(returning: success ? outputFile : nil)
                    }
                    return
                }
                if pcmBuffer.frameLength > 0 {
                    audioBuffers.append(pcmBuffer)
                }
            }

            // Safety timeout — if callback never fires after 15s, resume with nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                guard !resumed else { return }
                resumed = true
                if !audioBuffers.isEmpty {
                    let success = Self.writeBuffersToFile(audioBuffers, outputFile: outputFile)
                    continuation.resume(returning: success ? outputFile : nil)
                } else {
                    print("[TTS] Timeout for: \(text.prefix(30))...")
                    continuation.resume(returning: nil)
                }
            }
        }

        return result
    }

    /// Synthesize voiceover for multiple scenes, returning a list of audio files.
    @MainActor
    func synthesizeScenes(scenes: [LocalScriptGenerator.SceneScript], language: String = "en", outputDir: URL) async -> [URL] {
        var results: [URL] = []
        for (index, scene) in scenes.enumerated() {
            if let file = await synthesizeToFile(
                text: scene.voiceoverText,
                language: language,
                outputDir: outputDir,
                filename: "voice_\(index).caf"
            ) {
                results.append(file)
            }
            // Small delay between synths to avoid AVSpeechSynthesizer contention
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return results
    }

    /// Merge multiple audio files into one using AVAssetExportSession.
    func mergeAudioFiles(_ files: [URL], output: URL) async -> URL? {
        guard !files.isEmpty else { return nil }
        if files.count == 1 { return files.first }

        let composition = AVMutableComposition()
        guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return files.first
        }

        var insertTime = CMTime.zero
        for file in files {
            let asset = AVURLAsset(url: file)
            guard let sourceTrack = try? await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try? await asset.load(.duration)
            guard let duration else { continue }
            try? audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack, at: insertTime)
            insertTime = CMTimeAdd(insertTime, duration)
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            return files.first
        }

        try? FileManager.default.removeItem(at: output)
        exportSession.outputURL = output
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if exportSession.status == .completed {
            print("[TTS] Merged \(files.count) audio files")
            return output
        } else {
            print("[TTS] Merge failed: \(exportSession.error?.localizedDescription ?? "unknown")")
            return files.first
        }
    }

    // MARK: - Private

    private static func writeBuffersToFile(_ buffers: [AVAudioPCMBuffer], outputFile: URL) -> Bool {
        guard let firstPCM = buffers.first else { return false }
        guard let audioFile = try? AVAudioFile(forWriting: outputFile, settings: firstPCM.format.settings) else {
            return false
        }

        for buffer in buffers where buffer.frameLength > 0 {
            try? audioFile.write(from: buffer)
        }

        return true
    }
}
