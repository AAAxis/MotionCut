import Foundation

struct MusicTrack: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let file: String
    var title: String?
    var timelineStart: Double
    var timelineEnd: Double?
    var volume: Double
    var isMuted: Bool

    static let library: [MusicTrack] = [
        MusicTrack(
            id: "mixkit-hip-hop-02",
            name: "Hip Hop 02",
            file: "https://assets.mixkit.co/music/738/738.mp3",
            title: "Upbeat"
        ),
        MusicTrack(
            id: "mixkit-sun-and-his-daughter",
            name: "Sun and His Daughter",
            file: "https://assets.mixkit.co/music/580/580.mp3",
            title: "Warm"
        ),
        MusicTrack(
            id: "mixkit-hazy-after-hours",
            name: "Hazy After Hours",
            file: "https://assets.mixkit.co/music/132/132.mp3",
            title: "Chill"
        ),
        MusicTrack(
            id: "mixkit-tech-house-vibes",
            name: "Tech House Vibes",
            file: "https://assets.mixkit.co/music/130/130.mp3",
            title: "Tech"
        ),
        MusicTrack(
            id: "mixkit-driving-ambition",
            name: "Driving Ambition",
            file: "https://assets.mixkit.co/music/32/32.mp3",
            title: "Momentum"
        )
    ]

    enum CodingKeys: String, CodingKey {
        case id, name, file, title, timelineStart, timelineEnd, volume, isMuted
    }

    init(id: String, name: String, file: String, title: String? = nil, timelineStart: Double = 0, timelineEnd: Double? = nil, volume: Double = 1.0, isMuted: Bool = false) {
        self.id = id
        self.name = name
        self.file = file
        self.title = title
        self.timelineStart = timelineStart
        self.timelineEnd = timelineEnd
        self.volume = volume
        self.isMuted = isMuted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        file = try container.decode(String.self, forKey: .file)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        timelineStart = try container.decodeIfPresent(Double.self, forKey: .timelineStart) ?? 0
        timelineEnd = try container.decodeIfPresent(Double.self, forKey: .timelineEnd)
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1.0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
    }
}
