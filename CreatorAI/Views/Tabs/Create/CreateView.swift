import SwiftUI
import RevenueCatUI

struct CreateView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @StateObject private var viewModel = CreateViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header + Credits
                HStack {
                    Text("Create")
                        .font(.system(size: 29, weight: .semibold))
                        .foregroundColor(theme.text)
                    Spacer()
                    Button {
                        viewModel.showBuyCredits = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12))
                            Text("\(appState.credits >= 0 ? "\(appState.credits)" : "∞")")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(theme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(theme.primary.opacity(0.12))
                        )
                    }
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
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $viewModel.showBuyCredits) {
            PaywallView()
                .onPurchaseCompleted { customerInfo in
                    let productId = customerInfo.nonSubscriptions
                        .sorted { $0.purchaseDate > $1.purchaseDate }
                        .first?.productIdentifier
                    Task {
                        if let productId {
                            await PurchaseService.shared.handlePurchaseCompleted(productId: productId, appState: appState)
                        } else {
                            await PurchaseService.shared.handlePurchaseCompleted(appState: appState)
                        }
                        viewModel.showBuyCredits = false
                    }
                }
        }
        .onAppear {
            Task { await appState.fetchCredits() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .prefillPrompt)) { notification in
            if let prompt = notification.object as? String {
                viewModel.mode = .reel
                viewModel.reelTopic = prompt
            }
        }
    }
}
