import SwiftUI

/// Loads an image from URL with disk caching.
struct CachedAsyncImage: View {
    let url: String
    let id: String
    @State private var image: PlatformImage?
    @Environment(\.theme) var theme

    private var cacheFile: URL {
        FileStorageService.shared.thumbnailCacheDirectory.appendingPathComponent("img_\(id).jpg")
    }

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
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
               let data = try? Data(contentsOf: cacheFile),
               let cached = PlatformImage.from(data: data) {
                image = cached
                return
            }
            // Download and cache
            guard let url = URL(string: url),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let downloaded = PlatformImage.from(data: data) else { return }
            image = downloaded
            try? data.write(to: cacheFile)
        }
    }
}
