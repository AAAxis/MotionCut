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
    /// Falls back to resultVideoUrl for remote Firebase Storage URLs.
    var videoFileURL: URL? {
        let savedDir = FileStorageService.shared.savedVideosDirectory

        // 1. Check if we have a locally saved video (by generation id)
        let localFile = savedDir.appendingPathComponent("\(id).mp4")
        if FileManager.default.fileExists(atPath: localFile.path) {
            return localFile
        }

        // 2. Check for first clip file (local reel generations save as {id}_clip_0.mp4)
        let firstClip = savedDir.appendingPathComponent("\(id)_clip_0.mp4")
        if FileManager.default.fileExists(atPath: firstClip.path) {
            return firstClip
        }

        // 3. Check videoUri — resolve stale container paths by filename
        if let raw = videoUri, !raw.isEmpty {
            let path = raw.replacingOccurrences(of: "file://", with: "")
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
            // Try resolving filename in savedVideosDirectory
            let filename = (path as NSString).lastPathComponent
            if !filename.isEmpty {
                let resolved = savedDir.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: resolved.path) {
                    return resolved
                }
            }
        }

        // 4. Return remote URL for streaming/download.
        if let remote = resultVideoUrl, remote.hasPrefix("http") {
            return URL(string: remote)
        }

        return nil
    }

    /// True when the video is only available remotely (not cached locally).
    var isCloudOnly: Bool {
        // If videoFileURL resolves to a local file, it's not cloud-only
        if let url = videoFileURL, url.isFileURL { return false }
        // If we have takesJson, clips are local
        if let takes = takesJson, !takes.isEmpty { return false }
        return resultVideoUrl?.hasPrefix("http") == true
    }

    /// True only for content that is available from this device's app storage.
    /// Remote-only URLs are intentionally excluded from Library.
    var hasLocalLibraryMedia: Bool {
        if status == .processing { return true }
        if let url = videoFileURL, url.isFileURL { return true }
        if usableTakesJson != nil { return true }
        return false
    }

    /// Returns takes JSON only when at least one clip source can be used on this device.
    /// This avoids opening iOS-sandbox clip paths on macOS when a rendered remote video exists.
    var usableTakesJson: String? {
        guard let takesJson, !takesJson.isEmpty,
              let data = takesJson.data(using: .utf8),
              let clips = try? JSONDecoder().decode([Clip].self, from: data),
              !clips.isEmpty else { return nil }

        let savedDir = FileStorageService.shared.savedVideosDirectory
        let cacheDir = FileStorageService.shared.clipCacheDirectory
        let hasPlayableClip = clips.contains { clip in
            let source = clip.localUri ?? clip.uri
            if source.hasPrefix("http://") || source.hasPrefix("https://") { return true }
            let path = source.replacingOccurrences(of: "file://", with: "")
            if FileManager.default.fileExists(atPath: path) { return true }
            let filename = (path as NSString).lastPathComponent
            if filename.isEmpty { return false }
            return FileManager.default.fileExists(atPath: savedDir.appendingPathComponent(filename).path)
                || FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent(filename).path)
        }

        return hasPlayableClip ? takesJson : nil
    }

    var displayName: String {
        let cleanName = videoName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanName.isEmpty && !["Editor", "Video", "Imported Video"].contains(cleanName) {
            return cleanName
        }
        if let title = titleFromTakesJson() {
            return title
        }
        return cleanName.isEmpty ? "Video" : cleanName
    }

    private func titleFromTakesJson() -> String? {
        guard let takesJson,
              let data = takesJson.data(using: .utf8),
              let takes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

        for key in ["prompt", "projectTitle", "text", "name"] {
            if let value = takes.compactMap({ $0[key] as? String }).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return Self.shortDisplayTitle(value)
            }
        }
        return nil
    }

    private static func shortDisplayTitle(_ value: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "Video" }
        if collapsed.count <= 42 { return collapsed }
        let prefix = collapsed.prefix(42)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace])
        }
        return String(prefix)
    }

    /// Resolves musicFile path, handling stale container UUIDs.
    var resolvedMusicFile: String? {
        guard let raw = musicFile, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http") { return raw }
        let path = raw.replacingOccurrences(of: "file://", with: "")
        if FileManager.default.fileExists(atPath: path) { return path }
        let filename = (path as NSString).lastPathComponent
        let resolved = FileStorageService.shared.savedVideosDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: resolved.path) { return resolved.path }
        return nil
    }

    var createdAt: Date
    var userId: String?
    var musicId: String?
    var musicName: String?
    var musicFile: String?
    var musicVolume: Double?
    var faceImageUrl: String?
    var thumbnailPath: String?
    var errorMessage: String?
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
        errorMessage: String? = nil,
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
        self.errorMessage = errorMessage
        self.takesJson = takesJson
    }
}
