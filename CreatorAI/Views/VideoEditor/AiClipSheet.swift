import SwiftUI
#if os(iOS)
import RevenueCatUI
#endif

// MARK: - AI Model definitions (matches web pricing)

struct AIVideoModel: Identifiable {
    let id: String
    let name: String
    let tier: String // "budget", "standard", "premium"
    let creditsPerSec: Int
    let hasAudio: Bool
}

private let AI_VIDEO_MODELS: [AIVideoModel] = [
    // Budget — 1 credit/sec
    AIVideoModel(id: "bytedance/seedance-1-lite", name: "Seedance Lite", tier: "budget", creditsPerSec: 1, hasAudio: false),
    AIVideoModel(id: "wan-video/wan-2.5-t2v-fast", name: "Wan 2.5 Fast", tier: "budget", creditsPerSec: 1, hasAudio: false),
    // Standard — 2-4 credits/sec
    AIVideoModel(id: "bytedance/seedance-1-pro", name: "Seedance Pro", tier: "standard", creditsPerSec: 2, hasAudio: false),
    AIVideoModel(id: "kwaivgi/kling-v2.1", name: "Kling v2.1", tier: "standard", creditsPerSec: 3, hasAudio: false),
    AIVideoModel(id: "kwaivgi/kling-v3.0", name: "Kling v3", tier: "standard", creditsPerSec: 4, hasAudio: true),
    // Premium — 5-8 credits/sec
    AIVideoModel(id: "minimax/video-01", name: "MiniMax", tier: "premium", creditsPerSec: 5, hasAudio: false),
    AIVideoModel(id: "google/veo-3.1-fast", name: "Veo 3.1 Fast", tier: "premium", creditsPerSec: 5, hasAudio: true),
    AIVideoModel(id: "google/veo-3.1", name: "Veo 3.1", tier: "premium", creditsPerSec: 8, hasAudio: true),
]

struct AiClipSheet: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    @State private var showPaywall = false
    @State private var selectedModelId = "bytedance/seedance-1-lite"
    @State private var duration = 5

    private var selectedModel: AIVideoModel {
        AI_VIDEO_MODELS.first { $0.id == selectedModelId } ?? AI_VIDEO_MODELS[0]
    }

    private var totalCost: Int {
        selectedModel.creditsPerSec * duration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generate AI Clip")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(theme.text)

            // Prompt
            TextEditor(text: $viewModel.aiPrompt)
                .frame(minHeight: 70)
                .font(.system(size: 15))
                .foregroundColor(theme.text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.surfaceElevated)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.aiPrompt.isEmpty {
                        Text("Describe the video you want...")
                            .font(.system(size: 15))
                            .foregroundColor(theme.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            // Model selection
            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textTertiary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AI_VIDEO_MODELS) { model in
                            let isSelected = selectedModelId == model.id
                            VStack(spacing: 2) {
                                Text(model.name)
                                    .font(.system(size: 11, weight: .semibold))
                                HStack(spacing: 2) {
                                    Text("\(model.creditsPerSec)/s")
                                        .font(.system(size: 9))
                                    if model.hasAudio {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .font(.system(size: 7))
                                    }
                                }
                                .foregroundColor(isSelected ? .white.opacity(0.7) : theme.textTertiary)
                            }
                            .foregroundColor(isSelected ? .white : theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? theme.primary : theme.surfaceElevated)
                            )
                            .onTapGesture { selectedModelId = model.id }
                        }
                    }
                }
            }

            // Duration
            HStack {
                Text("Duration")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textTertiary)
                Spacer()
                ForEach([5, 10], id: \.self) { d in
                    Text("\(d)s")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(duration == d ? .white : theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(duration == d ? theme.primary : theme.surfaceElevated))
                        .onTapGesture { duration = d }
                }
            }

            // Status banner
            if viewModel.aiGenerating {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).tint(.white)
                    Text(viewModel.aiStatus)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.primary.opacity(0.8)))
            }

            // Cost + Balance
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                Text("Cost: \(totalCost) credits")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
                Spacer()
                Text("Balance: \(appState.credits >= 0 ? "\(appState.credits)" : "∞")")
                    .font(.system(size: 12))
                    .foregroundColor(appState.credits < totalCost && appState.credits >= 0 ? theme.error : theme.textTertiary)
            }

            // Generate button
            HStack(spacing: 8) {
                if viewModel.aiGenerating {
                    ProgressView().scaleEffect(0.7).tint(.white)
                    Text("Generating...")
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                    Text("Generate · \(totalCost) credits")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(viewModel.aiGenerating ? theme.primary.opacity(0.7) : theme.primary))
            .opacity(viewModel.aiPrompt.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                let prompt = viewModel.aiPrompt.trimmingCharacters(in: .whitespaces)
                guard !prompt.isEmpty, !viewModel.aiGenerating else { return }
                if appState.credits < totalCost && appState.credits >= 0 {
                    showPaywall = true
                } else {
                    appState.deductCredits(totalCost)
                    Task { await viewModel.generateAiClip(modelId: selectedModelId, duration: duration) }
                }
            }

            // Error
            if let error = viewModel.processingError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(theme.error)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(theme.error)
                }
            }

            Spacer()
        }
        .padding(16)
        .onChange(of: viewModel.aiGenerating) { generating in
            if !generating && viewModel.aiStatus.isEmpty {
                dismiss()
            }
        }
        .sheet(isPresented: $showPaywall) {
            #if os(iOS)
            PaywallView()
                .onPurchaseCompleted { _ in
                    Task { await PurchaseService.shared.handlePurchaseCompleted(appState: appState) }
                    showPaywall = false
                }
            #else
            MacBuyCreditsPlaceholder(dismiss: { showPaywall = false })
                .frame(minWidth: 400, minHeight: 300)
            #endif
        }
    }
}
