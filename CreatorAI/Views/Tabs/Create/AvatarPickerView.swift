import SwiftUI
import PhotosUI

struct UploadedAvatar: Identifiable {
    let id: String
    let name: String
    let url: String       // server relative path e.g. /uploads/avatar_xxx.jpg
    var fullURL: String {  // full HTTPS URL for AsyncImage
        "\(APIService.shared.syncBaseURL)\(url)"
    }
}

struct AvatarPickerView: View {
    @ObservedObject var viewModel: CreateViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var uploadedAvatars: [UploadedAvatar] = []
    @State private var isUploading = false
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 1–4: AI Models from Replicate
                ForEach(PRESET_AI_MODELS) { model in
                    Button {
                        viewModel.reelInfluencerId = model.id
                    } label: {
                        VStack(spacing: 6) {
                            AsyncImage(url: URL(string: model.imageURL)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                case .failure:
                                    Image(systemName: "film.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(theme.textSecondary)
                                        .frame(width: 48, height: 48)
                                default:
                                    ProgressView()
                                        .frame(width: 48, height: 48)
                                }
                            }
                            Text(model.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(viewModel.reelInfluencerId == model.id ? theme.primary : theme.text)
                                .lineLimit(1)
                        }
                        .frame(width: 72, height: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(viewModel.reelInfluencerId == model.id ? theme.primary.opacity(0.12) : theme.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(viewModel.reelInfluencerId == model.id ? theme.primary : theme.border, lineWidth: viewModel.reelInfluencerId == model.id ? 2 : 1)
                                )
                        )
                    }
                }
                
                // User's previously uploaded avatars
                ForEach(uploadedAvatars) { avatar in
                    Button {
                        viewModel.reelInfluencerId = avatar.id
                    } label: {
                        VStack(spacing: 6) {
                            AsyncImage(url: URL(string: avatar.fullURL)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                case .failure:
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(theme.textSecondary)
                                        .frame(width: 48, height: 48)
                                default:
                                    ProgressView()
                                        .frame(width: 48, height: 48)
                                }
                            }
                            Text(avatar.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(viewModel.reelInfluencerId == avatar.id ? theme.primary : theme.text)
                                .lineLimit(1)
                        }
                        .frame(width: 72, height: 72)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(viewModel.reelInfluencerId == avatar.id ? theme.primary.opacity(0.12) : theme.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(viewModel.reelInfluencerId == avatar.id ? theme.primary : theme.border, lineWidth: viewModel.reelInfluencerId == avatar.id ? 2 : 1)
                                )
                        )
                    }
                }
                
                // 5th: CREATE OWN — upload photo (always last)
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    VStack(spacing: 6) {
                        if isUploading {
                            ProgressView()
                                .frame(width: 48, height: 48)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(theme.primary.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(theme.primary)
                            }
                        }
                        Text("Your photo")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.primary)
                    }
                    .frame(width: 72, height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(theme.primary.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                    .foregroundColor(theme.primary.opacity(0.5))
                            )
                    )
                }
                .disabled(isUploading)
            }
        }
        .onChange(of: selectedPhotoItem) { newItem in
            guard let item = newItem else { return }
            Task { await handleImagePick(item) }
        }
        .onAppear {
            // Default to first AI model
            if viewModel.reelInfluencerId.hasPrefix("avatar_") || viewModel.reelInfluencerId == "custom" {
                viewModel.reelInfluencerId = PRESET_AI_MODELS.first?.id ?? ""
            }
            Task { await loadUploadedAvatars() }
        }
    }
    
    // MARK: - Upload Image
    
    private func handleImagePick(_ item: PhotosPickerItem) async {
        isUploading = true
        defer { 
            isUploading = false
            selectedPhotoItem = nil
        }
        
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let uiImage = UIImage(data: data) else { return }
        
        let resized = resizeImage(uiImage, maxSize: 1024)
        guard let jpegData = resized.jpegData(compressionQuality: 0.85) else { return }
        
        do {
            let result = try await uploadAvatarImage(jpegData: jpegData, filename: "avatar_\(UUID().uuidString).jpg")
            let avatar = UploadedAvatar(id: result.id, name: result.name, url: result.url)
            await MainActor.run {
                uploadedAvatars.insert(avatar, at: 0)
                viewModel.reelInfluencerId = avatar.id
            }
        } catch {
            print("Avatar upload failed: \(error)")
        }
    }
    
    private func uploadAvatarImage(jpegData: Data, filename: String) async throws -> (id: String, name: String, url: String) {
        let baseURL = await APIService.shared.baseURL
        let httpsBase = baseURL.replacingOccurrences(of: "http://", with: "https://")
        let url = URL(string: "\(httpsBase)/api/uploads/image")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        let userId = appState.userId ?? "demo-user"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"userId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(userId)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
        body.append("My photo\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct UploadResponse: Codable {
            let id: String
            let name: String
            let url: String
        }
        
        let response = try JSONDecoder().decode(UploadResponse.self, from: data)
        return (id: response.id, name: response.name, url: response.url)
    }
    
    private func loadUploadedAvatars() async {
        let userId = appState.userId ?? "demo-user"
        let baseURL = await APIService.shared.baseURL
        let httpsBase = baseURL.replacingOccurrences(of: "http://", with: "https://")
        guard let url = URL(string: "\(httpsBase)/api/uploads/avatars/\(userId)") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct AvatarsResponse: Codable {
                let avatars: [AvatarItem]
            }
            struct AvatarItem: Codable {
                let id: String
                let name: String
                let url: String
            }
            let response = try JSONDecoder().decode(AvatarsResponse.self, from: data)
            await MainActor.run {
                uploadedAvatars = response.avatars.map {
                    UploadedAvatar(id: $0.id, name: $0.name, url: $0.url)
                }
            }
        } catch {
            print("Failed to load avatars: \(error)")
        }
    }
    
    private func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxSize else { return image }
        let scale = maxSize / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
