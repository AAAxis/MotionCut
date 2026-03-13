import SwiftUI

enum CreateMode: String, CaseIterable {
    case reel = "reel"
    case ad = "ad"

    var label: String {
        switch self {
        case .reel: return "AI Influencer"
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

struct InfluencerAvatar: Identifiable {
    let id: String
    let name: String
    let iconName: String
}

struct AIModelOption: Identifiable {
    let id: String        // replicate model id e.g. "kwaivgi/kling-v2.1"
    let name: String
    let imageURL: String  // cover image URL from Replicate
    let runCount: Int
}

let PRESET_AI_MODELS: [AIModelOption] = [
    AIModelOption(id: "bytedance/seedance-1-lite", name: "Seedance Lite", imageURL: "https://tjzk.replicate.delivery/models_models_featured_image/961a33d5-e27a-4b15-8cdd-3e37d5375297/replicate-seedance-1-lite.webp", runCount: 2_800_000),
    AIModelOption(id: "bytedance/seedance-1-pro", name: "Seedance Pro", imageURL: "https://tjzk.replicate.delivery/models_models_featured_image/b11bb650-a993-485b-b433-f1ba1c4cb90b/replicate-seedance-1-pro.webp", runCount: 1_700_000),
    AIModelOption(id: "minimax/video-01", name: "MiniMax", imageURL: "https://tjzk.replicate.delivery/models_models_featured_image/b56c831c-4c68-4443-b474-e3274982de41/video-01-cover.webp", runCount: 900_000),
    AIModelOption(id: "kwaivgi/kling-v2.1", name: "Kling v2.1", imageURL: "https://tjzk.replicate.delivery/models_models_featured_image/a7690882-d1d2-44fb-b487-f41bd367adcf/replicate-prediction-2epyczsz.webp", runCount: 3_600_000),
]

// Keep old preset for backward compat
let PRESET_AVATARS: [InfluencerAvatar] = []

let AD_STYLES: [StyleOption] = [
    StyleOption(id: "modern", label: "Modern", icon: "sparkles"),
    StyleOption(id: "minimal", label: "Minimal", icon: "square"),
    StyleOption(id: "bold", label: "Bold", icon: "flame.fill"),
    StyleOption(id: "corporate", label: "Corporate", icon: "briefcase.fill"),
    StyleOption(id: "playful", label: "Playful", icon: "paintpalette.fill"),
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
    @Published var reelInfluencerId = "avatar_1"
    @Published var reelReferenceVideoURL: URL?
    @Published var reelAvatarImageURL: String?  // HTTPS URL of uploaded avatar for i2v

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

    func generateReel(appState: AppState) async -> Bool {
        let topic = reelTopic.trimmingCharacters(in: .whitespaces)

        guard !topic.isEmpty else {
            errorMessage = "Enter a topic for your reel"
            return false
        }
        guard checkCredits(appState) else { return false }

        errorMessage = nil
        let generation = Generation(
            videoName: topic,
            videoUri: nil,
            resultVideoUrl: nil,
            status: .processing,
            createdAt: Date(),
            userId: appState.userId ?? "demo-user"
        )

        await GenerationService.shared.saveGeneration(generation)
        appState.useCredits()

        let language = reelLang
        let duration = reelDuration
        let influencerId = reelInfluencerId
        let avatarImageURL = reelAvatarImageURL
        let referenceVideoURL = reelReferenceVideoURL
        let userId = appState.userId ?? "demo-user"

        resetReelForm()

        Task.detached(priority: .background) {
            do {
                if let localReferenceVideoURL = referenceVideoURL {
                    let uploadedVideo = try await GenerationService.shared.uploadReferenceVideo(
                        fileURL: localReferenceVideoURL,
                        userId: userId
                    )
                    let uploadedVideoURL = makeAbsoluteReelURL(uploadedVideo.url)

                    let influence = try await GenerationService.shared.startInfluenceReel(
                        topic: topic,
                        duration: duration,
                        influencerId: influencerId,
                        referenceVideoUrl: uploadedVideoURL,
                        userId: userId
                    )

                    try await pollInfluenceResult(
                        generationID: generation.id,
                        influenceID: influence.id
                    )
                } else if influencerId.contains("/") {
                    // AI model selected (e.g. "bytedance/seedance-1-lite") → Replicate
                    let imageUrl: String? = avatarImageURL
                    let createResponse = try await GenerationService.shared.startAICreate(
                        modelId: influencerId,
                        prompt: topic,
                        imageUrl: imageUrl,
                        duration: duration,
                        userId: userId
                    )
                    
                    guard let createId = createResponse.id else {
                        await GenerationService.shared.updateGeneration(id: generation.id, status: .failed)
                        return
                    }
                    
                    // Poll until done (max 5 min)
                    let deadline = Date().addingTimeInterval(300)
                    while Date() < deadline {
                        try await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                        let status = try await GenerationService.shared.pollAICreate(id: createId)
                        if status.status == "succeeded", let outputUrl = status.outputUrl {
                            await GenerationService.shared.updateGeneration(
                                id: generation.id,
                                status: .completed,
                                remoteVideoUrl: outputUrl
                            )
                            return
                        } else if status.status == "failed" || status.status == "canceled" {
                            await GenerationService.shared.updateGeneration(id: generation.id, status: .failed)
                            return
                        }
                    }
                    // Timeout
                    await GenerationService.shared.updateGeneration(id: generation.id, status: .failed)
                } else {
                    // Custom uploaded avatar without reference video → stock footage reel
                    let response = try await GenerationService.shared.generateReel(
                        topic: topic,
                        language: language,
                        duration: duration,
                        influencerId: influencerId,
                        referenceVideoUrl: nil
                    )

                    guard let downloadUrl = response.downloadUrl, !downloadUrl.isEmpty else {
                        await GenerationService.shared.updateGeneration(id: generation.id, status: .failed)
                        return
                    }

                    await GenerationService.shared.updateGeneration(
                        id: generation.id,
                        status: .completed,
                        remoteVideoUrl: makeAbsoluteReelURL(downloadUrl)
                    )
                }
            } catch {
                print("[CreateViewModel] Reel generation failed: \(error)")
                await GenerationService.shared.updateGeneration(id: generation.id, status: .failed)
            }
        }

        return true
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

private extension CreateViewModel {
    func resetReelForm() {
        reelTopic = ""
        reelReferenceVideoURL = nil
        reelAvatarImageURL = nil
    }
}

private func pollInfluenceResult(generationID: String, influenceID: String) async throws {
    for _ in 0..<120 {
        let status = try await GenerationService.shared.getInfluenceStatus(id: influenceID)

        switch status.status {
        case "succeeded":
            guard let outputURL = status.outputUrl, !outputURL.isEmpty else {
                await GenerationService.shared.updateGeneration(id: generationID, status: .failed)
                return
            }
            await GenerationService.shared.updateGeneration(
                id: generationID,
                status: .completed,
                remoteVideoUrl: outputURL
            )
            return
        case "failed", "canceled":
            await GenerationService.shared.updateGeneration(id: generationID, status: .failed)
            return
        default:
            try await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    await GenerationService.shared.updateGeneration(id: generationID, status: .failed)
}

private func makeAbsoluteReelURL(_ path: String) -> String {
    if path.hasPrefix("http://") || path.hasPrefix("https://") {
        return path
    }

    return "\(APIService.shared.syncBaseURL)\(path)"
}
