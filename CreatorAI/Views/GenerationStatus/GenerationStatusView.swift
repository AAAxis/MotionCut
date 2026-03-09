import SwiftUI
import AVKit

struct GenerationStatusView: View {
    let generationId: String
    let title: String
    let isLocalExport: Bool

    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: GenerationStatusViewModel

    init(generationId: String, title: String, isLocalExport: Bool = false) {
        self.generationId = generationId
        self.title = title
        self.isLocalExport = isLocalExport
        self._viewModel = StateObject(wrappedValue: GenerationStatusViewModel(generationId: generationId, title: title, isLocalExport: isLocalExport))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20))
                        .foregroundColor(theme.text)
                }

                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Spacer()

            if viewModel.status == "completed", let videoUrl = viewModel.videoUrl {
                completedView(videoUrl: videoUrl)
            } else {
                progressView
            }

            Spacer()
        }
        .background(theme.background.ignoresSafeArea(.all))
        .navigationBarHidden(true)
        .onAppear { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 0) {
            if viewModel.status == "processing" {
                ZStack {
                    Circle()
                        .fill(theme.primary.opacity(0.12))
                        .frame(width: 80, height: 80)
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(theme.primary)
                }
                .padding(.bottom, 32)
            }

            if viewModel.status == "failed" {
                ZStack {
                    Circle()
                        .fill(theme.error.opacity(0.12))
                        .frame(width: 80, height: 80)
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(theme.error)
                }
                .padding(.bottom, 32)
            }

            // Steps
            VStack(spacing: 16) {
                ForEach(Array(viewModel.steps.enumerated()), id: \.element.key) { i, step in
                    HStack(spacing: 14) {
                        Image(systemName: i < viewModel.currentStep ? "checkmark.circle.fill" : step.icon)
                            .font(.system(size: 24))
                            .foregroundColor(i <= viewModel.currentStep ? theme.text : theme.textTertiary)
                            .frame(width: 36)

                        Text(step.label)
                            .font(.system(size: 17, weight: i == viewModel.currentStep ? .semibold : .regular))
                            .foregroundColor(i <= viewModel.currentStep ? theme.text : theme.textTertiary)

                        Spacer()
                    }
                    .opacity(i <= viewModel.currentStep ? 1 : 0.3)
                }
            }
            .padding(.horizontal, 24)

            // Error
            if viewModel.status == "failed", let error = viewModel.error {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(theme.error)
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.error.opacity(0.08))
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                Button {
                    dismiss()
                } label: {
                    Text("Try Again")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 20)
            }
        }
    }

    // MARK: - Completed View

    private func completedView(videoUrl: String) -> some View {
        VStack(spacing: 20) {
            // Video Player
            if let url = URL(string: videoUrl) {
                VideoPlayer(player: viewModel.resultPlayer)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(9/16, contentMode: .fit)
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)
                    .onAppear {
                        viewModel.setupResultPlayer(url: url)
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(theme.textTertiary)
                    Text("Unable to load video")
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                }
                .frame(height: 300)
            }

            // Action Buttons
            VStack(spacing: 12) {
                if isLocalExport {
                    Button {
                        NotificationCenter.default.post(name: .switchToLibraryTab, object: nil)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 18))
                            Text("Go to Library")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                HStack(spacing: 12) {
                    NavigationLink(value: Route.videoEditor(VideoEditorParams(
                        videoUri: videoUrl,
                        videoName: title,
                        userId: "demo-user"
                    ))) {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil")
                                .font(.system(size: 18))
                            Text("Edit")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(isLocalExport ? theme.text : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isLocalExport ? theme.surfaceElevated : theme.primary)
                                .overlay(
                                    isLocalExport ? RoundedRectangle(cornerRadius: 14).stroke(theme.border, lineWidth: 1) : nil
                                )
                        )
                    }

                    ShareLink(item: URL(string: videoUrl)!) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                            Text("Share")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(theme.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(theme.border, lineWidth: 1)
                                )
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }
}
