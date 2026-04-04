import Foundation
import RevenueCat
#if os(iOS)
import RevenueCatUI
#endif

private let revenueCatAPIKey = "appl_KcCxWUWBcwWpTDjeoWMSASAXwLY"

/// Credits-based IAP via RevenueCat (consumable products)
@MainActor
class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    @Published var isReady = false
    @Published var isPurchasing = false
    @Published var packages: [Package] = []

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

    /// Called after a purchase with the product ID — sync credits to server
    func handlePurchaseCompleted(productId: String, appState: AppState) async {
        let creditsToAdd = creditAmounts[productId] ?? 100
        await addCreditsOnServer(userId: appState.userId ?? "", productId: productId, amount: creditsToAdd)
        print("[IAP] Purchase: \(productId) → +\(creditsToAdd) credits")
        await appState.fetchCredits()
    }

    /// Fallback: called from PaywallView which only gives CustomerInfo — infer product from most recent transaction
    func handlePurchaseCompleted(appState: AppState) async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let recent = customerInfo.nonSubscriptions
                .sorted { $0.purchaseDate > $1.purchaseDate }

            if let latest = recent.first {
                await handlePurchaseCompleted(productId: latest.productIdentifier, appState: appState)
            } else {
                await appState.fetchCredits()
            }
        } catch {
            print("[IAP] Failed to get customer info after purchase: \(error)")
            await appState.fetchCredits()
        }
    }

    func loadOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            if let current = offerings.current {
                packages = current.availablePackages
            }
        } catch {
            print("[PurchaseService] Failed to load offerings: \(error)")
        }
    }

    /// Purchase a package and sync credits to server. Returns true on success.
    func purchase(_ package: Package, appState: AppState) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            guard !result.userCancelled else { return false }
            let productId = package.storeProduct.productIdentifier
            await handlePurchaseCompleted(productId: productId, appState: appState)
            return true
        } catch {
            print("[PurchaseService] Purchase failed: \(error)")
            return false
        }
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
        let baseURL = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://creatorai-api.polskoydm.workers.dev"
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
