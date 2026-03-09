import Foundation

actor AuthService {
    static let shared = AuthService()

    private let keychainService = "com.creatorai.auth"

    func getToken() -> String? {
        guard let data = KeychainHelper.load(service: keychainService, account: "jwt") else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func saveToken(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        KeychainHelper.save(service: keychainService, account: "jwt", data: data)
    }

    func clearToken() {
        KeychainHelper.delete(service: keychainService, account: "jwt")
    }

    func getUserId() -> String? {
        guard let data = KeychainHelper.load(service: keychainService, account: "userId") else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func saveUserId(_ id: String) {
        guard let data = id.data(using: .utf8) else { return }
        KeychainHelper.save(service: keychainService, account: "userId", data: data)
    }
}
