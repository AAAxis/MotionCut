import SwiftUI
import AVFoundation

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var generations: [Generation] = []
    @Published var isGridView = false
    @Published var isLoading = false
    @Published var thumbnails: [String: UIImage] = [:]
    @Published var downloadingIds: Set<String> = []

    private let userId: String

    init(userId: String = "demo-user") {
        self.userId = userId
    }

    func loadGenerations() async {
        isLoading = true
        do {
            generations = try await GenerationService.shared.fetchGenerations(userId: userId)
            await loadThumbnails()
        } catch {
            print("Failed to load generations: \(error)")
        }
        isLoading = false
    }

    func deleteGeneration(_ generation: Generation) async {
        await GenerationService.shared.deleteGeneration(id: generation.id)
        generations.removeAll { $0.id == generation.id }
    }

    func shareVideo(_ generation: Generation) {
        guard let url = generation.videoFileURL else { return }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    /// Download a cloud-only video to local storage. Returns the local URL on success.
    func downloadCloudVideo(_ generation: Generation) async -> URL? {
        guard generation.isCloudOnly,
              let remoteUrlString = generation.resultVideoUrl,
              let remoteUrl = URL(string: remoteUrlString) else { return nil }

        downloadingIds.insert(generation.id)
        defer { downloadingIds.remove(generation.id) }

        let dest = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(generation.id).mp4")
        do {
            try await FileStorageService.shared.downloadFile(from: remoteUrlString, to: dest)
            // Update local metadata with the persistent path
            await GenerationService.shared.updateGeneration(id: generation.id, videoUri: dest.absoluteString)
            // Reload so the UI reflects the change
            if let idx = generations.firstIndex(where: { $0.id == generation.id }) {
                generations[idx].videoUri = dest.absoluteString
            }
            return dest
        } catch {
            print("[Library] Cloud download failed: \(error)")
            return nil
        }
    }

    private func loadThumbnails() async {
        var newThumbnails = thumbnails
        for generation in generations {
            guard let url = generation.videoFileURL else { continue }
            if let image = await ThumbnailService.shared.generateThumbnail(for: url) {
                newThumbnails[generation.id] = image
            }
        }
        thumbnails = newThumbnails
    }
}
