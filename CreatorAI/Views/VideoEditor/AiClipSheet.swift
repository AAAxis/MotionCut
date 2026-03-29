import SwiftUI
import RevenueCatUI

struct AiClipSheet: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate AI Clip")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(theme.text)

            Text("Describe the video clip you want AI to generate")
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)

            TextEditor(text: $viewModel.aiPrompt)
                .frame(minHeight: 80)
                .font(.system(size: 16))
                .foregroundColor(theme.text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(theme.border, lineWidth: 1)
                        )
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.aiPrompt.isEmpty {
                        Text("e.g. A person walking on the beach at sunset...")
                            .font(.system(size: 16))
                            .foregroundColor(theme.textTertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            // Status banner
            if viewModel.aiGenerating {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.8).tint(.white)
                    Text(viewModel.aiStatus)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.primary.opacity(0.8))
                )
            }

            // Generate button
            Button {
                if appState.credits < 10 {
                    showPaywall = true
                } else {
                    appState.deductCredits(10)
                    Task { await viewModel.generateAiClip() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                    Text("Generate")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.primary)
                )
            }
            .disabled(viewModel.aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.aiGenerating)
            .opacity(viewModel.aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

            Spacer()
        }
        .padding(20)
        .onChange(of: viewModel.aiGenerating) { generating in
            if !generating && viewModel.aiStatus.isEmpty {
                dismiss()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .onPurchaseCompleted { _ in
                    Task { await PurchaseService.shared.handlePurchaseCompleted(appState: appState) }
                    showPaywall = false
                }
        }
    }
}
