package com.theholylabs.creator.services

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

object AudioMixerService {

    suspend fun downloadAndCacheMusic(url: String, audioId: String): File? = withContext(Dispatchers.IO) {
        val cacheFile = File(FileStorageService.musicCacheDir, "$audioId.m4a")

        // Return cached if exists
        if (FileStorageService.fileExists(cacheFile)) {
            return@withContext cacheFile
        }

        try {
            FileStorageService.downloadFile(url, cacheFile)
            cacheFile
        } catch (e: Exception) {
            null
        }
    }

    fun getCachedMusic(audioId: String): File? {
        val cacheFile = File(FileStorageService.musicCacheDir, "$audioId.m4a")
        return if (FileStorageService.fileExists(cacheFile)) cacheFile else null
    }
}
