import Foundation
import RevenueCat
import RevenueCatUI

// Set your RevenueCat iOS API key (from RevenueCat dashboard → Project → API keys).
// Use the same project as your React app; the iOS key is different from the Android/React key.
private let revenueCatAPIKey = "appl_KcCxWUWBcwWpTDjeoWMSASAXwLY"

@MainActor
class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    @Published var isReady = false
    @Published var isSubscribed = false

    private var isConfigured = false

    private init() {}

    func configure(userId: String) {
        guard !isConfigured else {
            // Already configured, just update the user
            Purchases.shared.logIn(userId) { info, _, error in
                if let info = info {
                    Task { @MainActor in
                        self.isSubscribed = !info.entitlements.active.isEmpty
                        self.isReady = true
                    }
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

        Purchases.shared.getCustomerInfo { info, error in
            Task { @MainActor in
                if let info = info {
                    self.isSubscribed = !info.entitlements.active.isEmpty
                }
                self.isReady = true
                print("[PurchaseService] Configured for user: \(userId), subscribed: \(self.isSubscribed)")
            }
        }

        // Listen for real-time subscription changes
        Purchases.shared.delegate = PurchaseDelegateHandler.shared
    }

    func restorePurchases() async -> Bool {
        do {
            let info = try await Purchases.shared.restorePurchases()
            isSubscribed = !info.entitlements.active.isEmpty
            return isSubscribed
        } catch {
            print("[PurchaseService] Restore failed: \(error)")
            return false
        }
    }

    func refreshStatus() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            isSubscribed = !info.entitlements.active.isEmpty
        } catch {
            print("[PurchaseService] Failed to refresh status: \(error)")
        }
    }
}

// MARK: - Delegate to listen for subscription changes
class PurchaseDelegateHandler: NSObject, PurchasesDelegate {
    static let shared = PurchaseDelegateHandler()

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            PurchaseService.shared.isSubscribed = !customerInfo.entitlements.active.isEmpty
        }
    }
}
