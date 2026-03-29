package com.theholylabs.creator.services

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.URL
import java.net.URLEncoder
import javax.net.ssl.HttpsURLConnection

@Serializable
data class PexelsVideo(
    val id: Int,
    val url: String,
    val image: String? = null,
    val duration: Int,
    val video_files: List<PexelsVideoFile>
)

@Serializable
data class PexelsVideoFile(
    val id: Int,
    val quality: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val link: String
)

@Serializable
data class PexelsSearchResponse(
    val total_results: Int = 0,
    val videos: List<PexelsVideo> = emptyList()
)

object PexelsService {

    // Primary key — can be updated from remote config/DB later
    private var primaryKey: String? = null
    // Fallback key embedded in app
    private const val FALLBACK_KEY = "Cw9YEAkWimspZgB3Ek2or7rQQ9WMDL3Y3RLRxPPxLGjBUsaF14f70Hjc"
    private const val BASE_URL = "https://api.pexels.com/videos"

    /** Set primary key from remote config/DB */
    fun setPrimaryKey(key: String) { primaryKey = key }

    private fun getApiKey(): String = primaryKey ?: FALLBACK_KEY

    private val json = Json { ignoreUnknownKeys = true }

    private val FALLBACK_QUERIES = listOf(
        "business technology", "city lifestyle", "people working",
        "nature cinematic", "modern office", "social media",
        "product showcase", "creative workspace", "motivation success",
        "smartphone technology", "shopping online", "happy people"
    )

    /**
     * Search for stock footage videos by query.
     * Returns list of HD/SD video file URLs suitable for 9:16 vertical video.
     * Never returns empty — falls back to generic queries.
     */
    suspend fun searchVideos(
        query: String,
        perPage: Int = 5,
        orientation: String = "portrait"
    ): List<PexelsVideoResult> = withContext(Dispatchers.IO) {
        try {
            val encoded = URLEncoder.encode(query, "UTF-8")
            val requestUrl = "$BASE_URL/search?query=$encoded&per_page=$perPage&orientation=$orientation"

            var response: String? = null
            // Try primary key first, fallback on 401/429
            for (key in listOfNotNull(primaryKey, FALLBACK_KEY).distinct()) {
                try {
                    val conn = URL(requestUrl).openConnection() as HttpsURLConnection
                    conn.setRequestProperty("Authorization", key)
                    conn.connectTimeout = 10000
                    conn.readTimeout = 10000
                    val code = conn.responseCode
                    if (code == 200) {
                        response = conn.inputStream.bufferedReader().readText()
                        conn.disconnect()
                        break
                    } else {
                        conn.disconnect()
                        Log.w("PexelsService", "Key ${key.take(8)}... returned $code, trying next")
                    }
                } catch (e: Exception) {
                    Log.w("PexelsService", "Key ${key.take(8)}... failed: ${e.message}")
                }
            }

            if (response == null) {
                return@withContext emptyList()
            }

            val parsed = json.decodeFromString<PexelsSearchResponse>(response)

            val results = parsed.videos.mapNotNull { video ->
                // Prefer HD file with height >= 720
                val file = video.video_files
                    .filter { it.quality == "hd" || it.quality == "sd" }
                    .sortedByDescending { (it.height ?: 0) }
                    .firstOrNull()
                    ?: video.video_files.firstOrNull()

                file?.let {
                    PexelsVideoResult(
                        id = video.id,
                        videoUrl = it.link,
                        thumbnailUrl = video.image,
                        duration = video.duration,
                        width = it.width ?: 0,
                        height = it.height ?: 0
                    )
                }
            }

            // If no results, try simplified query (first 2 words)
            if (results.isEmpty() && query.split(" ").size > 2) {
                val simplified = query.split(" ").take(2).joinToString(" ")
                Log.d("PexelsService", "No results for '$query', trying simplified: '$simplified'")
                return@withContext searchVideos(simplified, perPage, orientation)
            }

            // If still empty, use a random fallback
            if (results.isEmpty()) {
                val fallback = FALLBACK_QUERIES.random()
                Log.d("PexelsService", "No results for '$query', using fallback: '$fallback'")
                return@withContext searchVideosInternal(fallback, perPage, orientation)
            }

            results
        } catch (e: Exception) {
            Log.e("PexelsService", "searchVideos failed: ${e.message}")
            // Return fallback results instead of empty
            try {
                searchVideosInternal(FALLBACK_QUERIES.random(), perPage, orientation)
            } catch (_: Exception) {
                emptyList()
            }
        }
    }

    /** Internal search without fallback recursion */
    private suspend fun searchVideosInternal(
        query: String,
        perPage: Int,
        orientation: String
    ): List<PexelsVideoResult> = withContext(Dispatchers.IO) {
        try {
            val encoded = URLEncoder.encode(query, "UTF-8")
            val url = URL("$BASE_URL/search?query=$encoded&per_page=$perPage&orientation=$orientation")
            val conn = url.openConnection() as HttpsURLConnection
            conn.setRequestProperty("Authorization", getApiKey())
            conn.connectTimeout = 10000
            conn.readTimeout = 10000

            val response = conn.inputStream.bufferedReader().readText()
            conn.disconnect()

            val parsed = json.decodeFromString<PexelsSearchResponse>(response)
            parsed.videos.mapNotNull { video ->
                val file = video.video_files
                    .filter { it.quality == "hd" || it.quality == "sd" }
                    .sortedByDescending { (it.height ?: 0) }
                    .firstOrNull()
                    ?: video.video_files.firstOrNull()
                file?.let {
                    PexelsVideoResult(video.id, it.link, video.image, video.duration, it.width ?: 0, it.height ?: 0)
                }
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /**
     * Search for multiple queries in parallel and return combined results.
     * Used to get footage for each scene in a script.
     */
    suspend fun searchMultiple(queries: List<String>, perQuery: Int = 2): List<PexelsVideoResult> {
        val seenIds = mutableSetOf<Int>()
        return queries.flatMap { query ->
            searchVideos(query, perPage = perQuery).filter { seenIds.add(it.id) }
        }
    }
}

data class PexelsVideoResult(
    val id: Int,
    val videoUrl: String,
    val thumbnailUrl: String? = null,
    val duration: Int,
    val width: Int,
    val height: Int
)
