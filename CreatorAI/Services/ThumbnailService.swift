import AVFoundation
import UIKit

actor ThumbnailService {
    static let shared = ThumbnailService()

    private var cache: [String: UIImage] = [:]
    private let storage = FileStorageService.shared

    func generateThumbnail(for videoURL: URL) async -> UIImage? {
        let key = videoURL.absoluteString

        // Check memory cache
        if let cached = cache[key] {
            return cached
        }

        // Check disk cache
        let thumbnailURL = storage.thumbnailCacheDirectory.appendingPathComponent("\(key.hashValue).jpg")
        if storage.fileExists(at: thumbnailURL),
           let data = try? Data(contentsOf: thumbnailURL),
           let image = UIImage(data: data) {
            cache[key] = image
            return image
        }

        // Generate from video
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)

        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let image = UIImage(cgImage: cgImage)

            // Save to disk cache
            if let jpegData = image.jpegData(compressionQuality: 0.7) {
                try? jpegData.write(to: thumbnailURL)
            }

            cache[key] = image
            return image
        } catch {
            print("Thumbnail generation failed: \(error)")
            return nil
        }
    }

    func clearCache() {
        cache.removeAll()
    }
}
