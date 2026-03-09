import Foundation

struct MusicTrack: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let file: String
    var title: String?

    /// No built-in library; music comes only from AI (e.g. reel generation).
    static let library: [MusicTrack] = []
}
