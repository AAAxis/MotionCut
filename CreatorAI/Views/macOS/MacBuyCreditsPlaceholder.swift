import SwiftUI
import RevenueCat

/// Native macOS credits purchase view using RevenueCat SDK directly.
struct MacBuyCreditsPlaceholder: View {
    let dismiss: () -> Void
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @ObservedObject private var purchaseService = PurchaseService.shared
    @State private var purchaseResult: String?
    @State private var hoveringId: String?

    private let creditMap: [String: Int] = [
        "credits_100": 100,
        "credits_200": 200,
        "credits_300": 300,
        "creatorai_100_credits": 100,
        "creatorai_200_credits": 200,
        "creatorai_300_credits": 300,
    ]

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Buy Credits")
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

            // Current balance
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.orange)
                Text("Current balance:")
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)
                Text("\(appState.credits >= 0 ? "\(appState.credits)" : "Unlimited")")
                    .font(.system(size: 14, weight: .bold))
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
                    Text("Loading credit packs...")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textTertiary)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    ForEach(purchaseService.packages, id: \.identifier) { package in
                        let product = package.storeProduct
                        let credits = creditMap[product.productIdentifier]
                        let title = credits != nil ? "\(credits!) Credits" : product.localizedTitle
                        let subtitle = credits != nil ? "\(credits!) seconds of video" : product.localizedDescription
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
