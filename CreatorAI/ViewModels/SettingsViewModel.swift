import Foundation
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var credits: Int = 0
    private let userId: String

    init(userId: String) {
        self.userId = userId
    }

    func loadData() async {
        let baseURL = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://creatorai-api.polskoydm.workers.dev"
        guard let url = URL(string: "\(baseURL)/api/credits/get") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["userId": userId])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let serverCredits = json["credits"] as? Int {
                self.credits = serverCredits
            }
        } catch {
            print("[Settings] Failed to load credits: \(error)")
        }
    }
}
