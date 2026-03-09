import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userId: String?
    @Published var userEmail: String?
    @Published var token: String?
    @Published var isSubscribed = false
    @Published var credits: Int = 3
    @Published var hasSeenOnboarding: Bool
    /// Set when app is opened via deeplink; MainTabView applies and clears.
    @Published var pendingDeeplink: DeeplinkAction?

    private let keychainService = "com.creatorai.auth"
    private var purchaseCancellable: AnyCancellable?
    static let creditCost = 3

    init() {
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
        self.credits = UserDefaults.standard.object(forKey: "user_credits") as? Int ?? 3
        loadToken()
        // Configure RevenueCat at launch so the paywall can open even before login
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
        // Keep AppState.isSubscribed in sync with RevenueCat so we remember the purchase
        purchaseCancellable = PurchaseService.shared.$isSubscribed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subscribed in
                self?.isSubscribed = subscribed
            }
    }

    func loadToken() {
        if let tokenData = KeychainHelper.load(service: keychainService, account: "jwt"),
           let token = String(data: tokenData, encoding: .utf8) {
            self.token = token
            self.isAuthenticated = true

            if let userIdData = KeychainHelper.load(service: keychainService, account: "userId"),
               let userId = String(data: userIdData, encoding: .utf8) {
                self.userId = userId
                PurchaseService.shared.configure(userId: userId)
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

        // Configure RevenueCat with the authenticated user
        PurchaseService.shared.configure(userId: userId)
    }

    func logout() {
        self.token = nil
        self.userId = nil
        self.userEmail = nil
        self.isAuthenticated = false
        self.isSubscribed = false
        self.credits = 3
        UserDefaults.standard.set(3, forKey: "user_credits")
        KeychainHelper.delete(service: keychainService, account: "jwt")
        KeychainHelper.delete(service: keychainService, account: "userId")
        KeychainHelper.delete(service: keychainService, account: "userEmail")
    }

    var canGenerate: Bool {
        isSubscribed || credits >= AppState.creditCost
    }

    func useCredits() {
        guard !isSubscribed else { return }
        credits = max(0, credits - AppState.creditCost)
        UserDefaults.standard.set(credits, forKey: "user_credits")
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
