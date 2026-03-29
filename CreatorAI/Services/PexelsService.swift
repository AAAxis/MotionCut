import Foundation

struct PexelsVideoResult {
    let id: Int
    let videoUrl: String
    let thumbnailUrl: String?
    let duration: Int
    let width: Int
    let height: Int
}

/// Stock video search via Pexels API. Direct port of Android PexelsService.
final class PexelsService {
    static let shared = PexelsService()
    private init() {}

    private var primaryKey: String?
    private let fallbackKey = "Cw9YEAkWimspZgB3Ek2or7rQQ9WMDL3Y3RLRxPPxLGjBUsaF14f70Hjc"
    private let baseURL = "https://api.pexels.com/videos"

    private let fallbackQueries = [
        "business technology", "city lifestyle", "people working",
        "nature cinematic", "modern office", "social media",
        "product showcase", "creative workspace", "motivation success",
        "smartphone technology", "shopping online", "happy people"
    ]

    func setPrimaryKey(_ key: String) { primaryKey = key }
    private var apiKey: String { primaryKey ?? fallbackKey }

    /// Search for stock footage. Never returns empty — falls back to generic queries.
    func searchVideos(query: String, perPage: Int = 5, orientation: String = "portrait") async -> [PexelsVideoResult] {
        do {
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(baseURL)/search?query=\(encoded)&per_page=\(perPage)&orientation=\(orientation)") else {
                return []
            }

            // Try keys in order
            let keys = [primaryKey, fallbackKey].compactMap { $0 }
            var responseData: Data?

            for key in keys {
                var request = URLRequest(url: url)
                request.setValue(key, forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 10

                if let (data, response) = try? await URLSession.shared.data(for: request),
                   let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    responseData = data
                    break
                }
            }

            guard let data = responseData else { return [] }

            let parsed = try JSONDecoder().decode(PexelsSearchResponse.self, from: data)
            let results = parseVideos(parsed)

            // Fallback: simplified query
            if results.isEmpty && query.split(separator: " ").count > 2 {
                let simplified = query.split(separator: " ").prefix(2).joined(separator: " ")
                return await searchVideos(query: simplified, perPage: perPage, orientation: orientation)
            }

            // Fallback: random generic query
            if results.isEmpty {
                let fallback = fallbackQueries.randomElement()!
                return await searchVideosInternal(query: fallback, perPage: perPage, orientation: orientation)
            }

            return results
        } catch {
            print("[Pexels] Search failed: \(error)")
            return await searchVideosInternal(query: fallbackQueries.randomElement()!, perPage: perPage, orientation: orientation)
        }
    }

    /// Internal search without recursion fallback.
    private func searchVideosInternal(query: String, perPage: Int, orientation: String) async -> [PexelsVideoResult] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search?query=\(encoded)&per_page=\(perPage)&orientation=\(orientation)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return []
        }

        guard let parsed = try? JSONDecoder().decode(PexelsSearchResponse.self, from: data) else {
            return []
        }

        return parseVideos(parsed)
    }

    private func parseVideos(_ response: PexelsSearchResponse) -> [PexelsVideoResult] {
        response.videos.compactMap { video in
            // Prefer HD file with height >= 720
            let file = video.video_files
                .filter { $0.quality == "hd" || $0.quality == "sd" }
                .sorted { ($0.height ?? 0) > ($1.height ?? 0) }
                .first ?? video.video_files.first

            guard let file else { return nil }

            return PexelsVideoResult(
                id: video.id,
                videoUrl: file.link,
                thumbnailUrl: video.image,
                duration: video.duration,
                width: file.width ?? 0,
                height: file.height ?? 0
            )
        }
    }
}

// MARK: - JSON models

private struct PexelsSearchResponse: Decodable {
    let total_results: Int
    let videos: [PexelsVideo]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total_results = (try? container.decode(Int.self, forKey: .total_results)) ?? 0
        videos = (try? container.decode([PexelsVideo].self, forKey: .videos)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case total_results, videos
    }
}

private struct PexelsVideo: Decodable {
    let id: Int
    let image: String?
    let duration: Int
    let video_files: [PexelsVideoFile]
}

private struct PexelsVideoFile: Decodable {
    let id: Int
    let quality: String?
    let width: Int?
    let height: Int?
    let link: String
}
