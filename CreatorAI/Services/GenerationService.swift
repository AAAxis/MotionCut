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

struct ReelGenerateResponse: Codable {
    let success: Bool?
    let hook: String?
    let subtitle: String?
    let search: [String]?
    let duration: Int?
    let downloadUrl: String?
}

struct InfluenceStartResponse: Codable {
    let success: Bool?
    let id: String
    let status: String?
    let pollUrl: String?
}

struct InfluenceStatusResponse: Codable {
    let id: String
    let status: String
    let outputUrl: String?
    let topic: String?
    let duration: Int?
    let createdAt: String?
    let completedAt: String?
}

struct UploadedVideoResponse: Codable {
    let id: String
    let url: String
    let filename: String?
    let duration: Double?
    let width: Int?
    let height: Int?
    let fps: Int?
    let fileSize: Int?
    let status: String?
}

// MARK: - AI Create (Replicate)

struct AICreateRequest: Encodable {
    let modelId: String
    let prompt: String
    let imageUrl: String?
    let duration: Int
    let userId: String?
}

struct AICreateResponse: Decodable {
    let success: Bool?
    let id: String?
    let mode: String?
    let model: String?
    let status: String?
    let replicateId: String?
    let error: String?
}

struct AICreateStatus: Decodable {
    let id: String?
    let status: String?
    let mode: String?
    let model: String?
    let outputUrl: String?
    let error: String?
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
    var language: String = "en"
}

struct GenerateResponse: Codable {
    let generationId: String
}

struct AdGenerateRequest: Encodable {
    let url: String
    let notes: String
    let userId: String
    let language: String
}

struct AdGenerateResponse: Codable {
    let id: String
    let status: String
}

struct AdOutputInfo: Codable {
    let download: String?
    let clips: [String]?
    let audio: String?
}

struct AdStatusResponse: Codable {
    let id: String
    let status: String
    let step: String?
    let script: String?
    let output: AdOutputInfo?
    let error: String?
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

    // MARK: - Single Reel Video

    func generateReel(
        topic: String,
        language: String,
        duration: Int,
        influencerId: String?,
        referenceVideoUrl: String?
    ) async throws -> ReelGenerateResponse {
        let request = ReelRequest(
            topic: topic,
            language: language,
            duration: duration,
            influencerId: influencerId,
            referenceVideoUrl: referenceVideoUrl
        )
        let baseURL = api.baseURL
        guard let url = URL(string: "\(baseURL)/api/reels/generate") else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 600
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(ReelGenerateResponse.self, from: data)
    }

    // MARK: - AI Create via Replicate
    
    func startAICreate(modelId: String, prompt: String, imageUrl: String?, duration: Int, userId: String?) async throws -> AICreateResponse {
        let body: [String: Any?] = [
            "modelId": modelId,
            "prompt": prompt,
            "imageUrl": imageUrl,
            "duration": duration,
            "userId": userId
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 })
        
        let baseURL = api.baseURL
        guard let url = URL(string: "\(baseURL)/api/create/generate") else {
            throw APIError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = jsonData
        
        print("[AICreate] POST \(url.absoluteString) body=\(String(data: jsonData, encoding: .utf8) ?? "")")
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[AICreate] Response: \(statusCode) \(String(data: data, encoding: .utf8) ?? "")")
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode)
        }
        return try JSONDecoder().decode(AICreateResponse.self, from: data)
    }
    
    func pollAICreate(id: String) async throws -> AICreateStatus {
        let baseURL = api.baseURL
        guard let url = URL(string: "\(baseURL)/api/create/status/\(id)") else {
            throw APIError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(AICreateStatus.self, from: data)
    }
    
    func uploadReferenceVideo(fileURL: URL, userId: String) async throws -> UploadedVideoResponse {
        let baseURL = api.baseURL
        guard let url = URL(string: "\(baseURL)/api/uploads/video") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent.isEmpty ? "\(UUID().uuidString).mp4" : fileURL.lastPathComponent
        let mimeType = "video/mp4"

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"userId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(userId)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(UploadedVideoResponse.self, from: data)
    }

    func startInfluenceReel(
        topic: String,
        duration: Int,
        influencerId: String?,
        referenceVideoUrl: String,
        userId: String
    ) async throws -> InfluenceStartResponse {
        let baseURL = api.baseURL
        guard let url = URL(string: "\(baseURL)/api/reels/influence") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "topic": topic,
            "duration": duration,
            "influencerId": influencerId as Any,
            "referenceVideoUrl": referenceVideoUrl,
            "userId": userId,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(InfluenceStartResponse.self, from: data)
    }

    func getInfluenceStatus(id: String) async throws -> InfluenceStatusResponse {
        let response: InfluenceStatusResponse = try await api.get("/api/reels/influence/status/\(id)")
        return response
    }

    // MARK: - Video Ad

    func previewURL(_ urlString: String) async throws -> PagePreview? {
        let response: PreviewResponse = try await api.post("/api/generate/preview", body: PreviewRequest(url: urlString))
        return response.preview
    }

    func generateAd(url: String, prompt: String, userId: String, scenes: Int, duration: Int, style: String, language: String = "en") async throws -> String {
        let adRequest = AdGenerateRequest(url: url, notes: prompt, userId: userId, language: language)
        let response: AdGenerateResponse = try await api.post("/api/ads/generate", body: adRequest)
        return response.id
    }

    func getGenerationStatus(id: String) async throws -> GenerationStatusResponse {
        // Try ads endpoint first
        if let adStatus = try? await api.get("/api/ads/status/\(id)") as AdStatusResponse,
           adStatus.status != "not_found" {
            return GenerationStatusResponse(
                status: adStatus.status == "succeeded" ? "completed" : adStatus.status,
                resultVideoUrl: adStatus.output?.download != nil ? "\(api.baseURL)\(adStatus.output!.download!)" : nil,
                error: adStatus.error
            )
        }
        // Fall back to create endpoint
        if let createStatus = try? await api.get("/api/create/status/\(id)") as AICreateStatus {
            return GenerationStatusResponse(
                status: createStatus.status == "succeeded" ? "completed" : createStatus.status,
                resultVideoUrl: createStatus.outputUrl,
                error: createStatus.error
            )
        }
        // Fall back to old generate endpoint
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
