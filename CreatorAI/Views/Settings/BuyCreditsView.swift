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
                VStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 48))
                        .foregroundColor(theme.primary)

                    Text(appState.hasUnlimitedAPIUsage ? "\(appState.subscriptionPlan.displayName) Active" : "Start trial")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(theme.text)

                    Text("Unlock premium voice and remove watermark")
                        .font(.system(size: 15))
                        .foregroundColor(theme.textSecondary)
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 8) {
                    planInfoRow("Premium Voice generation")
                    planInfoRow("No CreatorAI watermark")
                    planInfoRow("Use your own fal.ai key on any plan")
                    planInfoRow("Monthly or yearly access")
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
                                    Text(planLabel(for: package.storeProduct))
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(theme.text)
                                    Text(planSubLabel(for: package.storeProduct))
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

    private func planInfoRow(_ label: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.green)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(theme.text)
            Spacer()
        }
    }

    private func planLabel(for product: StoreProduct) -> String {
        product.localizedTitle.isEmpty ? "Subscription" : product.localizedTitle
    }

    private func planSubLabel(for product: StoreProduct) -> String {
        product.localizedDescription.isEmpty ? "Premium voice and watermark removal" : product.localizedDescription
    }
}
