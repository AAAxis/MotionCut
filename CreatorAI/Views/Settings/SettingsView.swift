import SwiftUI
import StoreKit
#if os(iOS)
import RevenueCatUI
#endif

private struct FalAccountBilling: Decodable {
    let credits: FalCreditBalance?
}

private struct FalCreditBalance: Decodable {
    let currentBalance: Double
    let currency: String

    enum CodingKeys: String, CodingKey {
        case currentBalance = "current_balance"
        case currency
    }
}

private enum FalBillingService {
    static func fetchBalance(apiKey: String) async throws -> FalCreditBalance {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw APIError.sseError("Add your fal.ai API key first.")
        }
        guard var components = URLComponents(string: "https://api.fal.ai/v1/account/billing") else {
            throw APIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "expand", value: "credits")]
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(authorizationHeader(for: trimmedKey), forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "fal.ai balance request failed."
            throw APIError.sseError("fal.ai balance HTTP \(statusCode): \(String(message.prefix(160)))")
        }

        let decoded = try JSONDecoder().decode(FalAccountBilling.self, from: data)
        guard let credits = decoded.credits else {
            throw APIError.sseError("fal.ai did not return credit balance.")
        }
        return credits
    }

    private static func authorizationHeader(for apiKey: String) -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.lowercased().hasPrefix("key ") {
            return trimmedKey
        }
        return "Key \(trimmedKey)"
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: SettingsViewModel

    var showCloseButton: Bool

    @State private var showSubscription = false
    @State private var showRedeemCode = false
    @State private var authLoading = false
    @State private var authError: String?
    @AppStorage("AI_SCENARIO_MODE") private var aiScenarioMode = "apple"
    @AppStorage("FAL_API_KEY") private var falAPIKey = ""
    @AppStorage("OPENAI_API_KEY") private var openAIAPIKey = ""
    @AppStorage("GEMINI_API_KEY") private var geminiAPIKey = ""
    @AppStorage("KLING_API_KEY") private var klingAPIKey = ""
    @AppStorage("REPLICATE_API_TOKEN") private var replicateAPIToken = ""
    @State private var freeBrainModels = OpenRouterScenarioGenerator.defaultFreeModels
    @State private var selectedFreeBrainModelId = OpenRouterScenarioGenerator.selectedFreeModel.id
    @State private var selectedBrainOptionId = "apple"
    @State private var loadingFreeBrainModels = false
    @State private var showFalKey = false
    @State private var showOpenAIKey = false
    @State private var showGeminiKey = false
    @State private var showKlingKey = false
    @State private var showReplicateKey = false
    @State private var falBalance: FalCreditBalance?
    @State private var isLoadingFalBalance = false
    @State private var falBalanceError: String?

    init(showCloseButton: Bool = true, userId: String = "demo-user") {
        self.showCloseButton = showCloseButton
        _viewModel = StateObject(wrappedValue: SettingsViewModel(userId: userId))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Profile, close button when presented
            HStack {
                Text("Account")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundColor(theme.text)

                Spacer()

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
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Text("Account")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(theme.text)
                            Button {
                                showSubscription = true
                            } label: {
                                proBadge
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }

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

                    // AI Brain
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(theme.primary)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("AI Brain")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(theme.text)
                                Text("Used for scripts, captions, cuts, and timeline decisions.")
                                    .font(.system(size: 13))
                                    .foregroundColor(theme.textSecondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text("Model")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(theme.textSecondary)
                                if loadingFreeBrainModels {
                                    ProgressView()
                                    .scaleEffect(0.7)
                                }
                            }

                            Picker("Model", selection: $selectedBrainOptionId) {
                                Text("Apple Intelligence")
                                    .tag("apple")
                                ForEach(freeBrainModels) { model in
                                    Text(model.name)
                                        .tag(model.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .onAppear {
                                syncBrainPickerFromDefaults()
                            }
                            .onChange(of: selectedBrainOptionId) { newValue in
                                if newValue == "apple" {
                                    aiScenarioMode = "apple"
                                    return
                                }
                                guard let model = freeBrainModels.first(where: { $0.id == newValue }) else { return }
                                aiScenarioMode = "openrouter"
                                selectedFreeBrainModelId = model.id
                                OpenRouterScenarioGenerator.selectFreeModel(model)
                            }
                        }
                        .task {
                            await loadFreeBrainModels()
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

                    // Video Providers
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles.tv")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(theme.primary)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Video providers")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(theme.text)
                                Text("Connect user keys for API video models.")
                                    .font(.system(size: 13))
                                    .foregroundColor(theme.textSecondary)
                            }
                        }

                        providerKeyRow(
                            title: "fal.ai",
                            placeholder: "fal key",
                            key: $falAPIKey,
                            isVisible: $showFalKey,
                            badge: AnyView(falBalanceBadge),
                            linkURL: URL(string: "https://fal.ai/dashboard/keys")
                        )

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
                }
                .padding(.horizontal, 26)
            }
        }
        .background(theme.background.ignoresSafeArea(.all))
        #if os(iOS)
        .navigationBarHidden(true)
        #else
        .buttonStyle(.plain)
        #endif
        .sheet(isPresented: $showSubscription) {
            #if os(iOS)
            PaywallView()
                .onPurchaseCompleted { customerInfo in
                    Task {
                        await PurchaseService.shared.handlePurchaseCompleted(customerInfo: customerInfo, appState: appState)
                    }
                    showSubscription = false
                }
            #else
            MacBuyCreditsPlaceholder(dismiss: { showSubscription = false })
                .frame(minWidth: 400, minHeight: 300)
            #endif
        }
        .alert("Sign in failed", isPresented: .init(get: { authError != nil }, set: { if !$0 { authError = nil } })) {
            Button("OK", role: .cancel) { authError = nil }
        } message: {
            if let authError = authError { Text(authError) }
        }
        .task {
            await viewModel.loadData()
            await refreshFalBalanceIfPossible()
        }
        .onChange(of: falAPIKey) { _ in
            falBalance = nil
            falBalanceError = nil
            Task { await refreshFalBalanceIfPossible() }
        }
    }

    private var proBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 9, weight: .bold))
            Text("Pro")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(appState.hasUnlimitedAPIUsage ? .white : theme.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(appState.hasUnlimitedAPIUsage ? theme.primary : theme.primary.opacity(0.12))
        )
    }

    private func providerKeyRow(title: String, placeholder: String, key: Binding<String>, isVisible: Binding<Bool>, badge: AnyView? = nil, linkURL: URL? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
                if let linkURL {
                    Link(destination: linkURL) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(theme.primary)
                            .accessibilityLabel("Open \(title)")
                    }
                    .buttonStyle(.plain)
                }
                if let badge {
                    badge
                }
                Spacer()
                Text(key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not connected" : "Connected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? theme.textTertiary : theme.success)
            }

            HStack(spacing: 8) {
                providerKeyInputField(placeholder: placeholder, key: key, isVisible: isVisible)

                Button {
                    isVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.textSecondary)
                }
                .buttonStyle(.plain)

                if !key.wrappedValue.isEmpty {
                    Button {
                        key.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(theme.error)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func providerKeyInputField(placeholder: String, key: Binding<String>, isVisible: Binding<Bool>) -> some View {
        if isVisible.wrappedValue {
            #if os(iOS)
            TextField(placeholder, text: key)
                .textInputAutocapitalization(TextInputAutocapitalization.never)
                .autocorrectionDisabled(true)
                .font(Font.system(size: 14))
                .foregroundColor(theme.text)
            #else
            TextField(placeholder, text: key)
                .font(Font.system(size: 14))
                .foregroundColor(theme.text)
            #endif
        } else {
            #if os(iOS)
            SecureField(placeholder, text: key)
                .textInputAutocapitalization(TextInputAutocapitalization.never)
                .autocorrectionDisabled(true)
                .font(Font.system(size: 14))
                .foregroundColor(theme.text)
            #else
            SecureField(placeholder, text: key)
                .font(Font.system(size: 14))
                .foregroundColor(theme.text)
            #endif
        }
    }

    @ViewBuilder
    private var falBalanceBadge: some View {
        if let falBalance {
            HStack(spacing: 4) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(formattedFalBalance(falBalance))
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(theme.primary))
        } else if isLoadingFalBalance {
            ProgressView()
                .scaleEffect(0.6)
        }
    }

    private var falBalanceRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.textSecondary)

            if isLoadingFalBalance {
                Text("Checking balance...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textTertiary)
                ProgressView()
                    .scaleEffect(0.65)
            } else if let falBalance {
                Text("Balance: \(formattedFalBalance(falBalance))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.textSecondary)
            } else if let falBalanceError {
                Text(falBalanceError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.error)
                    .lineLimit(3)
            } else {
                Text("Balance unavailable")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer()

            Button {
                Task { await refreshFalBalance(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.primary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(falAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingFalBalance)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.surfaceElevated.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @MainActor
    private func refreshFalBalanceIfPossible() async {
        guard !falAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await refreshFalBalance(force: false)
    }

    @MainActor
    private func refreshFalBalance(force: Bool) async {
        let key = falAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            falBalance = nil
            falBalanceError = nil
            return
        }
        if isLoadingFalBalance { return }
        if falBalance != nil && !force { return }

        isLoadingFalBalance = true
        falBalanceError = nil
        defer { isLoadingFalBalance = false }

        do {
            falBalance = try await FalBillingService.fetchBalance(apiKey: key)
        } catch {
            falBalance = nil
            let detail = error.localizedDescription
            if detail.localizedCaseInsensitiveContains("401") || detail.localizedCaseInsensitiveContains("403") {
                falBalanceError = nil
            } else {
                falBalanceError = detail.isEmpty ? "Could not fetch fal.ai balance" : detail
            }
            print("[Settings] fal.ai balance failed: \(error.localizedDescription)")
        }
    }

    private func formattedFalBalance(_ balance: FalCreditBalance) -> String {
        let amount = balance.currentBalance
        let number = amount.formatted(.number.precision(.fractionLength(2)))
        return "\(number) \(balance.currency.uppercased())"
    }

    private func profileSignInWithApple() {
        authLoading = true
        authError = nil
        Task {
            do {
                let (idToken, nonce) = try await performAppleSignIn()
                let result = try await FirebaseAuthService.shared.signInWithApple(idToken: idToken, nonce: nonce)
                await MainActor.run {
                    appState.setAuth(token: result.token, userId: result.userId, email: result.email)
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
                let result = try await FirebaseAuthService.shared.signInWithGoogle()
                await MainActor.run {
                    appState.setAuth(token: result.token, userId: result.userId, email: result.email)
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

    @MainActor
    private func loadFreeBrainModels() async {
        guard !loadingFreeBrainModels else { return }
        loadingFreeBrainModels = true
        defer { loadingFreeBrainModels = false }

        do {
            let models = try await OpenRouterScenarioGenerator.fetchFreeModels()
            freeBrainModels = models
            let selected = OpenRouterScenarioGenerator.selectedFreeModel
            if models.contains(where: { $0.id == selected.id }) {
                selectedFreeBrainModelId = selected.id
            } else if let first = models.first {
                selectedFreeBrainModelId = first.id
                OpenRouterScenarioGenerator.selectFreeModel(first)
            }
            syncBrainPickerFromDefaults()
        } catch {
            freeBrainModels = OpenRouterScenarioGenerator.defaultFreeModels
            selectedFreeBrainModelId = OpenRouterScenarioGenerator.selectedFreeModel.id
            syncBrainPickerFromDefaults()
            print("[Settings] Brain model fetch failed: \(error.localizedDescription)")
        }
    }

    private func syncBrainPickerFromDefaults() {
        if UserDefaults.standard.object(forKey: "AI_SCENARIO_MODE") == nil {
            aiScenarioMode = "apple"
        }
        if aiScenarioMode == "apple" {
            selectedBrainOptionId = "apple"
        } else {
            selectedFreeBrainModelId = OpenRouterScenarioGenerator.selectedFreeModel.id
            selectedBrainOptionId = selectedFreeBrainModelId
        }
    }
}
