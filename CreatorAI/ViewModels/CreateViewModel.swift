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
    AIModelOption(id: "wan-video/wan-2.2-turbo", name: "Wan 2.2 Turbo", imageURL: "https://fal.ai/fal-ai/wan/v2.2-a14b/text-to-video/turbo", runCount: 0),
    AIModelOption(id: "bytedance/seedance-1-lite", name: "Seedance Lite", imageURL: "https://tjzk.replicate.delivery/models_models_featured_image/961a33d5-e27a-4b15-8cdd-3e37d5375297/replicate-seedance-1-lite.webp", runCount: 2_800_000),
    AIModelOption(id: "bytedance/seedance-1-pro", name: "Seedance Pro", imageURL: "https://tjzk.replicate.delivery/models_models_featured_image/b11bb650-a993-485b-b433-f1ba1c4cb90b/replicate-seedance-1-pro.webp", runCount: 1_700_000),
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
    LanguageOption(id: "he", label: "Hebrew", flag: "IL"),
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
    @Published var reelInfluencerId = "wan-video/wan-2.2-turbo"
    @Published var reelReferenceVideoURL: URL?
    @Published var reelAvatarImageURL: String?  // HTTPS URL of uploaded avatar for i2v
    @Published var reelScrapedContext: String?   // Scraped page context to enrich prompt

    // Ad state
    @Published var adURL = ""
    @Published var adPrompt = ""
    @Published var adStyle = "modern"
    @Published var adLanguage = "en"
    @Published var adDuration = 30
    @Published var adScenes = 5
    @Published var adPreview: PagePreview?
    @Published var adStep: AdStep = .input

    // Free reel (stock footage) state
    @Published var freeReelProgress: LocalReelGenerator.GenerationProgress?
    @Published var isGeneratingFreeReel = false

    // Common
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showBuyCredits = false

    enum AdStep {
        case input, preview, generating
    }

    // Credits per second per model (must match server config/credits.js)
    var reelCreditCost: Int {
        // Custom photo (image-to-video) = flat 10 credits
        if reelAvatarImageURL != nil { return 10 }
        let perSecond: Int
        switch reelInfluencerId {
        case "wan-video/wan-2.2-turbo": perSecond = 1
        case "bytedance/seedance-1-lite": perSecond = 1
        case "bytedance/seedance-1-pro": perSecond = 2
        case "kwaivgi/kling-v2.1": perSecond = 3
        case "kwaivgi/kling-v1.6-standard": perSecond = 2
        case "minimax/video-01": perSecond = 5
        default: perSecond = 1
        }
        return perSecond * reelDuration
    }

    // MARK: - Credit Check

    func checkCredits(_ appState: AppState) -> Bool {
        if appState.canGenerate { return true }
        showBuyCredits = true
        return false
    }

    // MARK: - Reel Generation

    func generateReel(appState: AppState) async -> Bool {
        var topic = reelTopic.trimmingCharacters(in: .whitespaces)

        // Enrich prompt with scraped page context if available
        if let context = reelScrapedContext, !context.isEmpty {
            topic = "\(topic)\n\nContext: \(context)"
        }

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
        // Credits deducted server-side

        let language = reelLang
        let duration = reelDuration
        let influencerId = reelInfluencerId
        let avatarImageURL = reelAvatarImageURL
        let referenceVideoURL = reelReferenceVideoURL
        let userId = appState.userId ?? "demo-user"

        resetReelForm()

        // Navigate to progress screen
        NotificationCenter.default.post(
            name: .navigateToGenerationStatus,
            object: (id: generation.id, title: topic, isLocalExport: false, isReel: true)
        )

        Task.detached(priority: .background) {
            do {
                print("[Generate] influencerId=\(influencerId), hasSlash=\(influencerId.contains("/")), avatarImageURL=\(String(describing: avatarImageURL)), referenceVideoURL=\(String(describing: referenceVideoURL))")
                if influencerId.contains("/") {
                    // AI model selected (e.g. "bytedance/seedance-1-lite") → Replicate
                    let imageUrl: String? = avatarImageURL
                    
                    // Upload reference video if provided (for audio extraction on server)
                    var uploadedRefVideoURL: String? = nil
                    if let localRef = referenceVideoURL {
                        let uploadedVideo = try await GenerationService.shared.uploadReferenceVideo(
                            fileURL: localRef,
                            userId: userId
                        )
                        uploadedRefVideoURL = makeAbsoluteReelURL(uploadedVideo.url)
                    }
                    
                    let createResponse = try await GenerationService.shared.startAICreate(
                        modelId: influencerId,
                        prompt: topic,
                        imageUrl: imageUrl,
                        duration: duration,
                        userId: userId,
                        referenceVideoUrl: uploadedRefVideoURL
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
                            // Download to local storage so it doesn't re-download every time
                            let localFile = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(generation.id).mp4")
                            try? await FileStorageService.shared.downloadFile(from: outputUrl, to: localFile)
                            let localUri = FileManager.default.fileExists(atPath: localFile.path) ? localFile.path : nil
                            await GenerationService.shared.updateGeneration(
                                id: generation.id,
                                status: .completed,
                                videoUri: localUri,
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
                } else if let localReferenceVideoURL = referenceVideoURL {
                    // Custom avatar + reference video → LivePortrait
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
                } else {
                    // Custom avatar, no reference video → stock footage reel
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

                    let outputUrl = makeAbsoluteReelURL(downloadUrl)
                    let localUri = await downloadGenerationOutput(outputUrl, generationID: generation.id)
                    await GenerationService.shared.updateGeneration(
                        id: generation.id,
                        status: .completed,
                        videoUri: localUri
                    )
                }
            } catch let error as APIError {
                if case .httpError(402) = error {
                    await MainActor.run { self.showBuyCredits = true }
                }
                print("[CreateViewModel] Reel generation failed: \(error)")
                await GenerationService.shared.updateGeneration(id: generation.id, status: .failed)
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
            return
        }

        isLoading = true
        errorMessage = nil

        let preview = await LocalScraperService.scrape(url: adURL.trimmingCharacters(in: .whitespaces))
        if let preview {
            adPreview = preview
            adStep = .preview
        } else {
            errorMessage = nil // Silently fail — URL preview is optional
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
                userId: appState.userId ?? "demo-user",
                scenes: adScenes,
                duration: adDuration,
                style: adStyle,
                language: adLanguage
            )
            // Save to local library
            let adTitle = adPreview?.title ?? "Video Ad"
            let generation = Generation(
                id: generationId,
                videoName: adTitle,
                videoUri: nil,
                resultVideoUrl: nil,
                status: .processing,
                createdAt: Date(),
                userId: appState.userId ?? "demo-user"
            )
            await GenerationService.shared.saveGeneration(generation)
            
            // Poll in background and update when done
            Task.detached(priority: .background) {
                let baseURL = await GenerationService.shared.getBaseURL()
                let deadline = Date().addingTimeInterval(300)
                while Date() < deadline {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    do {
                        guard let statusURL = URL(string: "\(baseURL)/api/ads/status/\(generationId)") else { continue }
                        let (data, _) = try await URLSession.shared.data(from: statusURL)
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let status = json["status"] as? String {
                            if status == "succeeded" {
                                let output = json["output"] as? [String: Any]
                                let download = output?["download"] as? String
                                let videoUrl = download != nil ? "\(baseURL)\(download!)" : nil
                                await GenerationService.shared.updateGeneration(
                                    id: generationId,
                                    status: .completed,
                                    remoteVideoUrl: videoUrl
                                )
                                return
                            } else if status == "failed" {
                                await GenerationService.shared.updateGeneration(id: generationId, status: .failed)
                                return
                            }
                        }
                    } catch { }
                }
                await GenerationService.shared.updateGeneration(id: generationId, status: .failed)
            }
            
            isLoading = false
            return (id: generationId, title: adTitle)
        } catch let error as APIError {
            if case .httpError(402) = error {
                showBuyCredits = true
            } else {
                errorMessage = error.localizedDescription
            }
            adStep = .preview
            isLoading = false
            return nil
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

    // MARK: - Free Reel (Stock Footage, Local Generation)

    func generateFreeReel(appState: AppState) async -> Bool {
        let description = adPrompt.trimmingCharacters(in: .whitespaces)
        guard !description.isEmpty else {
            errorMessage = "Enter a description for your video"
            return false
        }

        errorMessage = nil
        isGeneratingFreeReel = true
        freeReelProgress = nil

        let language = adLanguage
        let topic = description

        let result = await LocalReelGenerator.generate(
            topic: topic,
            language: language,
            clipCount: 6
        ) { progress in
            Task { @MainActor in
                self.freeReelProgress = progress
            }
        }

        isGeneratingFreeReel = false
        freeReelProgress = nil

        guard result.success, let generationId = result.generationId else {
            errorMessage = result.error ?? "Generation failed"
            return false
        }

        // Save generation and open editor
        let generation = Generation(
            id: generationId,
            videoName: String(topic.prefix(40)),
            videoUri: result.videoPath,
            status: .saved,
            createdAt: Date(),
            userId: appState.userId ?? "demo-user",
            musicFile: result.voiceoverPath,
            takesJson: result.takesJson
        )
        await GenerationService.shared.saveGeneration(generation)

        // Navigate to editor
        let params = Route.VideoEditorParams(
            videoUri: result.videoPath,
            videoName: generation.videoName,
            takesJson: result.takesJson,
            musicUrl: result.voiceoverPath,
            userId: appState.userId ?? "demo-user"
        )
        NotificationCenter.default.post(name: .navigateToVideoEditor, object: params)
        NotificationCenter.default.post(name: .switchToLibraryTab, object: nil)

        adPrompt = ""
        return true
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
            let localUri = await downloadGenerationOutput(outputURL, generationID: generationID)
            await GenerationService.shared.updateGeneration(
                id: generationID,
                status: .completed,
                videoUri: localUri
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

private func downloadGenerationOutput(_ urlString: String, generationID: String) async -> String? {
    let localFile = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(generationID).mp4")
    try? await FileStorageService.shared.downloadFile(from: urlString, to: localFile)
    return FileManager.default.fileExists(atPath: localFile.path) ? localFile.path : nil
}
