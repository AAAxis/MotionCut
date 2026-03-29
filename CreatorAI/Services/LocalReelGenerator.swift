import Foundation

/// Orchestrates the fully local, free video generation pipeline:
/// 1. LocalScriptGenerator -> generates script from user prompt
/// 2. PexelsService -> fetches stock footage for each scene
/// 3. LocalTTSService -> generates voiceover audio
/// 4. Saves clips for editor (no full render on-device)
///
/// Zero cost. No backend. Direct port of Android LocalReelGenerator.
final class LocalReelGenerator {

    struct GenerationProgress {
        let step: String
        let progress: Float // 0.0 to 1.0
    }

    struct LocalReelResult {
        let success: Bool
        let generationId: String?
        let videoPath: String?
        let voiceoverPath: String?
        let takesJson: String?
        let script: LocalScriptGenerator.GeneratedScript?
        let error: String?
    }

    static func generate(
        topic: String,
        language: String = "en",
        clipCount: Int = 6,
        onProgress: @escaping (GenerationProgress) -> Void
    ) async -> LocalReelResult {
        let generationId = UUID().uuidString
        let jobDir = FileStorageService.shared.cacheDirectory.appendingPathComponent("local_reel_\(generationId)")
        try? FileManager.default.createDirectory(at: jobDir, withIntermediateDirectories: true)

        do {
            // Step 1: Generate script locally
            onProgress(GenerationProgress(step: "Generating script...", progress: 0.1))
            print("[LocalReel] Step 1: Generating script for: \(topic)")

            let script = LocalScriptGenerator.generateScript(
                topic: topic,
                language: language,
                clipCount: clipCount
            )
            print("[LocalReel] Script generated: \(script.scenes.count) scenes")

            // Step 2: Search Pexels for footage (parallel)
            onProgress(GenerationProgress(step: "Finding footage...", progress: 0.25))
            print("[LocalReel] Step 2: Searching Pexels for \(script.scenes.count) scenes")

            let footageResults = await withTaskGroup(of: (Int, LocalScriptGenerator.SceneScript, [PexelsVideoResult]).self) { group in
                for (index, scene) in script.scenes.enumerated() {
                    group.addTask {
                        let results = await PexelsService.shared.searchVideos(query: scene.searchQuery, perPage: 5, orientation: "portrait")
                        return (index, scene, results)
                    }
                }
                var results: [(Int, LocalScriptGenerator.SceneScript, [PexelsVideoResult])] = []
                for await result in group {
                    results.append(result)
                }
                return results.sorted { $0.0 < $1.0 }
            }

            // Step 3: Download footage clips
            onProgress(GenerationProgress(step: "Downloading clips...", progress: 0.4))
            print("[LocalReel] Step 3: Downloading clips")

            var clips: [Clip] = []
            var usedVideoIds: Set<Int> = []

            for (index, result) in footageResults.enumerated() {
                let (_, scene, pexelsVideos) = result
                guard !pexelsVideos.isEmpty else { continue }

                let candidates = pexelsVideos.filter { !usedVideoIds.contains($0.id) } + pexelsVideos
                var downloaded = false

                for candidate in candidates {
                    let clipFile = jobDir.appendingPathComponent("clip_\(index).mp4")
                    do {
                        try await FileStorageService.shared.downloadFile(from: candidate.videoUrl, to: clipFile)
                        if let size = FileStorageService.shared.fileSize(at: clipFile), size > 1000 {
                            usedVideoIds.insert(candidate.id)
                            clips.append(Clip(
                                id: index,
                                uri: clipFile.path,
                                name: "Scene \(index + 1)",
                                beatDuration: scene.durationSeconds,
                                sourceDuration: Double(candidate.duration),
                                text: scene.subtitleText,
                                localUri: clipFile.path
                            ))
                            downloaded = true
                            break
                        }
                    } catch {
                        print("[LocalReel] Download failed for clip \(index): \(error.localizedDescription)")
                    }
                }

                if !downloaded {
                    print("[LocalReel] All attempts failed for clip \(index), skipping")
                }

                let clipProgress = 0.4 + (0.2 * Float(index + 1) / Float(footageResults.count))
                onProgress(GenerationProgress(step: "Downloaded \(index + 1)/\(footageResults.count) clips", progress: clipProgress))
            }

            // Fallback: try raw topic if no clips
            if clips.isEmpty {
                print("[LocalReel] No clips from scene queries, trying raw topic")
                let topicQuery = topic.split(separator: " ").prefix(3).joined(separator: " ")
                let fallbackVideos = await PexelsService.shared.searchVideos(query: topicQuery, perPage: 6, orientation: "portrait")
                for (index, video) in fallbackVideos.enumerated() {
                    let clipFile = jobDir.appendingPathComponent("clip_\(index).mp4")
                    if let _ = try? await FileStorageService.shared.downloadFile(from: video.videoUrl, to: clipFile) {
                        clips.append(Clip(
                            id: index,
                            uri: clipFile.path,
                            name: "Scene \(index + 1)",
                            beatDuration: 2.5,
                            sourceDuration: Double(video.duration),
                            text: script.scenes.indices.contains(index) ? script.scenes[index].subtitleText : topic,
                            localUri: clipFile.path
                        ))
                    }
                }
            }

            guard !clips.isEmpty else {
                return LocalReelResult(
                    success: false, generationId: nil, videoPath: nil, voiceoverPath: nil,
                    takesJson: nil, script: nil,
                    error: "Could not download footage. Check your internet connection."
                )
            }

            // Step 4: Generate voiceover with TTS
            onProgress(GenerationProgress(step: "Generating voiceover...", progress: 0.65))
            print("[LocalReel] Step 4: Generating voiceover")

            let voiceoverFiles = await LocalTTSService.shared.synthesizeScenes(
                scenes: Array(script.scenes.prefix(clips.count)),
                language: language,
                outputDir: jobDir
            )
            print("[LocalReel] Generated \(voiceoverFiles.count) voiceover files")

            // Step 5: Save clips to permanent storage
            onProgress(GenerationProgress(step: "Saving clips...", progress: 0.9))
            print("[LocalReel] Step 5: Saving \(clips.count) clips")

            let savedClips = clips.map { clip -> Clip in
                let src = URL(fileURLWithPath: clip.localUri ?? clip.uri)
                let dest = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(generationId)_clip_\(clip.id).mp4")
                if FileManager.default.fileExists(atPath: src.path) {
                    try? FileManager.default.copyItem(at: src, to: dest)
                    var updated = clip
                    updated.uri = dest.path
                    updated.localUri = dest.path
                    return updated
                }
                return clip
            }

            // Merge and save voiceover
            var savedVoiceoverPath: String?
            if !voiceoverFiles.isEmpty {
                let mergedOutput = jobDir.appendingPathComponent("voiceover_merged.m4a")
                if let merged = await LocalTTSService.shared.mergeAudioFiles(voiceoverFiles, output: mergedOutput) {
                    let dest = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(generationId)_voiceover.m4a")
                    try? FileManager.default.copyItem(at: merged, to: dest)
                    savedVoiceoverPath = dest.path
                }
            }

            print("[LocalReel] Generation complete: \(savedClips.count) clips saved")
            onProgress(GenerationProgress(step: "Done!", progress: 1.0))

            // Build takesJson for the video editor
            let takesJson: String?
            if let data = try? JSONEncoder().encode(savedClips) {
                takesJson = String(data: data, encoding: .utf8)
            } else {
                takesJson = nil
            }

            return LocalReelResult(
                success: true,
                generationId: generationId,
                videoPath: savedClips.first?.localUri,
                voiceoverPath: savedVoiceoverPath,
                takesJson: takesJson,
                script: script,
                error: nil
            )

        } catch {
            print("[LocalReel] Generation failed: \(error)")
            return LocalReelResult(
                success: false, generationId: nil, videoPath: nil, voiceoverPath: nil,
                takesJson: nil, script: nil,
                error: error.localizedDescription
            )
        }
    }
}
