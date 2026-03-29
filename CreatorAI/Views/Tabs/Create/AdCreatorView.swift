import SwiftUI

private func flagEmoji(_ code: String) -> String {
    let base: UInt32 = 127397
    return code.uppercased().unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }.map { String($0) }.joined()
}

struct AdCreatorView: View {
    @ObservedObject var viewModel: CreateViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme

    /// Extract first URL from the description text
    private var detectedURL: String? {
        let pattern = #"https?://[^\s]+"#
        guard let range = viewModel.adPrompt.range(of: pattern, options: .regularExpression) else { return nil }
        return String(viewModel.adPrompt[range])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Unified description field (auto-detects URLs like Android)
            SectionLabel("DESCRIPTION")
            TextEditor(text: $viewModel.adPrompt)
                .frame(minHeight: 100)
                .font(.system(size: 16))
                .foregroundColor(theme.text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(theme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(theme.border, lineWidth: 1)
                        )
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.adPrompt.isEmpty {
                        Text("Describe your video or paste a product URL...")
                            .font(.system(size: 16))
                            .foregroundColor(theme.textTertiary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: viewModel.adPrompt) { newValue in
                    // Auto-extract URL and preview
                    if let url = detectedURL {
                        if viewModel.adURL != url {
                            viewModel.adURL = url
                            Task { await viewModel.previewAdURL() }
                        }
                    } else {
                        viewModel.adURL = ""
                        viewModel.adPreview = nil
                        viewModel.adStep = .input
                    }
                }
                .padding(.bottom, 12)

            // Show detected URL chip
            if let url = detectedURL {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                    Text(url)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundColor(theme.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(theme.primary.opacity(0.1))
                )
                .padding(.bottom, 16)
            }

            // Voiceover Language
            SectionLabel("VOICEOVER LANGUAGE")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(LANGUAGES) { lang in
                        Button {
                            viewModel.adLanguage = lang.id
                        } label: {
                            HStack(spacing: 6) {
                                Text(flagEmoji(lang.flag))
                                    .font(.system(size: 18))
                                Text(lang.label)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(viewModel.adLanguage == lang.id ? theme.primary.opacity(0.08) : theme.surfaceElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(viewModel.adLanguage == lang.id ? theme.primary : theme.border, lineWidth: 1.5)
                                    )
                            )
                            .foregroundColor(viewModel.adLanguage == lang.id ? theme.primary : theme.text)
                        }
                    }
                }
            }
            .padding(.bottom, 20)



            // Preview Card
            if let preview = viewModel.adPreview, viewModel.adStep != .input {
                VStack(alignment: .leading, spacing: 12) {
                    if let ogImage = preview.ogImage, !ogImage.isEmpty, let url = URL(string: ogImage) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            default:
                                EmptyView()
                            }
                        }
                    }

                    if let title = preview.title {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(theme.text)
                            .lineLimit(2)
                    }

                    if let desc = preview.description {
                        Text(desc)
                            .font(.system(size: 14))
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(3)
                    }

                    HStack(spacing: 4) {
                        if let domain = preview.domain { Text(domain) }
                        Text("*")
                        Text("\(preview.features?.count ?? 0) features")
                        Text("*")
                        Text("\(preview.images?.count ?? 0) images")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(theme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(theme.border, lineWidth: 1)
                        )
                )
                .padding(.bottom, 24)
            }

            // Generation Progress
            if viewModel.isGeneratingFreeReel, let progress = viewModel.freeReelProgress {
                VStack(spacing: 8) {
                    ProgressView(value: progress.progress)
                        .tint(theme.primary)
                    Text(progress.step)
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                }
                .padding(.bottom, 16)
            }

            // Generate Button (all local: script → Pexels → TTS → editor)
            Button {
                dismissKeyboard()
                Task {
                    await viewModel.generateFreeReel(appState: appState)
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isGeneratingFreeReel {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 20))
                        Text("Generate · 10 credits")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(theme.primary)
                )
                .opacity(viewModel.isGeneratingFreeReel ? 0.7 : 1)
            }
            .disabled(viewModel.isGeneratingFreeReel)
        }
    }
}
