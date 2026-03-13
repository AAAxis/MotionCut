import SwiftUI
import PhotosUI

struct UploadedAvatar: Identifiable {
    let id: String
    let name: String
    let url: String       // server path like /uploads/avatar_xxx.jpg
    var image: UIImage?   // local preview
}

struct AvatarPickerView: View {
    @ObservedObject var viewModel: CreateViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var uploadedAvatars: [UploadedAvatar] = []
    @State private var isUploading = false
    @State private var showPhotoPicker = false
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 1. CREATE OWN — always first
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    VStack(spacing: 6) {
                        if isUploading {
                            ProgressView()
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(theme.primary)
                        }
                        Text("Create own")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.primary)
                    }
                    .frame(width: 72, height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(theme.primary.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(theme.primary, lineWidth: 2)
                            )
                    )
                }
                .disabled(isUploading)
                
                // 2. User's uploaded avatars
                ForEach(uploadedAvatars) { avatar in
                    Button {
                        viewModel.reelInfluencerId = avatar.id
                    } label: {
                        VStack(spacing: 6) {
                            if let img = avatar.image {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                            } else {
                                AsyncImage(url: URL(string: "\(APIService.shared.syncBaseURL)\(avatar.url)")) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 48, height: 48)
                                            .clipShape(Circle())
                                    default:
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(theme.textSecondary)
                                    }
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
                
                // 3. Preset avatars
                ForEach(PRESET_AVATARS) { avatar in
                    Button {
                        viewModel.reelInfluencerId = avatar.id
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: avatar.iconName)
                                .font(.system(size: 32))
                                .foregroundColor(viewModel.reelInfluencerId == avatar.id ? theme.primary : theme.textSecondary)
                            Text(avatar.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(viewModel.reelInfluencerId == avatar.id ? theme.primary : theme.text)
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
            }
        }
        .onChange(of: selectedPhotoItem) { newItem in
            guard let item = newItem else { return }
            Task { await handleImagePick(item) }
        }
        .onAppear {
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
        
        // Resize to max 1024px to save bandwidth
        let resized = resizeImage(uiImage, maxSize: 1024)
        guard let jpegData = resized.jpegData(compressionQuality: 0.85) else { return }
        
        // Upload to server
        do {
            let result = try await uploadAvatarImage(jpegData: jpegData, filename: "avatar_\(UUID().uuidString).jpg")
            let avatar = UploadedAvatar(
                id: result.id,
                name: result.name,
                url: result.url,
                image: resized
            )
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
        let url = URL(string: "\(baseURL)/api/uploads/image")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // userId field
        let userId = appState.userId ?? "demo-user"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"userId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(userId)\r\n".data(using: .utf8)!)
        
        // name field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"name\"\r\n\r\n".data(using: .utf8)!)
        body.append("Custom\r\n".data(using: .utf8)!)
        
        // image file
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
    
    // MARK: - Load Previous Avatars
    
    private func loadUploadedAvatars() async {
        let userId = appState.userId ?? "demo-user"
        let baseURL = await APIService.shared.baseURL
        guard let url = URL(string: "\(baseURL)/api/uploads/avatars/\(userId)") else { return }
        
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
    
    // MARK: - Resize Helper
    
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
