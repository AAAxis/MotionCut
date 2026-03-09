import SwiftUI
import AVKit
import AVFoundation

// MARK: - Fill-mode video player (no black bars; fills and crops to fit)

struct FillVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerFillView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? PlayerFillView)?.player = player
    }
}

private final class PlayerFillView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private static let previewBackground = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Self.previewBackground
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = Self.previewBackground.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = Self.previewBackground
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = Self.previewBackground.cgColor
    }
}

// MARK: - Video Preview

struct VideoPreviewView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    var body: some View {
        VStack(spacing: 12) {
            // Video Player
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.surface)
                    .frame(width: viewModel.videoDimensions.width, height: viewModel.videoDimensions.height)

                if let player = viewModel.player {
                    FillVideoPlayerView(player: player)
                        .frame(width: viewModel.videoDimensions.width, height: viewModel.videoDimensions.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture {
                            viewModel.togglePlayPause()
                        }
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 40))
                        .foregroundColor(theme.textTertiary)
                }

                // Text on video (current clip subtitle)
                if viewModel.activeClipIndex >= 0,
                   viewModel.activeClipIndex < viewModel.clips.count,
                   let text = viewModel.clips[viewModel.activeClipIndex].text,
                   !text.isEmpty {
                    Text(text)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.9), radius: 2, x: 2, y: 2)
                        .padding(.horizontal, 20)
                        .frame(width: viewModel.videoDimensions.width, height: viewModel.videoDimensions.height)
                        .offset(y: viewModel.videoDimensions.height * 0.08)
                }

                // Play/Pause overlay
                if !viewModel.isPlaying {
                    Image(systemName: "play.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(radius: 4)
                }
            }

            // Controls Row
            HStack(spacing: 16) {
                // Mute Button
                Button {
                    viewModel.toggleMute()
                } label: {
                    Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 16))
                        .foregroundColor(theme.textSecondary)
                }

                // Play/Pause
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(theme.text)
                }

                // Time Display
                Text(formatTime(viewModel.currentTime))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(theme.textSecondary)

                Text("/")
                    .foregroundColor(theme.textTertiary)

                Text(formatTime(viewModel.duration))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(theme.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 20)

            // Timeline Scrubber
            GeometryReader { geometry in
                let progress = viewModel.duration > 0 ? viewModel.currentTime / viewModel.duration : 0

                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.border)
                        .frame(height: 6)

                    // Fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.primary)
                        .frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 6)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let percentage = max(0, min(100, Double(value.location.x / geometry.size.width) * 100))
                            viewModel.seek(to: percentage)
                        }
                )
            }
            .frame(height: 6)
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
