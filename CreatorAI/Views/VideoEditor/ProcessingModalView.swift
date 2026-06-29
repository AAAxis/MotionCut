import SwiftUI

struct ProcessingModalView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                if viewModel.processingStatus == "processing" {
                    // Processing State
                    ZStack {
                        Circle()
                            .fill(theme.primary.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "film.stack")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(theme.primary)
                    }

                    Text(viewModel.processingMessage?.replacingOccurrences(of: "...", with: "") ?? "Processing")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(theme.text)
                        .multilineTextAlignment(.center)

                } else if viewModel.processingStatus == "completed" || viewModel.processingStatus == "saved" {
                    ZStack {
                        Circle()
                            .fill(theme.success.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(theme.success)
                    }

                    Text("Saved!")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(theme.text)

                    Text("Your video has been saved to the app.")
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        viewModel.isProcessingModalVisible = false
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(theme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.top, 8)

                } else if viewModel.processingStatus == "failed" {
                    // Failed State
                    ZStack {
                        Circle()
                            .fill(theme.error.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(theme.error)
                    }

                    Text("Processing Failed")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(theme.text)

                    if let error = viewModel.processingError {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        viewModel.isProcessingModalVisible = false
                    } label: {
                        Text("Close")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(theme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(theme.background)
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: viewModel.processingStatus)
    }
}
