import Foundation

actor UploadService {
    static let shared = UploadService()

    // TODO: Replace with your Uploadcare public key
    private let publicKey = "YOUR_UPLOADCARE_PUBLIC_KEY"
    private let uploadURL = "https://upload.uploadcare.com/base/"

    func uploadFile(fileURL: URL, fileName: String) async throws -> String {
        var request = URLRequest(url: URL(string: uploadURL)!)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Public key
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"UPLOADCARE_PUB_KEY\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(publicKey)\r\n".data(using: .utf8)!)

        // Store
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"UPLOADCARE_STORE\"\r\n\r\n".data(using: .utf8)!)
        body.append("auto\r\n".data(using: .utf8)!)

        // File
        let fileData = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: request)

        struct UploadResponse: Codable {
            let file: String
        }

        let response = try JSONDecoder().decode(UploadResponse.self, from: data)
        return "https://ucarecdn.com/\(response.file)/"
    }
}
