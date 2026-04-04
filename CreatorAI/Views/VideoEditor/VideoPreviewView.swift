import SwiftUI
import AVKit
import AVFoundation

// MARK: - Compact Video Preview

struct VideoPreviewView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    var body: some View {
        ZStack {
            // Video
            if let player = viewModel.player {
                PlatformVideoPlayerView(player: player, videoGravity: .resizeAspectFill)
                    .onTapGesture {
                        viewModel.togglePlayPause()
                    }
            } else {
                theme.surface
                VStack(spacing: 12) {
                    if !viewModel.clipsCached {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(theme.textTertiary)
                        Text("Loading video...")
                            .font(.system(size: 14))
                            .foregroundColor(theme.textTertiary)
                    } else {
                        Image(systemName: "film")
                            .font(.system(size: 40))
                            .foregroundColor(theme.textTertiary)
                    }
                }
            }

            // Subtitle overlay
            if viewModel.activeClipIndex >= 0,
               viewModel.activeClipIndex < viewModel.clips.count,
               let text = viewModel.clips[viewModel.activeClipIndex].text,
               !text.isEmpty {
                VStack {
                    Spacer()
                    Text(text)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.9), radius: 2, x: 1, y: 1)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            }

            // Play/Pause overlay — centered
            if !viewModel.isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(radius: 4)
            }

            // Bottom controls bar (overlaid)
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    // Mute
                    Button {
                        viewModel.toggleMute()
                    } label: {
                        Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif

                    // Play/Pause
                    Button {
                        viewModel.togglePlayPause()
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif

                    // Time
                    Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    // Music off button
                    if viewModel.selectedMusic != nil {
                        Button {
                            viewModel.clearMusic()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "music.note.slash")
                                    .font(.system(size: 12))
                                Text("Music off")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(theme.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.5)))
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #endif
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.black.opacity(0.4))

                // Seek slider
                SeekSlider(
                    progress: viewModel.duration > 0 ? viewModel.currentTime / viewModel.duration : 0,
                    onSeek: { pct in viewModel.seek(to: pct * 100) },
                    accentColor: theme.primary
                )
                .padding(.bottom, 30)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Seek Slider

private struct SeekSlider: View {
    let progress: Double
    let onSeek: (Double) -> Void
    let accentColor: Color
    @State private var isSeeking = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(height: 4)

                // Filled portion
                Rectangle()
                    .fill(accentColor)
                    .frame(width: max(0, geo.size.width * CGFloat(progress)), height: 4)

                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: isSeeking ? 20 : 14, height: isSeeking ? 20 : 14)
                    .shadow(radius: 2)
                    .offset(x: max(0, geo.size.width * CGFloat(progress) - (isSeeking ? 10 : 7)))
                    .animation(.easeOut(duration: 0.15), value: isSeeking)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isSeeking = true
                        let pct = max(0, min(1, Double(value.location.x / geo.size.width)))
                        onSeek(pct)
                    }
                    .onEnded { _ in
                        isSeeking = false
                    }
            )
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
    }
}
