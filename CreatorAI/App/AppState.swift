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

    private let keychainService = "com.creatorai.auth"

    init() {
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
        self.credits = UserDefaults.standard.object(forKey: "user_credits") as? Int ?? 0
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
        // Register FCM token with Supabase
        FCMService.shared.registerTokenForUser(userId: userId)
        PurchaseService.shared.configure(userId: userId)
        Task { await fetchCredits() }
    }

    func logout() {
        self.token = nil
        self.userId = nil
        self.userEmail = nil
        self.isAuthenticated = false
        self.credits = 0
        UserDefaults.standard.set(0, forKey: "user_credits")
        UserDefaults.standard.removeObject(forKey: "cached_user_id")
        KeychainHelper.delete(service: keychainService, account: "jwt")
        KeychainHelper.delete(service: keychainService, account: "userId")
        KeychainHelper.delete(service: keychainService, account: "userEmail")
        FirebaseAuthService.shared.signOut()
    }

    // MARK: - Credits (server-side)

    func fetchCredits() async {
        guard let userId = userId else { return }
        isLoadingCredits = true
        defer { isLoadingCredits = false }

        let baseURL = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://creatorai-api.polskoydm.workers.dev"
        guard let url = URL(string: "\(baseURL)/api/credits/get") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = ["userId": userId]
        if let email = userEmail { body["email"] = email }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let serverCredits = json["credits"] as? Int {
                self.credits = serverCredits
                UserDefaults.standard.set(serverCredits, forKey: "user_credits")
            }
        } catch {
            print("[Credits] Failed to fetch: \(error)")
        }
    }

    func addCredits(_ amount: Int) {
        credits += amount
        UserDefaults.standard.set(credits, forKey: "user_credits")
    }

    func deductCredits(_ amount: Int) {
        credits = max(0, credits - amount)
        UserDefaults.standard.set(credits, forKey: "user_credits")

        // Sync deduction to server (same as Android)
        guard let userId = userId else { return }
        Task {
            let baseURL = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://creatorai-api.polskoydm.workers.dev"
            guard let url = URL(string: "\(baseURL)/api/credits/deduct") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "userId": userId,
                "amount": amount
            ])
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    var canGenerate: Bool {
        credits > 0
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
