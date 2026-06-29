import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

private enum HTTPDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }()
}

/// Orchestrates the video generation pipeline:
/// 1. LocalScriptGenerator -> generates script from user prompt
/// 2. Source tools -> reuses timeline footage, searches stock, or generates AI scenes
/// 3. Optional voiceover, otherwise no generated audio
/// 4. Saves clips for editor (no full render on-device)
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

    enum SceneSource {
        case timeline(reason: String)
        case stock(reason: String)
        case aiVideo(reason: String)

        var reason: String {
            switch self {
            case .timeline(let reason), .stock(let reason), .aiVideo(let reason):
                return reason
            }
        }
    }

    static func generate(
        topic: String,
        language: String = "en",
        clipCount: Int = 6,
        scriptOverride: LocalScriptGenerator.GeneratedScript? = nil,
        sourcePlan: [Int: SceneSource] = [:],
        reusableClips: [Clip] = [],
        aiModelId: String = "wan-video/wan-2.2-turbo",
        referenceImageUrl: String? = nil,
        referenceVideoUrl: String? = nil,
        voiceoverMode: String = "none",
        elevenLabsVoiceId: String? = nil,
        userId: String? = nil,
        onClipReady: ((Clip, Int, Int) async -> Void)? = nil,
        onProgress: @escaping (GenerationProgress) -> Void
    ) async -> LocalReelResult {
        let generationId = UUID().uuidString
        let jobDir = FileStorageService.shared.cacheDirectory.appendingPathComponent("local_reel_\(generationId)")
        try? FileManager.default.createDirectory(at: jobDir, withIntermediateDirectories: true)

        do {
            // Step 1: Generate script locally
            onProgress(GenerationProgress(step: "Generating script...", progress: 0.1))
            print("[LocalReel] Step 1: Generating script for: \(topic)")

            let script = scriptOverride ?? LocalScriptGenerator.generateScript(
                topic: topic,
                language: language,
                clipCount: clipCount
            )
            print("[LocalReel] Script generated: \(script.scenes.count) scenes")

            let voiceoverTask = Task<[URL], Error> {
                try await generateVoiceoverFiles(
                    script: script,
                    voiceoverMode: voiceoverMode,
                    elevenLabsVoiceId: elevenLabsVoiceId,
                    language: language,
                    outputDir: jobDir,
                    onProgress: onProgress
                )
            }

            // Step 2: Execute source tools per scene. Pexels is one tool, not the mandatory path.
            onProgress(GenerationProgress(step: "Voiceover rendering while footage loads...", progress: 0.25))
            print("[LocalReel] Step 2: Executing source tools for \(script.scenes.count) scenes")

            var clips: [Clip] = []
            var usedVideoIds: Set<Int> = []
            var reusedTimelineIndexes: Set<Int> = []

            func acceptClip(_ clip: Clip, index: Int) async {
                let savedClip = saveClip(clip, generationId: generationId)
                clips.append(savedClip)
                await onClipReady?(savedClip, index, script.scenes.count)
            }

            for (index, scene) in script.scenes.enumerated() {
                let plannedSource = sourcePlan[index]
                let progress = 0.3 + (0.3 * Float(index + 1) / Float(max(1, script.scenes.count)))

                if case .timeline = plannedSource,
                   let reusedClip = copyReusableClip(
                    from: reusableClips,
                    excluding: reusedTimelineIndexes,
                    scene: scene,
                    index: index,
                    jobDir: jobDir
                   ) {
                    reusedTimelineIndexes.insert(reusedClip.sourceReusableIndex)
                    await acceptClip(reusedClip.clip, index: index)
                    onProgress(GenerationProgress(step: "Tool: timeline clip for scene \(index + 1)", progress: progress))
                    continue
                }

                if case .aiVideo = plannedSource {
                    onProgress(GenerationProgress(step: "Tool: fal.ai video for scene \(index + 1)/\(script.scenes.count)", progress: progress))
                    if let generatedClip = await generateAiSceneClip(
                        scene: scene,
                        index: index,
                        jobDir: jobDir,
                        modelId: aiModelId,
                        referenceImageUrl: referenceImageUrl,
                        referenceVideoUrl: referenceVideoUrl,
                        userId: userId
                    ) {
                        await acceptClip(generatedClip, index: index)
                        continue
                    } else {
                        onProgress(GenerationProgress(step: "fal.ai video failed for scene \(index + 1)", progress: progress))
                        continue
                    }
                }

                onProgress(GenerationProgress(step: "Tool: stock search for scene \(index + 1)", progress: progress))
                let pexelsVideos = await PexelsService.shared.searchVideos(query: scene.searchQuery, perPage: 5, orientation: "portrait")
                guard !pexelsVideos.isEmpty else {
                    if let generatedClip = await generateAiSceneClip(
                        scene: scene,
                        index: index,
                        jobDir: jobDir,
                        modelId: aiModelId,
                        referenceImageUrl: referenceImageUrl,
                        referenceVideoUrl: referenceVideoUrl,
                        userId: userId
                    ) {
                        await acceptClip(generatedClip, index: index)
                        onProgress(GenerationProgress(step: "Tool fallback: AI video for scene \(index + 1)", progress: progress))
                    }
                    continue
                }

                let candidates = pexelsVideos.filter { !usedVideoIds.contains($0.id) } + pexelsVideos
                var downloaded = false

                for candidate in candidates {
                    let clipFile = jobDir.appendingPathComponent("clip_\(index).mp4")
                    do {
                        try await FileStorageService.shared.downloadFile(from: candidate.videoUrl, to: clipFile)
                        if let size = FileStorageService.shared.fileSize(at: clipFile), size > 1000 {
                            usedVideoIds.insert(candidate.id)
                            await acceptClip(Clip(
                                id: index + 1,
                                uri: clipFile.path,
                                name: "Scene \(index + 1)",
                                beatDuration: scene.durationSeconds,
                                sourceDuration: Double(candidate.duration),
                                text: scene.subtitleText,
                                localUri: clipFile.path,
                                isMuted: true
                            ), index: index)
                            downloaded = true
                            break
                        }
                    } catch {
                        print("[LocalReel] Download failed for clip \(index): \(error.localizedDescription)")
                    }
                }

                if !downloaded {
                    print("[LocalReel] All stock attempts failed for clip \(index), trying AI generation")
                    if let generatedClip = await generateAiSceneClip(
                        scene: scene,
                        index: index,
                        jobDir: jobDir,
                        modelId: aiModelId,
                        referenceImageUrl: referenceImageUrl,
                        referenceVideoUrl: referenceVideoUrl,
                        userId: userId
                    ) {
                        await acceptClip(generatedClip, index: index)
                        onProgress(GenerationProgress(step: "Tool fallback: AI video for scene \(index + 1)", progress: progress))
                    }
                }

                onProgress(GenerationProgress(step: "Prepared scene \(index + 1)/\(script.scenes.count)", progress: progress))
            }

            // Fallback: generate scenes if every selected tool failed.
            if clips.isEmpty {
                print("[LocalReel] No clips from selected tools, generating AI scenes")
                for (index, scene) in script.scenes.enumerated() {
                    if let generatedClip = await generateAiSceneClip(
                        scene: scene,
                        index: index,
                        jobDir: jobDir,
                        modelId: aiModelId,
                        referenceImageUrl: referenceImageUrl,
                        referenceVideoUrl: referenceVideoUrl,
                        userId: userId
                    ) {
                        await acceptClip(generatedClip, index: index)
                    }
                }
            }

            guard !clips.isEmpty else {
                voiceoverTask.cancel()
                return LocalReelResult(
                    success: false, generationId: nil, videoPath: nil, voiceoverPath: nil,
                    takesJson: nil, script: nil,
                    error: "Could not download footage. Check your internet connection."
                )
            }

            // Step 4: Voiceover started in parallel after the script was ready.
            onProgress(GenerationProgress(step: "Waiting for voiceover mix...", progress: 0.68))
            let voiceoverFiles = try await voiceoverTask.value
            print("[LocalReel] Generated \(voiceoverFiles.count) voiceover files")

            // Step 5: Clips are saved as soon as each source tool finishes, so the editor can spawn them live.
            onProgress(GenerationProgress(step: "Finalizing clips...", progress: 0.9))
            print("[LocalReel] Step 5: Finalizing \(clips.count) clips")

            // Merge and save voiceover
            var savedVoiceoverPath: String?
            if !voiceoverFiles.isEmpty {
                let mergedOutput = jobDir.appendingPathComponent("voiceover_merged.m4a")
                if let merged = await AudioMergeService.shared.mergeAudioFiles(voiceoverFiles, output: mergedOutput) {
                    let dest = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(generationId)_voiceover.m4a")
                    try? FileManager.default.copyItem(at: merged, to: dest)
                    savedVoiceoverPath = dest.path
                }
            }

            print("[LocalReel] Generation complete: \(clips.count) clips saved")
            onProgress(GenerationProgress(step: "Done!", progress: 1.0))

            // Build takesJson for the video editor
            let takesJson: String?
            if let data = try? JSONEncoder().encode(clips) {
                takesJson = String(data: data, encoding: .utf8)
            } else {
                takesJson = nil
            }

            return LocalReelResult(
                success: true,
                generationId: generationId,
                videoPath: clips.first?.localUri,
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

    private static func copyReusableClip(
        from reusableClips: [Clip],
        excluding usedIndexes: Set<Int>,
        scene: LocalScriptGenerator.SceneScript,
        index: Int,
        jobDir: URL
    ) -> (clip: Clip, sourceReusableIndex: Int)? {
        for reusableIndex in reusableClips.indices where !usedIndexes.contains(reusableIndex) {
            let source = reusableClips[reusableIndex]
            let sourcePath = (source.localUri ?? source.uri).replacingOccurrences(of: "file://", with: "")
            guard FileManager.default.fileExists(atPath: sourcePath) else { continue }

            let dest = jobDir.appendingPathComponent("clip_\(index)_timeline.mp4")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: dest)
                return (
                    Clip(
                        id: index + 1,
                        uri: dest.path,
                        name: "Scene \(index + 1) · Timeline",
                        beatDuration: scene.durationSeconds,
                        sourceDuration: source.sourceDuration ?? source.beatDuration,
                        text: scene.subtitleText,
                        localUri: dest.path
                    ),
                    reusableIndex
                )
            } catch {
                print("[LocalReel] Timeline reuse failed for clip \(reusableIndex): \(error.localizedDescription)")
            }
        }
        return nil
    }

    private static func generateVoiceoverFiles(
        script: LocalScriptGenerator.GeneratedScript,
        voiceoverMode: String,
        elevenLabsVoiceId: String?,
        language: String,
        outputDir: URL,
        onProgress: @escaping (GenerationProgress) -> Void
    ) async throws -> [URL] {
        if voiceoverMode == "none" || voiceoverMode == "music" {
            onProgress(GenerationProgress(step: voiceoverMode == "music" ? "Planning music..." : "Skipping voiceover...", progress: 0.32))
            return []
        }

        if voiceoverMode == "elevenlabs" {
            if ElevenLabsTTSService.shared.isConfigured,
               !(elevenLabsVoiceId ?? "").isEmpty,
               PremiumVoiceQuota.consumeIfAvailable() {
                onProgress(GenerationProgress(step: "Voice rendering in parallel...", progress: 0.32))
                print("[LocalReel] Parallel task: Generating premium voiceover")
                return try await ElevenLabsTTSService.shared.synthesizeScenes(
                    scenes: script.scenes,
                    voiceId: elevenLabsVoiceId ?? "",
                    outputDir: outputDir
                )
            }

            onProgress(GenerationProgress(step: "Voice rendering in parallel...", progress: 0.32))
            var files: [URL] = []
            for (index, scene) in script.scenes.enumerated() {
                let file = try await SystemTTSService.shared.synthesizeToFile(
                    text: scene.voiceoverText,
                    outputDir: outputDir,
                    filename: "system_voice_\(index).caf",
                    language: language
                )
                files.append(file)
            }
            return files
        }

        onProgress(GenerationProgress(step: "Skipping voiceover...", progress: 0.32))
        return []
    }

    private static func saveClip(_ clip: Clip, generationId: String) -> Clip {
        let src = URL(fileURLWithPath: (clip.localUri ?? clip.uri).replacingOccurrences(of: "file://", with: ""))
        let dest = FileStorageService.shared.savedVideosDirectory.appendingPathComponent("\(generationId)_clip_\(clip.id).mp4")

        guard FileManager.default.fileExists(atPath: src.path) else {
            return clip
        }

        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            var saved = clip
            saved.uri = dest.path
            saved.localUri = dest.path
            return saved
        } catch {
            print("[LocalReel] Save clip failed for \(clip.id): \(error.localizedDescription)")
            return clip
        }
    }

    private static func generateAiSceneClip(
        scene: LocalScriptGenerator.SceneScript,
        index: Int,
        jobDir: URL,
        modelId: String,
        referenceImageUrl: String?,
        referenceVideoUrl: String?,
        userId: String?
    ) async -> Clip? {
        guard modelId != "noai" else { return nil }
        let generationDuration = Int(max(5, min(10, ceil(scene.durationSeconds))))
        let referenceLine: String
        if referenceImageUrl?.isEmpty == false {
            referenceLine = "Use the attached image as the first frame reference."
        } else if referenceVideoUrl?.isEmpty == false {
            referenceLine = "Use the attached reference video for motion control only."
        } else {
            referenceLine = ""
        }
        let prompt = """
        Vertical ad scene, \(generationDuration) seconds.
        Visual: \(scene.searchQuery).
        Moment: \(scene.voiceoverText)
        \(referenceLine)
        Cinematic, natural movement, realistic lighting, no text overlay.
        """

        do {
            let response = try await GenerationService.shared.startAICreate(
                modelId: modelId,
                prompt: prompt,
                imageUrl: referenceImageUrl,
                duration: generationDuration,
                userId: userId,
                referenceVideoUrl: referenceVideoUrl
            )
            guard let generationId = response.id, response.error == nil else {
                print("[LocalReel] AI scene start failed: \(response.error ?? "missing id")")
                return nil
            }

            let deadline = Date().addingTimeInterval(600)
            while Date() < deadline {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                let status = try await GenerationService.shared.pollAICreate(id: generationId)
                if status.status == "succeeded", let outputUrl = status.outputUrl {
                    let clipFile = jobDir.appendingPathComponent("clip_\(index)_ai.mp4")
                    do {
                        if outputUrl.hasPrefix("/") || outputUrl.hasPrefix("file://") {
                            let sourcePath = outputUrl.replacingOccurrences(of: "file://", with: "")
                            try? FileManager.default.removeItem(at: clipFile)
                            try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: clipFile)
                        } else {
                            try await FileStorageService.shared.downloadFile(from: outputUrl, to: clipFile)
                        }
                    } catch {
                        print("[LocalReel] AI scene download failed: \(error.localizedDescription) url=\(outputUrl)")
                        return nil
                    }
                    guard FileManager.default.fileExists(atPath: clipFile.path) else {
                        print("[LocalReel] AI scene download produced no file: \(outputUrl)")
                        return nil
                    }
                    return Clip(
                        id: index + 1,
                        uri: clipFile.path,
                        name: "Scene \(index + 1) · AI",
                        beatDuration: scene.durationSeconds,
                        sourceDuration: Double(generationDuration),
                        text: scene.subtitleText,
                        localUri: clipFile.path
                    )
                }
                if status.status == "succeeded", status.outputUrl == nil {
                    print("[LocalReel] AI scene succeeded without output URL: \(status.error ?? "unknown fal result shape")")
                    return nil
                }
                if status.status == "failed" || status.status == "canceled" {
                    print("[LocalReel] AI scene failed: \(status.error ?? "unknown")")
                    return nil
                }
            }
            print("[LocalReel] AI scene timed out waiting for fal.ai result: \(generationId)")
        } catch {
            print("[LocalReel] AI scene generation error: \(error.localizedDescription)")
        }
        return nil
    }
}

enum AppleIntelligenceScenarioGenerator {
    enum ScenarioError: LocalizedError {
        case unavailable
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Apple Intelligence is not available on this device."
            case .invalidResponse:
                return "Apple Intelligence returned a scenario we could not read."
            }
        }
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return FoundationScenarioGenerator.isAvailable
        }
        #endif
        return false
    }

    static func generateScript(topic: String, language: String, clipCount: Int) async throws -> LocalScriptGenerator.GeneratedScript {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let script = try await FoundationScenarioGenerator.generateScript(topic: topic, language: language, clipCount: clipCount)
            try ScenarioQualityGate.validate(script, originalTopic: topic)
            return script
        }
        #endif
        throw ScenarioError.unavailable
    }

    static func generateSingleClipPrompt(topic: String, language: String, duration: Int) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await FoundationScenarioGenerator.generateSingleClipPrompt(
                topic: topic,
                language: language,
                duration: duration
            )
        }
        #endif
        throw ScenarioError.unavailable
    }

    static func generateTimelineEditPlan(request: String, timelineSummary: String, language: String) async throws -> [TimelineEditInstruction] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let plan = try await FoundationScenarioGenerator.generateTimelineEditPlan(
                request: request,
                timelineSummary: timelineSummary,
                language: language
            )
            try validateTimelinePlan(plan, request: request)
            return plan
        }
        #endif
        throw ScenarioError.unavailable
    }

    private static func validateTimelinePlan(_ plan: [TimelineEditInstruction], request: String) throws {
        guard !plan.isEmpty else { throw ScenarioError.invalidResponse }
        let allowedActions: Set<String> = [
            "selectClip", "moveClip", "trimClip", "splitClip", "duplicateClip", "deleteClip",
            "removeBadTakes", "setSpeed", "muteClip", "unmuteClip", "muteMusic", "unmuteMusic",
            "muteVoiceover", "unmuteVoiceover", "setCaption", "setCaptionsEnabled", "setAspectRatio",
            "setBeatDuration", "syncBeatCuts", "setMusic", "playAll"
        ]
        guard plan.allSatisfy({ allowedActions.contains($0.action) }) else {
            throw ScenarioError.invalidResponse
        }

        let requestWords = Set(request.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let echoedTextCount = plan.compactMap(\.text).filter { text in
            let words = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            return !words.isEmpty && words.isSubset(of: requestWords)
        }.count
        guard echoedTextCount < max(2, plan.count) else {
            throw ScenarioError.invalidResponse
        }
    }
}

private enum ScenarioQualityGate {
    enum QualityError: LocalizedError {
        case weakScript

        var errorDescription: String? {
            "The planner returned a repetitive keyword list instead of a real ad script."
        }
    }

    static let systemPrompt = """
    You are a senior direct-response creative director writing polished short-form ads.
    Return only valid JSON. No markdown. No commentary.
    Each scene must include searchQuery, subtitleText, voiceoverText, and durationSeconds.
    The result must feel like a ChatGPT-quality ad concept, not SEO keywords.
    Write a clear hook, useful proof or transformation, and a final payoff/CTA.
    Voiceover must be natural spoken language with complete sentences.
    Subtitles must be punchy, readable on a phone, and not identical to searchQuery.
    Search queries are only for visual sourcing: concrete camera-visible nouns and actions.
    Do not repeat the product/topic word in every caption or voiceover line.
    Do not output keyword chains like "table factory table making machine".
    Do not make every scene the same duration unless the story truly needs it.
    """

    static func userPrompt(topic: String, language: String, requestedCount: Int) -> String {
        """
        Create a \(requestedCount)-scene vertical ad scenario.
        Language code: \(language)

        Topic/product/context:
        \(topic)

        Make it specific and persuasive:
        - Scene 1: hook with tension or curiosity.
        - Middle scenes: show process, benefit, contrast, or proof.
        - Final scene: memorable payoff or CTA.
        - Use varied visual search queries, not the same phrase with one word changed.
        - Voiceover should sound like a smart human ad writer.

        JSON schema:
        {
          "topic": "string",
          "scenes": [
            {
              "searchQuery": "concrete visual stock search, 2-6 words",
              "subtitleText": "short ad caption, max 8 words",
              "voiceoverText": "natural spoken sentence, 7-18 words",
              "durationSeconds": 1.6
            }
          ]
        }
        """
    }

    static func validate(_ script: LocalScriptGenerator.GeneratedScript, originalTopic: String) throws {
        guard script.scenes.count >= 3 else { throw QualityError.weakScript }

        let voiceover = script.scenes.map(\.voiceoverText).joined(separator: " ")
        let voiceoverTokens = contentTokens(voiceover)
        let uniqueVoiceoverTokens = Set(voiceoverTokens)
        guard voiceoverTokens.count >= max(14, script.scenes.count * 4),
              uniqueVoiceoverTokens.count >= max(8, script.scenes.count * 2) else {
            throw QualityError.weakScript
        }

        let topicTokens = Set(contentTokens(originalTopic))
        let repeatedTopicLines = script.scenes.filter { scene in
            let tokens = contentTokens(scene.voiceoverText)
            guard !tokens.isEmpty, !topicTokens.isEmpty else { return false }
            let topicCount = tokens.filter { topicTokens.contains($0) }.count
            return Double(topicCount) / Double(tokens.count) > 0.55
        }.count
        guard repeatedTopicLines < max(2, script.scenes.count / 2) else {
            throw QualityError.weakScript
        }

        let weakScenes = script.scenes.filter { scene in
            let captionTokens = contentTokens(scene.subtitleText)
            let voiceTokens = contentTokens(scene.voiceoverText)
            let searchTokens = contentTokens(scene.searchQuery)
            let captionEqualsSearch = !captionTokens.isEmpty && captionTokens == searchTokens
            let tooFewVoiceWords = voiceTokens.count < 4
            let tooRepetitive = Set(voiceTokens).count <= 2 && voiceTokens.count >= 3
            return captionEqualsSearch || tooFewVoiceWords || tooRepetitive
        }
        guard weakScenes.count <= 1 else { throw QualityError.weakScript }

        let searchQueries = script.scenes.map { normalized($0.searchQuery) }
        guard Set(searchQueries).count >= min(script.scenes.count, 4) else {
            throw QualityError.weakScript
        }
    }

    private static func normalized(_ text: String) -> String {
        contentTokens(text).joined(separator: " ")
    }

    private static func contentTokens(_ text: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "that", "this", "your", "you", "are", "was", "were",
            "into", "from", "they", "them", "their", "our", "out", "now", "how", "why", "what",
            "make", "makes", "making", "made", "get", "got", "can", "will", "just", "like"
        ]
        return text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }
}

enum OpenRouterScenarioGenerator {
    struct FreeModel: Identifiable, Equatable {
        let id: String
        let name: String

        var providerName: String {
            let rawProvider = id.split(separator: "/").first.map(String.init) ?? name
            return rawProvider
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    struct RateLimitUpdate {
        let modelName: String
        let retryInSeconds: Int
        let attempt: Int
        let maxAttempts: Int
    }

    enum OpenRouterError: LocalizedError {
        case missingKey
        case invalidResponse
        case rateLimited(model: String, retryAfter: Int?, details: String)
        case http(model: String, code: Int, details: String)
        case allModelsFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "NVIDIA Nemotron is not configured for this build."
            case .invalidResponse:
                return "NVIDIA Nemotron returned a response we could not read."
            case .rateLimited(let model, let retryAfter, let details):
                let wait = retryAfter.map { " Retrying in \($0)s." } ?? " Retrying soon."
                let suffix = details.isEmpty ? "" : " \(details)"
                return "\(model) is busy.\(wait)\(suffix)"
            case .http(let model, let code, let details):
                let suffix = details.isEmpty ? "" : ": \(details)"
                return "\(model) HTTP error \(code)\(suffix)"
            case .allModelsFailed(let details):
                return "All free planning models failed. \(details)"
            }
        }
    }

    static var displayName: String {
        selectedFreeModel.name
    }

    static var lastUsedModelName: String {
        UserDefaults.standard.string(forKey: lastUsedModelNameKey) ?? displayName
    }

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private static let modelsEndpoint = URL(string: "https://openrouter.ai/api/v1/models")!
    private static let selectedModelIdKey = "OPENROUTER_FREE_MODEL_ID"
    private static let selectedModelNameKey = "OPENROUTER_FREE_MODEL_NAME"
    private static let lastUsedModelNameKey = "OPENROUTER_LAST_USED_MODEL_NAME"
    private static let modelCandidates: [OpenRouterModelCandidate] = [
        OpenRouterModelCandidate(id: "nvidia/nemotron-3-super-120b-a12b:free", name: "NVIDIA Nemotron 3 Super"),
        OpenRouterModelCandidate(id: "nvidia/nemotron-3-ultra-550b-a55b:free", name: "NVIDIA Nemotron 3 Ultra"),
        OpenRouterModelCandidate(id: "qwen/qwen3-next-80b-a3b-instruct:free", name: "Qwen3 Next"),
        OpenRouterModelCandidate(id: "openai/gpt-oss-120b:free", name: "GPT OSS 120B"),
        OpenRouterModelCandidate(id: "meta-llama/llama-3.3-70b-instruct:free", name: "Llama 3.3 70B")
    ]

    static var defaultFreeModels: [FreeModel] {
        modelCandidates.map { FreeModel(id: $0.id, name: $0.name) }
    }

    static var selectedFreeModel: FreeModel {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: selectedModelIdKey), !id.isEmpty {
            let name = defaults.string(forKey: selectedModelNameKey)
                ?? defaultFreeModels.first { $0.id == id }?.name
                ?? readableModelName(id)
            return FreeModel(id: id, name: name)
        }
        return defaultFreeModels[0]
    }

    static func selectFreeModel(_ model: FreeModel) {
        UserDefaults.standard.set(model.id, forKey: selectedModelIdKey)
        UserDefaults.standard.set(model.name, forKey: selectedModelNameKey)
    }

    static func fetchFreeModels() async throws -> [FreeModel] {
        let (data, response) = try await URLSession.shared.data(from: modelsEndpoint)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]] else {
            return defaultFreeModels
        }

        let fetched = items.compactMap(freeTextModel(from:))
        var seen: Set<String> = []
        let merged = (fetched + defaultFreeModels).filter { model in
            guard !seen.contains(model.id) else { return false }
            seen.insert(model.id)
            return true
        }
        return merged.sorted { lhs, rhs in
            if lhs.id == selectedFreeModel.id { return true }
            if rhs.id == selectedFreeModel.id { return false }
            if lhs.providerName == rhs.providerName { return lhs.name < rhs.name }
            return lhs.providerName < rhs.providerName
        }
    }

    private static var apiKey: String? {
        let env = ProcessInfo.processInfo.environment
        return env["OPENROUTER_API_KEY"]
            ?? env["OPENROUTER_KEY"]
            ?? secretValue("OPENROUTER_API_KEY")
            ?? (Bundle.main.object(forInfoDictionaryKey: "OPENROUTER_API_KEY") as? String)
            ?? UserDefaults.standard.string(forKey: "OPENROUTER_API_KEY")
    }

    private static func secretValue(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let value = plist[key] as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static func generateScript(
        topic: String,
        language: String,
        clipCount: Int,
        onRateLimit: ((RateLimitUpdate) async -> Void)? = nil,
        preferQualityFallback: Bool = false
    ) async throws -> LocalScriptGenerator.GeneratedScript {
        let requestedCount = max(3, min(8, clipCount))
        let system = ScenarioQualityGate.systemPrompt
        let user = ScenarioQualityGate.userPrompt(topic: topic, language: language, requestedCount: requestedCount)

        var lastError: Error?
        for attempt in 1...2 {
            let repairInstruction = attempt == 1 ? "" : """

            Previous attempt was rejected because it sounded like repetitive keywords.
            Rewrite completely with a stronger hook, varied visual scenes, and natural spoken ad copy.
            """
            do {
                let content = try await complete(
                    system: system,
                    user: user + repairInstruction,
                    maxTokens: 1800,
                    onRateLimit: onRateLimit,
                    preferQualityFallback: preferQualityFallback
                )
                let payload = try decodeScenario(from: content)
                let scenes = payload.scenes.prefix(requestedCount).map { scene in
                    LocalScriptGenerator.SceneScript(
                        searchQuery: scene.searchQuery,
                        subtitleText: scene.subtitleText,
                        voiceoverText: scene.voiceoverText,
                        durationSeconds: max(1.5, min(5.0, scene.durationSeconds))
                    )
                }

                guard !scenes.isEmpty else { throw OpenRouterError.invalidResponse }
                let script = LocalScriptGenerator.GeneratedScript(
                    topic: payload.topic.isEmpty ? topic : payload.topic,
                    scenes: Array(scenes),
                    fullVoiceover: scenes.map(\.voiceoverText).joined(separator: " "),
                    totalDuration: scenes.reduce(0) { $0 + $1.durationSeconds }
                )
                try ScenarioQualityGate.validate(script, originalTopic: topic)
                return script
            } catch {
                lastError = error
            }
        }
        throw lastError ?? OpenRouterError.invalidResponse
    }

    static func generateSingleClipPrompt(
        topic: String,
        language: String,
        duration: Int,
        onRateLimit: ((RateLimitUpdate) async -> Void)? = nil
    ) async throws -> String {
        let system = """
        You write concise prompts for vertical AI video generation.
        Return only the final prompt. No markdown. No commentary.
        Make it visual, concrete, camera-aware, and suitable for a single short clip.
        """
        let user = """
        Rewrite this idea into one high-quality AI video prompt.
        Language code: \(language)
        Duration: \(duration) seconds
        Idea:
        \(topic)
        """
        let content = try await complete(system: system, user: user, maxTokens: 700, onRateLimit: onRateLimit)
        let prompt = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw OpenRouterError.invalidResponse }
        return prompt
    }

    static func generateTimelineEditPlan(
        request: String,
        timelineSummary: String,
        language: String,
        onRateLimit: ((RateLimitUpdate) async -> Void)? = nil
    ) async throws -> [TimelineEditInstruction] {
        let system = """
        You are a video editor agent for CreatorAI.
        Return only valid JSON. No markdown. No commentary.
        Choose safe timeline edits using only these action values:
        selectClip, moveClip, trimClip, splitClip, duplicateClip, deleteClip, removeBadTakes, setSpeed, muteClip, unmuteClip, muteMusic, unmuteMusic, muteVoiceover, unmuteVoiceover, setCaption, setCaptionsEnabled, setAspectRatio, setBeatDuration, syncBeatCuts, setMusic, playAll.
        Clip indexes are zero-based. Never delete the only clip. Keep trimStart below trimEnd. For ad pacing, use beatDuration between 0.1 and 2.0 seconds.
        For speed, use setSpeed with clipIndex for one clip, or setSpeed with allClips true to change every clip. Speed must be 0.1 to 5.0.
        For mute tools, use muteClip/unmuteClip with clipIndex, muteMusic/unmuteMusic for music rows, and muteVoiceover/unmuteVoiceover for voiceover.
        For music, use setMusic with musicMood, musicVolume, musicStart, and musicEnd. Lower musicVolume when voiceover exists.
        For "cut current clip", return splitClip with the currently selected or most relevant clipIndex.
        For "remove bad takes", return removeBadTakes unless the user names one exact clip to delete.
        """
        let user = """
        User request language code: \(language)
        User request:
        \(request)

        Current timeline:
        \(timelineSummary)

        Return a JSON array. Each item can contain:
        {
          "action": "trimClip",
          "clipIndex": 0,
          "fromIndex": 0,
          "toIndex": 1,
          "allClips": false,
          "trimStart": 5,
          "trimEnd": 90,
          "beatDuration": 1.5,
          "splitAt": 0.8,
          "speed": 1.25,
          "text": "caption text",
          "enabled": true,
          "aspectRatio": "9:16",
          "musicMood": "upbeat",
          "musicVolume": 0.25,
          "musicStart": 0,
          "musicEnd": 15
        }
        """
        let content = try await complete(system: system, user: user, maxTokens: 1200, onRateLimit: onRateLimit)
        return try decodeTimelinePlan(from: content)
    }

    private static func complete(
        system: String,
        user: String,
        maxTokens: Int,
        onRateLimit: ((RateLimitUpdate) async -> Void)? = nil,
        preferQualityFallback: Bool = false
    ) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw OpenRouterError.missingKey }

        let maxAttemptsPerModel = 3
        var failures: [String] = []
        for candidate in orderedModelCandidates(preferQualityFallback: preferQualityFallback) {
            var lastRateLimit: OpenRouterError?
            for attempt in 1...maxAttemptsPerModel {
                do {
                    return try await completeOnce(
                        system: system,
                        user: user,
                        maxTokens: maxTokens,
                        apiKey: apiKey,
                        candidate: candidate
                    )
                } catch OpenRouterError.missingKey {
                    throw OpenRouterError.missingKey
                } catch OpenRouterError.http(model: let model, code: let code, details: let details) where code == 401 || code == 402 || code == 403 {
                    throw OpenRouterError.http(model: model, code: code, details: details)
                } catch OpenRouterError.rateLimited(model: let model, retryAfter: let retryAfter, details: let details) {
                    let delay = min(60, max(1, retryAfter ?? 1))
                    lastRateLimit = .rateLimited(model: model, retryAfter: delay, details: details)
                    await onRateLimit?(RateLimitUpdate(
                        modelName: model,
                        retryInSeconds: delay,
                        attempt: 1,
                        maxAttempts: 1
                    ))
                    break
                } catch {
                    let message = error.localizedDescription
                    failures.append("\(candidate.name): \(message)")
                    print("[OpenRouter] Planner fallback after \(candidate.id): \(message)")
                    break
                }
            }
            if let lastRateLimit {
                let message = lastRateLimit.localizedDescription
                failures.append("\(candidate.name): \(message)")
                print("[OpenRouter] Planner rate limited after retries for \(candidate.id): \(message)")
            }
        }

        throw OpenRouterError.allModelsFailed(failures.joined(separator: " | "))
    }

    private static func orderedModelCandidates(preferQualityFallback: Bool = false) -> [OpenRouterModelCandidate] {
        let selected = selectedFreeModel
        let selectedCandidate = OpenRouterModelCandidate(id: selected.id, name: selected.name)
        let ordered = preferQualityFallback
            ? (modelCandidates + [selectedCandidate])
            : ([selectedCandidate] + modelCandidates)
        return ordered.reduce(into: []) { result, candidate in
            if !result.contains(where: { $0.id == candidate.id }) {
                result.append(candidate)
            }
        }
    }

    private static func completeOnce(
        system: String,
        user: String,
        maxTokens: Int,
        apiKey: String,
        candidate: OpenRouterModelCandidate
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CreatorAI", forHTTPHeaderField: "X-OpenRouter-Title")
        request.httpBody = try JSONEncoder().encode(OpenRouterChatRequest(
            model: candidate.id,
            messages: [
                OpenRouterMessage(role: "system", content: system),
                OpenRouterMessage(role: "user", content: user)
            ],
            temperature: 0.7,
            maxTokens: maxTokens
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let statusCode = http?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            let details = responseDetails(from: data)
            if statusCode == 429 {
                throw OpenRouterError.rateLimited(
                    model: candidate.name,
                    retryAfter: retryAfterSeconds(from: http),
                    details: details
                )
            }
            throw OpenRouterError.http(model: candidate.name, code: statusCode, details: details)
        }

        let decoded = try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw OpenRouterError.invalidResponse
        }
        UserDefaults.standard.set(candidate.name, forKey: lastUsedModelNameKey)
        return content
    }

    private static func responseDetails(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any] {
                return sanitizedDetail((error["message"] as? String) ?? (error["code"] as? String) ?? "")
            }
            if let message = json["message"] as? String {
                return sanitizedDetail(message)
            }
        }
        return sanitizedDetail(String(data: data, encoding: .utf8) ?? "")
    }

    private static func retryAfterSeconds(from response: HTTPURLResponse?) -> Int? {
        guard let value = response?.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = Int(value) {
            return seconds
        }
        if let date = HTTPDateFormatter.shared.date(from: value) {
            return max(1, Int(date.timeIntervalSinceNow.rounded(.up)))
        }
        return nil
    }

    private static func sanitizedDetail(_ value: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "" }
        return String(collapsed.prefix(180))
    }

    private static func decodeScenario(from text: String) throws -> ScenarioPayload {
        let jsonText = extractJSON(from: text, opening: "{", closing: "}") ?? text
        guard let data = jsonText.data(using: .utf8) else { throw OpenRouterError.invalidResponse }
        return try JSONDecoder().decode(ScenarioPayload.self, from: data)
    }

    private static func decodeTimelinePlan(from text: String) throws -> [TimelineEditInstruction] {
        let jsonText: String
        if let array = extractJSON(from: text, opening: "[", closing: "]") {
            jsonText = array
        } else if let object = extractJSON(from: text, opening: "{", closing: "}") {
            jsonText = "[\(object)]"
        } else {
            jsonText = text
        }
        guard let data = jsonText.data(using: .utf8) else { throw OpenRouterError.invalidResponse }
        return try JSONDecoder().decode([TimelineEditInstruction].self, from: data)
    }

    private static func extractJSON(from text: String, opening: Character, closing: Character) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: opening), let end = trimmed.lastIndex(of: closing), start <= end else {
            return nil
        }
        return String(trimmed[start...end])
    }

    private struct OpenRouterChatRequest: Encodable {
        let model: String
        let messages: [OpenRouterMessage]
        let temperature: Double
        let maxTokens: Int

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case maxTokens = "max_tokens"
        }
    }

    private struct OpenRouterModelCandidate {
        let id: String
        let name: String
    }

    private static func freeTextModel(from item: [String: Any]) -> FreeModel? {
        guard let id = item["id"] as? String else { return nil }
        let lowerId = id.lowercased()
        let architecture = item["architecture"] as? [String: Any]
        let outputModalities = architecture?["output_modalities"] as? [String] ?? []
        let inputModalities = architecture?["input_modalities"] as? [String] ?? []
        let modality = architecture?["modality"] as? String ?? ""
        let searchable = ([lowerId, modality.lowercased()] + outputModalities + inputModalities)
            .joined(separator: " ")
            .lowercased()

        let isFree = lowerId.hasSuffix(":free") || pricingIsFree(item["pricing"] as? [String: Any])
        let isTextCapable = searchable.contains("text") || searchable.contains("chat") || searchable.contains("language")
        let isNonTextPrimary = searchable.contains("video")
            || searchable.contains("image")
            || searchable.contains("audio")
            || searchable.contains("embedding")
        guard isFree, isTextCapable, !isNonTextPrimary else { return nil }

        let rawName = (item["name"] as? String) ?? readableModelName(id)
        return FreeModel(id: id, name: shortFreeModelName(rawName, fallbackId: id))
    }

    private static func pricingIsFree(_ pricing: [String: Any]?) -> Bool {
        guard let pricing else { return false }
        let prompt = doubleValue(pricing["prompt"])
        let completion = doubleValue(pricing["completion"])
        guard let prompt, let completion else { return false }
        return prompt == 0 && completion == 0
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func readableModelName(_ id: String) -> String {
        let tail = id.split(separator: "/").last.map(String.init) ?? id
        return tail
            .replacingOccurrences(of: ":free", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func shortFreeModelName(_ name: String, fallbackId: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: ":free", with: "")
            .replacingOccurrences(of: "NVIDIA: ", with: "")
            .replacingOccurrences(of: "Qwen: ", with: "")
            .replacingOccurrences(of: "Meta: ", with: "")
            .replacingOccurrences(of: "OpenAI: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? readableModelName(fallbackId) : String(cleaned.prefix(32))
    }

    private struct OpenRouterMessage: Codable {
        let role: String
        let content: String
    }

    private struct OpenRouterChatResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: OpenRouterMessage
        }
    }

    private struct ScenarioPayload: Decodable {
        let topic: String
        let scenes: [Scene]

        struct Scene: Decodable {
            let searchQuery: String
            let subtitleText: String
            let voiceoverText: String
            let durationSeconds: Double
        }
    }
}

struct TimelineEditInstruction: Codable, Equatable {
    let action: String
    let clipIndex: Int?
    let fromIndex: Int?
    let toIndex: Int?
    let allClips: Bool?
    let trimStart: Double?
    let trimEnd: Double?
    let beatDuration: Double?
    let splitAt: Double?
    let speed: Double?
    let text: String?
    let enabled: Bool?
    let aspectRatio: String?
    let musicVolume: Double?
    let musicStart: Double?
    let musicEnd: Double?
    let musicMood: String?

    init(
        action: String,
        clipIndex: Int? = nil,
        fromIndex: Int? = nil,
        toIndex: Int? = nil,
        allClips: Bool? = nil,
        trimStart: Double? = nil,
        trimEnd: Double? = nil,
        beatDuration: Double? = nil,
        splitAt: Double? = nil,
        speed: Double? = nil,
        text: String? = nil,
        enabled: Bool? = nil,
        aspectRatio: String? = nil,
        musicVolume: Double? = nil,
        musicStart: Double? = nil,
        musicEnd: Double? = nil,
        musicMood: String? = nil
    ) {
        self.action = action
        self.clipIndex = clipIndex
        self.fromIndex = fromIndex
        self.toIndex = toIndex
        self.allClips = allClips
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.beatDuration = beatDuration
        self.splitAt = splitAt
        self.speed = speed
        self.text = text
        self.enabled = enabled
        self.aspectRatio = aspectRatio
        self.musicVolume = musicVolume
        self.musicStart = musicStart
        self.musicEnd = musicEnd
        self.musicMood = musicMood
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private enum FoundationScenarioGenerator {
    static var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        default:
            return false
        }
    }

    static func generateScript(topic: String, language: String, clipCount: Int) async throws -> LocalScriptGenerator.GeneratedScript {
        guard isAvailable else { throw AppleIntelligenceScenarioGenerator.ScenarioError.unavailable }

        let session = LanguageModelSession {
            ScenarioQualityGate.systemPrompt
        }

        let requestedCount = max(3, min(8, clipCount))
        let prompt = ScenarioQualityGate.userPrompt(topic: topic, language: language, requestedCount: requestedCount)

        let response = try await session.respond(to: prompt)
        let payload = try decodeScenario(from: response.content)
        let scenes = payload.scenes.prefix(requestedCount).map { scene in
            LocalScriptGenerator.SceneScript(
                searchQuery: scene.searchQuery,
                subtitleText: scene.subtitleText,
                voiceoverText: scene.voiceoverText,
                durationSeconds: max(1.5, min(5.0, scene.durationSeconds))
            )
        }

        guard !scenes.isEmpty else {
            throw AppleIntelligenceScenarioGenerator.ScenarioError.invalidResponse
        }

        let script = LocalScriptGenerator.GeneratedScript(
            topic: payload.topic.isEmpty ? topic : payload.topic,
            scenes: Array(scenes),
            fullVoiceover: scenes.map(\.voiceoverText).joined(separator: " "),
            totalDuration: scenes.reduce(0) { $0 + $1.durationSeconds }
        )
        try ScenarioQualityGate.validate(script, originalTopic: topic)
        return script
    }

    static func generateSingleClipPrompt(topic: String, language: String, duration: Int) async throws -> String {
        guard isAvailable else { throw AppleIntelligenceScenarioGenerator.ScenarioError.unavailable }

        let session = LanguageModelSession {
            """
            You write concise prompts for vertical AI video generation.
            Return only the final prompt. No markdown. No commentary.
            Make the prompt visual, concrete, camera-aware, and suitable for a single short clip.
            """
        }

        let prompt = """
        Rewrite this idea into one high-quality AI video prompt.
        Language code: \(language)
        Duration: \(duration) seconds
        Idea:
        \(topic)
        """

        let response = try await session.respond(to: prompt)
        let generatedPrompt = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !generatedPrompt.isEmpty else {
            throw AppleIntelligenceScenarioGenerator.ScenarioError.invalidResponse
        }
        return generatedPrompt
    }

    static func generateTimelineEditPlan(request: String, timelineSummary: String, language: String) async throws -> [TimelineEditInstruction] {
        guard isAvailable else { throw AppleIntelligenceScenarioGenerator.ScenarioError.unavailable }

        let session = LanguageModelSession {
            """
            You are a video editor agent for CreatorAI.
            Return only JSON. No markdown. No commentary.
            Choose safe timeline edits using only these action values:
            selectClip, moveClip, trimClip, splitClip, duplicateClip, deleteClip, removeBadTakes, setSpeed, muteClip, unmuteClip, muteMusic, unmuteMusic, muteVoiceover, unmuteVoiceover, setCaption, setCaptionsEnabled, setAspectRatio, setBeatDuration, syncBeatCuts, setMusic, playAll.
            Clip indexes are zero-based. Never delete the only clip. Keep trimStart below trimEnd. For ad pacing, use beatDuration between 0.1 and 2.0 seconds.
            For speed, use setSpeed with clipIndex for one clip, or setSpeed with allClips true to change every clip. Speed must be 0.1 to 5.0.
            For mute tools, use muteClip/unmuteClip with clipIndex, muteMusic/unmuteMusic for music rows, and muteVoiceover/unmuteVoiceover for voiceover.
            For music, use setMusic with musicMood, musicVolume, musicStart, and musicEnd. Lower musicVolume when voiceover exists.
            For "cut current clip", return splitClip with the currently selected or most relevant clipIndex.
            For "remove bad takes", return removeBadTakes unless the user names one exact clip to delete.
            """
        }

        let prompt = """
        User request language code: \(language)
        User request:
        \(request)

        Current timeline:
        \(timelineSummary)

        Return a JSON array. Each item can contain:
        {
          "action": "trimClip",
          "clipIndex": 0,
          "fromIndex": 0,
          "toIndex": 1,
          "allClips": false,
          "trimStart": 5,
          "trimEnd": 90,
          "beatDuration": 1.5,
          "splitAt": 0.8,
          "speed": 1.25,
          "text": "caption text",
          "enabled": true,
          "aspectRatio": "9:16",
          "musicMood": "upbeat",
          "musicVolume": 0.25,
          "musicStart": 0,
          "musicEnd": 15
        }
        """

        let response = try await session.respond(to: prompt)
        return try decodeTimelinePlan(from: response.content)
    }

    private static func decodeScenario(from text: String) throws -> ScenarioPayload {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String

        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            jsonText = String(trimmed[start...end])
        } else {
            jsonText = trimmed
        }

        guard let data = jsonText.data(using: .utf8) else {
            throw AppleIntelligenceScenarioGenerator.ScenarioError.invalidResponse
        }

        return try JSONDecoder().decode(ScenarioPayload.self, from: data)
    }

    private static func decodeTimelinePlan(from text: String) throws -> [TimelineEditInstruction] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String

        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]") {
            jsonText = String(trimmed[start...end])
        } else if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            jsonText = "[\(String(trimmed[start...end]))]"
        } else {
            jsonText = trimmed
        }

        guard let data = jsonText.data(using: .utf8) else {
            throw AppleIntelligenceScenarioGenerator.ScenarioError.invalidResponse
        }

        return try JSONDecoder().decode([TimelineEditInstruction].self, from: data)
    }

    private struct ScenarioPayload: Decodable {
        let topic: String
        let scenes: [Scene]
    }

    private struct Scene: Decodable {
        let searchQuery: String
        let subtitleText: String
        let voiceoverText: String
        let durationSeconds: Double
    }
}
#endif
