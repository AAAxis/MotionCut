import SwiftUI
#if os(iOS)
import RevenueCatUI
#endif

struct CreateView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @StateObject private var viewModel = CreateViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Create")
                        .font(.system(size: 29, weight: .semibold))
                        .foregroundColor(theme.text)
                    Spacer()
                }
                .padding(.bottom, 8)

                // Mode Toggle
                HStack(spacing: 0) {
                    ForEach(CreateMode.allCases, id: \.rawValue) { mode in
                        Button {
                            viewModel.mode = mode
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 16))
                                Text(mode.label)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(viewModel.mode == mode ? .white : theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 11)
                                    .fill(viewModel.mode == mode ? theme.primary : Color.clear)
                            )
                        }
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(theme.surfaceElevated)
                )
                .padding(.bottom, 24)

                // Content
                switch viewModel.mode {
                case .reel:
                    ReelCreatorView(viewModel: viewModel)
                case .ad:
                    AdCreatorView(viewModel: viewModel)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(theme.background.ignoresSafeArea(.all))
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $viewModel.showBuyCredits) {
            #if os(iOS)
            PaywallView()
                .onPurchaseCompleted { customerInfo in
                    Task {
                        await PurchaseService.shared.handlePurchaseCompleted(customerInfo: customerInfo, appState: appState)
                        viewModel.showBuyCredits = false
                    }
                }
            #else
            MacBuyCreditsPlaceholder(dismiss: { viewModel.showBuyCredits = false })
                .frame(minWidth: 400, minHeight: 300)
            #endif
        }
        .onAppear {
            Task { await appState.refreshSubscriptionStatus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .prefillPrompt)) { notification in
            if let prompt = notification.object as? String {
                viewModel.mode = .reel
                viewModel.reelTopic = prompt
            }
        }
    }
}
