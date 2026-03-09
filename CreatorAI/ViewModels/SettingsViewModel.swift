import SwiftUI
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var credits: Int = 3
    @Published var totalGenerations: Int = 0
    @Published var isSubscribed = false

    private let userId: String
    private let purchaseService = PurchaseService.shared
    private var cancellable: AnyCancellable?

    init(userId: String = "demo-user") {
        self.userId = userId

        // Observe PurchaseService subscription changes in real-time
        cancellable = purchaseService.$isSubscribed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subscribed in
                self?.isSubscribed = subscribed
            }
    }

    func loadData() async {
        do {
            let response = try await CreditsService.shared.fetchCredits(userId: userId)
            credits = response.credits
            totalGenerations = response.totalGenerations ?? 0
        } catch {
            print("Failed to load credits: \(error)")
        }

        // Refresh subscription status from RevenueCat
        await purchaseService.refreshStatus()
        isSubscribed = purchaseService.isSubscribed
    }

    func handleRestore() async -> Bool {
        let restored = await purchaseService.restorePurchases()
        if restored {
            isSubscribed = true
        }
        return restored
    }
}
