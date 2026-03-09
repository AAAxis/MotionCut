import Foundation

/// Action to perform when a deeplink is opened. Applied by MainTabView after onboarding.
enum DeeplinkAction: Equatable {
    case switchTab(Int)
    case generationStatus(id: String, title: String)
    case videoEditor(VideoEditorParams)
    case settings
}

/// Parses `creatorai://` URLs into navigation actions. Use for redirect deeplinks (campaigns, emails, web).
enum DeeplinkService {
    private static let scheme = "creatorai"

    /// Returns a navigation action for the URL, or nil if not a handled deeplink (e.g. auth callback).
    static func parse(_ url: URL) -> DeeplinkAction? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        // Let OAuth callback be handled only by ASWebAuthenticationSession
        if url.host?.lowercased() == "auth", url.path.contains("callback") { return nil }

        let path = (url.path as NSString).pathTrimmed
        let components = path.split(separator: "/").map(String.init)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch (url.host?.lowercased(), components.first) {
        case ("library", _), (nil, "library"):
            return .switchTab(0)
        case ("create", _), (nil, "create"):
            return .switchTab(1)
        case ("profile", _), ("settings", _), (nil, "profile"), (nil, "settings"):
            return .switchTab(2)
        case ("generation", _):
            let generationId = components.isEmpty ? "" : components[0]
            guard !generationId.isEmpty else { return nil }
            let title = query.first(where: { $0.name == "title" })?.value ?? "Video"
            return .generationStatus(id: generationId, title: title)
        case (nil, "generation") where components.count > 1:
            let generationId = components[1]
            let title = query.first(where: { $0.name == "title" })?.value ?? "Video"
            return .generationStatus(id: generationId, title: title)
        case ("editor", _), (nil, "editor"):
            let videoUri = query.first(where: { $0.name == "uri" || $0.name == "url" })?.value
            let videoName = query.first(where: { $0.name == "name" || $0.name == "title" })?.value ?? "Video"
            let userId = query.first(where: { $0.name == "userId" })?.value ?? "demo-user"
            return .videoEditor(VideoEditorParams(
                videoUri: videoUri,
                videoName: videoName,
                takesJson: nil,
                musicUrl: nil,
                userId: userId
            ))
        default:
            return nil
        }
    }
}

private extension NSString {
    var pathTrimmed: String {
        (self as String).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
