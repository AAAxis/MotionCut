import SwiftUI

struct SubtitlesTabView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Text on video")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.text)

            Text("The text below is added to each clip when you save. It comes from your reel script.")
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)

            Toggle(isOn: $viewModel.addCaptionsViaCloud) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add captions when exporting")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.text)
                    Text("Captions will be burned in by cloud (optional)")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                }
            }
            .tint(theme.primary)
            .padding(.vertical, 8)

            if viewModel.clips.isEmpty {
                Text("No clips.")
                    .font(.system(size: 14))
                    .foregroundColor(theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(theme.primary)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(theme.primary.opacity(0.12)))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(clip.text?.isEmpty == false ? clip.text! : "—")
                                    .font(.system(size: 15))
                                    .foregroundColor(clip.text?.isEmpty == false ? theme.text : theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(theme.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(theme.border, lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
