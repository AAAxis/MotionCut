package com.theholylabs.creator.services

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.util.LruCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

object ThumbnailService {

    private val memoryCache = LruCache<String, List<Bitmap>>(20)

    suspend fun generateThumbnails(
        uri: String,
        count: Int,
        durationSec: Double
    ): List<Bitmap> = withContext(Dispatchers.IO) {
        val cacheKey = "${uri}_${count}"
        memoryCache.get(cacheKey)?.let { return@withContext it }

        val retriever = MediaMetadataRetriever()
        val bitmaps = mutableListOf<Bitmap>()
        try {
            if (uri.startsWith("http://") || uri.startsWith("https://")) {
                retriever.setDataSource(uri, HashMap())
            } else {
                retriever.setDataSource(uri)
            }

            val totalUs = (durationSec * 1_000_000).toLong()
            for (i in 0 until count) {
                val timeUs = (i.toDouble() / count * totalUs).toLong()
                val frame = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                if (frame != null) {
                    val scaled = Bitmap.createScaledBitmap(frame, 120, 120, true)
                    bitmaps.add(scaled)
                    if (scaled !== frame) frame.recycle()
                }
            }
        } catch (e: Exception) {
            // Return whatever we got
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }

        if (bitmaps.isNotEmpty()) {
            memoryCache.put(cacheKey, bitmaps)
        }
        bitmaps
    }

    fun clearCache() {
        memoryCache.evictAll()
    }
}
