import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @StateObject private var viewModel = LibraryViewModel()
    @State private var selectedVideoURL: URL?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title
            HStack {
                Text("Library")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundColor(theme.text)
                Spacer()

                // Grid/List toggle
                Button {
                    viewModel.isGridView.toggle()
                } label: {
                    Image(systemName: viewModel.isGridView ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 18))
                        .foregroundColor(theme.textSecondary)
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
            } else if viewModel.isGridView {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.generations) { gen in
                            VideoCardView(
                                generation: gen,
                                thumbnail: viewModel.thumbnails[gen.id],
                                onShare: { viewModel.shareVideo(gen) },
                                onDelete: { Task { await viewModel.deleteGeneration(gen) } },
                                onEdit: (gen.status == .saved || gen.status == .completed) ? { openEditor(for: gen) } : nil
                            )
                            .overlay(alignment: .topTrailing) {
                                if gen.isCloudOnly {
                                    if viewModel.downloadingIds.contains(gen.id) {
                                        ProgressView().scaleEffect(0.7).padding(6)
                                    } else {
                                        Image(systemName: "icloud.and.arrow.down")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                            .padding(5)
                                            .background(Color.black.opacity(0.5))
                                            .clipShape(Circle())
                                            .padding(6)
                                    }
                                }
                            }
                            .onTapGesture {
                                Task {
                                    if gen.isCloudOnly {
                                        if let url = await viewModel.downloadCloudVideo(gen) {
                                            selectedVideoURL = url
                                        }
                                    } else if let url = gen.videoFileURL {
                                        selectedVideoURL = url
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 26)
                }
                .refreshable {
                    await viewModel.loadGenerations()
                }
            } else {
                List {
                    ForEach(viewModel.generations) { gen in
                        VideoListRow(
                            generation: gen,
                            thumbnail: viewModel.thumbnails[gen.id],
                            isDownloading: viewModel.downloadingIds.contains(gen.id)
                        )
                        .onTapGesture {
                            Task {
                                if gen.isCloudOnly {
                                    if let url = await viewModel.downloadCloudVideo(gen) {
                                        selectedVideoURL = url
                                    }
                                } else if let url = gen.videoFileURL {
                                    selectedVideoURL = url
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteGeneration(gen) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                viewModel.shareVideo(gen)
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .tint(theme.primary)

                            if gen.status == .saved || gen.status == .completed {
                                Button {
                                    openEditor(for: gen)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(theme.primary)
                            }
                        }
                        .listRowBackground(theme.background)
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
            // Auto-refresh processing items every 5s
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
        .fullScreenCover(item: $selectedVideoURL) { url in
            VideoPreviewModal(videoURL: url)
        }
    }

    private func openEditor(for generation: Generation) {
        let userId = generation.userId ?? "demo-user"
        let params: Route.VideoEditorParams
        if let takesJson = generation.takesJson, !takesJson.isEmpty {
            params = Route.VideoEditorParams(
                videoUri: nil,
                videoName: generation.videoName,
                takesJson: takesJson,
                musicUrl: generation.musicFile,
                userId: userId
            )
        } else {
            guard let urlString = generation.videoFileURL?.absoluteString ?? generation.videoUri else { return }
            params = Route.VideoEditorParams(
                videoUri: urlString,
                videoName: generation.videoName,
                takesJson: nil,
                musicUrl: nil,
                userId: userId
            )
        }
        NotificationCenter.default.post(name: .navigateToVideoEditor, object: params)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct VideoListRow: View {
    let generation: Generation
    let thumbnail: UIImage?
    var isDownloading: Bool = false
    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.surfaceElevated)
                    .frame(width: 80, height: 60)
                    .overlay(
                        Image(systemName: "film")
                            .foregroundColor(theme.textTertiary)
                    )
            }

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

            statusBadge
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if isDownloading {
            ProgressView()
                .scaleEffect(0.8)
        } else if generation.isCloudOnly {
            Image(systemName: "icloud.and.arrow.down")
                .foregroundColor(theme.primary)
        } else {
            switch generation.status {
            case .completed, .saved:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(theme.success)
            case .processing:
                ProgressView()
                    .scaleEffect(0.8)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(theme.error)
            }
        }
    }
}
