package com.theholylabs.creator.services

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.URL

object FileStorageService {

    private lateinit var cacheDir: File
    private lateinit var filesDir: File

    lateinit var clipCacheDir: File
        private set
    lateinit var musicCacheDir: File
        private set
    lateinit var thumbnailCacheDir: File
        private set
    lateinit var renderedVideosDir: File
        private set
    lateinit var savedVideosDir: File
        private set

    fun initialize(context: Context) {
        cacheDir = context.cacheDir
        filesDir = context.filesDir

        clipCacheDir = File(cacheDir, "clip_cache")
        musicCacheDir = File(filesDir, "music_cache")
        thumbnailCacheDir = File(filesDir, "thumbnails")
        renderedVideosDir = File(cacheDir, "rendered_videos")
        savedVideosDir = File(filesDir, "saved_videos")

        listOf(clipCacheDir, musicCacheDir, thumbnailCacheDir, renderedVideosDir, savedVideosDir).forEach {
            it.mkdirs()
        }
    }

    fun fileExists(file: File): Boolean = file.exists() && file.length() > 0

    fun fileSize(file: File): Long = if (file.exists()) file.length() else 0L

    fun deleteFile(file: File) {
        file.delete()
    }

    fun moveFile(source: File, dest: File) {
        if (dest.exists()) dest.delete()
        source.renameTo(dest)
    }

    fun copyFile(source: File, dest: File) {
        if (dest.exists()) dest.delete()
        source.copyTo(dest, overwrite = true)
    }

    fun copyToSavedVideos(source: File, id: String): File {
        savedVideosDir.mkdirs()
        val dest = File(savedVideosDir, "$id.mp4")
        copyFile(source, dest)
        return dest
    }

    suspend fun downloadFile(urlString: String, dest: File): File = withContext(Dispatchers.IO) {
        if (fileExists(dest)) return@withContext dest

        val tempFile = File(dest.parentFile, "${dest.name}.tmp")
        try {
            URL(urlString).openStream().use { input ->
                tempFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            moveFile(tempFile, dest)
        } catch (e: Exception) {
            tempFile.delete()
            throw e
        }
        dest
    }

    fun cleanupOldFiles(directory: File, maxAgeDays: Int = 7) {
        val cutoff = System.currentTimeMillis() - maxAgeDays * 86_400_000L
        directory.listFiles()?.forEach { file ->
            if (file.lastModified() < cutoff) {
                file.delete()
            }
        }
    }
}
