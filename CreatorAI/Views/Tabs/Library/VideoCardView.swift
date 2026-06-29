import SwiftUI

struct VideoCardView: View {
    let generation: Generation
    let thumbnail: PlatformImage?
    let onShare: () -> Void
    let onDelete: () -> Void
    var onEdit: (() -> Void)?

    @Environment(\.theme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                if let thumbnail = thumbnail {
                    Image(platformImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(theme.surfaceElevated)
                    Image(systemName: "film")
                        .font(.system(size: 28))
                        .foregroundColor(theme.textTertiary)
                }

                // Status overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        statusIndicator
                            .padding(8)
                    }
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(generation.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineLimit(1)

                Text(generation.createdAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(.top, 8)
        }
        .contextMenu {
            if (generation.status == .saved || generation.status == .completed), let onEdit = onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            Button {
                onShare()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch generation.status {
        case .completed, .saved:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .shadow(radius: 2)
        case .processing:
            Image(systemName: "film.stack")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .shadow(radius: 2)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(theme.error)
                .shadow(radius: 2)
        }
    }
}
