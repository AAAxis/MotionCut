import SwiftUI

/// Loads an image from URL with disk caching.
struct CachedAsyncImage: View {
    let url: String
    let id: String
    @State private var image: UIImage?
    @Environment(\.theme) var theme

    private var cacheFile: URL {
        FileStorageService.shared.thumbnailCacheDirectory.appendingPathComponent("img_\(id).jpg")
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(theme.surfaceElevated)
            }
        }
        .task {
            // Check disk cache
            if FileManager.default.fileExists(atPath: cacheFile.path),
               let cached = UIImage(contentsOfFile: cacheFile.path) {
                image = cached
                return
            }
            // Download and cache
            guard let url = URL(string: url),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let downloaded = UIImage(data: data) else { return }
            image = downloaded
            try? data.write(to: cacheFile)
        }
    }
}
