import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct MusicTabView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme
    @State private var showFilePicker = false
    @State private var isExtracting = false
    @State private var extractError: String?

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

            // Action Buttons
            HStack(spacing: 10) {
                // Add Your Music
                Button {
                    showFilePicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text(viewModel.selectedMusic != nil ? "Change" : "Add Music")
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

                // Extract from Video
                Button {
                    Task { await extractAudioFromVideo() }
                } label: {
                    HStack(spacing: 8) {
                        if isExtracting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(theme.foxBlue)
                        } else {
                            Image(systemName: "waveform")
                                .font(.system(size: 18))
                        }
                        Text("Extract")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(theme.foxBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.foxBlue.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(theme.foxBlue.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .disabled(isExtracting || viewModel.clips.isEmpty)
                .opacity(viewModel.clips.isEmpty ? 0.4 : 1)
            }

            // Error message
            if let error = extractError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 13))
                }
                .foregroundColor(.orange)
            }

            // Hint
            if viewModel.selectedMusic == nil {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textTertiary)
                    Text("Add a file or extract audio from your video clips")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textTertiary)
                }
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

    // MARK: - Extract Audio

    private func extractAudioFromVideo() async {
        guard let firstClip = viewModel.clips.first else { return }

        isExtracting = true
        extractError = nil

        do {
            // Resolve clip URL
            let clipURL: URL
            if let localUri = firstClip.localUri, let url = URL(string: localUri) {
                clipURL = url
            } else if let url = URL(string: firstClip.uri) {
                // Remote URL — need to download first
                let tempVideo = FileManager.default.temporaryDirectory
                    .appendingPathComponent("extract-source-\(UUID().uuidString).mp4")
                let (data, _) = try await URLSession.shared.data(from: url)
                try data.write(to: tempVideo)
                clipURL = tempVideo
            } else {
                throw NSError(domain: "MusicTab", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid clip URL"])
            }

            // Check if video has audio track
            let asset = AVURLAsset(url: clipURL)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            guard !audioTracks.isEmpty else {
                await MainActor.run {
                    extractError = "This video has no audio track"
                    isExtracting = false
                }
                return
            }

            // Extract audio to M4A
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("extracted-\(UUID().uuidString).m4a")

            let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
            guard let session = exportSession else {
                throw NSError(domain: "MusicTab", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not create export session"])
            }

            session.outputURL = outputURL
            session.outputFileType = .m4a

            await session.export()

            guard session.status == .completed else {
                throw session.error ?? NSError(domain: "MusicTab", code: -3, userInfo: [NSLocalizedDescriptionKey: "Audio extraction failed"])
            }

            // Play extracted audio
            let track = MusicTrack(
                id: "extracted-\(UUID().uuidString)",
                name: "Extracted Audio",
                file: outputURL.absoluteString
            )

            await MainActor.run {
                isExtracting = false
            }
            await viewModel.selectMusic(track)

        } catch {
            await MainActor.run {
                extractError = error.localizedDescription
                isExtracting = false
            }
        }
    }
}
