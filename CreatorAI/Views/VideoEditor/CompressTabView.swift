import SwiftUI

struct CompressTabView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    private let aspectRatios = ["9:16", "16:9", "1:1", "4:5"]
    private let qualities = [
        ("original", "Original"),
        ("high", "High"),
        ("medium", "Medium"),
        ("low", "Low"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Aspect Ratio
            VStack(alignment: .leading, spacing: 12) {
                Text("Aspect Ratio")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.text)

                HStack(spacing: 10) {
                    ForEach(aspectRatios, id: \.self) { ratio in
                        Button {
                            viewModel.aspectRatio = ratio
                        } label: {
                            VStack(spacing: 6) {
                                aspectRatioIcon(ratio)
                                    .frame(width: 30, height: 30)

                                Text(ratio)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(viewModel.aspectRatio == ratio ? theme.primary.opacity(0.08) : theme.surfaceElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(viewModel.aspectRatio == ratio ? theme.primary : theme.border, lineWidth: 1.5)
                                    )
                            )
                            .foregroundColor(viewModel.aspectRatio == ratio ? theme.primary : theme.text)
                        }
                    }
                }
            }

            // Export Quality
            VStack(alignment: .leading, spacing: 12) {
                Text("Export Quality")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.text)

                VStack(spacing: 8) {
                    ForEach(qualities, id: \.0) { (id, label) in
                        Button {
                            viewModel.exportQuality = id
                        } label: {
                            HStack {
                                Image(systemName: viewModel.exportQuality == id ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(viewModel.exportQuality == id ? theme.primary : theme.textTertiary)

                                Text(label)
                                    .font(.system(size: 15))
                                    .foregroundColor(theme.text)

                                Spacer()

                                if id == "original" {
                                    Text("Best")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(theme.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule().fill(theme.primary.opacity(0.1))
                                        )
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(viewModel.exportQuality == id ? theme.primary.opacity(0.05) : Color.clear)
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func aspectRatioIcon(_ ratio: String) -> some View {
        let (w, h): (CGFloat, CGFloat) = {
            switch ratio {
            case "9:16": return (18, 30)
            case "16:9": return (30, 18)
            case "1:1": return (24, 24)
            case "4:5": return (20, 25)
            default: return (24, 24)
            }
        }()

        RoundedRectangle(cornerRadius: 3)
            .stroke(theme.textSecondary, lineWidth: 1.5)
            .frame(width: w, height: h)
    }
}
