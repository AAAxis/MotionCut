import Foundation
import AuthenticationServices
import CryptoKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Runs native Sign in with Apple and returns the identity token and nonce for Supabase.
/// Enable "Sign in with Apple" capability in Xcode and configure Apple provider in Supabase Dashboard.
@MainActor
func performAppleSignIn() async throws -> (idToken: String, nonce: String) {
    let rawNonce = randomNonce()
    let hashedNonce = sha256(rawNonce)

    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = [.fullName, .email]
    request.nonce = hashedNonce

    let controller = ASAuthorizationController(authorizationRequests: [request])
    let delegate = AppleSignInDelegate()
    controller.delegate = delegate
    controller.presentationContextProvider = delegate
    controller.performRequests()

    return try await withCheckedThrowingContinuation { continuation in
        delegate.continuation = continuation
        delegate.rawNonce = rawNonce
    }
}

private func randomNonce(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz")
    var result = ""
    var remaining = length
    while remaining > 0 {
        let rand: UInt8 = .random(in: 0 ..< 255)
        result.append(charset[Int(rand) % charset.count])
        remaining -= 1
    }
    return result
}

private func sha256(_ string: String) -> String {
    let data = Data(string.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

@MainActor
private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var continuation: CheckedContinuation<(idToken: String, nonce: String), Error>?
    var rawNonce: String?

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = rawNonce else {
            continuation?.resume(throwing: AppleSignInError.missingCredential)
            continuation = nil
            return
        }
        continuation?.resume(returning: (idToken, nonce))
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
            continuation?.resume(throwing: AppleSignInError.canceled)
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
            ?? scenes.flatMap(\.windows).first
        return window ?? UIWindow()
        #else
        return NSApplication.shared.keyWindow ?? NSWindow()
        #endif
    }
}

enum AppleSignInError: Error, LocalizedError {
    case missingCredential
    case canceled

    var errorDescription: String? {
        switch self {
        case .missingCredential: return "Sign in with Apple failed: missing credential"
        case .canceled: return "Sign in was canceled"
        }
    }
}
