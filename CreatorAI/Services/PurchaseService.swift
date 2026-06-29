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
    @Published var subscriptionPlan: CreatorSubscriptionPlan = .none

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
        Task { await refreshSubscriptionStatus() }
    }

    @discardableResult
    func refreshSubscriptionStatus() async -> CreatorSubscriptionPlan {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let plan = Self.subscriptionPlan(from: customerInfo)
            subscriptionPlan = plan
            UserDefaults.standard.set(plan.rawValue, forKey: "creator_subscription_plan")
            return plan
        } catch {
            print("[PurchaseService] Failed to refresh subscription: \(error)")
            let cached = UserDefaults.standard.string(forKey: "creator_subscription_plan")
                .flatMap(CreatorSubscriptionPlan.init(rawValue:)) ?? .none
            subscriptionPlan = cached
            return cached
        }
    }

    /// Called after a purchase with the product ID.
    func handlePurchaseCompleted(productId: String, appState: AppState) async {
        if let plan = Self.subscriptionPlan(fromProductId: productId), plan != .none {
            appState.applySubscriptionPlan(plan)
            subscriptionPlan = plan
            print("[IAP] Subscription active: \(productId) → \(plan.rawValue)")
            return
        }

        let creditsToAdd = creditAmounts[productId] ?? 100
        appState.addCredits(creditsToAdd)
        print("[IAP] Purchase: \(productId) → +\(creditsToAdd) credits")
    }

    func handlePurchaseCompleted(customerInfo: CustomerInfo, appState: AppState) async {
        let detectedPlan = Self.subscriptionPlan(from: customerInfo)
        let plan: CreatorSubscriptionPlan = detectedPlan.isActive ? detectedPlan : .monthly
        subscriptionPlan = plan
        appState.applySubscriptionPlan(plan)
        print("[IAP] Subscription active from Paywall completion → \(plan.rawValue)")
    }

    /// Fallback: called from PaywallView which only gives CustomerInfo — infer product from most recent transaction
    func handlePurchaseCompleted(appState: AppState) async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            let plan = Self.subscriptionPlan(from: customerInfo)
            subscriptionPlan = plan
            appState.applySubscriptionPlan(plan)
            if plan.isActive {
                return
            }

            let recent = customerInfo.nonSubscriptions
                .sorted { $0.purchaseDate > $1.purchaseDate }

            if let latest = recent.first {
                await handlePurchaseCompleted(productId: latest.productIdentifier, appState: appState)
            } else {
                await appState.refreshSubscriptionStatus()
                await appState.fetchCredits()
            }
        } catch {
            print("[IAP] Failed to get customer info after purchase: \(error)")
            await appState.refreshSubscriptionStatus()
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

    /// Purchase a package. Returns true on success.
    func purchase(_ package: Package, appState: AppState) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            guard !result.userCancelled else { return false }
            let productId = package.storeProduct.productIdentifier
            let detectedPlan = Self.subscriptionPlan(from: result.customerInfo)
            if detectedPlan.isActive {
                subscriptionPlan = detectedPlan
                appState.applySubscriptionPlan(detectedPlan)
            } else {
                await appState.refreshSubscriptionStatus()
            }
            if !appState.hasUnlimitedAPIUsage {
                await handlePurchaseCompleted(productId: productId, appState: appState)
            }
            return true
        } catch {
            print("[PurchaseService] Purchase failed: \(error)")
            return false
        }
    }

    func restorePurchases() async -> Bool {
        do {
            let _ = try await Purchases.shared.restorePurchases()
            await refreshSubscriptionStatus()
            return true
        } catch {
            print("[PurchaseService] Restore failed: \(error)")
            return false
        }
    }

    nonisolated static func subscriptionPlan(from customerInfo: CustomerInfo) -> CreatorSubscriptionPlan {
        let entitlementIds = customerInfo.entitlements.active.keys.map { $0.lowercased() }
        let entitlementProducts = customerInfo.entitlements.active.values.map { $0.productIdentifier.lowercased() }
        let subscriptionProducts = customerInfo.activeSubscriptions.map { $0.lowercased() }
        let allIds = entitlementIds + entitlementProducts + subscriptionProducts

        if allIds.contains(where: { $0.contains("year") || $0.contains("annual") }) {
            return .yearly
        }
        if allIds.contains(where: { $0.contains("month") || $0.contains("monthly") }) {
            return .monthly
        }
        if allIds.contains(where: { $0.contains("subscription") || $0.contains("unlimited") || $0.contains("premium") || $0.contains("pro") }) {
            return .monthly
        }
        if !entitlementIds.isEmpty || !subscriptionProducts.isEmpty {
            return .monthly
        }
        return .none
    }

    nonisolated private static func subscriptionPlan(fromProductId productId: String) -> CreatorSubscriptionPlan? {
        let id = productId.lowercased()
        if id.contains("year") || id.contains("annual") { return .yearly }
        if id.contains("month") || id.contains("subscription") || id.contains("premium") || id.contains("pro") { return .monthly }
        return nil
    }
}

// MARK: - Delegate

enum CreatorSubscriptionPlan: String {
    case none
    case monthly
    case yearly

    var isActive: Bool { self != .none }

    var displayName: String {
        switch self {
        case .none: return "Free"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    static var current: CreatorSubscriptionPlan {
        UserDefaults.standard.string(forKey: "creator_subscription_plan")
            .flatMap(CreatorSubscriptionPlan.init(rawValue:)) ?? .none
    }
}

class PurchaseDelegateHandler: NSObject, PurchasesDelegate {
    static let shared = PurchaseDelegateHandler()

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        let plan = PurchaseService.subscriptionPlan(from: customerInfo)
        Task { @MainActor in
            PurchaseService.shared.subscriptionPlan = plan
            UserDefaults.standard.set(plan.rawValue, forKey: "creator_subscription_plan")
            NotificationCenter.default.post(name: .subscriptionPlanChanged, object: plan)
        }
    }
}

extension Notification.Name {
    static let subscriptionPlanChanged = Notification.Name("subscriptionPlanChanged")
}
