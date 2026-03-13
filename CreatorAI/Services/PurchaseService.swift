import Foundation
import StoreKit

/// Credits-based IAP using StoreKit 2 (no subscriptions)
@MainActor
class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    @Published var products: [Product] = []
    @Published var isPurchasing = false

    private let productIds = ["credits_100", "credits_200", "credits_300"]
    private let creditAmounts: [String: Int] = [
        "credits_100": 100,
        "credits_200": 200,
        "credits_300": 300,
    ]

    private var transactionListener: Task<Void, Error>?

    init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: productIds)
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            print("[IAP] Failed to load products: \(error)")
        }
    }

    func purchase(_ product: Product, appState: AppState) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                let creditsToAdd = creditAmounts[product.id] ?? 100

                // Add credits on server
                await addCreditsOnServer(userId: appState.userId ?? "", amount: creditsToAdd)
                appState.addCredits(creditsToAdd)

                await transaction.finish()
                print("[IAP] Purchase successful: \(product.id) → +\(creditsToAdd) credits")
                return true

            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            print("[IAP] Purchase failed: \(error)")
            return false
        }
    }

    func restorePurchases(appState: AppState) async {
        // For consumable IAPs, there's nothing to restore
        // Just sync credits from server
        await appState.fetchCredits()
    }

    // MARK: - Private

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await transaction.finish()
                } catch {
                    print("[IAP] Transaction update error: \(error)")
                }
            }
        }
    }

    private func addCreditsOnServer(userId: String, amount: Int) async {
        let baseURL = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://api.holylabs.net"
        guard let url = URL(string: "\(baseURL)/api/credits/add") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "userId": userId,
            "amount": amount
        ])

        do {
            let _ = try await URLSession.shared.data(for: request)
        } catch {
            print("[IAP] Failed to add credits on server: \(error)")
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}
