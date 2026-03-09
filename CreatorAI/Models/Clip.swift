import Foundation

struct Clip: Identifiable, Codable, Equatable {
    let id: Int
    var uri: String
    var name: String
    var mimeType: String
    var trimStart: Double
    var trimEnd: Double
    var beatDuration: Double?
    var sourceDuration: Double?
    var text: String?
    var localUri: String?

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
        localUri: String? = nil
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
    }
}
