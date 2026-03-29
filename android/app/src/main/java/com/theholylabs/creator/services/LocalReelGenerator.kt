package com.theholylabs.creator.services

import android.content.Context
import android.util.Log
import androidx.media3.common.util.UnstableApi
import com.theholylabs.creator.models.Clip
import com.theholylabs.creator.models.Generation
import com.theholylabs.creator.models.GenerationStatus
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
 * 3. LocalTTSService → generates voiceover audio
 * 4. VideoRenderService → composites clips into final MP4
 *
 * Zero cost. No backend. No API keys (except Pexels free tier).
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

            val clips = mutableListOf<Clip>()
            val subtitles = mutableListOf<SubtitleEntry>()
            var timeOffset = 0.0
            val usedVideoIds = mutableSetOf<Int>()

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
                    Log.w(TAG, "All download attempts failed for clip $index, skipping")
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

            if (clips.isEmpty()) {
                return@withContext LocalReelResult(
                    success = false,
                    error = "Could not download footage. Check your internet connection."
                )
            }

            // Step 4: Generate voiceover with TTS
            onProgress(GenerationProgress("Generating voiceover...", 0.65f))
            Log.d(TAG, "Step 4: Generating voiceover")

            val voiceoverFiles = LocalTTSService.synthesizeScenes(
                scenes = script.scenes.take(clips.size),
                language = language,
                outputDir = jobDir
            )

            Log.d(TAG, "Generated ${voiceoverFiles.size} voiceover files")
            LocalTTSService.shutdown()

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
