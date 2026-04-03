import Foundation

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
    /// Original reel takes JSON to store on Generation for Edit.
    let takesJson: String?
    /// If true, after render the app will request cloud caption burn-in (no local captions).
    let addCaptionsViaCloud: Bool
    /// Local file URL for recorded voiceover audio.
    let voiceoverFileURL: URL?
    let voiceoverVolume: Double
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
            takesJson: editorParams.takesJson,
            addCaptionsViaCloud: false,
            voiceoverFileURL: nil,
            voiceoverVolume: 1.0
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
                localUri: nil
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
        var musicOptions: MusicRenderOptions?
        if let musicUrl = params.musicFileUrl, !musicUrl.isEmpty {
            let localURL = await AudioMixerService.shared.downloadAndSaveAudio(from: musicUrl, audioId: params.musicId ?? "reel-music")
            musicOptions = MusicRenderOptions(
                file: musicUrl,
                volume: params.musicVolume,
                quality: params.exportQuality,
                resolvedPath: localURL?.path
            )
        }

        var voiceoverOptions: VoiceoverRenderOptions?
        if let voURL = params.voiceoverFileURL {
            voiceoverOptions = VoiceoverRenderOptions(fileURL: voURL, volume: params.voiceoverVolume)
        }

        let result = await VideoRenderService.shared.renderVideo(
            clips: params.clips,
            music: musicOptions,
            voiceover: voiceoverOptions,
            aspectRatio: params.aspectRatio,
            onProgress: nil
        )

        // Verify the rendered file actually exists and is not empty
        if let resultURL = result,
           FileStorageService.shared.fileExists(at: resultURL),
           (FileStorageService.shared.fileSize(at: resultURL) ?? 0) > 1000 {
            do {
                let persistentURL = try FileStorageService.shared.copyToSavedVideos(sourceURL: resultURL, id: generationId)
                await GenerationService.shared.updateGeneration(id: generationId, status: .saved, videoUri: persistentURL.absoluteString)
                NotificationService.shared.notifyVideoReady(videoName: params.videoName)

                // Upload to Supabase, then optional cloud caption burn-in
                Task {
                    guard let remoteUrl = await SupabaseService.shared.uploadVideo(fileURL: persistentURL, generationId: generationId) else { return }
                    await GenerationService.shared.updateGeneration(id: generationId, remoteVideoUrl: remoteUrl)

                    if params.addCaptionsViaCloud, let outputUrl = await CaptionService.shared.requestCloudCaptions(generationId: generationId, videoUri: remoteUrl, takesJson: params.takesJson) {
                        await GenerationService.shared.updateGeneration(id: generationId, remoteVideoUrl: outputUrl)
                    }
                }
            } catch {
                // Never store cache URL — system can purge Caches when app is backgrounded, so video would disappear
                print("[BackgroundRender] Copy to saved_videos failed: \(error) — video not persisted")
                await GenerationService.shared.updateGeneration(id: generationId, status: .failed)
                NotificationService.shared.notifyVideoFailed(videoName: params.videoName)
            }
        } else {
            print("[BackgroundRender] Render failed or produced empty file for \(generationId)")
            await GenerationService.shared.updateGeneration(id: generationId, status: .failed)
            NotificationService.shared.notifyVideoFailed(videoName: params.videoName)
        }
    }
}
