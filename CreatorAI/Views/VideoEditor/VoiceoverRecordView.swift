import SwiftUI
import AVKit

struct VoiceoverRecordView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @StateObject private var recorder = VoiceoverRecorderService.shared
    @Environment(\.theme) var theme
    @State private var previewPlayer: AVAudioPlayer?
    @State private var isPreviewPlaying = false

    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text("Record Voiceover")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.text)

            // Timer display
            Text(formatTime(recorder.isRecording ? recorder.recordingDuration : previewDuration))
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundColor(recorder.isRecording ? theme.error : theme.text)

            // Waveform indicator
            if recorder.isRecording {
                HStack(spacing: 3) {
                    ForEach(0..<12, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(theme.primary)
                            .frame(width: 4, height: .random(in: 8...28))
                            .animation(
                                .easeInOut(duration: 0.3)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.05),
                                value: recorder.recordingDuration
                            )
                    }
                }
                .frame(height: 32)
            }

            // Permission denied message
            if recorder.permissionDenied {
                Text("Microphone access denied. Enable it in Settings.")
                    .font(.system(size: 13))
                    .foregroundColor(theme.error)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Existing voiceover preview
            if let url = viewModel.voiceoverFileURL, !recorder.isRecording {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        // Play/stop preview
                        Button {
                            togglePreview(url: url)
                        } label: {
                            Image(systemName: isPreviewPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 18))
                                .foregroundColor(theme.primary)
                                .frame(width: 44, height: 44)
                                .background(theme.primary.opacity(0.15))
                                .clipShape(Circle())
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Voiceover recorded")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(theme.text)
                            Text(formatTime(previewDuration))
                                .font(.system(size: 12))
                                .foregroundColor(theme.textTertiary)
                        }

                        Spacer()

                        // Remove
                        Button {
                            stopPreview()
                            viewModel.removeVoiceover()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 16))
                                .foregroundColor(theme.error)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
            }

            // Record / Stop button
            HStack(spacing: 20) {
                if recorder.isRecording {
                    // Stop
                    Button {
                        recorder.stopRecording()
                        if let url = recorder.recordedFileURL {
                            viewModel.setVoiceover(url: url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 16))
                            Text("Stop")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(theme.error)
                        .clipShape(Capsule())
                    }
                } else {
                    // Record
                    Button {
                        stopPreview()
                        Task {
                            await recorder.startRecording()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(theme.error)
                                .frame(width: 12, height: 12)
                            Text(viewModel.voiceoverFileURL != nil ? "Re-record" : "Record")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(theme.primary)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .padding(.top, 24)
        .onDisappear {
            if recorder.isRecording {
                recorder.stopRecording()
                if let url = recorder.recordedFileURL {
                    viewModel.setVoiceover(url: url)
                }
            }
            stopPreview()
        }
    }

    // MARK: - Preview playback

    private var previewDuration: TimeInterval {
        guard let url = viewModel.voiceoverFileURL ?? recorder.recordedFileURL else { return 0 }
        let asset = AVURLAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }

    private func togglePreview(url: URL) {
        if isPreviewPlaying {
            stopPreview()
        } else {
            do {
                previewPlayer = try AVAudioPlayer(contentsOf: url)
                previewPlayer?.play()
                isPreviewPlaying = true
            } catch {
                print("[Voiceover] Preview failed: \(error)")
            }
        }
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewPlaying = false
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, frac)
    }
}
