package com.theholylabs.creator.services

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.OverlaySettings
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import com.theholylabs.creator.models.Clip
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.math.max
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
        burnSubtitles: Boolean = false,
        subtitleYPosition: Float = 0.80f,
        includeBranding: Boolean = true,
        onProgress: (String) -> Unit = {}
    ): File? = withContext(Dispatchers.Main) {
        if (clips.isEmpty()) return@withContext null

        val outputFile = File(FileStorageService.renderedVideosDir, "render_${UUID.randomUUID()}.mp4")

        try {
            onProgress("Preparing clips...")
            android.util.Log.d("VideoRender", "renderVideo: ${clips.size} clips, music=${musicFile?.absolutePath}, burnSubs=$burnSubtitles")

            // Build edited media items for each clip with subtitle overlay
            val editedItems = clips.mapNotNull { clip ->
                val uri = clip.localUri ?: clip.uri
                if (uri.isEmpty()) {
                    android.util.Log.w("VideoRender", "Skipping clip ${clip.id}: empty URI")
                    return@mapNotNull null
                }

                // Verify file exists for local paths
                if (!uri.startsWith("content://") && !uri.startsWith("http")) {
                    val file = File(uri)
                    if (!file.exists()) {
                        android.util.Log.w("VideoRender", "Skipping clip ${clip.id}: file not found: $uri")
                        return@mapNotNull null
                    }
                }

                android.util.Log.d("VideoRender", "Clip ${clip.id}: uri=$uri, trimStart=${clip.trimStart}, trimEnd=${clip.trimEnd}, beatDur=${clip.beatDuration}, srcDur=${clip.sourceDuration}")
                val mediaItem = buildClipMediaItem(clip, uri)
                val builder = EditedMediaItem.Builder(mediaItem)

                // Strip clip audio when music/voiceover will be mixed in
                if (musicFile != null && musicFile.exists()) {
                    builder.setRemoveAudio(true)
                }

                // Build overlay list: watermark + optional subtitle
                val overlays = mutableListOf<TextureOverlay>()

                if (includeBranding) {
                    // CreatorAI watermark (bottom-right corner)
                    val watermarkBitmap = createWatermarkBitmap(context)
                    overlays.add(
                        BitmapOverlay.createStaticBitmapOverlay(
                            watermarkBitmap,
                            OverlaySettings.Builder().build()
                        )
                    )
                }

                // Burn subtitle overlay if enabled and clip has text
                if (burnSubtitles && !clip.text.isNullOrBlank()) {
                    val subtitleBitmap = createSubtitleBitmap(clip.text, subtitleYPosition)
                    overlays.add(
                        BitmapOverlay.createStaticBitmapOverlay(
                            subtitleBitmap,
                            OverlaySettings.Builder().build()
                        )
                    )
                }

                if (overlays.isNotEmpty()) {
                    @Suppress("UNCHECKED_CAST")
                    val overlayEffect = OverlayEffect(ImmutableList.copyOf(overlays) as ImmutableList<TextureOverlay>)
                    builder.setEffects(
                        androidx.media3.transformer.Effects(
                            listOf(),
                            listOf(overlayEffect)
                        )
                    )
                }

                builder.build()
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

            val composition = Composition.Builder(sequences)
                // Tone-map HDR to SDR so clips with different color spaces don't crash
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                // Force audio track: needed when some clips lack audio tracks.
                // Duration is always known because reel clips have clipping endPositionMs,
                // and non-reel clips get sourceDuration probed before export.
                .experimentalSetForceAudioTrack(true)
                .build()

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
                        android.util.Log.e("VideoRender", "Transformer export failed", exportException)
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
            android.util.Log.e("VideoRender", "Render exception", e)
            onProgress("Render error: ${e.message}")
            null
        }
    }

    private fun buildClipMediaItem(clip: Clip, uri: String): MediaItem {
        val builder = MediaItem.Builder().setUri(uri)

        val isReelMode = clip.beatDuration != null
        if (isReelMode) {
            // Clip from start to beatDuration — avoids seek issues with
            // progressive MP4s (moov atom at end) from Pexels downloads
            val endMs = (clip.beatDuration!! * 1000).toLong()
            builder.setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setEndPositionMs(endMs)
                    .build()
            )
        } else {
            // Apply trim percentages
            val srcDur = clip.sourceDuration ?: 0.0
            if (srcDur > 0) {
                val startMs = (clip.trimStart / 100.0 * srcDur * 1000).toLong()
                val endMs = (clip.trimEnd / 100.0 * srcDur * 1000).toLong()
                if (startMs == 0L) {
                    // Only set end position — always seekable from 0
                    builder.setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setEndPositionMs(endMs)
                            .build()
                    )
                } else {
                    builder.setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(startMs)
                            .setEndPositionMs(endMs)
                            .setStartsAtKeyFrame(false)
                            .build()
                    )
                }
            }
        }

        return builder.build()
    }

    /**
     * Create a transparent bitmap with CreatorAI logo + text watermark in the bottom-right corner.
     */
    private fun createWatermarkBitmap(context: Context): android.graphics.Bitmap {
        val width = 1080
        val height = 1920

        val bitmap = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val textPaint = TextPaint().apply {
            color = Color.argb(128, 255, 255, 255) // 50% white
            textSize = 28f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            isAntiAlias = true
            setShadowLayer(4f, 1f, 1f, Color.argb(180, 0, 0, 0))
        }

        val text = "CreatorAI"
        val textWidth = textPaint.measureText(text)
        val margin = 32f
        val x = width - textWidth - margin
        val y = height - margin

        canvas.drawText(text, x, y, textPaint)

        // Draw app icon next to text
        try {
            val iconSize = 36
            val appIcon = context.packageManager.getApplicationIcon(context.packageName)
            val iconBitmap = android.graphics.Bitmap.createBitmap(iconSize, iconSize, android.graphics.Bitmap.Config.ARGB_8888)
            val iconCanvas = Canvas(iconBitmap)
            appIcon.setBounds(0, 0, iconSize, iconSize)
            appIcon.draw(iconCanvas)

            val iconPaint = Paint().apply { alpha = 153 } // 60% opacity
            canvas.drawBitmap(iconBitmap, x - iconSize - 8f, y - iconSize + 4f, iconPaint)
        } catch (e: Exception) {
            android.util.Log.w("VideoRender", "Could not draw app icon: ${e.message}")
        }

        return bitmap
    }

    /**
     * Create a transparent bitmap with subtitle text at the bottom.
     * White bold text with black outline, centered.
     */
    private fun createSubtitleBitmap(text: String, yPosition: Float = 0.80f): android.graphics.Bitmap {
        val width = 1080
        val height = 1920

        val bitmap = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val textPaint = TextPaint().apply {
            color = Color.WHITE
            textSize = 56f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            isAntiAlias = true
            setShadowLayer(8f, 0f, 0f, Color.BLACK)
        }

        val outlinePaint = TextPaint().apply {
            color = Color.BLACK
            textSize = 56f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            isAntiAlias = true
            style = Paint.Style.STROKE
            strokeWidth = 4f
        }

        val textWidth = (width * 0.85f).toInt()

        val outlineLayout = StaticLayout.Builder.obtain(text, 0, text.length, outlinePaint, textWidth)
            .setAlignment(Layout.Alignment.ALIGN_CENTER)
            .setLineSpacing(4f, 1.0f)
            .build()

        val textLayout = StaticLayout.Builder.obtain(text, 0, text.length, textPaint, textWidth)
            .setAlignment(Layout.Alignment.ALIGN_CENTER)
            .setLineSpacing(4f, 1.0f)
            .build()

        val textHeight = textLayout.height
        val x = (width - textWidth) / 2f
        val y = (height * yPosition) - textHeight / 2f

        canvas.save()
        canvas.translate(x, y)
        outlineLayout.draw(canvas)
        textLayout.draw(canvas)
        canvas.restore()

        return bitmap
    }
}
