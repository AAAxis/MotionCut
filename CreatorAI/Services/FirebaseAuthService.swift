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

        // Save user to Supabase app_users table (matches Android behavior)
        await SupabaseService.shared.upsertUser(
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
