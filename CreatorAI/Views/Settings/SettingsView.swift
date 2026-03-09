import SwiftUI
import StoreKit
import RevenueCatUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: SettingsViewModel

    var showCloseButton: Bool

    @State private var showPaywall = false
    @State private var showRedeemCode = false
    @State private var authLoading = false
    @State private var authError: String?

    init(showCloseButton: Bool = true, userId: String = "demo-user") {
        self.showCloseButton = showCloseButton
        _viewModel = StateObject(wrappedValue: SettingsViewModel(userId: userId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Profile (left) | Credits (right), close button when presented
            HStack {
                Text("Profile")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundColor(theme.text)

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundColor(theme.primary)
                    Text(appState.isSubscribed ? "PRO" : "\(appState.credits) Credits")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(theme.text)
                }
                .padding(.horizontal, 16)
                .frame(height: 42)
                .overlay(
                    RoundedRectangle(cornerRadius: 21)
                        .stroke(theme.border, lineWidth: 1)
                )

                if showCloseButton {
                    Button {
                        dismiss()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(theme.surfaceElevated)
                                .frame(width: 40, height: 40)
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(theme.text)
                        }
                    }
                    .padding(.leading, 8)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 21)
            .padding(.bottom, 21)

            ScrollView {
                VStack(spacing: 16) {
                    // Account / Login
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Account")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(theme.text)

                        if appState.isAuthenticated {
                            if let email = appState.userEmail, !email.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(theme.textSecondary)
                                    Text(email)
                                        .font(.system(size: 14))
                                        .foregroundColor(theme.text)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            Text("Your library syncs across devices.")
                                .font(.system(size: 14))
                                .foregroundColor(theme.textSecondary)
                                .padding(.bottom, 4)
                            Button {
                                appState.logout()
                                Task {
                                    try? await SupabaseService.shared.signOut()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 16))
                                    Text("Log out")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Sign in to sync your library across devices.")
                                .font(.system(size: 14))
                                .foregroundColor(theme.textSecondary)
                            VStack(spacing: 10) {
                                Button {
                                    profileSignInWithApple()
                                } label: {
                                    HStack(spacing: 10) {
                                        if authLoading {
                                            ProgressView().tint(theme.text)
                                        } else {
                                            Image(systemName: "apple.logo")
                                                .font(.system(size: 18, weight: .semibold))
                                        }
                                        Text("Continue with Apple")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(theme.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(theme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .disabled(authLoading)

                                Button {
                                    profileSignInWithGoogle()
                                } label: {
                                    HStack(spacing: 10) {
                                        if authLoading {
                                            ProgressView().tint(theme.text)
                                        } else {
                                            Image(systemName: "globe")
                                                .font(.system(size: 18, weight: .medium))
                                        }
                                        Text("Continue with Google")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(theme.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(theme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .disabled(authLoading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(theme.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(theme.cardBorder, lineWidth: 1)
                            )
                    )

                    // Subscription Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 24))
                                .foregroundColor(viewModel.isSubscribed ? .white : theme.primary)

                            Text(viewModel.isSubscribed ? "Premium Active" : "Free Plan")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(viewModel.isSubscribed ? .white : theme.text)
                        }

                        Text(viewModel.isSubscribed
                            ? "You have unlimited video generations"
                            : "You have \(viewModel.credits) free credits remaining")
                            .font(.system(size: 14))
                            .foregroundColor(viewModel.isSubscribed
                                ? Color.white.opacity(0.9)
                                : theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(viewModel.isSubscribed ? theme.primary : theme.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(viewModel.isSubscribed ? theme.primary : theme.cardBorder, lineWidth: 1)
                            )
                    )

                    // Upgrade Button
                    if !viewModel.isSubscribed {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 20))
                                Text("Upgrade to Premium")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(theme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    // Redeem Code Button
                    Button {
                        showRedeemCode = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "giftcard")
                                .font(.system(size: 16))
                            Text("Redeem Code")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }

                    // Info
                    Text("Free plan includes 3 credits. Premium subscription gives you unlimited generations.")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 24)
                }
                .padding(.horizontal, 26)
            }
        }
        .background(theme.background.ignoresSafeArea(.all))
        .navigationBarHidden(true)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .onPurchaseCompleted { _ in
                    viewModel.isSubscribed = true
                    appState.isSubscribed = true
                    showPaywall = false
                }
                .onRestoreCompleted { _ in
                    viewModel.isSubscribed = true
                    appState.isSubscribed = true
                    showPaywall = false
                }
        }
        .offerCodeRedemption(isPresented: $showRedeemCode) { _ in
            Task { await viewModel.loadData() }
        }
        .alert("Sign in failed", isPresented: .init(get: { authError != nil }, set: { if !$0 { authError = nil } })) {
            Button("OK", role: .cancel) { authError = nil }
        } message: {
            if let authError = authError { Text(authError) }
        }
        .task {
            await viewModel.loadData()
        }
    }

    private func profileSignInWithApple() {
        authLoading = true
        authError = nil
        Task {
            do {
                let (idToken, nonce) = try await performAppleSignIn()
                let session = try await SupabaseService.shared.signInWithApple(idToken: idToken, nonce: nonce)
                await MainActor.run {
                    appState.setAuth(token: session.accessToken, userId: session.user.id.uuidString, email: session.user.email)
                    authLoading = false
                }
            } catch {
                await MainActor.run {
                    authLoading = false
                    if let appleErr = error as? AppleSignInError, case .canceled = appleErr { return }
                    authError = error.localizedDescription
                }
            }
        }
    }

    private func profileSignInWithGoogle() {
        authLoading = true
        authError = nil
        Task {
            do {
                let session = try await SupabaseService.shared.signInWithGoogle()
                await MainActor.run {
                    appState.setAuth(token: session.accessToken, userId: session.user.id.uuidString, email: session.user.email)
                    authLoading = false
                }
            } catch {
                await MainActor.run {
                    authLoading = false
                    authError = error.localizedDescription
                }
            }
        }
    }
}
