import Foundation
import FirebaseAuth
import GoogleSignIn

/// Firebase Auth for sign-in (Google + Apple).
/// User saved directly to Supabase app_users table (same pattern as Android).
final class FirebaseAuthService {
    static let shared = FirebaseAuthService()
    private init() {}

    struct AuthResult {
        let token: String      // Firebase ID token
        let userId: String     // Firebase UID
        let email: String?
    }

    // MARK: - Google Sign-In

    @MainActor
    func signInWithGoogle() async throws -> AuthResult {
        guard let presentingVC = topViewController() else {
            throw AuthError.noPresentingViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingGoogleIdToken
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        return try await firebaseSignIn(credential: credential)
    }

    // MARK: - Apple Sign-In

    func signInWithApple(idToken: String, nonce: String) async throws -> AuthResult {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: nil
        )
        return try await firebaseSignIn(credential: credential)
    }

    // MARK: - Common Firebase flow

    private func firebaseSignIn(credential: AuthCredential) async throws -> AuthResult {
        let authResult = try await Auth.auth().signIn(with: credential)
        guard let user = authResult.user as FirebaseAuth.User? else {
            throw AuthError.noFirebaseUser
        }

        let tokenResult = try await user.getIDTokenResult()
        let token = tokenResult.token

        print("[Auth] Firebase sign-in OK: uid=\(user.uid) email=\(user.email ?? "nil")")

        // Register user via Worker (uses service key to bypass RLS)
        await registerUserViaWorker(
            userId: user.uid,
            email: user.email,
            displayName: user.displayName,
            avatarUrl: user.photoURL?.absoluteString
        )

        return AuthResult(
            token: token,
            userId: user.uid,
            email: user.email
        )
    }

    private func registerUserViaWorker(userId: String, email: String?, displayName: String?, avatarUrl: String?) async {
        let baseURL = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://creatorai-api.polskoydm.workers.dev"
        guard let url = URL(string: "\(baseURL)/api/auth/token") else { return }

        var body: [String: String] = ["externalId": userId, "platform": "ios"]
        if let email = email { body["email"] = email }
        if let displayName = displayName { body["displayName"] = displayName }
        if let avatarUrl = avatarUrl { body["avatarUrl"] = avatarUrl }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[Auth] Worker register user: \(status)")
        } catch {
            print("[Auth] Worker register failed: \(error)")
        }
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            print("[Auth] Sign out error: \(error)")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.flatMap(\.windows).first
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }
}

enum AuthError: Error, LocalizedError {
    case noPresentingViewController
    case missingGoogleIdToken
    case noFirebaseUser

    var errorDescription: String? {
        switch self {
        case .noPresentingViewController: return "Cannot find a view controller to present sign-in"
        case .missingGoogleIdToken: return "Google sign-in did not return an ID token"
        case .noFirebaseUser: return "Firebase sign-in returned no user"
        }
    }
}
