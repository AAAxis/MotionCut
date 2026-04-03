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
    var localUri: String?
    /// Playback speed multiplier. 1.0 = normal, 0.5 = half speed, 2.0 = double speed.
    var speed: Double

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
        localUri: String? = nil,
        speed: Double = 1.0
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
        self.localUri = localUri
        self.speed = speed
    }
}
