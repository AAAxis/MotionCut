package com.theholylabs.creator.services

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.provider.MediaStore
import androidx.media3.common.util.UnstableApi
import com.theholylabs.creator.models.Clip
import com.theholylabs.creator.models.Generation
import com.theholylabs.creator.models.GenerationStatus
import com.theholylabs.creator.models.MusicTrack
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

@UnstableApi
object BackgroundRenderService {

    suspend fun startExport(
        context: Context,
        videoName: String,
        clips: List<Clip>,
        aspectRatio: String,
        exportQuality: String,
        userId: String?,
        selectedMusic: MusicTrack?,
        musicVolume: Float,
        addCaptionsViaCloud: Boolean,
        burnSubtitles: Boolean = false,
        subtitleYPosition: Float = 0.80f,
        existingGenerationId: String? = null,
        onStatusUpdate: (GenerationStatus) -> Unit,
        onProgress: (String) -> Unit
    ): String? {
        val generationId = existingGenerationId ?: UUID.randomUUID().toString()
        val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)

        // Create initial generation record
        val generation = Generation(
            id = generationId,
            videoName = videoName,
            status = GenerationStatus.PROCESSING,
            createdAt = dateFormat.format(Date()),
            userId = userId
        )

        onStatusUpdate(GenerationStatus.PROCESSING)
        onProgress("Starting export...")

        // Resolve music file
        var musicFile: File? = null
        if (selectedMusic != null) {
            val musicPath = selectedMusic.file
            val localFile = File(musicPath)
            if (localFile.exists()) {
                // Local file (e.g. voiceover) — use directly
                musicFile = localFile
            } else {
                // Remote URL — download and cache
                onProgress("Downloading music...")
                musicFile = AudioMixerService.downloadAndCacheMusic(musicPath, selectedMusic.id)
            }
        }

        // Render the video
        val result = VideoRenderService.renderVideo(
            context = context,
            clips = clips,
            musicFile = musicFile,
            musicVolume = musicVolume,
            aspectRatio = aspectRatio,
            exportQuality = exportQuality,
            burnSubtitles = burnSubtitles,
            subtitleYPosition = subtitleYPosition,
            onProgress = onProgress
        )

        if (result != null && result.exists() && result.length() > 1000) {
            // Copy to persistent storage
            val savedFile = FileStorageService.copyToSavedVideos(result, generationId)

            // Save to device gallery
            saveToGallery(context, savedFile, videoName)

            // Build takesJson so the editor can restore all clips when re-opened
            val takesJson = try {
                kotlinx.serialization.json.Json.encodeToString(
                    kotlinx.serialization.builtins.ListSerializer(Clip.serializer()),
                    clips
                )
            } catch (_: Exception) { null }

            // Resolve music path for re-opening
            val musicPath = musicFile?.absolutePath

            // Save to local library
            val gen = Generation(
                id = generationId,
                videoName = videoName,
                videoUri = savedFile.absolutePath,
                status = GenerationStatus.SAVED,
                createdAt = dateFormat.format(Date()),
                userId = userId,
                takesJson = takesJson,
                musicPath = musicPath
            )
            GenerationService.saveGenerationLocal(context, gen)

            onStatusUpdate(GenerationStatus.SAVED)
            onProgress("Video saved!")

            NotificationService.notifyVideoReady(context, videoName)

            return generationId
        } else {
            onStatusUpdate(GenerationStatus.FAILED)
            onProgress("Export failed")

            NotificationService.notifyVideoFailed(context, videoName)
            return null
        }
    }

    private suspend fun saveToGallery(context: Context, videoFile: File, name: String) = withContext(Dispatchers.IO) {
        try {
            val contentValues = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, "$name.mp4")
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/CreatorAI")
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }
            }

            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, contentValues) ?: return@withContext

            resolver.openOutputStream(uri)?.use { output ->
                videoFile.inputStream().use { input ->
                    input.copyTo(output)
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentValues.clear()
                contentValues.put(MediaStore.Video.Media.IS_PENDING, 0)
                resolver.update(uri, contentValues, null, null)
            }
        } catch (e: Exception) {
            // Gallery save failed, video is still in app storage
        }
    }
}
