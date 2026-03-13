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
                    // Clip Actions
                    Divider().background(theme.border)

                    HStack(spacing: 16) {
                        // Split at playhead
                        EditActionButton(icon: "scissors", label: "Split") {
                            viewModel.splitClipAtPlayhead()
                        }

                        // Duplicate clip
                        EditActionButton(icon: "doc.on.doc", label: "Duplicate") {
                            viewModel.duplicateClip(at: viewModel.activeClipIndex)
                        }

                        // Delete clip
                        if viewModel.clips.count > 1 {
                            EditActionButton(icon: "trash", label: "Delete", isDestructive: true) {
                                viewModel.removeClip(at: viewModel.activeClipIndex)
                            }
                        }

                        Spacer()
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
            }
            .foregroundColor(isDestructive ? .red : theme.text)
            .frame(width: 60, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.surfaceElevated)
            )
        }
    }
}
