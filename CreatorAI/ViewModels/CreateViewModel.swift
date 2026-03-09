import SwiftUI

enum CreateMode: String, CaseIterable {
    case reel = "reel"
    case ad = "ad"

    var label: String {
        switch self {
        case .reel: return "Quick Reel"
        case .ad: return "Video Ad"
        }
    }

    var icon: String {
        switch self {
        case .reel: return "bolt.fill"
        case .ad: return "film.fill"
        }
    }
}

struct StyleOption: Identifiable {
    let id: String
    let label: String
    let icon: String
}

struct DurationOption: Identifiable {
    var id: Int { value }
    let value: Int
    let label: String
    let desc: String
}

struct LanguageOption: Identifiable {
    let id: String
    let label: String
    let flag: String
}

let AD_STYLES: [StyleOption] = [
    StyleOption(id: "modern", label: "Modern", icon: "sparkles"),
    StyleOption(id: "minimal", label: "Minimal", icon: "square"),
    StyleOption(id: "bold", label: "Bold", icon: "flame.fill"),
    StyleOption(id: "corporate", label: "Corporate", icon: "briefcase.fill"),
    StyleOption(id: "playful", label: "Playful", icon: "paintpalette.fill"),
]

let AD_DURATIONS: [DurationOption] = [
    DurationOption(value: 15, label: "15s", desc: "Story/Reel"),
    DurationOption(value: 30, label: "30s", desc: "Standard"),
    DurationOption(value: 60, label: "60s", desc: "Extended"),
]

let REEL_DURATIONS: [DurationOption] = [
    DurationOption(value: 7, label: "7s", desc: "Quick"),
    DurationOption(value: 10, label: "10s", desc: "Standard"),
    DurationOption(value: 15, label: "15s", desc: "Max"),
]

let LANGUAGES: [LanguageOption] = [
    LanguageOption(id: "en", label: "English", flag: "US"),
    LanguageOption(id: "ru", label: "Russian", flag: "RU"),
    LanguageOption(id: "es", label: "Spanish", flag: "ES"),
    LanguageOption(id: "de", label: "German", flag: "DE"),
    LanguageOption(id: "fr", label: "French", flag: "FR"),
    LanguageOption(id: "pt", label: "Portuguese", flag: "BR"),
]

enum ReelStep: String, CaseIterable {
    case scenario, music, beats, footage, downloading, rendering, assembling

    var label: String {
        switch self {
        case .scenario: return "Writing scenario"
        case .music: return "Finding music"
        case .beats: return "Detecting beats"
        case .footage: return "Finding footage"
        case .downloading: return "Downloading clips"
        case .rendering: return "Rendering takes"
        case .assembling: return "Assembling reel"
        }
    }

    var icon: String {
        switch self {
        case .scenario: return "doc.text"
        case .music: return "music.note"
        case .beats: return "waveform"
        case .footage: return "film"
        case .downloading: return "arrow.down.circle"
        case .rendering: return "square.stack.3d.up"
        case .assembling: return "square.stack.3d.up.fill"
        }
    }
}

@MainActor
class CreateViewModel: ObservableObject {
    @Published var mode: CreateMode = .reel

    // Reel state
    @Published var reelTopic = ""
    @Published var reelLang = "en"
    @Published var reelDuration = 10

    // Ad state
    @Published var adURL = ""
    @Published var adPrompt = ""
    @Published var adStyle = "modern"
    @Published var adDuration = 30
    @Published var adScenes = 5
    @Published var adPreview: PagePreview?
    @Published var adStep: AdStep = .input

    // Common
    @Published var isLoading = false
    @Published var genProgress: (step: String, message: String)?
    @Published var errorMessage: String?
    @Published var showPaywall = false

    enum AdStep {
        case input, preview, generating
    }

    // MARK: - Credit Check

    func checkCredits(_ appState: AppState) -> Bool {
        if appState.canGenerate { return true }
        showPaywall = true
        return false
    }

    // MARK: - Reel Generation

    func generateReel(appState: AppState) async -> VideoEditorParams? {
        guard !reelTopic.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter a topic for your reel"
            return nil
        }
        guard checkCredits(appState) else { return nil }

        isLoading = true
        genProgress = (step: "starting", message: "Starting...")
        errorMessage = nil

        var result: VideoEditorParams?

        await GenerationService.shared.generateReel(
            topic: reelTopic.trimmingCharacters(in: .whitespaces),
            language: reelLang,
            duration: reelDuration,
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    self?.genProgress = (step: progress.step, message: progress.message)
                }
            },
            onDone: { [weak self] reelResult in
                Task { @MainActor in
                    self?.genProgress = (step: "done", message: "Done!")
                    appState.useCredits()

                    if let takes = reelResult.takes, !takes.isEmpty {
                        let clipData = takes.enumerated().map { (i, t) -> [String: Any] in
                            var clip: [String: Any] = [
                                "id": Int(Date().timeIntervalSince1970 * 1000) + i,
                                "uri": t.pexelsUrl ?? "",
                                "name": t.text ?? "Take \(i + 1)",
                                "mimeType": "video/mp4",
                                "trimStart": 0,
                                "trimEnd": 100,
                                "text": t.text ?? "",
                            ]
                            if let bd = t.beatDuration { clip["beatDuration"] = bd }
                            if let sd = t.sourceDuration { clip["sourceDuration"] = sd }
                            return clip
                        }

                        if let jsonData = try? JSONSerialization.data(withJSONObject: clipData),
                           let jsonString = String(data: jsonData, encoding: .utf8) {

                            let apiBase = await APIService.shared.baseURL
                            var musicURL: String?
                            if let mu = reelResult.musicUrl {
                                musicURL = "\(apiBase)\(mu)"
                            }

                            result = VideoEditorParams(
                                takesJson: jsonString,
                                musicUrl: musicURL,
                                userId: "demo-user"
                            )
                        }
                    }

                    try? await Task.sleep(nanoseconds: 500_000_000)
                    self?.isLoading = false
                    self?.genProgress = nil
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.errorMessage = error
                    self?.isLoading = false
                    self?.genProgress = nil
                }
            }
        )

        return result
    }

    // MARK: - Ad Preview

    func previewAdURL() async {
        guard !adURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter a URL to preview"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let preview = try await GenerationService.shared.previewURL(adURL.trimmingCharacters(in: .whitespaces))
            adPreview = preview
            adStep = .preview
        } catch {
            errorMessage = "Couldn't read that URL."
        }

        isLoading = false
    }

    // MARK: - Ad Generation

    func generateAd(appState: AppState) async -> (id: String, title: String)? {
        guard checkCredits(appState) else { return nil }

        isLoading = true
        adStep = .generating
        errorMessage = nil

        do {
            let generationId = try await GenerationService.shared.generateAd(
                url: adURL.trimmingCharacters(in: .whitespaces),
                prompt: adPrompt.trimmingCharacters(in: .whitespaces),
                userId: "demo-user",
                scenes: adScenes,
                duration: adDuration,
                style: adStyle
            )
            appState.useCredits()
            isLoading = false
            return (id: generationId, title: adPreview?.title ?? "Video Ad")
        } catch {
            errorMessage = error.localizedDescription
            adStep = .preview
            isLoading = false
            return nil
        }
    }

    func resetAdPreview() {
        adPreview = nil
        adStep = .input
    }
}
