import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userId: String?
    @Published var userEmail: String?
    @Published var token: String?
    @Published var credits: Int = 0
    @Published var hasSeenOnboarding: Bool
    @Published var pendingDeeplink: DeeplinkAction?
    @Published var isLoadingCredits = false
    @Published var subscriptionPlan: CreatorSubscriptionPlan = .none

    private let keychainService = "com.creatorai.auth"
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
        self.credits = UserDefaults.standard.object(forKey: "user_credits") as? Int ?? 0
        self.subscriptionPlan = UserDefaults.standard.string(forKey: "creator_subscription_plan")
            .flatMap(CreatorSubscriptionPlan.init(rawValue:)) ?? .none
        loadToken()

        // Configure RevenueCat
        if let userIdData = KeychainHelper.load(service: keychainService, account: "userId"),
           let userId = String(data: userIdData, encoding: .utf8) {
            PurchaseService.shared.configure(userId: userId)
        } else {
            let key = "RevenueCatAnonymousId"
            let anonymousId = UserDefaults.standard.string(forKey: key) ?? {
                let id = UUID().uuidString
                UserDefaults.standard.set(id, forKey: key)
                return id
            }()
            PurchaseService.shared.configure(userId: anonymousId)
        }
        Task { await refreshSubscriptionStatus() }
        NotificationCenter.default.publisher(for: .subscriptionPlanChanged)
            .compactMap { $0.object as? CreatorSubscriptionPlan }
            .receive(on: RunLoop.main)
            .sink { [weak self] plan in
                self?.applySubscriptionPlan(plan)
            }
            .store(in: &cancellables)
    }

    func loadToken() {
        if let tokenData = KeychainHelper.load(service: keychainService, account: "jwt"),
           let token = String(data: tokenData, encoding: .utf8) {
            self.token = token
            self.isAuthenticated = true

            if let userIdData = KeychainHelper.load(service: keychainService, account: "userId"),
               let userId = String(data: userIdData, encoding: .utf8) {
                self.userId = userId
            }
            if let emailData = KeychainHelper.load(service: keychainService, account: "userEmail"),
               let email = String(data: emailData, encoding: .utf8) {
                self.userEmail = email
            }
        }
    }

    func setAuth(token: String, userId: String, email: String? = nil) {
        self.token = token
        self.userId = userId
        self.userEmail = email
        self.isAuthenticated = true
        KeychainHelper.save(service: keychainService, account: "jwt", data: token.data(using: .utf8)!)
        KeychainHelper.save(service: keychainService, account: "userId", data: userId.data(using: .utf8)!)
        if let email = email, !email.isEmpty {
            KeychainHelper.save(service: keychainService, account: "userEmail", data: email.data(using: .utf8)!)
        } else {
            KeychainHelper.delete(service: keychainService, account: "userEmail")
        }
        // Cache userId for FCM token refresh (mirrors Android SharedPreferences)
        UserDefaults.standard.set(userId, forKey: "cached_user_id")
        // Register FCM token with Firestore.
        #if os(iOS)
        FCMService.shared.registerTokenForUser(userId: userId)
        #endif
        PurchaseService.shared.configure(userId: userId)
        Task {
            await refreshSubscriptionStatus()
            loadLocalCredits()
        }
    }

    func logout() {
        self.token = nil
        self.userId = nil
        self.userEmail = nil
        self.isAuthenticated = false
        self.credits = 0
        self.subscriptionPlan = .none
        UserDefaults.standard.set(0, forKey: "user_credits")
        UserDefaults.standard.set(CreatorSubscriptionPlan.none.rawValue, forKey: "creator_subscription_plan")
        UserDefaults.standard.removeObject(forKey: "cached_user_id")
        KeychainHelper.delete(service: keychainService, account: "jwt")
        KeychainHelper.delete(service: keychainService, account: "userId")
        KeychainHelper.delete(service: keychainService, account: "userEmail")
        FirebaseAuthService.shared.signOut()
    }

    // MARK: - Usage

    var hasUnlimitedAPIUsage: Bool {
        subscriptionPlan.isActive
    }

    var usageBadgeText: String {
        hasUnlimitedAPIUsage ? "∞" : "\(credits)"
    }

    func refreshSubscriptionStatus() async {
        subscriptionPlan = await PurchaseService.shared.refreshSubscriptionStatus()
    }

    func applySubscriptionPlan(_ plan: CreatorSubscriptionPlan) {
        subscriptionPlan = plan
        UserDefaults.standard.set(plan.rawValue, forKey: "creator_subscription_plan")
    }

    func fetchCredits() async {
        loadLocalCredits()
    }

    func loadLocalCredits() {
        credits = UserDefaults.standard.object(forKey: "user_credits") as? Int ?? credits
    }

    func addCredits(_ amount: Int) {
        credits += amount
        UserDefaults.standard.set(credits, forKey: "user_credits")
    }

    func deductCredits(_ amount: Int) {
        credits = max(0, credits - amount)
        UserDefaults.standard.set(credits, forKey: "user_credits")
    }

    var canGenerate: Bool {
        hasUnlimitedAPIUsage
    }

    func canSpendCredits(_ amount: Int) -> Bool {
        amount <= 0 || credits >= amount
    }

    func completeOnboarding() {
        hasSeenOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(service: String, account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
