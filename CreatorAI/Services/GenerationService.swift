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

struct UploadedImageResponse: Codable {
    let id: String
    let name: String
    let url: String
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

private struct OpenRouterVideoJob: Decodable {
    let id: String
    let pollingUrl: String?
    let status: String
    let generationId: String?
    let unsignedUrls: [String]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id, status, error
        case pollingUrl = "polling_url"
        case generationId = "generation_id"
        case unsignedUrls = "unsigned_urls"
    }
}

private struct FalQueueSubmitResponse: Decodable {
    let requestId: String?
    let statusUrl: String?
    let responseUrl: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case statusUrl = "status_url"
        case responseUrl = "response_url"
    }
}

private struct FalQueueStatusResponse: Decodable {
    let status: String?
    let error: String?
    let logs: [FalQueueLog]?
    let responseUrl: String?

    enum CodingKeys: String, CodingKey {
        case status, error, logs
        case responseUrl = "response_url"
    }
}

private struct FalQueueLog: Decodable {
    let message: String?
}

private struct OpenAIVideoJob: Decodable {
    let id: String
    let status: String?
    let error: OpenAIVideoError?
}

private struct OpenAIVideoError: Decodable {
    let message: String?
}

struct AIScriptRequest: Encodable {
    let topic: String
    let language: String
    let clipCount: Int
    let durationSeconds: Double
}

struct AIScriptScene: Codable {
    let searchQuery: String
    let subtitleText: String
    let voiceoverText: String
    let durationSeconds: Double
}

struct AIScriptPayload: Codable {
    let topic: String
    let scenes: [AIScriptScene]
    let fullVoiceover: String
    let totalDuration: Double
}

struct AIScriptResponse: Decodable {
    let success: Bool?
    let provider: String?
    let script: AIScriptPayload?
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
    private struct FalVideoJob {
        let modelId: String
        let statusUrl: String?
        let responseUrl: String?
    }

    private var falVideoJobs: [String: FalVideoJob] = [:]
    
    func getBaseURL() -> String {
        api.syncBaseURL
    }

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

    // MARK: - AI Create via fal.ai / OpenRouter Video
    
    func startAICreate(modelId: String, prompt: String, imageUrl: String?, duration: Int, userId: String?, referenceVideoUrl: String? = nil) async throws -> AICreateResponse {
        if modelId.hasPrefix("fal-ai/") {
            return try await startFalAICreate(
                modelId: modelId,
                prompt: prompt,
                imageUrl: imageUrl,
                duration: duration,
                userId: userId,
                referenceVideoUrl: referenceVideoUrl
            )
        }

        if modelId.hasPrefix("openai/") {
            return try await startOpenAICreate(
                modelId: modelId,
                prompt: prompt,
                imageUrl: imageUrl,
                duration: duration
            )
        }

        guard let apiKey = openRouterAPIKey else {
            throw APIError.sseError("Video model API is not configured for this build.")
        }

        var body: [String: Any] = [
            "model": modelId,
            "prompt": prompt,
            "duration": duration,
            "resolution": "720p",
            "aspect_ratio": "9:16",
            "generate_audio": false
        ]

        if let imageUrl, !imageUrl.isEmpty {
            body["frame_images"] = [[
                "type": "image_url",
                "image_url": ["url": imageUrl],
                "frame_type": "first_frame"
            ]]
        }

        if let referenceVideoUrl, !referenceVideoUrl.isEmpty {
            body["reference_video_url"] = referenceVideoUrl
            body["referenceVideoUrl"] = referenceVideoUrl
        }

        guard let url = URL(string: "https://openrouter.ai/api/v1/videos") else {
            throw APIError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 90
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("CreatorAI", forHTTPHeaderField: "X-OpenRouter-Title")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("[AICreate] OpenRouter POST \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[AICreate] Response: \(statusCode) \(String(data: data, encoding: .utf8) ?? "")")
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.sseError(openRouterVideoErrorMessage(code: statusCode, data: data))
        }

        let job = try JSONDecoder().decode(OpenRouterVideoJob.self, from: data)
        return AICreateResponse(
            success: job.error == nil,
            id: job.id,
            mode: "openrouter",
            model: modelId,
            status: mapOpenRouterVideoStatus(job.status),
            replicateId: job.generationId,
            error: job.error
        )
    }
    
    func pollAICreate(id: String) async throws -> AICreateStatus {
        if id.hasPrefix("openai:") {
            let rawId = String(id.dropFirst("openai:".count))
            return try await pollOpenAICreate(id: rawId)
        }

        if let falJob = falVideoJobs[id] {
            return try await pollFalAICreate(id: id, job: falJob)
        }

        guard let apiKey = openRouterAPIKey else {
            throw APIError.sseError("Video model API is not configured for this build.")
        }
        guard let url = URL(string: "https://openrouter.ai/api/v1/videos/\(id)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            throw APIError.sseError(openRouterVideoErrorMessage(code: statusCode, data: data))
        }

        let job = try JSONDecoder().decode(OpenRouterVideoJob.self, from: data)
        return AICreateStatus(
            id: job.id,
            status: mapOpenRouterVideoStatus(job.status),
            mode: "openrouter",
            model: nil,
            outputUrl: job.unsignedUrls?.first,
            error: job.error
        )
    }

    private func startOpenAICreate(modelId: String, prompt: String, imageUrl: String?, duration: Int) async throws -> AICreateResponse {
        guard let apiKey = openAIAPIKey else {
            throw APIError.sseError("Add your OpenAI API key in Settings before using Sora.")
        }
        guard let url = URL(string: "https://api.openai.com/v1/videos") else {
            throw APIError.invalidURL
        }

        let seconds = duration <= 4 ? "4" : duration <= 8 ? "8" : "12"
        var body: [String: Any] = [
            "model": modelId.replacingOccurrences(of: "openai/", with: ""),
            "prompt": prompt,
            "seconds": seconds,
            "size": "720x1280"
        ]

        if let imageUrl, !imageUrl.isEmpty {
            body["input_reference"] = [
                "type": "image_url",
                "image_url": imageUrl
            ]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[AICreate] OpenAI POST \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[AICreate] OpenAI Response: \(statusCode) \(String(data: data, encoding: .utf8) ?? "")")

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.sseError(videoProviderErrorMessage(provider: "OpenAI", code: statusCode, data: data))
        }

        let decoded = try JSONDecoder().decode(OpenAIVideoJob.self, from: data)
        return AICreateResponse(
            success: true,
            id: "openai:\(decoded.id)",
            mode: "openai",
            model: modelId,
            status: mapOpenAIStatus(decoded.status ?? "queued"),
            replicateId: nil,
            error: decoded.error?.message
        )
    }

    private func pollOpenAICreate(id: String) async throws -> AICreateStatus {
        guard let apiKey = openAIAPIKey else {
            throw APIError.sseError("Add your OpenAI API key in Settings before using Sora.")
        }
        guard let url = URL(string: "https://api.openai.com/v1/videos/\(id)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.sseError(videoProviderErrorMessage(provider: "OpenAI", code: statusCode, data: data))
        }

        let decoded = try JSONDecoder().decode(OpenAIVideoJob.self, from: data)
        let status = mapOpenAIStatus(decoded.status ?? "queued")
        let outputPath = status == "succeeded" ? try await downloadOpenAIContent(id: id, apiKey: apiKey) : nil
        return AICreateStatus(
            id: "openai:\(decoded.id)",
            status: status,
            mode: "openai",
            model: nil,
            outputUrl: outputPath,
            error: decoded.error?.message
        )
    }

    private func downloadOpenAIContent(id: String, apiKey: String) async throws -> String {
        let output = FileStorageService.shared.cacheDirectory.appendingPathComponent("openai_\(id).mp4")
        if FileManager.default.fileExists(atPath: output.path) {
            return output.path
        }
        guard let url = URL(string: "https://api.openai.com/v1/videos/\(id)/content") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 600
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.sseError("OpenAI content download failed with HTTP \(statusCode).")
        }
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: tempURL, to: output)
        return output.path
    }

    private func startFalAICreate(modelId: String, prompt: String, imageUrl: String?, duration: Int, userId: String?, referenceVideoUrl: String?) async throws -> AICreateResponse {
        guard let apiKey = falAPIKey else {
            throw APIError.sseError("Add your fal.ai API key in Settings before using fal video models.")
        }
        let normalizedModelId = normalizedFalVideoModelId(modelId)
        guard let url = URL(string: "https://queue.fal.run/\(normalizedModelId)") else {
            throw APIError.invalidURL
        }

        var input: [String: Any] = [
            "prompt": prompt,
            "duration": max(5, min(15, duration)),
            "aspect_ratio": "9:16",
            "resolution": "720p",
            "generate_audio": true
        ]

        if let imageUrl, !imageUrl.isEmpty {
            input["image_url"] = imageUrl
            input["first_frame_image"] = imageUrl
        }

        if let referenceVideoUrl, !referenceVideoUrl.isEmpty {
            input["video_url"] = referenceVideoUrl
            input["reference_video_url"] = referenceVideoUrl
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(falAuthorizationHeader(for: apiKey), forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: input)

        print("[AICreate] fal.ai POST \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[AICreate] fal.ai Response: \(statusCode) \(String(data: data, encoding: .utf8) ?? "")")

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.sseError(videoProviderErrorMessage(provider: "fal.ai", code: statusCode, data: data))
        }

        let decoded = try JSONDecoder().decode(FalQueueSubmitResponse.self, from: data)
        guard let requestId = decoded.requestId, !requestId.isEmpty else {
            throw APIError.sseError("fal.ai did not return a request id.")
        }

        falVideoJobs[requestId] = FalVideoJob(
            modelId: normalizedModelId,
            statusUrl: decoded.statusUrl,
            responseUrl: decoded.responseUrl
        )
        print("[AICreate] fal.ai queued request=\(requestId) statusUrl=\(decoded.statusUrl ?? "nil") responseUrl=\(decoded.responseUrl ?? "nil")")
        return AICreateResponse(
            success: true,
            id: requestId,
            mode: "fal",
            model: normalizedModelId,
            status: "processing",
            replicateId: nil,
            error: nil
        )
    }

    private func normalizedFalVideoModelId(_ modelId: String) -> String {
        switch modelId {
        case "fal-ai/kling-video/v2.1/pro/text-to-video":
            return "fal-ai/kling-video/v2.5-turbo/pro/text-to-video"
        default:
            return modelId
        }
    }

    private func pollFalAICreate(id: String, job: FalVideoJob) async throws -> AICreateStatus {
        guard let apiKey = falAPIKey else {
            throw APIError.sseError("Add your fal.ai API key in Settings before using fal video models.")
        }
        let fallbackStatusURL = "https://queue.fal.run/\(job.modelId)/requests/\(id)/status"
        let fallbackResultURL = "https://queue.fal.run/\(job.modelId)/requests/\(id)"
        guard let statusURL = URL(string: job.statusUrl ?? fallbackStatusURL),
              let fallbackResult = URL(string: fallbackResultURL) else {
            throw APIError.invalidURL
        }

        var statusRequest = URLRequest(url: statusURL)
        statusRequest.httpMethod = "GET"
        statusRequest.setValue(falAuthorizationHeader(for: apiKey), forHTTPHeaderField: "Authorization")

        let (statusData, statusResponse) = try await URLSession.shared.data(for: statusRequest)
        let statusCode = (statusResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            throw APIError.sseError(videoProviderErrorMessage(provider: "fal.ai", code: statusCode, data: statusData))
        }

        let queueStatus = try JSONDecoder().decode(FalQueueStatusResponse.self, from: statusData)
        let mappedStatus = mapFalStatus(queueStatus.status ?? "")
        if mappedStatus == "failed" {
            falVideoJobs[id] = nil
            return AICreateStatus(id: id, status: "failed", mode: "fal", model: job.modelId, outputUrl: nil, error: queueStatus.error ?? queueStatus.logs?.last?.message)
        }
        guard mappedStatus == "succeeded" else {
            return AICreateStatus(id: id, status: mappedStatus, mode: "fal", model: job.modelId, outputUrl: nil, error: nil)
        }

        let resultURL = URL(string: queueStatus.responseUrl ?? job.responseUrl ?? fallbackResultURL) ?? fallbackResult
        var resultRequest = URLRequest(url: resultURL)
        resultRequest.httpMethod = "GET"
        resultRequest.setValue(falAuthorizationHeader(for: apiKey), forHTTPHeaderField: "Authorization")

        let (resultData, resultResponse) = try await URLSession.shared.data(for: resultRequest)
        let resultCode = (resultResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(resultCode) else {
            throw APIError.sseError(videoProviderErrorMessage(provider: "fal.ai", code: resultCode, data: resultData))
        }

        falVideoJobs[id] = nil
        let outputUrl = falOutputVideoURL(from: resultData)
        if outputUrl == nil {
            let preview = String(data: resultData, encoding: .utf8) ?? ""
            print("[AICreate] fal.ai completed but no video URL was parsed: \(String(preview.prefix(600)))")
        }

        return AICreateStatus(
            id: id,
            status: "succeeded",
            mode: "fal",
            model: job.modelId,
            outputUrl: outputUrl,
            error: outputUrl == nil ? "fal.ai completed but no video URL was found in the result." : nil
        )
    }

    private var openRouterAPIKey: String? {
        let env = ProcessInfo.processInfo.environment
        return env["OPENROUTER_API_KEY"]
            ?? env["OPENROUTER_KEY"]
            ?? secretValue("OPENROUTER_API_KEY")
            ?? (Bundle.main.object(forInfoDictionaryKey: "OPENROUTER_API_KEY") as? String)
            ?? UserDefaults.standard.string(forKey: "OPENROUTER_API_KEY")
    }

    private var falAPIKey: String? {
        let env = ProcessInfo.processInfo.environment
        return env["FAL_API_KEY"]
            ?? env["FAL_KEY"]
            ?? secretValue("FAL_API_KEY")
            ?? (Bundle.main.object(forInfoDictionaryKey: "FAL_API_KEY") as? String)
            ?? UserDefaults.standard.string(forKey: "FAL_API_KEY")
    }

    private func falAuthorizationHeader(for apiKey: String) -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.lowercased().hasPrefix("key ") {
            return trimmedKey
        }
        return "Key \(trimmedKey)"
    }

    private var openAIAPIKey: String? {
        let env = ProcessInfo.processInfo.environment
        return env["OPENAI_API_KEY"]
            ?? secretValue("OPENAI_API_KEY")
            ?? (Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String)
            ?? UserDefaults.standard.string(forKey: "OPENAI_API_KEY")
    }

    private func secretValue(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let value = plist[key] as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func openRouterVideoErrorMessage(code: Int, data: Data) -> String {
        videoProviderErrorMessage(provider: "Video model", code: code, data: data)
    }

    private func videoProviderErrorMessage(provider: String, code: Int, data: Data) -> String {
        let detail: String
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any] {
            detail = (error["message"] as? String) ?? (error["code"] as? String) ?? ""
        } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? String {
            detail = message
        } else {
            detail = String(data: data, encoding: .utf8) ?? ""
        }

        let cleaned = detail
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return "\(provider) HTTP error \(code)."
        }
        return "\(provider) HTTP error \(code): \(String(cleaned.prefix(180)))"
    }

    private func mapOpenRouterVideoStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "completed":
            return "succeeded"
        case "failed", "cancelled", "canceled", "expired":
            return "failed"
        case "pending", "in_progress", "queued", "running":
            return "processing"
        default:
            return status
        }
    }

    private func mapFalStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "completed":
            return "succeeded"
        case "failed", "cancelled", "canceled":
            return "failed"
        case "in_queue", "in_progress", "queued", "running":
            return "processing"
        default:
            return status.isEmpty ? "processing" : status
        }
    }

    private func mapOpenAIStatus(_ status: String) -> String {
        switch status.lowercased() {
        case "completed", "succeeded":
            return "succeeded"
        case "failed", "cancelled", "canceled", "expired":
            return "failed"
        case "queued", "in_progress", "processing", "running":
            return "processing"
        default:
            return status.isEmpty ? "processing" : status
        }
    }

    private func falOutputVideoURL(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return findFalVideoURL(in: root)
    }

    private func findFalVideoURL(in value: Any) -> String? {
        if let string = value as? String, looksLikeVideoURL(string) {
            return string
        }

        if let dictionary = value as? [String: Any] {
            let preferredKeys = ["video", "videos", "output", "data", "file", "url", "content", "result"]
            for key in preferredKeys {
                if let nested = dictionary[key], let found = findFalVideoURL(in: nested) {
                    return found
                }
            }
            for (_, nested) in dictionary {
                if let found = findFalVideoURL(in: nested) {
                    return found
                }
            }
        }

        if let array = value as? [Any] {
            for nested in array {
                if let found = findFalVideoURL(in: nested) {
                    return found
                }
            }
        }

        return nil
    }

    private func looksLikeVideoURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
        return lower.contains(".mp4")
            || lower.contains(".mov")
            || lower.contains(".webm")
            || lower.contains("video")
            || lower.contains("fal.media")
    }

    func generateAIScript(topic: String, language: String, clipCount: Int) async throws -> AIScriptPayload {
        let baseURL = api.baseURL
        guard let url = URL(string: "\(baseURL)/api/ai/script") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AIScriptRequest(
            topic: topic,
            language: language,
            clipCount: clipCount,
            durationSeconds: Double(clipCount) * 2.5
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode)
        }

        let decoded = try JSONDecoder().decode(AIScriptResponse.self, from: data)
        if let script = decoded.script {
            return script
        }
        throw APIError.noData
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

    func uploadReferenceImage(imageData: Data, filename: String, userId: String) async throws -> UploadedImageResponse {
        let baseURL = api.baseURL
        guard let url = URL(string: "\(baseURL)/api/uploads/image") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"userId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(userId)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
        body.append("Reference image\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(UploadedImageResponse.self, from: data)
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
        if let createStatus = try? await api.get("/api/create/status/\(id)") as AICreateStatus,
           let createStatusStr = createStatus.status {
            return GenerationStatusResponse(
                status: createStatusStr == "succeeded" ? "completed" : createStatusStr,
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
            return GenerationStatusResponse(status: "failed", resultVideoUrl: nil, error: gen.errorMessage ?? "Export failed")
        case .processing:
            return GenerationStatusResponse(status: "processing", resultVideoUrl: nil, error: nil)
        }
    }

    // MARK: - List

    func fetchGenerations(userId: String) async throws -> [Generation] {
        // The user's video library is device-local only. Do not merge remote
        // generations here; otherwise one account/config mistake can expose
        // another user's generated videos in Library.
        let deletedIds = loadDeletedGenerationIds()
        var local = loadLocalGenerations().filter {
            !deletedIds.contains($0.id) && $0.hasLocalLibraryMedia
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

    private var deletedGenerationsFileURL: URL {
        FileStorageService.shared.documentsDirectory.appendingPathComponent("deleted_generations.json")
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

    private func loadDeletedGenerationIds() -> Set<String> {
        let url = deletedGenerationsFileURL
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            return Set(ids)
        }
        return []
    }

    private func saveDeletedGenerationIds(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(Array(ids)) else { return }
        do {
            try data.write(to: deletedGenerationsFileURL, options: [.atomic])
        } catch {
            print("[GenerationService] Failed to save deleted ids: \(error)")
        }
    }

    private func markGenerationDeleted(_ id: String) {
        var ids = loadDeletedGenerationIds()
        ids.insert(id)
        saveDeletedGenerationIds(ids)
    }

    func saveGeneration(_ generation: Generation) {
        var deletedIds = loadDeletedGenerationIds()
        if deletedIds.remove(generation.id) != nil {
            saveDeletedGenerationIds(deletedIds)
        }
        var existing = loadLocalGenerations()
        existing.removeAll { $0.id == generation.id }
        existing.insert(generation, at: 0)
        saveGenerations(existing)
    }

    /// Update an existing generation by id; preserves createdAt and other fields.
    func updateGeneration(id: String, status: GenerationStatus? = nil, videoUri: String? = nil, remoteVideoUrl: String? = nil, takesJson: String? = nil, musicFile: String? = nil, errorMessage: String? = nil) {
        var existing = loadLocalGenerations()
        guard let idx = existing.firstIndex(where: { $0.id == id }) else { return }
        if let s = status { existing[idx].status = s }
        if let v = videoUri { existing[idx].videoUri = v }
        if let r = remoteVideoUrl { existing[idx].resultVideoUrl = r }
        if let t = takesJson { existing[idx].takesJson = t }
        if let m = musicFile { existing[idx].musicFile = m }
        if let e = errorMessage { existing[idx].errorMessage = e }
        saveGenerations(existing)
    }

    func deleteGeneration(id: String) {
        var existing = loadLocalGenerations()
        let deleted = existing.first { $0.id == id }
        markGenerationDeleted(id)
        deleteLocalFiles(for: deleted, id: id)
        existing.removeAll { $0.id == id }
        saveGenerations(existing)
    }

    /// Deletes all local generations and their video files. Call when user chooses "Delete my data".
    func deleteAllLocalGenerations() {
        let existing = loadLocalGenerations()
        for gen in existing {
            markGenerationDeleted(gen.id)
            deleteLocalFiles(for: gen, id: gen.id)
        }
        saveGenerations([])
    }

    private func deleteLocalFiles(for generation: Generation?, id: String) {
        let storage = FileStorageService.shared
        let fm = FileManager.default
        let savedDir = storage.savedVideosDirectory
        let thumbDir = storage.thumbnailCacheDirectory

        deleteFileIfInAppStorage(savedDir.appendingPathComponent("\(id).mp4"))
        deleteFileIfInAppStorage(thumbDir.appendingPathComponent("\(id).jpg"))

        if let files = try? fm.contentsOfDirectory(at: savedDir, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("\(id)_") {
                deleteFileIfInAppStorage(file)
            }
        }

        guard let generation else { return }

        deletePathIfInAppStorage(generation.videoUri)
        deletePathIfInAppStorage(generation.thumbnailPath)

        if let takesJson = generation.takesJson,
           let data = takesJson.data(using: .utf8),
           let clips = try? JSONDecoder().decode([Clip].self, from: data) {
            for clip in clips {
                deletePathIfInAppStorage(clip.uri)
                deletePathIfInAppStorage(clip.localUri)
                deletePathIfInAppStorage(clip.overlayImageUri)
            }
        }
    }

    private func deletePathIfInAppStorage(_ rawPath: String?) {
        guard let rawPath, !rawPath.isEmpty, !rawPath.hasPrefix("http") else { return }
        let path = rawPath.replacingOccurrences(of: "file://", with: "")
        deleteFileIfInAppStorage(URL(fileURLWithPath: path))
    }

    private func deleteFileIfInAppStorage(_ url: URL) {
        let storage = FileStorageService.shared
        let path = url.path
        let allowedRoots = [
            storage.documentsDirectory.path,
            storage.cacheDirectory.path
        ]
        guard allowedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return }
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
