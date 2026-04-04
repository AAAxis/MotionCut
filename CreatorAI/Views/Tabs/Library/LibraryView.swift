import SwiftUI
#if os(iOS)
import PhotosUI
#endif

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @StateObject private var viewModel = LibraryViewModel()
    @State private var showVideoPicker = false
    #if os(iOS)
    @State private var selectedVideoItem: PhotosPickerItem?
    #endif
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("Library")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundColor(theme.text)
                Spacer()

                // Import from gallery
                Button {
                    showVideoPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Import")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(theme.primary)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 16)

            // Content
            if viewModel.generations.isEmpty && !viewModel.isLoading {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundColor(theme.textTertiary)

                    Text("No videos yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(theme.text)

                    Text("Create your first video to see it here")
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(viewModel.generations) { gen in
                        GenerationListItem(
                            generation: gen,
                            thumbnail: viewModel.thumbnails[gen.id],
                            isDownloading: viewModel.downloadingIds.contains(gen.id),
                            onTap: {
                                if gen.status == .saved || gen.status == .completed {
                                    openEditor(for: gen)
                                } else if gen.isCloudOnly {
                                    Task {
                                        if let _ = await viewModel.downloadCloudVideo(gen) {
                                            openEditor(for: gen)
                                        }
                                    }
                                }
                            },
                            onShare: { viewModel.shareVideo(gen) }
                        )
                        .listRowBackground(theme.background)
                        .listRowInsets(EdgeInsets(top: 0, leading: 26, bottom: 0, trailing: 26))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteGeneration(gen) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.loadGenerations()
                }
            }
        }
        .background(theme.background.ignoresSafeArea(.all))
        .onAppear {
            Task { await viewModel.loadGenerations() }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let hasProcessing = viewModel.generations.contains { $0.status == .processing }
                if hasProcessing {
                    await viewModel.refreshProcessingGenerations()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToLibraryTab)) { _ in
            Task { await viewModel.loadGenerations() }
        }
        #if os(iOS)
        .photosPicker(isPresented: $showVideoPicker, selection: $selectedVideoItem, matching: .videos)
        .onChange(of: selectedVideoItem) { newItem in
            guard let newItem else { return }
            selectedVideoItem = nil
            isImporting = true
            Task {
                defer { isImporting = false }
                guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                let id = UUID().uuidString
                let dest = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(id).mp4")
                try? data.write(to: dest)
                let params = Route.VideoEditorParams(
                    videoUri: dest.absoluteString,
                    videoName: "Imported Video",
                    takesJson: nil,
                    musicUrl: nil,
                    userId: appState.userId ?? "demo-user"
                )
                NotificationCenter.default.post(name: .navigateToVideoEditor, object: params)
            }
        }
        #endif
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.white)
                        Text("Importing video...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(theme.surfaceElevated)
                    )
                }
            }
        }
    }

    private func openEditor(for generation: Generation) {
        let localFile = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(generation.id).mp4")
        let exists = FileManager.default.fileExists(atPath: localFile.path)
        print("[Library] openEditor: id=\(generation.id) localExists=\(exists) videoUri=\(generation.videoUri ?? "nil") remoteUrl=\(generation.resultVideoUrl ?? "nil") takesJson=\(generation.takesJson != nil)")

        // If video exists locally, open immediately
        if exists {
            print("[Library] Opening from local: \(localFile.path)")
            navigateToEditor(generation: generation, localVideoPath: localFile.path)
            return
        }

        // If has takesJson (reel with clips), open directly
        if let takesJson = generation.takesJson, !takesJson.isEmpty {
            navigateToEditor(generation: generation, localVideoPath: nil)
            return
        }

        // Remote video — download first, then open
        if let remoteUrl = generation.resultVideoUrl, remoteUrl.hasPrefix("http") {
            print("[Library] Downloading remote: \(remoteUrl)")
            isImporting = true
            Task {
                defer { isImporting = false }
                do {
                    try await FileStorageService.shared.downloadFile(from: remoteUrl, to: localFile)
                    await GenerationService.shared.updateGeneration(id: generation.id, videoUri: localFile.path)
                    print("[Library] Downloaded and saved to: \(localFile.path)")
                    navigateToEditor(generation: generation, localVideoPath: localFile.path)
                } catch {
                    print("[Library] Download failed: \(error)")
                }
            }
            return
        }

        // Fallback — try videoFileURL
        if let fileURL = generation.videoFileURL {
            print("[Library] Fallback: \(fileURL)")
            navigateToEditor(generation: generation, localVideoPath: fileURL.isFileURL ? fileURL.path : nil)
        }
    }

    private func navigateToEditor(generation: Generation, localVideoPath: String?) {
        let userId = generation.userId ?? "demo-user"
        let params: Route.VideoEditorParams

        if let takesJson = generation.takesJson, !takesJson.isEmpty {
            params = Route.VideoEditorParams(
                generationId: generation.id,
                videoUri: nil,
                videoName: generation.videoName,
                takesJson: takesJson,
                musicUrl: generation.resolvedMusicFile,
                userId: userId
            )
        } else {
            guard let path = localVideoPath else { return }
            params = Route.VideoEditorParams(
                generationId: generation.id,
                videoUri: path,
                videoName: generation.videoName,
                takesJson: nil,
                musicUrl: nil,
                userId: userId
            )
        }
        NotificationCenter.default.post(name: .navigateToVideoEditor, object: params)
    }
}

// MARK: - Generation List Item (matches Android GenerationListItem)

struct GenerationListItem: View {
    let generation: Generation
    let thumbnail: PlatformImage?
    var isDownloading: Bool = false
    let onTap: () -> Void
    let onShare: () -> Void
    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: 12) {
            // Tappable area (thumbnail + text) — opens editor
            HStack(spacing: 12) {
                // Thumbnail
                if let thumbnail {
                    Image(platformImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 90, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.surfaceElevated)
                        .frame(width: 90, height: 60)
                        .overlay(
                            Image(systemName: "film")
                                .foregroundColor(theme.textTertiary)
                        )
                }

                // Name + date
                VStack(alignment: .leading, spacing: 4) {
                    Text(generation.videoName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.text)
                        .lineLimit(1)

                    Text(generation.createdAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            // Share button — separate from tap area
            if generation.status == .saved || generation.status == .completed {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if isDownloading {
                ProgressView().scaleEffect(0.8)
            } else if generation.isCloudOnly {
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundColor(theme.primary)
            } else {
                statusBadge
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch generation.status {
        case .completed, .saved:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(theme.success)
        case .processing:
            ProgressView().scaleEffect(0.8)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(theme.error)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
