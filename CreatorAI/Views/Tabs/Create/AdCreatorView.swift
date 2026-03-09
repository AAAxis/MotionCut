import SwiftUI

struct AdCreatorView: View {
    @ObservedObject var viewModel: CreateViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Paste a link, add your direction, get a video ad.")
                .font(.system(size: 16))
                .foregroundColor(theme.textSecondary)
                .padding(.bottom, 24)

            // URL Input
            SectionLabel("WEBSITE OR PRODUCT URL")
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 18))
                    .foregroundColor(theme.textTertiary)

                TextField("https://example.com/product", text: $viewModel.adURL)
                    .font(.system(size: 16))
                    .foregroundColor(theme.text)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(theme.border, lineWidth: 1)
                    )
            )
            .padding(.bottom, 20)

            // Prompt
            SectionLabel("CREATIVE DIRECTION (OPTIONAL)")
            TextEditor(text: $viewModel.adPrompt)
                .frame(minHeight: 80)
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
                        Text("e.g. Focus on speed, target small businesses")
                            .font(.system(size: 16))
                            .foregroundColor(theme.textTertiary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.bottom, 20)

            // Style
            SectionLabel("STYLE")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AD_STYLES) { s in
                        Button {
                            viewModel.adStyle = s.id
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: s.icon)
                                    .font(.system(size: 16))
                                Text(s.label)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(viewModel.adStyle == s.id ? theme.primary.opacity(0.08) : theme.surfaceElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(viewModel.adStyle == s.id ? theme.primary : theme.border, lineWidth: 1.5)
                                    )
                            )
                            .foregroundColor(viewModel.adStyle == s.id ? theme.primary : theme.text)
                        }
                    }
                }
            }
            .padding(.bottom, 20)

            // Duration
            SectionLabel("DURATION")
            HStack(spacing: 10) {
                ForEach(AD_DURATIONS) { d in
                    Button {
                        viewModel.adDuration = d.value
                        viewModel.adScenes = d.value == 15 ? 3 : d.value == 30 ? 5 : 8
                    } label: {
                        VStack(spacing: 2) {
                            Text(d.label)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(viewModel.adDuration == d.value ? theme.primary : theme.text)
                            Text(d.desc)
                                .font(.system(size: 12))
                                .foregroundColor(theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(viewModel.adDuration == d.value ? theme.primary.opacity(0.08) : theme.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(viewModel.adDuration == d.value ? theme.primary : theme.border, lineWidth: 1.5)
                                )
                        )
                    }
                }
            }
            .padding(.bottom, 24)

            // Preview Card
            if let preview = viewModel.adPreview, viewModel.adStep != .input {
                VStack(alignment: .leading, spacing: 12) {
                    if let ogImage = preview.ogImage, let url = URL(string: ogImage) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(theme.surfaceElevated)
                                .frame(height: 160)
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

            // Action Button
            Button {
                dismissKeyboard()
                Task {
                    if viewModel.adStep == .input || viewModel.adPreview == nil {
                        await viewModel.previewAdURL()
                    } else {
                        if let result = await viewModel.generateAd(appState: appState) {
                            NotificationCenter.default.post(
                                name: .navigateToGenerationStatus,
                                object: result
                            )
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else if viewModel.adStep == .input || viewModel.adPreview == nil {
                        Image(systemName: "eye")
                            .font(.system(size: 20))
                        Text("Preview")
                            .font(.system(size: 17, weight: .semibold))
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 20))
                        Text("Generate Video Ad")
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
                .opacity(viewModel.isLoading ? 0.7 : 1)
            }
            .disabled(viewModel.isLoading)

            // Change URL link
            if viewModel.adStep == .preview && viewModel.adPreview != nil {
                Button {
                    viewModel.resetAdPreview()
                } label: {
                    Text("<- Change URL")
                        .font(.system(size: 15))
                        .foregroundColor(theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
            }
        }
    }
}
