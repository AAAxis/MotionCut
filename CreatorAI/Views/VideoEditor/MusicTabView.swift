import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct MusicTabView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme
    @State private var showFilePicker = false

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
                            .lineLimit(1)
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

            // Add Music Button
            Button {
                showFilePicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                    Text(viewModel.selectedMusic != nil ? "Change Music" : "Add Music")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(theme.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.primary.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(theme.primary.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }

                let fileName = url.lastPathComponent
                let destURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("user-music-\(UUID().uuidString)")
                    .appendingPathExtension(url.pathExtension)

                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: url, to: destURL)

                    let trackName = fileName
                        .replacingOccurrences(of: ".\(url.pathExtension)", with: "")
                        .replacingOccurrences(of: "_", with: " ")
                        .replacingOccurrences(of: "-", with: " ")

                    let track = MusicTrack(
                        id: "user-\(UUID().uuidString)",
                        name: trackName,
                        file: destURL.absoluteString
                    )
                    Task { await viewModel.selectMusic(track) }
                } catch {
                    print("[Music] Failed to copy file: \(error)")
                }

            case .failure(let error):
                print("[Music] File picker error: \(error)")
            }
        }
    }

}
