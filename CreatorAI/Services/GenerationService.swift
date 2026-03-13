import Foundation

struct ReelRequest: Encodable {
    let topic: String
    let language: String
    let duration: Int
    let influencerId: String?
    let referenceVideoUrl: String?
}

struct ReelProgress {
    let step: String
    let message: String
}

struct ReelTake: Codable {
    let pexelsUrl: String?
    let text: String?
    let beatDuration: Double?
    let sourceDuration: Double?
}

struct ReelResult: Codable {
    let takes: [ReelTake]?
    let musicUrl: String?
    let musicMood: String?
    let hook: String?
}

struct PreviewRequest: Encodable {
    let url: String
}

struct PreviewResponse: Codable {
    let preview: PagePreview?
}

struct PagePreview: Codable {
    let ogImage: String?
    let title: String?
    let description: String?
    let domain: String?
    let features: [String]?
    let images: [String]?
}

struct GenerateRequest: Encodable {
    let url: String
    let prompt: String
    let userId: String
    let options: GenerateOptions
}

struct GenerateOptions: Encodable {
    let scenes: Int
    let duration: Int
    let style: String
}

struct GenerateResponse: Codable {
    let generationId: String
}

struct GenerationStatusResponse: Codable {
    let status: String
    let resultVideoUrl: String?
    let error: String?
}

struct GenerationListRequest: Encodable {
    let userId: String
}

actor GenerationService {
    static let shared = GenerationService()

    private let api = APIService.shared

    // MARK: - Quick Reel (SSE)

    func generateReel(
        topic: String,
        language: String,
        duration: Int,
        influencerId: String?,
        referenceVideoUrl: String?,
        onProgress: @escaping @Sendable (ReelProgress) -> Void,
        onDone: @escaping @Sendable (ReelResult) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async {
        let request = ReelRequest(
            topic: topic,
            language: language,
            duration: duration,
            influencerId: influencerId,
            referenceVideoUrl: referenceVideoUrl
        )

        do {
            try await api.streamSSE(path: "/api/reels/plan", body: request) { event in
                guard let data = event.data.data(using: .utf8) else { return }

                switch event.event {
                case "progress":
                    if let payload = try? JSONDecoder().decode([String: String].self, from: data) {
                        onProgress(ReelProgress(
                            step: payload["step"] ?? "",
                            message: payload["message"] ?? ""
                        ))
                    }
                case "done":
                    if let result = try? JSONDecoder().decode(ReelResult.self, from: data) {
                        onDone(result)
                    }
                case "error":
                    if let payload = try? JSONDecoder().decode([String: String].self, from: data) {
                        onError(payload["error"] ?? "Generation failed")
                    }
                default:
                    break
                }
            }
        } catch {
            onError(error.localizedDescription)
        }
    }

    // MARK: - Video Ad

    func previewURL(_ urlString: String) async throws -> PagePreview? {
        let response: PreviewResponse = try await api.post("/api/generate/preview", body: PreviewRequest(url: urlString))
        return response.preview
    }

    func generateAd(url: String, prompt: String, userId: String, scenes: Int, duration: Int, style: String) async throws -> String {
        let request = GenerateRequest(
            url: url,
            prompt: prompt,
            userId: userId,
            options: GenerateOptions(scenes: scenes, duration: duration, style: style)
        )
        let response: GenerateResponse = try await api.post("/api/generate", body: request)
        return response.generationId
    }

    func getGenerationStatus(id: String) async throws -> GenerationStatusResponse {
        return try await api.get("/api/generate/\(id)")
    }

    /// Check status of a local export from on-device storage (no network call).
    func getLocalGenerationStatus(id: String) -> GenerationStatusResponse {
        let generations = loadLocalGenerations()
        guard let gen = generations.first(where: { $0.id == id }) else {
            return GenerationStatusResponse(status: "processing", resultVideoUrl: nil, error: nil)
        }
        switch gen.status {
        case .saved, .completed:
            let videoUrl = gen.videoFileURL?.absoluteString ?? gen.videoUri ?? gen.resultVideoUrl
            return GenerationStatusResponse(status: "completed", resultVideoUrl: videoUrl, error: nil)
        case .failed:
            return GenerationStatusResponse(status: "failed", resultVideoUrl: nil, error: "Export failed")
        case .processing:
            return GenerationStatusResponse(status: "processing", resultVideoUrl: nil, error: nil)
        }
    }

    // MARK: - List

    func fetchGenerations(userId: String) async throws -> [Generation] {
        // Load local first (instant)
        var local = loadLocalGenerations()

        // Fetch remote from Supabase and merge
        let remote = await SupabaseService.shared.fetchGenerations(userId: userId)
        for remoteGen in remote {
            if !local.contains(where: { $0.id == remoteGen.id }) {
                local.append(remoteGen)
            }
        }

        // Sort by newest first
        local.sort { $0.createdAt > $1.createdAt }
        saveGenerations(local)
        return local
    }

    // MARK: - Local Storage (file in Documents so list survives app restart)

    private var generationsFileURL: URL {
        FileStorageService.shared.documentsDirectory.appendingPathComponent("generations.json")
    }

    private func loadLocalGenerations() -> [Generation] {
        let url = generationsFileURL
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let generations = try? JSONDecoder().decode([Generation].self, from: data) {
            return generations
        }
        // Migrate from UserDefaults if file never written (e.g. app update)
        if let data = UserDefaults.standard.data(forKey: "saved_videos"),
           let generations = try? JSONDecoder().decode([Generation].self, from: data), !generations.isEmpty {
            saveGenerations(generations)
            UserDefaults.standard.removeObject(forKey: "saved_videos")
            return generations
        }
        return []
    }

    private func saveGenerations(_ generations: [Generation]) {
        guard let data = try? JSONEncoder().encode(generations) else { return }
        let url = generationsFileURL
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[GenerationService] Failed to save list: \(error)")
        }
    }

    func saveGeneration(_ generation: Generation) {
        var existing = loadLocalGenerations()
        existing.insert(generation, at: 0)
        saveGenerations(existing)
        // Sync to Supabase in background
        Task { await SupabaseService.shared.upsertGeneration(generation) }
    }

    /// Update an existing generation by id; preserves createdAt and other fields.
    func updateGeneration(id: String, status: GenerationStatus? = nil, videoUri: String? = nil, remoteVideoUrl: String? = nil) {
        var existing = loadLocalGenerations()
        guard let idx = existing.firstIndex(where: { $0.id == id }) else { return }
        if let s = status { existing[idx].status = s }
        if let v = videoUri { existing[idx].videoUri = v }
        if let r = remoteVideoUrl { existing[idx].resultVideoUrl = r }
        saveGenerations(existing)
        // Sync to Supabase in background
        Task { await SupabaseService.shared.upsertGeneration(existing[idx], remoteVideoUrl: existing[idx].resultVideoUrl) }
    }

    func deleteGeneration(id: String) {
        var existing = loadLocalGenerations()
        // Delete local video file
        let localFile = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(id).mp4")
        if FileManager.default.fileExists(atPath: localFile.path) {
            try? FileManager.default.removeItem(at: localFile)
        }
        existing.removeAll { $0.id == id }
        saveGenerations(existing)
        // Delete from Supabase in background
        Task {
            await SupabaseService.shared.deleteGeneration(id: id)
            await SupabaseService.shared.deleteVideo(generationId: id)
        }
    }

    /// Deletes all local generations and their video files. Call when user chooses "Delete my data".
    func deleteAllLocalGenerations() {
        let existing = loadLocalGenerations()
        for gen in existing {
            let localFile = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(gen.id).mp4")
            if FileManager.default.fileExists(atPath: localFile.path) {
                try? FileManager.default.removeItem(at: localFile)
            }
            Task {
                await SupabaseService.shared.deleteGeneration(id: gen.id)
                await SupabaseService.shared.deleteVideo(generationId: gen.id)
            }
        }
        saveGenerations([])
    }
}
