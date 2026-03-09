import Foundation

struct CreditsRequest: Encodable {
    let userId: String
}

struct CreditsResponse: Codable {
    let credits: Int
    let totalGenerations: Int?

    enum CodingKeys: String, CodingKey {
        case credits
        case totalGenerations = "total_generations"
    }
}

actor CreditsService {
    static let shared = CreditsService()

    func fetchCredits(userId: String) async throws -> CreditsResponse {
        return try await APIService.shared.post("/api/credits/get", body: CreditsRequest(userId: userId))
    }
}
