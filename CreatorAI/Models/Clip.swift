import Foundation

struct Clip: Identifiable, Codable, Equatable {
    var id: Int
    var uri: String
    var name: String
    var mimeType: String
    var trimStart: Double
    var trimEnd: Double
    var beatDuration: Double?
    var sourceDuration: Double?
    var text: String?
    var textStart: Double
    var textEnd: Double
    var textX: Double
    var textY: Double
    var textFontName: String
    var localUri: String?
    /// Playback speed multiplier. 1.0 = normal, 0.5 = half speed, 2.0 = double speed.
    var speed: Double
    var audioVolume: Double
    var isMuted: Bool
    var filterName: String
    var overlayImageUri: String?
    var overlayX: Double
    var overlayY: Double
    var overlayScale: Double
    var transitionName: String
    var transitionDuration: Double
    var videoLayoutMode: String
    var videoScale: Double
    var videoX: Double
    var videoY: Double

    enum CodingKeys: String, CodingKey {
        case id, uri, name, mimeType, trimStart, trimEnd, beatDuration, sourceDuration
        case text, textStart, textEnd, textX, textY, textFontName, localUri, speed, audioVolume, isMuted
        case filterName, overlayImageUri, overlayX, overlayY, overlayScale
        case transitionName, transitionDuration
        case videoLayoutMode, videoScale, videoX, videoY
    }

    init(
        id: Int,
        uri: String,
        name: String = "",
        mimeType: String = "video/mp4",
        trimStart: Double = 0,
        trimEnd: Double = 100,
        beatDuration: Double? = nil,
        sourceDuration: Double? = nil,
        text: String? = nil,
        textStart: Double = 0,
        textEnd: Double = 100,
        textX: Double = 0.5,
        textY: Double = 0.82,
        textFontName: String = "System",
        localUri: String? = nil,
        speed: Double = 1.0,
        audioVolume: Double = 1.0,
        isMuted: Bool = false,
        filterName: String = "None",
        overlayImageUri: String? = nil,
        overlayX: Double = 0.82,
        overlayY: Double = 0.18,
        overlayScale: Double = 0.22,
        transitionName: String = "None",
        transitionDuration: Double = 0.35,
        videoLayoutMode: String = "Full",
        videoScale: Double = 1.0,
        videoX: Double = 0.5,
        videoY: Double = 0.5
    ) {
        self.id = id
        self.uri = uri
        self.name = name
        self.mimeType = mimeType
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.beatDuration = beatDuration
        self.sourceDuration = sourceDuration
        self.text = text
        self.textStart = textStart
        self.textEnd = textEnd
        self.textX = textX
        self.textY = textY
        self.textFontName = textFontName
        self.localUri = localUri
        self.speed = speed
        self.audioVolume = audioVolume
        self.isMuted = isMuted
        self.filterName = filterName
        self.overlayImageUri = overlayImageUri
        self.overlayX = overlayX
        self.overlayY = overlayY
        self.overlayScale = overlayScale
        self.transitionName = transitionName
        self.transitionDuration = transitionDuration
        self.videoLayoutMode = videoLayoutMode
        self.videoScale = videoScale
        self.videoX = videoX
        self.videoY = videoY
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        uri = try container.decode(String.self, forKey: .uri)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "video/mp4"
        trimStart = try container.decodeIfPresent(Double.self, forKey: .trimStart) ?? 0
        trimEnd = try container.decodeIfPresent(Double.self, forKey: .trimEnd) ?? 100
        beatDuration = try container.decodeIfPresent(Double.self, forKey: .beatDuration)
        sourceDuration = try container.decodeIfPresent(Double.self, forKey: .sourceDuration)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        textStart = try container.decodeIfPresent(Double.self, forKey: .textStart) ?? 0
        textEnd = try container.decodeIfPresent(Double.self, forKey: .textEnd) ?? 100
        textX = try container.decodeIfPresent(Double.self, forKey: .textX) ?? 0.5
        textY = try container.decodeIfPresent(Double.self, forKey: .textY) ?? 0.82
        textFontName = try container.decodeIfPresent(String.self, forKey: .textFontName) ?? "System"
        localUri = try container.decodeIfPresent(String.self, forKey: .localUri)
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
        audioVolume = try container.decodeIfPresent(Double.self, forKey: .audioVolume) ?? 1.0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        filterName = try container.decodeIfPresent(String.self, forKey: .filterName) ?? "None"
        overlayImageUri = try container.decodeIfPresent(String.self, forKey: .overlayImageUri)
        overlayX = try container.decodeIfPresent(Double.self, forKey: .overlayX) ?? 0.82
        overlayY = try container.decodeIfPresent(Double.self, forKey: .overlayY) ?? 0.18
        overlayScale = try container.decodeIfPresent(Double.self, forKey: .overlayScale) ?? 0.22
        transitionName = try container.decodeIfPresent(String.self, forKey: .transitionName) ?? "None"
        transitionDuration = try container.decodeIfPresent(Double.self, forKey: .transitionDuration) ?? 0.35
        videoLayoutMode = try container.decodeIfPresent(String.self, forKey: .videoLayoutMode) ?? "Full"
        videoScale = try container.decodeIfPresent(Double.self, forKey: .videoScale) ?? 1.0
        videoX = try container.decodeIfPresent(Double.self, forKey: .videoX) ?? 0.5
        videoY = try container.decodeIfPresent(Double.self, forKey: .videoY) ?? 0.5
    }
}
