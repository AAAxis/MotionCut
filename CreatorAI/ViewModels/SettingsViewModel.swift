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
        credits = UserDefaults.standard.object(forKey: "user_credits") as? Int ?? 0
    }
}
