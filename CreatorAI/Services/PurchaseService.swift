import Foundation
import RevenueCat
import RevenueCatUI

private let revenueCatAPIKey = "appl_KcCxWUWBcwWpTDjeoWMSASAXwLY"

/// Credits-based IAP via RevenueCat (consumable products)
@MainActor
class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    @Published var isReady = false
    @Published var isPurchasing = false

    private var isConfigured = false

    private let creditAmounts: [String: Int] = [
        "credits_100": 100,
        "credits_200": 200,
        "credits_300": 300,
    ]

    private init() {}

    func configure(userId: String) {
        guard !isConfigured else {
            Purchases.shared.logIn(userId) { info, _, error in
                Task { @MainActor in
                    self.isReady = true
                }
            }
            return
        }

        Purchases.configure(
            with: .builder(withAPIKey: revenueCatAPIKey)
                .with(appUserID: userId)
                .build()
        )
        isConfigured = true
        isReady = true

        Purchases.shared.delegate = PurchaseDelegateHandler.shared
        print("[PurchaseService] Configured for user: \(userId)")
    }

    /// Called after RevenueCat PaywallView completes a purchase — sync credits to server
    func handlePurchaseCompleted(appState: AppState) async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let recent = customerInfo.nonSubscriptions
                .sorted { $0.purchaseDate > $1.purchaseDate }

            if let latest = recent.first {
                let productId = latest.productIdentifier
                let creditsToAdd = creditAmounts[productId] ?? 100

                await addCreditsOnServer(userId: appState.userId ?? "", productId: productId, amount: creditsToAdd)
                appState.addCredits(creditsToAdd)
                print("[IAP] PaywallView purchase: \(productId) → +\(creditsToAdd) credits")
            }
        } catch {
            print("[IAP] Failed to get customer info after purchase: \(error)")
        }

        await appState.fetchCredits()
    }

    func restorePurchases() async -> Bool {
        do {
            let _ = try await Purchases.shared.restorePurchases()
            return true
        } catch {
            print("[PurchaseService] Restore failed: \(error)")
            return false
        }
    }

    // MARK: - Private

    private func addCreditsOnServer(userId: String, productId: String, amount: Int) async {
        let baseURL = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://api.holylabs.net"
        guard let url = URL(string: "\(baseURL)/api/credits/add") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "userId": userId,
            "productId": productId,
            "amount": amount,
        ])

        do {
            let _ = try await URLSession.shared.data(for: request)
        } catch {
            print("[IAP] Failed to add credits on server: \(error)")
        }
    }
}

// MARK: - Delegate

class PurchaseDelegateHandler: NSObject, PurchasesDelegate {
    static let shared = PurchaseDelegateHandler()

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        // Credits are server-side, no subscription tracking needed
    }
}
