import Foundation

class FileStorageService {
    static let shared = FileStorageService()

    let cacheDirectory: URL
    let documentsDirectory: URL
    let clipCacheDirectory: URL
    let musicCacheDirectory: URL
    let thumbnailCacheDirectory: URL
    let renderedVideosDirectory: URL
    /// Persistent directory for saved library videos (survives cache clear).
    let savedVideosDirectory: URL

    private init() {
        let fm = FileManager.default
        cacheDirectory = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        documentsDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        clipCacheDirectory = cacheDirectory.appendingPathComponent("clip_cache")
        musicCacheDirectory = documentsDirectory.appendingPathComponent("music_cache")
        thumbnailCacheDirectory = documentsDirectory.appendingPathComponent("thumbnails")
        renderedVideosDirectory = cacheDirectory.appendingPathComponent("rendered_videos")
        savedVideosDirectory = documentsDirectory.appendingPathComponent("saved_videos")

        createDirectories()
    }

    private func createDirectories() {
        let fm = FileManager.default
        let dirs = [clipCacheDirectory, musicCacheDirectory, thumbnailCacheDirectory, renderedVideosDirectory, savedVideosDirectory]
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attrs[.size] as? Int64
    }

    func deleteFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func moveFile(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: source, to: destination)
    }

    func copyFile(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    /// Copies a video to persistent storage (Documents/saved_videos) and returns the new file URL (for library).
    /// Use this so videos survive app backgrounding and cache purge.
    func copyToSavedVideos(sourceURL: URL, id: String) throws -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: savedVideosDirectory.path) {
            try fm.createDirectory(at: savedVideosDirectory, withIntermediateDirectories: true)
        }
        let dest = savedVideosDirectory.appendingPathComponent("\(id).mp4")
        try copyFile(from: sourceURL, to: dest)
        return dest
    }

    func downloadFile(from urlString: String, to localURL: URL) async throws {
        guard let url = URL(string: urlString) else { return }

        if fileExists(at: localURL), let size = fileSize(at: localURL), size > 0 {
            return // Already cached
        }

        let (tempURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        try moveFile(from: tempURL, to: localURL)
    }

    func cleanupOldFiles(in directory: URL, olderThan days: Int = 7) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(days * 86400))

        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }

        for file in files {
            guard let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = attrs.contentModificationDate,
                  modified < cutoff else { continue }
            try? fm.removeItem(at: file)
        }
    }
}
