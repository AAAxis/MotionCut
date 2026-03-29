import Foundation

/// On-device URL scraper that extracts Open Graph metadata.
/// Port of Android LocalScraperService.
struct LocalScraperService {

    static func scrape(url urlString: String) async -> PagePreview? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            print("[Scraper] Failed to fetch URL: \(urlString)")
            return nil
        }

        let ogImage = extractMetaContent(html: html, attr: "property", value: "og:image")
        let ogTitle = extractMetaContent(html: html, attr: "property", value: "og:title") ?? extractTitle(html: html)
        let ogDescription = extractMetaContent(html: html, attr: "property", value: "og:description")
            ?? extractMetaContent(html: html, attr: "name", value: "description")
        let domain = url.host

        print("[Scraper] title=\(ogTitle ?? "nil") desc=\(ogDescription?.prefix(50) ?? "nil") image=\(ogImage != nil)")

        return PagePreview(
            ogImage: ogImage,
            title: ogTitle,
            description: ogDescription,
            domain: domain,
            features: nil,
            images: nil
        )
    }

    // MARK: - HTML Parsing

    /// Extract content from <meta> tags. Handles both attribute orders.
    private static func extractMetaContent(html: String, attr: String, value: String) -> String? {
        let nsHtml = html as NSString

        // Pattern 1: <meta property="og:title" content="...">
        let p1 = try? NSRegularExpression(
            pattern: "<meta[^>]+\(attr)\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: value))[\"'][^>]+content\\s*=\\s*[\"']([^\"']*)[\"']",
            options: .caseInsensitive
        )
        if let match = p1?.firstMatch(in: html, range: NSRange(location: 0, length: nsHtml.length)),
           match.numberOfRanges > 1 {
            return nsHtml.substring(with: match.range(at: 1))
        }

        // Pattern 2: <meta content="..." property="og:title">
        let p2 = try? NSRegularExpression(
            pattern: "<meta[^>]+content\\s*=\\s*[\"']([^\"']*)[\"'][^>]+\(attr)\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: value))[\"']",
            options: .caseInsensitive
        )
        if let match = p2?.firstMatch(in: html, range: NSRange(location: 0, length: nsHtml.length)),
           match.numberOfRanges > 1 {
            return nsHtml.substring(with: match.range(at: 1))
        }

        return nil
    }

    private static func extractTitle(html: String) -> String? {
        let nsHtml = html as NSString
        let regex = try? NSRegularExpression(pattern: "<title[^>]*>([^<]+)</title>", options: .caseInsensitive)
        if let match = regex?.firstMatch(in: html, range: NSRange(location: 0, length: nsHtml.length)),
           match.numberOfRanges > 1 {
            return nsHtml.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
