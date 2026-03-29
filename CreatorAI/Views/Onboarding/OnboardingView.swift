import SwiftUI

struct OnboardingStep {
    let id: Int
    let title: String
    let description: String
    let icon: String
}

private let purposeSteps: [OnboardingStep] = [
    OnboardingStep(
        id: 1,
        title: "Create Short Videos",
        description: "Turn ideas into reels. Pick a topic, get AI-suggested clips and beats, then make your video in minutes.",
        icon: "film.stack.fill"
    ),
    OnboardingStep(
        id: 2,
        title: "Edit & Add Music",
        description: "Trim clips, add a soundtrack, and style your video. Everything you need is in one place.",
        icon: "music.note.list"
    ),
    OnboardingStep(
        id: 3,
        title: "Save & Share",
        description: "Export to your Library, save to Photos, or share with friends. Your creations, your way.",
        icon: "square.and.arrow.up"
    ),
]

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @State private var currentStep = 0
    @State private var authLoading = false
    @State private var authError: String?

    private var isPurposeStep: Bool { currentStep < purposeSteps.count }
    private var isLoginStep: Bool { currentStep == purposeSteps.count }

    var body: some View {
        VStack(spacing: 0) {
            if isPurposeStep {
                purposeScreen
            } else {
                loginOptionalScreen
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea(.all))
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    // MARK: - 3 purpose screens

    private var purposeScreen: some View {
        VStack {
            Spacer()

            ZStack {
                Circle()
                    .fill(theme.surfaceElevated)
                    .frame(width: 120, height: 120)
                Image(systemName: purposeSteps[currentStep].icon)
                    .font(.system(size: 48))
                    .foregroundColor(theme.primary)
            }
            .padding(.bottom, 40)

            Text(purposeSteps[currentStep].title)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(theme.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            Text(purposeSteps[currentStep].description)
                .font(.system(size: 16))
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            HStack(spacing: 8) {
                ForEach(0..<purposeSteps.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? theme.primary : theme.border)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 40)

            Spacer()

            Button {
                if currentStep < purposeSteps.count - 1 {
                    currentStep += 1
                } else {
                    currentStep = purposeSteps.count
                }
            } label: {
                Text("Next")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(theme.primary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Optional login screen (keep your data)

    private var loginOptionalScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(theme.surfaceElevated)
                    .frame(width: 100, height: 100)
                Image(systemName: "icloud.fill")
                    .font(.system(size: 44))
                    .foregroundColor(theme.primary)
            }
            .padding(.bottom, 32)

            Text("Keep your data safe")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(theme.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            Text("Sign in to sync your library across devices. You can skip and sign in later from Profile.")
                .font(.system(size: 15))
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)
                .padding(.bottom, 36)

            VStack(spacing: 14) {
                Button {
                    signInWithApple()
                } label: {
                    HStack(spacing: 12) {
                        if authLoading { ProgressView().tint(theme.text) } else {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 20, weight: .semibold))
                        }
                        Text("Continue with Apple")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(authLoading)

                Button {
                    signInWithGoogle()
                } label: {
                    HStack(spacing: 12) {
                        if authLoading { ProgressView().tint(theme.text) } else {
                            Image(systemName: "globe")
                                .font(.system(size: 20, weight: .medium))
                        }
                        Text("Continue with Google")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(authLoading)

                Button {
                    skipAndContinue()
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                }
                .padding(.top, 8)
                .disabled(authLoading)
            }
            .padding(.horizontal, 26)

            Spacer()
        }
        .alert("Sign in failed", isPresented: .init(get: { authError != nil }, set: { if !$0 { authError = nil } })) {
            Button("OK", role: .cancel) { authError = nil }
        } message: {
            if let authError = authError { Text(authError) }
        }
    }

    private func signInWithApple() {
        authLoading = true
        authError = nil
        Task {
            do {
                let (idToken, nonce) = try await performAppleSignIn()
                let result = try await FirebaseAuthService.shared.signInWithApple(idToken: idToken, nonce: nonce)
                await MainActor.run {
                    appState.setAuth(token: result.token, userId: result.userId, email: result.email)
                    appState.completeOnboarding()
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

    private func signInWithGoogle() {
        authLoading = true
        authError = nil
        Task {
            do {
                let result = try await FirebaseAuthService.shared.signInWithGoogle()
                await MainActor.run {
                    appState.setAuth(token: result.token, userId: result.userId, email: result.email)
                    appState.completeOnboarding()
                }
            } catch {
                await MainActor.run {
                    authLoading = false
                    authError = error.localizedDescription
                }
            }
        }
    }

    private func skipAndContinue() {
        appState.completeOnboarding()
    }
}
