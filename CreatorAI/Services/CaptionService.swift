import Foundation

/// Requests cloud caption burn-in from EC2 caption service (44.201.125.130:3001).
actor CaptionService {
    static let shared = CaptionService()

    private let baseURL: String = {
        ProcessInfo.processInfo.environment["CAPTION_SERVICE_URL"] ?? "http://44.201.125.130:3001"
    }()

    private init() {}

    /// Request caption burn-in. Returns the captioned video URL on success.
    func requestCloudCaptions(generationId: String, videoUri: String, takesJson: String?) async -> String? {
        guard let url = URL(string: "\(baseURL)/api/generations/\(generationId)/add-captions") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "videoUri": videoUri,
            "takesJson": takesJson ?? "[]"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = data

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
            return json?["outputUrl"] as? String
        } catch {
            print("[CaptionService] Request failed: \(error)")
            return nil
        }
    }
}
