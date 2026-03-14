import Foundation
import RevenueCat

/// Credits-based IAP via RevenueCat (consumable, no subscriptions)
@MainActor
class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    @Published var packages: [Package] = []
    @Published var isPurchasing = false

    private let creditAmounts: [String: Int] = [
        "credits_100": 100,
        "credits_200": 200,
        "credits_300": 300,
    ]

    func configure(userId: String) {
        Purchases.configure(withAPIKey: "appl_XYZyourRevenueCatKey", appUserID: userId)
        Purchases.shared.delegate = PurchaseDelegateHandler.shared
        Task { await loadOfferings() }
    }

    func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            if let current = offerings.current {
                packages = current.availablePackages
            }
        } catch {
            print("[IAP] Failed to load offerings: \(error)")
        }
    }

    func purchase(_ package: Package, appState: AppState) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)

            if !result.userCancelled {
                let productId = package.storeProduct.productIdentifier
                let creditsToAdd = creditAmounts[productId] ?? 100

                // Add credits on server
                await addCreditsOnServer(userId: appState.userId ?? "", productId: productId, amount: creditsToAdd)
                appState.addCredits(creditsToAdd)

                print("[IAP] Purchase successful: \(productId) → +\(creditsToAdd) credits")
                return true
            }
            return false
        } catch {
            print("[IAP] Purchase failed: \(error)")
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

// MARK: - RevenueCat Delegate

class PurchaseDelegateHandler: NSObject, PurchasesDelegate {
    static let shared = PurchaseDelegateHandler()

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        // No subscription logic — credits are server-side
    }
}
