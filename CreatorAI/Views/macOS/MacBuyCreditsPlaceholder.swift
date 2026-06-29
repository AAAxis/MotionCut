import SwiftUI
import RevenueCat

/// Native macOS subscription view using RevenueCat SDK directly.
struct MacBuyCreditsPlaceholder: View {
    let dismiss: () -> Void
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @ObservedObject private var purchaseService = PurchaseService.shared
    @State private var purchaseResult: String?
    @State private var hoveringId: String?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Subscription")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(theme.text)
                Spacer()
                Text("Done")
                    .font(.system(size: 13))
                    .foregroundColor(theme.primary)
                    .onTapGesture { dismiss() }
                    #if os(macOS)
                    .cursor(.pointingHand)
                    #endif
            }
            .padding(.bottom, 4)

            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .foregroundColor(theme.primary)
                Text(appState.hasUnlimitedAPIUsage ? "\(appState.subscriptionPlan.displayName) plan active" : "Voice + no watermark")
                    .font(.system(size: 14))
                    .foregroundColor(theme.text)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.surfaceElevated))

            Divider()

            // Packages
            if purchaseService.packages.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading plans...")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textTertiary)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    ForEach(purchaseService.packages, id: \.identifier) { package in
                        let product = package.storeProduct
                        let title = product.localizedTitle
                        let subtitle = product.localizedDescription.isEmpty ? "Premium voice and watermark removal" : product.localizedDescription
                        let isHovering = hoveringId == package.identifier

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(theme.text)
                                Text(subtitle)
                                    .font(.system(size: 11))
                                    .foregroundColor(theme.textTertiary)
                            }
                            Spacer()
                            Text(product.localizedPriceString)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(theme.primary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isHovering ? theme.surfaceElevated.opacity(0.8) : theme.surfaceElevated)
                        )
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            hoveringId = hovering ? package.identifier : nil
                        }
                        .onTapGesture {
                            guard !purchaseService.isPurchasing else { return }
                            Task {
                                let success = await purchaseService.purchase(package, appState: appState)
                                if success {
                                    purchaseResult = "Purchase successful!"
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    dismiss()
                                }
                            }
                        }
                        .opacity(purchaseService.isPurchasing ? 0.5 : 1)
                    }
                }
            }

            if purchaseService.isPurchasing {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Processing purchase...")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textSecondary)
                }
            }

            if let result = purchaseResult {
                Text(result)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.green)
            }

            Spacer()

            // Restore
            Text("Restore Purchases")
                .font(.system(size: 12))
                .foregroundColor(theme.textTertiary)
                .onTapGesture {
                    Task { await purchaseService.restorePurchases() }
                }

            // Terms of Use (EULA) + Privacy Policy — required by App Review
            // for any screen offering in-app purchases or subscriptions.
            HStack(spacing: 20) {
                Link("Terms of Use", destination: URL(string: "https://holylabs.net/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://holylabs.net/privacy")!)
            }
            .font(.system(size: 11))
            .foregroundColor(theme.textTertiary)
        }
        .padding(24)
        .background(theme.background)
        .task {
            await purchaseService.loadOfferings()
        }
    }
}

#if os(macOS)
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering { cursor.push() } else { NSCursor.pop() }
        }
    }
}
#endif
