import SwiftUI
import RevenueCat

struct BuyCreditsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var purchaseService = PurchaseService.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Current balance
                VStack(spacing: 8) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(theme.primary)

                    Text("\(appState.credits)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(theme.text)

                    Text("credits remaining")
                        .font(.system(size: 15))
                        .foregroundColor(theme.textSecondary)
                }
                .padding(.top, 20)

                // What credits buy
                VStack(alignment: .leading, spacing: 8) {
                    creditInfoRow("5s Seedance Lite video", cost: "5")
                    creditInfoRow("5s Seedance Pro video", cost: "10")
                    creditInfoRow("5s Kling v2.1 video", cost: "15")
                    creditInfoRow("AI Ad (full pipeline)", cost: "10")
                }
                .padding(.horizontal, 20)

                Divider().background(theme.border)

                // RevenueCat packages
                VStack(spacing: 12) {
                    ForEach(purchaseService.packages, id: \.identifier) { package in
                        Button {
                            Task {
                                if await purchaseService.purchase(package, appState: appState) {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(creditLabel(for: package.storeProduct.productIdentifier))
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(theme.text)
                                    Text(creditSubLabel(for: package.storeProduct.productIdentifier))
                                        .font(.system(size: 13))
                                        .foregroundColor(theme.textSecondary)
                                }

                                Spacer()

                                Text(package.localizedPriceString)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(theme.primary)
                                    )
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(theme.surfaceElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(theme.border, lineWidth: 1)
                                    )
                            )
                        }
                        .disabled(purchaseService.isPurchasing)
                    }

                    if purchaseService.packages.isEmpty {
                        ProgressView()
                            .padding()
                        Text("Loading prices...")
                            .font(.system(size: 14))
                            .foregroundColor(theme.textSecondary)
                    }
                }
                .padding(.horizontal, 20)

                if purchaseService.isPurchasing {
                    ProgressView("Processing purchase...")
                        .padding()
                }

                Spacer()
            }
            .background(theme.background.ignoresSafeArea(.all))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func creditInfoRow(_ label: String, cost: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.green)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(theme.text)
            Spacer()
            Text("\(cost) credits")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.textSecondary)
        }
    }

    private func creditLabel(for productId: String) -> String {
        switch productId {
        case "credits_100": return "100 Credits"
        case "credits_200": return "200 Credits"
        case "credits_300": return "300 Credits"
        default: return productId
        }
    }

    private func creditSubLabel(for productId: String) -> String {
        switch productId {
        case "credits_100": return "~20 videos"
        case "credits_200": return "~40 videos • 10% off"
        case "credits_300": return "~60 videos • 17% off"
        default: return ""
        }
    }
}
