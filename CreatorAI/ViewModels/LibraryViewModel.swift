import SwiftUI
import AVFoundation

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var generations: [Generation] = []
    @Published var isLoading = false
    @Published var thumbnails: [String: PlatformImage] = [:]
    @Published var downloadingIds: Set<String> = []

    private let userId: String
    #if os(macOS)
    private var activeSharingPicker: NSSharingServicePicker?
    #endif

    init(userId: String = "demo-user") {
        self.userId = userId
    }

    func loadGenerations() async {
        isLoading = true
        do {
            generations = try await GenerationService.shared.fetchGenerations(userId: userId)
                .filter { generation in
                    generation.status == .saved || generation.status == .completed || generation.status == .processing
                }
                .filter { generation in
                    generation.status == .processing || generation.videoFileURL != nil || generation.usableTakesJson != nil
                }
            await refreshProcessingGenerations()
            await loadThumbnails()
        } catch {
            print("Failed to load generations: \(error)")
        }
        isLoading = false
    }
    
    /// Check any stuck "processing" generations against the server and update
    func refreshProcessingGenerations() async {
        let processing = generations.filter { $0.status == .processing }
        guard !processing.isEmpty else { return }
        
        let baseURL = await GenerationService.shared.getBaseURL()
        
        for gen in processing {
            // Try ads endpoint
            if let updated = await checkAdStatus(id: gen.id, baseURL: baseURL) {
                if let idx = generations.firstIndex(where: { $0.id == gen.id }) {
                    generations[idx].status = updated.status
                    generations[idx].resultVideoUrl = updated.videoUrl
                    await GenerationService.shared.updateGeneration(
                        id: gen.id,
                        status: updated.status,
                        remoteVideoUrl: updated.videoUrl
                    )
                }
                continue
            }
            // Try create endpoint
            if let updated = await checkCreateStatus(id: gen.id, baseURL: baseURL) {
                if let idx = generations.firstIndex(where: { $0.id == gen.id }) {
                    generations[idx].status = updated.status
                    generations[idx].resultVideoUrl = updated.videoUrl
                    await GenerationService.shared.updateGeneration(
                        id: gen.id,
                        status: updated.status,
                        remoteVideoUrl: updated.videoUrl
                    )
                }
            }
        }
    }
    
    private struct StatusResult {
        let status: GenerationStatus
        let videoUrl: String?
    }
    
    private func checkAdStatus(id: String, baseURL: String) async -> StatusResult? {
        guard let url = URL(string: "\(baseURL)/api/ads/status/\(id)") else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else { return nil }
        
        if status == "succeeded" {
            let output = json["output"] as? [String: Any]
            let download = output?["download"] as? String
            let videoUrl = download != nil ? "\(baseURL)\(download!)" : nil
            return StatusResult(status: .completed, videoUrl: videoUrl)
        } else if status == "failed" {
            return StatusResult(status: .failed, videoUrl: nil)
        }
        return nil
    }
    
    private func checkCreateStatus(id: String, baseURL: String) async -> StatusResult? {
        guard let url = URL(string: "\(baseURL)/api/create/status/\(id)") else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else { return nil }
        
        if status == "succeeded" {
            let videoUrl = json["outputUrl"] as? String
            return StatusResult(status: .completed, videoUrl: videoUrl)
        } else if status == "failed" {
            return StatusResult(status: .failed, videoUrl: nil)
        }
        return nil
    }

    func deleteGeneration(_ generation: Generation) async {
        withAnimation(.easeOut(duration: 0.18)) {
            generations.removeAll { $0.id == generation.id }
        }
        thumbnails[generation.id] = nil
        downloadingIds.remove(generation.id)
        await GenerationService.shared.deleteGeneration(id: generation.id)
    }

    func shareVideo(_ generation: Generation) async {
        let resolvedURL: URL?
        if generation.isCloudOnly {
            resolvedURL = await downloadCloudVideo(generation)
        } else {
            resolvedURL = generation.videoFileURL
        }

        guard let url = resolvedURL else {
            print("[Share] No shareable video URL for generation \(generation.id)")
            return
        }

        #if os(iOS)
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = scene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #else
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            print("[Share] Local video file is missing: \(url)")
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let picker = NSSharingServicePicker(items: [url])
        activeSharingPicker = picker
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
        if let view = window?.contentView {
            let anchor = NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            DispatchQueue.main.async {
                picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
            }
        } else if let service = NSSharingService(named: .sendViaAirDrop) {
            service.perform(withItems: [url])
        } else {
            print("[Share] No visible window available for share picker")
        }
        #endif
    }

    /// Download a cloud-only video to local storage. Returns the local URL on success.
    func downloadCloudVideo(_ generation: Generation) async -> URL? {
        guard generation.isCloudOnly,
              let remoteUrlString = generation.resultVideoUrl,
              URL(string: remoteUrlString) != nil else { return nil }

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
        let thumbDir = FileStorageService.shared.thumbnailCacheDirectory
        var newThumbnails = thumbnails

        for generation in generations {
            // Skip if already loaded in memory
            if newThumbnails[generation.id] != nil { continue }

            // Check disk cache first
            let cachedPath = thumbDir.appendingPathComponent("\(generation.id).jpg")
            if FileManager.default.fileExists(atPath: cachedPath.path),
               let data = try? Data(contentsOf: cachedPath),
               let cached = PlatformImage.from(data: data) {
                newThumbnails[generation.id] = cached
                continue
            }

            // Generate from video and save to disk
            guard let url = generation.videoFileURL else { continue }
            if let image = await ThumbnailService.shared.generateThumbnail(for: url) {
                newThumbnails[generation.id] = image
                // Cache to disk
                if let data = image.jpegData(quality: 0.7) {
                    try? data.write(to: cachedPath)
                }
            }
        }
        thumbnails = newThumbnails
    }
}
