import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(Int)
    case decodingError(Error)
    case noData
    case sseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .httpError(let code): return "HTTP error: \(code)"
        case .decodingError(let e): return "Decoding error: \(e.localizedDescription)"
        case .noData: return "No data received"
        case .sseError(let msg): return msg
        }
    }
}

struct SSEEvent {
    let event: String
    let data: String
}

actor APIService {
    static let shared = APIService()

    let baseURL: String
    
    // Non-isolated accessor for use in synchronous contexts (e.g. AsyncImage URLs)
    // Always use HTTPS for image loading (ATS blocks HTTP)
    nonisolated var syncBaseURL: String {
        let base = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://api.holylabs.net"
        return base.replacingOccurrences(of: "http://", with: "https://")
    }

    private init() {
        self.baseURL = ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://api.holylabs.net"
    }

    // MARK: - Standard HTTP

    func post<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - SSE Streaming

    func streamSSE(
        path: String,
        body: Encodable,
        onEvent: @escaping @Sendable (SSEEvent) -> Void
    ) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        var currentEvent: String?

        for try await line in bytes.lines {
            if line.hasPrefix("event: ") {
                currentEvent = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data: "), let eventType = currentEvent {
                let data = String(line.dropFirst(6))
                onEvent(SSEEvent(event: eventType, data: data))
                currentEvent = nil
            }
        }
    }

    // MARK: - File Download

    nonisolated func downloadFile(from urlString: String, to localPath: URL) async throws {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        let (tempURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: localPath.path) {
            try fileManager.removeItem(at: localPath)
        }
        try fileManager.moveItem(at: tempURL, to: localPath)
    }
}
