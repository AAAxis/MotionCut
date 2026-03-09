import Foundation

enum GenerationStatus: String, Codable {
    case processing
    case completed
    case failed
    case saved
}

struct Generation: Identifiable, Codable, Equatable {
    let id: String
    var videoName: String
    var videoUri: String?
    var resultVideoUrl: String?
    var status: GenerationStatus

    /// Returns a local file URL for playback/thumbnail.
    /// Resolves saved_videos paths relative to Documents at runtime (container UUID can change between launches).
    /// Falls back to resultVideoUrl for remote (Supabase) URLs.
    var videoFileURL: URL? {
        // 1. Check if we have a locally saved video (by generation id)
        let localFile = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(id).mp4")
        if FileManager.default.fileExists(atPath: localFile.path) {
            return localFile
        }

        // 2. Check videoUri for absolute paths that still exist
        if let raw = videoUri, !raw.isEmpty {
            let path = raw.replacingOccurrences(of: "file://", with: "")
            // Skip cache-only paths
            if !path.contains("Caches") && !path.contains("rendered_videos") {
                let url = raw.hasPrefix("file://") ? URL(string: raw) : URL(fileURLWithPath: path)
                if let url = url, FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        // 3. Return remote URL (Supabase Storage) for streaming/download
        if let remote = resultVideoUrl, remote.hasPrefix("http") {
            return URL(string: remote)
        }

        return nil
    }

    /// True when the video is only available remotely (not cached locally).
    var isCloudOnly: Bool {
        let localFile = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(id).mp4")
        if FileManager.default.fileExists(atPath: localFile.path) { return false }
        if let raw = videoUri, !raw.isEmpty {
            let path = raw.replacingOccurrences(of: "file://", with: "")
            if !path.contains("Caches"), FileManager.default.fileExists(atPath: path) { return false }
        }
        return resultVideoUrl?.hasPrefix("http") == true
    }
    var createdAt: Date
    var userId: String?
    var musicId: String?
    var musicName: String?
    var musicFile: String?
    var musicVolume: Double?
    var faceImageUrl: String?
    var thumbnailPath: String?
    /// Original reel takes JSON so Edit can restore full structure (clips, text, beats).
    var takesJson: String?

    init(
        id: String = UUID().uuidString,
        videoName: String = "",
        videoUri: String? = nil,
        resultVideoUrl: String? = nil,
        status: GenerationStatus = .processing,
        createdAt: Date = Date(),
        userId: String? = nil,
        musicId: String? = nil,
        musicName: String? = nil,
        musicFile: String? = nil,
        musicVolume: Double? = nil,
        faceImageUrl: String? = nil,
        thumbnailPath: String? = nil,
        takesJson: String? = nil
    ) {
        self.id = id
        self.videoName = videoName
        self.videoUri = videoUri
        self.resultVideoUrl = resultVideoUrl
        self.status = status
        self.createdAt = createdAt
        self.userId = userId
        self.musicId = musicId
        self.musicName = musicName
        self.musicFile = musicFile
        self.musicVolume = musicVolume
        self.faceImageUrl = faceImageUrl
        self.thumbnailPath = thumbnailPath
        self.takesJson = takesJson
    }
}
