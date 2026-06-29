package com.theholylabs.creator.services

import android.content.Context
import android.util.Log
import androidx.media3.common.util.UnstableApi
import com.theholylabs.creator.models.Clip
import com.theholylabs.creator.models.PRESET_AI_MODELS
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * Orchestrates the fully local, free video generation pipeline:
 *
 * 1. LocalScriptGenerator → generates script from user prompt
 * 2. PexelsService → fetches stock footage for each scene
 * 3. Optional voiceover audio
 * 4. Saves editable clips for the editor
 *
 * Pexels runs without backend. AI scenes use the user's configured provider key.
 */
@UnstableApi
object LocalReelGenerator {

    private const val TAG = "LocalReelGenerator"

    data class GenerationProgress(
        val step: String,
        val progress: Float // 0.0 to 1.0
    )

    /**
     * Generate a complete stock footage reel from a text prompt.
     * All processing happens on-device.
     */
    suspend fun generate(
        context: Context,
        topic: String,
        language: String = "en",
        clipCount: Int = 6,
        aiModelId: String = PRESET_AI_MODELS.firstOrNull()?.id ?: "fal-ai/kling-video/v2.6/pro/text-to-video",
        sourceMode: String = "smart",
        voiceoverMode: String = "none",
        userId: String? = null,
        onProgress: (GenerationProgress) -> Unit = {}
    ): LocalReelResult = withContext(Dispatchers.IO) {

        val generationId = UUID.randomUUID().toString()
        val jobDir = File(context.cacheDir, "local_reel_$generationId")
        jobDir.mkdirs()

        try {
            // Step 1: Generate script locally
            onProgress(GenerationProgress("Generating script...", 0.1f))
            Log.d(TAG, "Step 1: Generating script for topic: $topic")

            val script = LocalScriptGenerator.generateScript(
                topic = topic,
                language = language,
                clipCount = clipCount
            )

            Log.d(TAG, "Script generated: ${script.scenes.size} scenes")

            val clips = mutableListOf<Clip>()
            val subtitles = mutableListOf<SubtitleEntry>()
            var timeOffset = 0.0
            val usedVideoIds = mutableSetOf<Int>()

            if (sourceMode == "ai") {
                onProgress(GenerationProgress("Generating AI scenes...", 0.25f))
                Log.d(TAG, "Step 2: Generating ${script.scenes.size} AI scenes with $aiModelId")

                for ((index, scene) in script.scenes.withIndex()) {
                    val generatedClip = generateAiSceneClip(context, scene, index, jobDir, aiModelId, userId)
                    if (generatedClip != null) {
                        clips.add(generatedClip)
                        subtitles.add(
                            SubtitleEntry(
                                text = scene.subtitleText,
                                startTime = timeOffset,
                                endTime = timeOffset + scene.durationSeconds
                            )
                        )
                        timeOffset += scene.durationSeconds
                    }
                    val clipProgress = 0.25f + (0.35f * (index + 1) / script.scenes.size)
                    onProgress(GenerationProgress("Generated AI scene ${index + 1}/${script.scenes.size}", clipProgress))
                }
            } else {
                // Step 2: Search Pexels for footage (parallel)
                onProgress(GenerationProgress("Finding footage...", 0.25f))
                Log.d(TAG, "Step 2: Searching Pexels for ${script.scenes.size} scenes")

                val footageResults = withContext(Dispatchers.IO) {
                    script.scenes.map { scene ->
                        async {
                            val results = PexelsService.searchVideos(
                                query = scene.searchQuery,
                                perPage = 5,
                                orientation = "portrait"
                            )
                            scene to results
                        }
                    }.awaitAll()
                }

                // Step 3: Download footage clips
                onProgress(GenerationProgress("Downloading clips...", 0.4f))
                Log.d(TAG, "Step 3: Downloading footage clips")

                for ((index, pair) in footageResults.withIndex()) {
                    val (scene, pexelsVideos) = pair

                    val video = pexelsVideos.firstOrNull { it.id !in usedVideoIds } ?: pexelsVideos.firstOrNull() ?: continue
                    usedVideoIds.add(video.id)

                    val clipFile = File(jobDir, "clip_$index.mp4")
                    var downloaded = false
                    // Try all available results until one downloads successfully
                    val candidates = listOf(video) + pexelsVideos.filter { it.id != video.id }
                    for (candidate in candidates) {
                        try {
                            FileStorageService.downloadFile(candidate.videoUrl, clipFile)
                            if (clipFile.exists() && clipFile.length() > 1000) {
                                downloaded = true
                                usedVideoIds.add(candidate.id)
                                break
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to download clip $index from video ${candidate.id}: ${e.message}")
                        }
                    }
                    if (!downloaded) {
                        Log.w(TAG, "All download attempts failed for clip $index, trying AI generation")
                        val generatedClip = generateAiSceneClip(context, scene, index, jobDir, aiModelId, userId)
                        if (generatedClip == null) continue
                        clips.add(generatedClip)
                        subtitles.add(
                            SubtitleEntry(
                                text = scene.subtitleText,
                                startTime = timeOffset,
                                endTime = timeOffset + scene.durationSeconds
                            )
                        )
                        timeOffset += scene.durationSeconds
                        val clipProgress = 0.4f + (0.2f * (index + 1) / footageResults.size)
                        onProgress(GenerationProgress("Generated AI scene ${index + 1}/${footageResults.size}", clipProgress))
                        continue
                    }

                    val beatDuration = scene.durationSeconds
                    clips.add(
                        Clip(
                            id = index,
                            uri = clipFile.absolutePath,
                            name = "Scene ${index + 1}",
                            beatDuration = beatDuration,
                            sourceDuration = video.duration.toDouble(),
                            text = scene.subtitleText,
                            localUri = clipFile.absolutePath
                        )
                    )

                    subtitles.add(
                        SubtitleEntry(
                            text = scene.subtitleText,
                            startTime = timeOffset,
                            endTime = timeOffset + beatDuration
                        )
                    )
                    timeOffset += beatDuration

                    val clipProgress = 0.4f + (0.2f * (index + 1) / footageResults.size)
                    onProgress(GenerationProgress("Downloaded ${index + 1}/${footageResults.size} clips", clipProgress))
                }

                // If no clips from specific queries, try with the raw topic
                if (clips.isEmpty()) {
                    Log.w(TAG, "No clips from scene queries, trying raw topic search")
                    val fallbackVideos = PexelsService.searchVideos(
                        query = topic.split(" ").take(3).joinToString(" "),
                        perPage = 6,
                        orientation = "portrait"
                    )
                    for ((index, video) in fallbackVideos.withIndex()) {
                        val clipFile = File(jobDir, "clip_$index.mp4")
                        try {
                            FileStorageService.downloadFile(video.videoUrl, clipFile)
                            clips.add(
                                Clip(
                                    id = index,
                                    uri = clipFile.absolutePath,
                                    name = "Scene ${index + 1}",
                                    beatDuration = 2.5,
                                    sourceDuration = video.duration.toDouble(),
                                    text = script.scenes.getOrNull(index)?.subtitleText ?: topic,
                                    localUri = clipFile.absolutePath
                                )
                            )
                        } catch (_: Exception) { continue }
                    }
                }
            }

            if (clips.isEmpty()) {
                return@withContext LocalReelResult(
                    success = false,
                    error = if (sourceMode == "ai") {
                        "AI model did not return any videos. Check your fal.ai key and model access."
                    } else {
                        "Could not download or generate footage. Check your internet connection."
                    }
                )
            }

            // Step 4: Voice is optional. Free/default mode does not generate local TTS.
            val voiceoverFiles = if (voiceoverMode == "local") {
                onProgress(GenerationProgress("Generating voiceover...", 0.65f))
                Log.d(TAG, "Step 4: Generating voiceover")
                LocalTTSService.synthesizeScenes(
                    scenes = script.scenes.take(clips.size),
                    language = language,
                    outputDir = jobDir
                ).also {
                    Log.d(TAG, "Generated ${it.size} voiceover files")
                    LocalTTSService.shutdown()
                }
            } else {
                onProgress(GenerationProgress("Skipping voiceover...", 0.65f))
                emptyList()
            }

            // Step 5: Save clips (skip rendering — user edits in editor)
            onProgress(GenerationProgress("Saving clips...", 0.9f))
            Log.d(TAG, "Step 5: Saving ${clips.size} clips for editor")

            // Copy clip files to permanent storage so they survive cache cleanup
            val savedClips = clips.map { clip ->
                val srcFile = File(clip.localUri ?: clip.uri)
                if (srcFile.exists()) {
                    val destFile = File(FileStorageService.savedVideosDir, "${generationId}_clip_${clip.id}.mp4")
                    srcFile.copyTo(destFile, overwrite = true)
                    clip.copy(uri = destFile.absolutePath, localUri = destFile.absolutePath)
                } else clip
            }

            // Save voiceover to permanent storage if available
            val savedVoiceover = if (voiceoverFiles.isNotEmpty()) {
                val merged = mergeAudioFiles(voiceoverFiles, File(jobDir, "voiceover_merged.wav"))
                if (merged != null && merged.exists()) {
                    val destVo = File(FileStorageService.savedVideosDir, "${generationId}_voiceover.wav")
                    merged.copyTo(destVo, overwrite = true)
                    destVo
                } else null
            } else null

            Log.d(TAG, "Generation complete: ${savedClips.size} clips saved")
            onProgress(GenerationProgress("Done!", 1.0f))

            // Build takesJson for the video editor
            val takesJson = kotlinx.serialization.json.Json.encodeToString(
                kotlinx.serialization.builtins.ListSerializer(Clip.serializer()),
                savedClips
            )

            // Don't save generation record here — only save when user
            // taps Save/Export in the editor. This avoids duplicate entries.
            val firstClipPath = savedClips.firstOrNull()?.localUri

            LocalReelResult(
                success = true,
                generationId = generationId,
                videoPath = firstClipPath,
                voiceoverPath = savedVoiceover?.absolutePath,
                subtitles = subtitles,
                takesJson = takesJson,
                script = script
            )

        } catch (e: Exception) {
            Log.e(TAG, "Generation failed: ${e.message}", e)
            LocalReelResult(
                success = false,
                error = e.message ?: "Unknown error"
            )
        } finally {
            // Clean up temp files (keep saved video)
            try {
                jobDir.listFiles()?.forEach { it.delete() }
                jobDir.delete()
            } catch (_: Exception) {}
        }
    }

    private suspend fun generateAiSceneClip(
        context: Context,
        scene: SceneScript,
        index: Int,
        jobDir: File,
        modelId: String,
        userId: String?
    ): Clip? {
        val generationDuration = scene.durationSeconds.coerceIn(5.0, 10.0).toInt()
        val prompt = """
            Vertical ad scene, $generationDuration seconds.
            Visual: ${scene.searchQuery}.
            Moment: ${scene.voiceoverText}
            Cinematic, natural movement, realistic lighting, no text overlay.
        """.trimIndent()

        return try {
            val response = GenerationService.startAICreate(
                modelId = modelId,
                prompt = prompt,
                imageUrl = null,
                duration = generationDuration,
                userId = userId,
                context = context
            )
            val generationId = response?.id
            if (generationId == null || response.error != null) {
                Log.w(TAG, "AI scene start failed: ${response?.error ?: "missing id"}")
                return null
            }

            repeat(36) {
                kotlinx.coroutines.delay(5_000)
                val status = GenerationService.pollAICreate(generationId)
                when (status?.status) {
                    "succeeded" -> {
                        val outputUrl = status.outputUrl ?: return null
                        val clipFile = File(jobDir, "clip_${index}_ai.mp4")
                        FileStorageService.downloadFile(outputUrl, clipFile)
                        return Clip(
                            id = index,
                            uri = clipFile.absolutePath,
                            name = "Scene ${index + 1} · AI",
                            beatDuration = scene.durationSeconds,
                            sourceDuration = generationDuration.toDouble(),
                            text = scene.subtitleText,
                            localUri = clipFile.absolutePath
                        )
                    }
                    "failed", "canceled" -> return null
                }
            }
            null
        } catch (e: Exception) {
            Log.w(TAG, "AI scene generation failed: ${e.message}")
            null
        }
    }

    /**
     * Simple audio concatenation — appends WAV files sequentially.
     * For a production app, consider using Media3 or FFmpeg for proper mixing.
     */
    private fun mergeAudioFiles(files: List<File>, output: File): File? {
        if (files.isEmpty()) return null
        if (files.size == 1) return files.first()

        try {
            // Simple approach: use the first file as the merged result.
            // Media3 Transformer will handle mixing video + single audio.
            // For multiple voiceover segments, we concatenate the raw audio bytes.
            output.outputStream().use { out ->
                files.forEachIndexed { index, file ->
                    if (file.exists()) {
                        val bytes = file.readBytes()
                        if (index == 0) {
                            // Write full WAV including header
                            out.write(bytes)
                        } else if (bytes.size > 44) {
                            // Skip WAV header (44 bytes) for subsequent files
                            out.write(bytes, 44, bytes.size - 44)
                        }
                    }
                }
            }

            // Update the WAV header with correct file size
            updateWavHeader(output)
            return output
        } catch (e: Exception) {
            Log.e(TAG, "Failed to merge audio files: ${e.message}")
            return files.firstOrNull()
        }
    }

    private fun updateWavHeader(wavFile: File) {
        val raf = java.io.RandomAccessFile(wavFile, "rw")
        try {
            val fileSize = raf.length()
            // Update RIFF chunk size (offset 4, 4 bytes, little-endian)
            raf.seek(4)
            val riffSize = (fileSize - 8).toInt()
            raf.write(byteArrayOf(
                (riffSize and 0xFF).toByte(),
                ((riffSize shr 8) and 0xFF).toByte(),
                ((riffSize shr 16) and 0xFF).toByte(),
                ((riffSize shr 24) and 0xFF).toByte()
            ))
            // Update data chunk size (offset 40, 4 bytes, little-endian)
            raf.seek(40)
            val dataSize = (fileSize - 44).toInt()
            raf.write(byteArrayOf(
                (dataSize and 0xFF).toByte(),
                ((dataSize shr 8) and 0xFF).toByte(),
                ((dataSize shr 16) and 0xFF).toByte(),
                ((dataSize shr 24) and 0xFF).toByte()
            ))
        } finally {
            raf.close()
        }
    }
}

data class LocalReelResult(
    val success: Boolean,
    val generationId: String? = null,
    val videoPath: String? = null,
    val voiceoverPath: String? = null,
    val subtitles: List<SubtitleEntry>? = null,
    val takesJson: String? = null,
    val script: GeneratedScript? = null,
    val error: String? = null
)

data class SubtitleEntry(
    val text: String,
    val startTime: Double,
    val endTime: Double
)
