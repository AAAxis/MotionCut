import Foundation
#if canImport(Photos)
import Photos
#endif

/// Parameters for a single export job (survives closing the editor).
struct ExportParams {
    var existingGenerationId: String?
    let videoName: String
    let clips: [Clip]
    let aspectRatio: String
    let exportQuality: String
    let userId: String
    let musicId: String?
    let musicName: String?
    let musicFileUrl: String?
    let musicVolume: Double
    let musicTrackVolume: Double
    let musicMuted: Bool
    let musicTimelineStart: Double
    let musicTimelineEnd: Double?
    let additionalMusic: [MusicTrack]
    /// Original reel takes JSON to store on Generation for Edit.
    let takesJson: String?
    /// If true, after render the app will request cloud caption burn-in (no local captions).
    let addCaptionsViaCloud: Bool
    /// Local file URL for recorded voiceover audio.
    let voiceoverFileURL: URL?
    let voiceoverVolume: Double
    let voiceoverMuted: Bool
    let voiceoverTimelineStart: Double
    let voiceoverTimelineEnd: Double?
    let includeBranding: Bool
}

/// Runs video render in the background. Saves a generation with status .processing so it appears in Library, then updates when done.
final class BackgroundRenderService {
    static let shared = BackgroundRenderService()

    private init() {}

    /// Start export from reel creation params (takesJson + musicUrl). Parses takes into clips and renders in background.
    func startExport(fromReelParams editorParams: Route.VideoEditorParams) async -> String? {
        guard let clips = parseClips(from: editorParams.takesJson) else { return nil }
        let exportParams = ExportParams(
            videoName: editorParams.videoName ?? "Reel",
            clips: clips,
            aspectRatio: "1:1",
            exportQuality: "original",
            userId: editorParams.userId,
            musicId: "reel-music",
            musicName: "Reel Music",
            musicFileUrl: editorParams.musicUrl,
            musicVolume: 0.75,
            musicTrackVolume: 1.0,
            musicMuted: false,
            musicTimelineStart: 0,
            musicTimelineEnd: nil,
            additionalMusic: [],
            takesJson: editorParams.takesJson,
            addCaptionsViaCloud: false,
            voiceoverFileURL: nil,
            voiceoverVolume: 1.0,
            voiceoverMuted: false,
            voiceoverTimelineStart: 0,
            voiceoverTimelineEnd: nil,
            includeBranding: !CreatorSubscriptionPlan.current.isActive
        )
        return await startExport(params: exportParams)
    }

    private func parseClips(from takesJson: String?) -> [Clip]? {
        guard let json = takesJson,
              let data = json.data(using: .utf8),
              let takes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return takes.enumerated().map { i, t in
            Clip(
                id: (t["id"] as? Int) ?? (Int(Date().timeIntervalSince1970 * 1000) + i),
                uri: t["uri"] as? String ?? "",
                name: t["name"] as? String ?? "Take \(i + 1)",
                mimeType: t["mimeType"] as? String ?? "video/mp4",
                trimStart: t["trimStart"] as? Double ?? 0,
                trimEnd: t["trimEnd"] as? Double ?? 100,
                beatDuration: t["beatDuration"] as? Double,
                sourceDuration: t["sourceDuration"] as? Double,
                text: t["text"] as? String ?? "",
                textStart: t["textStart"] as? Double ?? 0,
                textEnd: t["textEnd"] as? Double ?? 100,
                textX: t["textX"] as? Double ?? 0.5,
                textY: t["textY"] as? Double ?? 0.82,
                localUri: nil,
                speed: t["speed"] as? Double ?? 1.0,
                audioVolume: t["audioVolume"] as? Double ?? 1.0,
                isMuted: t["isMuted"] as? Bool ?? false
            )
        }
    }

    /// Start export; adds a "Rendering..." row to the list and runs render in background. Returns generation id so caller can dismiss.
    func startExport(params: ExportParams) async -> String {
        // Delete old generation if re-exporting
        if let oldId = params.existingGenerationId {
            await GenerationService.shared.deleteGeneration(id: oldId)
        }

        let generationId = UUID().uuidString
        let generation = Generation(
            id: generationId,
            videoName: params.videoName,
            videoUri: nil,
            resultVideoUrl: nil,
            status: .processing,
            createdAt: Date(),
            userId: params.userId,
            musicId: params.musicId,
            musicName: params.musicName,
            musicFile: params.musicFileUrl,
            takesJson: params.takesJson
        )
        await GenerationService.shared.saveGeneration(generation)

        Task {
            await runRender(generationId: generationId, params: params)
        }

        return generationId
    }

    private func runRender(generationId: String, params: ExportParams) async {
        guard validateLocalClipSources(params.clips) else {
            print("[BackgroundRender] Missing local clip source for export")
            await GenerationService.shared.updateGeneration(id: generationId, status: .failed, errorMessage: "Video source file is missing. Re-import the video.")
            NotificationService.shared.notifyVideoFailed(videoName: params.videoName)
            return
        }

        var musicOptions: MusicRenderOptions?
        if let musicUrl = params.musicFileUrl, !musicUrl.isEmpty {
            let localURL = await AudioMixerService.shared.downloadAndSaveAudio(from: musicUrl, audioId: params.musicId ?? "reel-music")
            if localURL == nil && !(musicUrl.hasPrefix("/") || musicUrl.hasPrefix("file://")) {
                print("[BackgroundRender] Required music could not be resolved for export")
                await GenerationService.shared.updateGeneration(id: generationId, status: .failed, errorMessage: "Music could not be prepared for export.")
                NotificationService.shared.notifyVideoFailed(videoName: params.videoName)
                return
            }
            musicOptions = MusicRenderOptions(
                file: musicUrl,
                volume: params.musicVolume * params.musicTrackVolume,
                quality: params.exportQuality,
                timelineStart: params.musicTimelineStart,
                timelineEnd: params.musicTimelineEnd,
                resolvedPath: localURL?.path,
                isMuted: params.musicMuted
            )
        }
        var additionalMusicOptions: [MusicRenderOptions] = []
        for track in params.additionalMusic {
            let localURL = await AudioMixerService.shared.downloadAndSaveAudio(from: track.file, audioId: track.id)
            if localURL == nil && !(track.file.hasPrefix("/") || track.file.hasPrefix("file://")) {
                print("[BackgroundRender] Required additional music could not be resolved for export: \(track.name)")
                await GenerationService.shared.updateGeneration(id: generationId, status: .failed, errorMessage: "Music track \"\(track.name)\" could not be prepared for export.")
                NotificationService.shared.notifyVideoFailed(videoName: params.videoName)
                return
            }
            additionalMusicOptions.append(MusicRenderOptions(
                file: track.file,
                volume: params.musicVolume * track.volume,
                quality: params.exportQuality,
                timelineStart: track.timelineStart,
                timelineEnd: track.timelineEnd,
                resolvedPath: localURL?.path,
                isMuted: track.isMuted
            ))
        }

        var voiceoverOptions: VoiceoverRenderOptions?
        if let voURL = params.voiceoverFileURL {
            voiceoverOptions = VoiceoverRenderOptions(
                fileURL: voURL,
                volume: params.voiceoverVolume,
                timelineStart: params.voiceoverTimelineStart,
                timelineEnd: params.voiceoverTimelineEnd,
                isMuted: params.voiceoverMuted
            )
        }

        let result = await VideoRenderService.shared.renderVideo(
            clips: params.clips,
            music: musicOptions,
            additionalMusic: additionalMusicOptions,
            voiceover: voiceoverOptions,
            aspectRatio: params.aspectRatio,
            includeBranding: params.includeBranding,
            onProgress: nil
        )

        // Verify the rendered file actually exists and is not empty
        if let resultURL = result,
           FileStorageService.shared.fileExists(at: resultURL),
           (FileStorageService.shared.fileSize(at: resultURL) ?? 0) > 1000 {
            do {
                let persistentURL = try FileStorageService.shared.copyToSavedVideos(sourceURL: resultURL, id: generationId)
                await GenerationService.shared.updateGeneration(id: generationId, status: .saved, videoUri: persistentURL.absoluteString)
                let savedToGallery = await saveRenderedVideoToGallery(persistentURL)
                if !savedToGallery {
                    print("[BackgroundRender] Export saved in app library but not Photos: \(persistentURL.lastPathComponent)")
                }
                NotificationService.shared.notifyVideoReady(videoName: params.videoName)

            } catch {
                // Never store cache URL — system can purge Caches when app is backgrounded, so video would disappear
                print("[BackgroundRender] Copy to saved_videos failed: \(error) — video not persisted")
                await GenerationService.shared.updateGeneration(id: generationId, status: .failed, errorMessage: "Rendered video could not be saved to the library.")
                NotificationService.shared.notifyVideoFailed(videoName: params.videoName)
            }
        } else {
            print("[BackgroundRender] Render failed or produced empty file for \(generationId)")
            await GenerationService.shared.updateGeneration(id: generationId, status: .failed, errorMessage: "Render failed while mixing the required audio.")
            NotificationService.shared.notifyVideoFailed(videoName: params.videoName)
        }
    }

    private func validateLocalClipSources(_ clips: [Clip]) -> Bool {
        for clip in clips {
            let source = clip.localUri ?? clip.uri
            if source.hasPrefix("http://") || source.hasPrefix("https://") { continue }
            let path = source.replacingOccurrences(of: "file://", with: "")
            if FileManager.default.fileExists(atPath: path) { continue }
            let filename = (path as NSString).lastPathComponent
            guard !filename.isEmpty else { return false }
            let storage = FileStorageService.shared
            let candidates = [
                storage.savedVideosDirectory.appendingPathComponent(filename),
                storage.clipCacheDirectory.appendingPathComponent(filename),
                storage.renderedVideosDirectory.appendingPathComponent(filename)
            ]
            if candidates.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                continue
            }
            return false
        }
        return true
    }

    private func saveRenderedVideoToGallery(_ videoURL: URL) async -> Bool {
        #if canImport(Photos)
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    print("[BackgroundRender] Photos add permission denied: \(status.rawValue)")
                    continuation.resume(returning: false)
                    return
                }

                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                } completionHandler: { success, error in
                    if let error {
                        print("[BackgroundRender] Save to Photos failed: \(error)")
                    }
                    continuation.resume(returning: success)
                }
            }
        }
        #else
        return false
        #endif
    }
}
