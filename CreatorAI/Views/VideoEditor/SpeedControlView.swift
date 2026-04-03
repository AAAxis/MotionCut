import SwiftUI

struct SpeedControlView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    private let presets: [Double] = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 5.0]

    var body: some View {
        VStack(spacing: 24) {
            Text("Speed")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.text)

            // Current speed display
            Text("\(String(format: "%.2g", viewModel.activeClipSpeed))x")
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundColor(viewModel.activeClipSpeed == 1.0 ? theme.text : theme.primary)

            // Slider
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { viewModel.activeClipSpeed },
                        set: { viewModel.setClipSpeed($0) }
                    ),
                    in: 0.1...5.0,
                    step: 0.05
                )
                .tint(theme.primary)
                .padding(.horizontal, 20)

                HStack {
                    Text("0.1x")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                    Spacer()
                    Text("5x")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                }
                .padding(.horizontal, 20)
            }

            // Preset buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { speed in
                        Button {
                            viewModel.setClipSpeed(speed)
                        } label: {
                            Text("\(String(format: "%.2g", speed))x")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(
                                    abs(viewModel.activeClipSpeed - speed) < 0.01
                                        ? .white
                                        : theme.textSecondary
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            abs(viewModel.activeClipSpeed - speed) < 0.01
                                                ? theme.primary
                                                : theme.surfaceElevated
                                        )
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .padding(.top, 24)
    }
}
