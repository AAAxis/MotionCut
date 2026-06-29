import Foundation
import AVFoundation

final class AudioMergeService {
    static let shared = AudioMergeService()
    private init() {}

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
            print("[AudioMerge] Merged \(files.count) audio files")
            return output
        } else {
            print("[AudioMerge] Merge failed: \(exportSession.error?.localizedDescription ?? "unknown")")
            return files.first
        }
    }
}

struct ElevenLabsVoice: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let previewURL: String?
}

enum PremiumVoiceQuota {
    private static let dateKey = "premium_voice_usage_date"
    private static let countKey = "premium_voice_usage_count"
    static let dailyLimit = 3

    static var remainingToday: Int {
        resetIfNeeded()
        return max(0, dailyLimit - UserDefaults.standard.integer(forKey: countKey))
    }

    static func consumeIfAvailable() -> Bool {
        resetIfNeeded()
        let count = UserDefaults.standard.integer(forKey: countKey)
        guard count < dailyLimit else { return false }
        UserDefaults.standard.set(count + 1, forKey: countKey)
        return true
    }

    private static func resetIfNeeded() {
        let today = Self.todayKey()
        if UserDefaults.standard.string(forKey: dateKey) != today {
            UserDefaults.standard.set(today, forKey: dateKey)
            UserDefaults.standard.set(0, forKey: countKey)
        }
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

final class SystemTTSService {
    static let shared = SystemTTSService()
    private init() {}

    enum SystemTTSError: LocalizedError {
        case emptyText
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .emptyText: return "Voice text is empty."
            case .writeFailed: return "System voice could not be written."
            }
        }
    }

    @MainActor
    func synthesizeToFile(text: String, outputDir: URL, filename: String, language: String = "en-US") async throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SystemTTSError.emptyText }

        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputFile = outputDir.appendingPathComponent(filename.replacingOccurrences(of: ".mp3", with: ".caf"))
        try? FileManager.default.removeItem(at: outputFile)

        return try await withCheckedThrowingContinuation { continuation in
            let synthesizer = AVSpeechSynthesizer()
            let utterance = AVSpeechUtterance(string: trimmed)
            utterance.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0

            var audioFile: AVAudioFile?
            var didResume = false

            func finish(_ result: Result<URL, Error>) {
                guard !didResume else { return }
                didResume = true
                switch result {
                case .success(let url): continuation.resume(returning: url)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }

            synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    finish(.failure(SystemTTSError.writeFailed))
                    return
                }

                if pcmBuffer.frameLength == 0 {
                    finish(FileManager.default.fileExists(atPath: outputFile.path) ? .success(outputFile) : .failure(SystemTTSError.writeFailed))
                    return
                }

                do {
                    if audioFile == nil {
                        audioFile = try AVAudioFile(forWriting: outputFile, settings: pcmBuffer.format.settings)
                    }
                    try audioFile?.write(from: pcmBuffer)
                } catch {
                    finish(.failure(error))
                }
            }
        }
    }
}

final class ElevenLabsTTSService {
    static let shared = ElevenLabsTTSService()
    private init() {}

    enum ElevenLabsError: LocalizedError {
        case missingKey
        case missingVoice
        case invalidResponse
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Premium voice is not configured for this build."
            case .missingVoice:
                return "Select a voice first."
            case .invalidResponse:
                return "Voice service returned a response we could not read."
            case .http(let code):
                return "Voice service HTTP error: \(code)"
            }
        }
    }

    private var apiKey: String? {
        let env = ProcessInfo.processInfo.environment
        return env["ELEVENLABS_API_KEY"]
            ?? env["ELEVEN_LABS_API_KEY"]
            ?? Self.secretValue("ELEVENLABS_API_KEY")
            ?? (Bundle.main.object(forInfoDictionaryKey: "ELEVENLABS_API_KEY") as? String)
            ?? UserDefaults.standard.string(forKey: "ELEVENLABS_API_KEY")
    }

    var isConfigured: Bool {
        guard let apiKey else { return false }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func fetchVoices() async throws -> [ElevenLabsVoice] {
        guard let apiKey, !apiKey.isEmpty else { throw ElevenLabsError.missingKey }
        guard let url = URL(string: "https://api.elevenlabs.io/v1/voices") else { throw ElevenLabsError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ElevenLabsError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw ElevenLabsError.http(http.statusCode) }

        let decoded = try JSONDecoder().decode(VoicesResponse.self, from: data)
        return decoded.voices.map { ElevenLabsVoice(id: $0.voice_id, name: $0.name, previewURL: $0.preview_url) }
    }

    func synthesizeScenes(
        scenes: [LocalScriptGenerator.SceneScript],
        voiceId: String,
        outputDir: URL
    ) async throws -> [URL] {
        guard !voiceId.isEmpty else { throw ElevenLabsError.missingVoice }

        var results: [URL] = []
        for (index, scene) in scenes.enumerated() {
            let file = try await synthesizeToFile(
                text: scene.voiceoverText,
                voiceId: voiceId,
                outputDir: outputDir,
                filename: "elevenlabs_voice_\(index).mp3"
            )
            results.append(file)
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return results
    }

    func synthesizeToFile(text: String, voiceId: String, outputDir: URL, filename: String) async throws -> URL {
        guard let apiKey, !apiKey.isEmpty else { throw ElevenLabsError.missingKey }
        guard !voiceId.isEmpty else { throw ElevenLabsError.missingVoice }
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)?output_format=mp3_44100_128") else {
            throw ElevenLabsError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TextToSpeechRequest(
            text: text,
            model_id: "eleven_v3",
            voice_settings: VoiceSettings(stability: 0.45, similarity_boost: 0.8, style: 0.35, use_speaker_boost: true)
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ElevenLabsError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw ElevenLabsError.http(http.statusCode) }

        let outputFile = outputDir.appendingPathComponent(filename)
        try data.write(to: outputFile, options: .atomic)
        return outputFile
    }

    private struct VoicesResponse: Decodable {
        let voices: [Voice]

        struct Voice: Decodable {
            let voice_id: String
            let name: String
            let preview_url: String?
        }
    }

    private struct TextToSpeechRequest: Encodable {
        let text: String
        let model_id: String
        let voice_settings: VoiceSettings
    }

    private struct VoiceSettings: Encodable {
        let stability: Double
        let similarity_boost: Double
        let style: Double
        let use_speaker_boost: Bool
    }

    private static func secretValue(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let value = plist[key] as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
