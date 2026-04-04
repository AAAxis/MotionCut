import Foundation
import FirebaseCore
import FirebaseAuth
import CryptoKit
#if os(iOS)
import GoogleSignIn
#else
import AuthenticationServices
#endif

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
        #if os(iOS)
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
        #else
        // macOS: Google OAuth via ASWebAuthenticationSession
        return try await signInWithGoogleWeb()
        #endif
    }

    // MARK: - Google Sign-In via Web (macOS)

    #if os(macOS)
    @MainActor
    private func signInWithGoogleWeb() async throws -> AuthResult {
        let clientID = FirebaseApp.app()?.options.clientID ?? ""
        // Use reversed client ID as redirect scheme (same as iOS GoogleSignIn SDK)
        let reversedClientID = clientID.components(separatedBy: ".").reversed().joined(separator: ".")
        let redirectURI = "\(reversedClientID):/oauthredirect"

        // PKCE: generate code verifier and challenge
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = sha256Base64URL(codeVerifier)

        var urlComponents = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        urlComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let authURL = urlComponents.url else {
            throw AuthError.noPresentingViewController
        }

        // Open browser for Google sign-in
        let contextProvider = WebAuthContextProvider()
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: reversedClientID) { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: AuthError.missingGoogleIdToken) }
            }
            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        // Extract authorization code from callback
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.missingGoogleIdToken
        }

        // Exchange code for tokens
        let (idToken, accessToken) = try await exchangeCodeForTokens(
            code: code,
            clientID: clientID,
            redirectURI: redirectURI,
            codeVerifier: codeVerifier
        )

        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        return try await firebaseSignIn(credential: credential)
    }

    /// Exchange authorization code for id_token + access_token via Google token endpoint
    private func exchangeCodeForTokens(code: String, clientID: String, redirectURI: String, codeVerifier: String) async throws -> (idToken: String, accessToken: String) {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code=\(code)",
            "client_id=\(clientID)",
            "redirect_uri=\(redirectURI)",
            "grant_type=authorization_code",
            "code_verifier=\(codeVerifier)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String,
              let accessToken = json["access_token"] as? String else {
            print("[Auth] Token exchange failed: \(String(data: data, encoding: .utf8) ?? "")")
            throw AuthError.missingGoogleIdToken
        }

        return (idToken, accessToken)
    }

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func sha256Base64URL(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Provides the key window as presentation anchor for ASWebAuthenticationSession.
    private class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            NSApplication.shared.keyWindow ?? NSWindow()
        }
    }
    #endif

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
            #if os(iOS)
            GIDSignIn.sharedInstance.signOut()
            #endif
        } catch {
            print("[Auth] Sign out error: \(error)")
        }
    }

    // MARK: - Helpers

    #if os(iOS)
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
    #endif
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
