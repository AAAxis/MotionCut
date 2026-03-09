import SwiftUI

struct MusicTabView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Selected Music Banner
            if let selected = viewModel.selectedMusic {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(theme.primary.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundColor(theme.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(theme.text)
                        Text("Currently playing")
                            .font(.system(size: 12))
                            .foregroundColor(theme.textTertiary)
                    }

                    Spacer()

                    Button {
                        viewModel.clearMusic()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(theme.textTertiary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(theme.primary.opacity(0.3), lineWidth: 1)
                        )
                )

                // Volume Slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Volume")
                            .font(.system(size: 14))
                            .foregroundColor(theme.textSecondary)
                        Spacer()
                        Text("\(Int(viewModel.musicVolume * 100))%")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(theme.textTertiary)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 12))
                            .foregroundColor(theme.textTertiary)

                        Slider(value: Binding(
                            get: { viewModel.musicVolume },
                            set: { viewModel.updateMusicVolume($0) }
                        ), in: 0...1)
                        .tint(theme.primary)

                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 12))
                            .foregroundColor(theme.textTertiary)
                    }
                }
                .padding(.top, 4)
            }

            // No library list; music is only from AI (reel). Show message when no music.
            if viewModel.selectedMusic == nil {
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundColor(theme.textTertiary)
                    Text("Music is added automatically from your reel.")
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
