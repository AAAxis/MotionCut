import SwiftUI

struct AspectRatioView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    private let ratios: [(label: String, value: String, icon: String)] = [
        ("9:16", "9:16", "rectangle.portrait"),
        ("16:9", "16:9", "rectangle"),
        ("1:1", "1:1", "square"),
        ("4:5", "4:5", "rectangle.portrait.fill"),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Text("Aspect Ratio")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.text)

            // Preview shape
            let size = previewSize(for: viewModel.aspectRatio)
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.primary, lineWidth: 2)
                .frame(width: size.width, height: size.height)
                .overlay(
                    Text(viewModel.aspectRatio)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.textSecondary)
                )
                .padding(.vertical, 8)

            // Ratio buttons
            HStack(spacing: 12) {
                ForEach(ratios, id: \.value) { ratio in
                    Button {
                        viewModel.setAspectRatio(ratio.value)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: ratio.icon)
                                .font(.system(size: 24))
                            Text(ratio.label)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(
                            viewModel.aspectRatio == ratio.value ? .white : theme.textSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    viewModel.aspectRatio == ratio.value
                                        ? theme.primary
                                        : theme.surfaceElevated
                                )
                        )
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.top, 24)
    }

    private func previewSize(for ratio: String) -> CGSize {
        let maxDim: CGFloat = 120
        switch ratio {
        case "9:16": return CGSize(width: maxDim * 9 / 16, height: maxDim)
        case "16:9": return CGSize(width: maxDim, height: maxDim * 9 / 16)
        case "4:5": return CGSize(width: maxDim * 4 / 5, height: maxDim)
        default: return CGSize(width: maxDim, height: maxDim) // 1:1
        }
    }
}
