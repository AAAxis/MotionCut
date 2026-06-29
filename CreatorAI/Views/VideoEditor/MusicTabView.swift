import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct MusicTabView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme
    var onClose: (() -> Void)? = nil
    @State private var showFilePicker = false
    @State private var previewPlayer: AVPlayer?
    @State private var previewingTrackId: String?
    @State private var addingTrackId: String?

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

            if !viewModel.musicLibrary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Library")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.musicLibrary) { track in
                                let isAdding = addingTrackId == track.id
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Button {
                                            togglePreview(track)
                                        } label: {
                                            ZStack {
                                                Circle()
                                                    .fill(theme.primary.opacity(0.12))
                                                    .frame(width: 26, height: 26)
                                                Image(systemName: previewingTrackId == track.id ? "stop.fill" : "play.fill")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(theme.primary)
                                            }
                                        }
                                        #if os(macOS)
                                        .buttonStyle(.plain)
                                        #endif
                                        .disabled(isAdding)

                                        Image(systemName: "waveform")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(theme.primary)

                                        Spacer(minLength: 0)

                                        if isAdding {
                                            ProgressView()
                                                .scaleEffect(0.55)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title ?? "Track")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(theme.textTertiary)
                                        Text(track.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(theme.text)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 132, alignment: .leading)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(theme.surfaceElevated)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(viewModel.selectedMusic?.id == track.id ? theme.primary : theme.border, lineWidth: 1)
                                        )
                                )
                                .opacity(isAdding ? 0.72 : 1)
                                .scaleEffect(isAdding ? 0.98 : 1)
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                                .onTapGesture {
                                    guard !isAdding else { return }
                                    addTrackAndClose(track)
                                }
                            }
                        }
                    }
                }
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
        .onDisappear {
            stopPreview()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .movie, .mpeg4Movie, .quickTimeMovie],
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
                    Task {
                        await viewModel.addMusicTrack(track)
                        onClose?()
                    }
                } catch {
                    print("[Music] Failed to copy file: \(error)")
                }

            case .failure(let error):
                print("[Music] File picker error: \(error)")
            }
        }
    }

    private func addTrackAndClose(_ track: MusicTrack) {
        guard addingTrackId == nil else { return }
        stopPreview()
        addingTrackId = track.id
        Task {
            await viewModel.addMusicTrack(track)
            await MainActor.run {
                addingTrackId = nil
                onClose?()
            }
        }
    }

    private func togglePreview(_ track: MusicTrack) {
        if previewingTrackId == track.id {
            stopPreview()
            return
        }

        guard let url = previewURL(for: track) else { return }
        stopPreview()
        let player = AVPlayer(url: url)
        previewPlayer = player
        previewingTrackId = track.id
        player.play()
    }

    private func stopPreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        previewingTrackId = nil
    }

    private func previewURL(for track: MusicTrack) -> URL? {
        if track.file.hasPrefix("file://"), let url = URL(string: track.file) {
            return url
        }
        let filePath = track.file.replacingOccurrences(of: "file://", with: "")
        if filePath.hasPrefix("/"), FileManager.default.fileExists(atPath: filePath) {
            return URL(fileURLWithPath: filePath)
        }
        return URL(string: track.file)
    }

}
