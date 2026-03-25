package com.theholylabs.creator.services

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import com.theholylabs.creator.models.Clip
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

@UnstableApi
object VideoRenderService {

    suspend fun renderVideo(
        context: Context,
        clips: List<Clip>,
        musicFile: File? = null,
        musicVolume: Float = 0.5f,
        aspectRatio: String = "9:16",
        exportQuality: String = "original",
        onProgress: (String) -> Unit = {}
    ): File? = withContext(Dispatchers.Main) {
        if (clips.isEmpty()) return@withContext null

        val outputFile = File(FileStorageService.renderedVideosDir, "render_${UUID.randomUUID()}.mp4")

        try {
            onProgress("Preparing clips...")

            // Build edited media items for each clip
            val editedItems = clips.mapNotNull { clip ->
                val uri = clip.localUri ?: clip.uri
                if (uri.isEmpty()) return@mapNotNull null

                val mediaItem = buildClipMediaItem(clip, uri)
                EditedMediaItem.Builder(mediaItem).build()
            }

            if (editedItems.isEmpty()) {
                onProgress("No valid clips")
                return@withContext null
            }

            onProgress("Rendering video...")

            val videoSequence = EditedMediaItemSequence(editedItems)

            val sequences = mutableListOf(videoSequence)

            // Add music track if available
            if (musicFile != null && musicFile.exists()) {
                val musicMediaItem = MediaItem.Builder()
                    .setUri(musicFile.absolutePath)
                    .build()
                val musicEditedItem = EditedMediaItem.Builder(musicMediaItem).build()
                val musicSequence = EditedMediaItemSequence(listOf(musicEditedItem))
                sequences.add(musicSequence)
            }

            val composition = Composition.Builder(sequences).build()

            val transformer = Transformer.Builder(context)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .build()

            val result = suspendCancellableCoroutine<File?> { continuation ->
                transformer.addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        onProgress("Export complete!")
                        continuation.resume(outputFile)
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException
                    ) {
                        onProgress("Export failed: ${exportException.message}")
                        continuation.resume(null)
                    }
                })

                transformer.start(composition, outputFile.absolutePath)

                continuation.invokeOnCancellation {
                    transformer.cancel()
                }
            }

            result
        } catch (e: Exception) {
            onProgress("Render error: ${e.message}")
            null
        }
    }

    private fun buildClipMediaItem(clip: Clip, uri: String): MediaItem {
        val builder = MediaItem.Builder().setUri(uri)

        val isReelMode = clip.beatDuration != null
        if (isReelMode) {
            val beatDur = clip.beatDuration!!
            val srcDur = clip.sourceDuration ?: 10.0
            val maxStart = max(0.0, srcDur - beatDur - 0.5)
            val startOffset = Random.nextDouble(0.0, max(0.01, maxStart))
            val startMs = (startOffset * 1000).toLong()
            val endMs = ((startOffset + beatDur) * 1000).toLong()

            builder.setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .build()
            )
        } else {
            // Apply trim percentages
            val srcDur = clip.sourceDuration ?: 0.0
            if (srcDur > 0 && (clip.trimStart > 0 || clip.trimEnd < 100)) {
                val startMs = (clip.trimStart / 100.0 * srcDur * 1000).toLong()
                val endMs = (clip.trimEnd / 100.0 * srcDur * 1000).toLong()
                builder.setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(startMs)
                        .setEndPositionMs(endMs)
                        .build()
                )
            }
        }

        return builder.build()
    }
}
