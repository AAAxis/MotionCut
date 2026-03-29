import SwiftUI

struct EditTabView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme

    private var selectedClip: Clip? {
        guard viewModel.activeClipIndex >= 0,
              viewModel.activeClipIndex < viewModel.clips.count else { return nil }
        return viewModel.clips[viewModel.activeClipIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let clip = selectedClip {
                HStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.system(size: 14))
                        .foregroundColor(theme.primary)

                    Text(clip.text?.isEmpty == false ? clip.text! : clip.name.isEmpty ? "Take \(viewModel.activeClipIndex + 1)" : clip.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(theme.text)
                        .lineLimit(1)

                    Spacer()

                    Text("Clip \(viewModel.activeClipIndex + 1) of \(viewModel.clips.count)")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                }

                if viewModel.clips.count > 1 {
                    Divider().background(theme.border)

                    HStack(spacing: 12) {
                        Button {
                            let prev = viewModel.activeClipIndex - 1
                            if prev >= 0 { viewModel.selectClip(at: prev) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Previous")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(viewModel.activeClipIndex > 0 ? theme.primary : theme.textTertiary)
                        }
                        .disabled(viewModel.activeClipIndex <= 0)

                        Spacer()

                        Button {
                            viewModel.rebuildPlaylistIfNeeded()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                Text("Preview All")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(theme.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(theme.primary.opacity(0.1))
                            )
                        }

                        Spacer()

                        Button {
                            let next = viewModel.activeClipIndex + 1
                            if next < viewModel.clips.count { viewModel.selectClip(at: next) }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Next")
                                Image(systemName: "chevron.right")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(viewModel.activeClipIndex < viewModel.clips.count - 1 ? theme.primary : theme.textTertiary)
                        }
                        .disabled(viewModel.activeClipIndex >= viewModel.clips.count - 1)
                    }
                }

            } else {
                Text("No clip selected")
                    .font(.system(size: 15))
                    .foregroundColor(theme.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

struct EditActionButton: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void
    @Environment(\.theme) var theme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isDestructive ? .red : theme.text)
            .frame(width: 68, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.surfaceElevated)
            )
        }
    }
}

// MARK: - Pexels Search Sheet

struct PexelsSearchSheet: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    @State private var hasLoaded = false

    private static let preloadQueries = [
        "cinematic nature", "city lifestyle", "business technology",
        "people working", "modern office", "creative workspace"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("Search stock videos...", text: $viewModel.pexelsQuery)
                        .font(.system(size: 16))
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await viewModel.searchPexels() }
                        }

                    Button {
                        Task { await viewModel.searchPexels() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(theme.primary))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if viewModel.isPexelsSearching {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if viewModel.pexelsResults.isEmpty && !hasLoaded {
                    Spacer()
                    ProgressView("Loading popular clips...")
                    Spacer()
                } else if viewModel.pexelsResults.isEmpty {
                    Spacer()
                    Text("No results. Try a different search.")
                        .font(.system(size: 15))
                        .foregroundColor(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                } else {
                    Text("\(viewModel.pexelsResults.count) results")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    List(viewModel.pexelsResults, id: \.id) { video in
                        HStack(spacing: 12) {
                            if let thumbUrl = video.thumbnailUrl, let url = URL(string: thumbUrl) {
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle().fill(theme.surfaceElevated)
                                }
                                .frame(width: 64, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(video.width)x\(video.height)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(theme.text)
                                Text("\(video.duration)s")
                                    .font(.system(size: 12))
                                    .foregroundColor(theme.textSecondary)
                            }

                            Spacer()

                            Button {
                                Task {
                                    if viewModel.pexelsReplaceMode {
                                        await viewModel.replaceClipFromPexels(video)
                                    } else {
                                        await viewModel.addClipFromPexels(video)
                                    }
                                }
                            } label: {
                                if viewModel.pexelsDownloadingId == video.id {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: viewModel.pexelsReplaceMode ? "arrow.triangle.2.circlepath" : "plus.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(theme.primary)
                                }
                            }
                            .disabled(viewModel.isPexelsDownloading)
                        }
                        .listRowBackground(theme.background)
                    }
                    .listStyle(.plain)
                }
            }
            .background(theme.background)
            .navigationTitle(viewModel.pexelsReplaceMode ? "Replace Clip" : "Add Stock Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                if viewModel.pexelsResults.isEmpty {
                    let query = Self.preloadQueries.randomElement()!
                    viewModel.pexelsQuery = query
                    await viewModel.searchPexels()
                }
            }
        }
    }
}
