package com.theholylabs.creator.services

import android.content.Context
import android.util.Log
import com.theholylabs.creator.BuildConfig
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.okhttp.*
import io.ktor.client.plugins.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import java.io.File
import java.util.UUID

@Serializable
data class AICreateResponse(
    val id: String? = null,
    val status: String? = null,
    val error: String? = null
)

@Serializable
data class AICreateStatus(
    val id: String? = null,
    val status: String? = null,
    val outputUrl: String? = null,
    val error: String? = null
)

@Serializable
data class UploadResponse(
    val id: String,
    val name: String,
    val url: String
)

@Serializable
data class AvatarsResponse(
    val avatars: List<AvatarItem>
)

@Serializable
data class AvatarItem(
    val id: String,
    val name: String,
    val url: String
)

@Serializable
data class AdGenerateResponse(
    val id: String,
    val status: String
)

@Serializable
data class PagePreview(
    val ogImage: String? = null,
    val title: String? = null,
    val description: String? = null,
    val domain: String? = null,
    val features: List<String>? = null,
    val images: List<String>? = null
)

@Serializable
data class PreviewResponse(
    val preview: PagePreview? = null
)

object GenerationService {
    private val client = HttpClient(OkHttp) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                coerceInputValues = true
            })
        }
        install(HttpTimeout) {
            requestTimeoutMillis = 600000 // 10 minutes for video gen
        }
    }

    suspend fun startAICreate(
        modelId: String,
        prompt: String,
        imageUrl: String?,
        duration: Int,
        userId: String?,
        referenceVideoUrl: String? = null
    ): AICreateResponse? {
        val body = buildJsonObject {
            put("modelId", JsonPrimitive(modelId))
            put("prompt", JsonPrimitive(prompt))
            imageUrl?.let { put("imageUrl", JsonPrimitive(it)) }
            put("duration", JsonPrimitive(duration))
            userId?.let { put("userId", JsonPrimitive(it)) }
            referenceVideoUrl?.let { put("referenceVideoUrl", JsonPrimitive(it)) }
        }

        return try {
            val response = client.post("${BuildConfig.API_BASE_URL}/api/create/generate") {
                contentType(ContentType.Application.Json)
                setBody(body)
            }
            response.body()
        } catch (e: io.ktor.client.plugins.ClientRequestException) {
            // Handle 4xx errors (e.g., 402 Insufficient credits)
            try {
                val errorBody = e.response.body<AICreateResponse>()
                Log.e("GenerationService", "startAICreate 4xx: ${errorBody.error}")
                errorBody
            } catch (_: Exception) {
                AICreateResponse(error = e.message)
            }
        } catch (e: Exception) {
            Log.e("GenerationService", "startAICreate failed: ${e.message}")
            AICreateResponse(error = e.message)
        }
    }

    suspend fun pollAICreate(id: String): AICreateStatus? {
        return try {
            client.get("${BuildConfig.API_BASE_URL}/api/create/status/$id").body()
        } catch (e: Exception) {
            Log.e("GenerationService", "pollAICreate failed: ${e.message}")
            null
        }
    }

    suspend fun uploadAvatarImage(byteArray: ByteArray, filename: String, userId: String): UploadResponse? {
        return try {
            client.post("${BuildConfig.API_BASE_URL}/api/uploads/image") {
                setBody(MultiPartFormDataContent(
                    formData {
                        append("userId", userId)
                        append("name", "My photo")
                        append("image", byteArray, Headers.build {
                            append(HttpHeaders.ContentType, "image/jpeg")
                            append(HttpHeaders.ContentDisposition, "filename=\"$filename\"")
                        })
                    }
                ))
            }.body()
        } catch (e: Exception) {
            Log.e("GenerationService", "uploadAvatarImage failed: ${e.message}")
            null
        }
    }

    suspend fun uploadReferenceVideo(byteArray: ByteArray, filename: String, userId: String): UploadResponse? {
        return try {
            client.post("${BuildConfig.API_BASE_URL}/api/uploads/video") {
                setBody(MultiPartFormDataContent(
                    formData {
                        append("userId", userId)
                        append("video", byteArray, Headers.build {
                            append(HttpHeaders.ContentType, "video/mp4")
                            append(HttpHeaders.ContentDisposition, "filename=\"$filename\"")
                        })
                    }
                ))
            }.body()
        } catch (e: Exception) {
            Log.e("GenerationService", "uploadReferenceVideo failed: ${e.message}")
            null
        }
    }

    suspend fun fetchAvatars(userId: String): List<AvatarItem> {
        return try {
            val response: AvatarsResponse = client.get("${BuildConfig.API_BASE_URL}/api/uploads/avatars/$userId").body()
            response.avatars
        } catch (e: Exception) {
            Log.e("GenerationService", "fetchAvatars failed: ${e.message}")
            emptyList()
        }
    }

    suspend fun deleteAvatar(avatarId: String): Boolean {
        return try {
            val response = client.delete("${BuildConfig.API_BASE_URL}/api/uploads/avatar/$avatarId")
            response.status.isSuccess()
        } catch (e: Exception) {
            Log.e("GenerationService", "deleteAvatar failed: ${e.message}")
            false
        }
    }

    suspend fun previewURL(urlString: String): PagePreview? {
        return try {
            val response: PreviewResponse = client.post("${BuildConfig.API_BASE_URL}/api/generate/preview") {
                contentType(ContentType.Application.Json)
                setBody(mapOf("url" to urlString))
            }.body()
            response.preview
        } catch (e: Exception) {
            Log.e("GenerationService", "previewURL failed: ${e.message}")
            null
        }
    }

    suspend fun generateAd(
        url: String,
        prompt: String,
        userId: String,
        scenes: Int,
        duration: Int,
        style: String,
        language: String = "en"
    ): String? {
        val body = mapOf(
            "url" to url,
            "notes" to prompt,
            "userId" to userId,
            "language" to language,
            "scenes" to scenes,
            "duration" to duration,
            "style" to style
        )
        return try {
            val response: AdGenerateResponse = client.post("${BuildConfig.API_BASE_URL}/api/ads/generate") {
                contentType(ContentType.Application.Json)
                setBody(body)
            }.body()
            response.id
        } catch (e: Exception) {
            Log.e("GenerationService", "generateAd failed: ${e.message}")
            null
        }
    }

    suspend fun fetchGenerations(userId: String): List<com.theholylabs.creator.models.Generation> {
        return try {
            val response: GenerationsResponse = client.get("${BuildConfig.API_BASE_URL}/api/generations/$userId").body()
            response.generations
        } catch (e: Exception) {
            Log.e("GenerationService", "fetchGenerations failed: ${e.message}")
            emptyList()
        }
    }

    suspend fun deleteGeneration(id: String): Boolean {
        return try {
            val response = client.delete("${BuildConfig.API_BASE_URL}/api/generations/$id")
            response.status.isSuccess()
        } catch (e: Exception) {
            Log.e("GenerationService", "deleteGeneration failed: ${e.message}")
            false
        }
    }

    // MARK: - Local Persistence

    private val json = Json { 
        ignoreUnknownKeys = true
        encodeDefaults = true
        coerceInputValues = true
    }

    private fun getGenerationsFile(context: Context): java.io.File {
        return java.io.File(context.filesDir, "generations.json")
    }

    fun loadLocalGenerations(context: Context): List<com.theholylabs.creator.models.Generation> {
        val file = getGenerationsFile(context)
        if (!file.exists()) return emptyList()
        return try {
            json.decodeFromString<List<com.theholylabs.creator.models.Generation>>(file.readText())
        } catch (e: Exception) {
            Log.e("GenerationService", "Failed to load local generations: ${e.message}")
            emptyList()
        }
    }

    fun saveGenerationLocal(context: Context, generation: com.theholylabs.creator.models.Generation) {
        val existing = loadLocalGenerations(context).toMutableList()
        existing.removeAll { it.id == generation.id }
        existing.add(0, generation)
        saveGenerationsLocal(context, existing)
    }

    fun saveGenerationsLocal(context: Context, generations: List<com.theholylabs.creator.models.Generation>) {
        val file = getGenerationsFile(context)
        try {
            file.writeText(json.encodeToString(generations))
        } catch (e: Exception) {
            Log.e("GenerationService", "Failed to save local generations: ${e.message}")
        }
    }

    fun updateGenerationLocal(context: Context, id: String, status: com.theholylabs.creator.models.GenerationStatus? = null, videoUrl: String? = null) {
        val existing = loadLocalGenerations(context).toMutableList()
        val idx = existing.indexOfFirst { it.id == id }
        if (idx != -1) {
            val updated = existing[idx].copy(
                status = status ?: existing[idx].status,
                resultVideoUrl = videoUrl ?: existing[idx].resultVideoUrl
            )
            existing[idx] = updated
            saveGenerationsLocal(context, existing)
        }
    }
}

@Serializable
data class GenerationsResponse(
    val generations: List<com.theholylabs.creator.models.Generation>
)
