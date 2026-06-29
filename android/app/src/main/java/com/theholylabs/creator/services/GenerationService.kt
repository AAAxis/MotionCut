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
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
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
private data class FalQueueSubmitResponse(
    @kotlinx.serialization.SerialName("request_id") val requestId: String? = null,
    @kotlinx.serialization.SerialName("status_url") val statusUrl: String? = null,
    @kotlinx.serialization.SerialName("response_url") val responseUrl: String? = null
)

@Serializable
private data class FalQueueStatusResponse(
    val status: String? = null,
    val error: String? = null,
    @kotlinx.serialization.SerialName("response_url") val responseUrl: String? = null
)

private data class FalVideoJob(
    val modelId: String,
    val statusUrl: String?,
    val responseUrl: String?,
    val authorization: String
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

data class FalCreditBalance(
    val currentBalance: Double,
    val currency: String
)

data class FreeBrainModel(
    val id: String,
    val name: String
)

object GenerationService {
    val defaultFreeBrainModels = listOf(
        FreeBrainModel("nvidia/nemotron-3-super-120b-a12b:free", "NVIDIA Nemotron 3 Super"),
        FreeBrainModel("nvidia/nemotron-3-ultra-550b-a55b:free", "NVIDIA Nemotron 3 Ultra"),
        FreeBrainModel("qwen/qwen3-next-80b-a3b-instruct:free", "Qwen3 Next"),
        FreeBrainModel("openai/gpt-oss-120b:free", "GPT OSS 120B"),
        FreeBrainModel("meta-llama/llama-3.3-70b-instruct:free", "Llama 3.3 70B")
    )

    private val falVideoJobs = mutableMapOf<String, FalVideoJob>()
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
        referenceVideoUrl: String? = null,
        context: Context? = null
    ): AICreateResponse? {
        if (modelId.startsWith("fal-ai/") && context != null) {
            return startFalAICreate(context, modelId, prompt, imageUrl, duration, referenceVideoUrl)
        }

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
        falVideoJobs[id]?.let { return pollFalAICreate(id, it) }
        return try {
            client.get("${BuildConfig.API_BASE_URL}/api/create/status/$id").body()
        } catch (e: Exception) {
            Log.e("GenerationService", "pollAICreate failed: ${e.message}")
            null
        }
    }

    private suspend fun startFalAICreate(
        context: Context,
        modelId: String,
        prompt: String,
        imageUrl: String?,
        duration: Int,
        referenceVideoUrl: String?
    ): AICreateResponse? {
        val apiKey = SecureStorage(context).get("FAL_API_KEY")?.trim().orEmpty()
        if (apiKey.isEmpty()) {
            return AICreateResponse(error = "Connect fal.ai in Settings before using this model.")
        }

        val normalizedModelId = normalizedFalVideoModelId(modelId)
        val input = buildJsonObject {
            put("prompt", JsonPrimitive(prompt))
            put("duration", JsonPrimitive(duration.coerceIn(5, 15)))
            put("aspect_ratio", JsonPrimitive("9:16"))
            put("resolution", JsonPrimitive("720p"))
            put("generate_audio", JsonPrimitive(true))
            if (!imageUrl.isNullOrBlank()) {
                put("image_url", JsonPrimitive(imageUrl))
                put("first_frame_image", JsonPrimitive(imageUrl))
            }
            if (!referenceVideoUrl.isNullOrBlank()) {
                put("video_url", JsonPrimitive(referenceVideoUrl))
                put("reference_video_url", JsonPrimitive(referenceVideoUrl))
            }
        }

        return try {
            val response: FalQueueSubmitResponse = client.post("https://queue.fal.run/$normalizedModelId") {
                contentType(ContentType.Application.Json)
                header(HttpHeaders.Authorization, falAuthorizationHeader(apiKey))
                setBody(input)
            }.body()
            val requestId = response.requestId
            if (requestId.isNullOrBlank()) {
                AICreateResponse(error = "fal.ai did not return a request id.")
            } else {
                falVideoJobs[requestId] = FalVideoJob(normalizedModelId, response.statusUrl, response.responseUrl, falAuthorizationHeader(apiKey))
                AICreateResponse(id = requestId, status = "processing")
            }
        } catch (e: Exception) {
            Log.e("GenerationService", "startFalAICreate failed: ${e.message}")
            AICreateResponse(error = e.message)
        }
    }

    private suspend fun pollFalAICreate(id: String, job: FalVideoJob): AICreateStatus? {
        val statusUrl = job.statusUrl ?: "https://queue.fal.run/${job.modelId}/requests/$id/status"
        val resultUrl = job.responseUrl ?: "https://queue.fal.run/${job.modelId}/requests/$id"
        return try {
            val status: FalQueueStatusResponse = client.get(statusUrl) {
                header(HttpHeaders.Authorization, job.authorization)
            }.body()
            when (mapFalStatus(status.status.orEmpty())) {
                "failed" -> {
                    falVideoJobs.remove(id)
                    AICreateStatus(id = id, status = "failed", error = status.error)
                }
                "succeeded" -> {
                    val bodyText = client.get(status.responseUrl ?: resultUrl) {
                        header(HttpHeaders.Authorization, job.authorization)
                    }.bodyAsText()
                    falVideoJobs.remove(id)
                    AICreateStatus(id = id, status = "succeeded", outputUrl = falOutputVideoUrl(bodyText))
                }
                else -> AICreateStatus(id = id, status = "processing")
            }
        } catch (e: Exception) {
            Log.e("GenerationService", "pollFalAICreate failed: ${e.message}")
            AICreateStatus(id = id, status = "processing", error = e.message)
        }
    }

    private fun falAuthorizationHeader(apiKey: String): String {
        val trimmed = apiKey.trim()
        return if (trimmed.lowercase().startsWith("key ")) trimmed else "Key $trimmed"
    }

    suspend fun fetchFalCreditBalance(context: Context): FalCreditBalance? {
        val apiKey = SecureStorage(context).get("FAL_API_KEY")?.trim().orEmpty()
        if (apiKey.isEmpty()) return null

        return try {
            val body = client.get("https://api.fal.ai/v1/account/billing") {
                header(HttpHeaders.Authorization, falAuthorizationHeader(apiKey))
                parameter("expand", "credits")
            }.bodyAsText()
            val credits = Json.parseToJsonElement(body).jsonObject["credits"]?.jsonObject ?: return null
            val currentBalance = credits["current_balance"]?.jsonPrimitive?.doubleOrNull ?: return null
            val currency = credits["currency"]?.jsonPrimitive?.contentOrNull ?: "USD"
            FalCreditBalance(currentBalance, currency)
        } catch (e: Exception) {
            Log.d("GenerationService", "fal.ai balance unavailable: ${e.message}")
            null
        }
    }

    suspend fun fetchOpenRouterFreeBrainModels(): List<FreeBrainModel> {
        return try {
            val body = client.get("https://openrouter.ai/api/v1/models").bodyAsText()
            val root = Json.parseToJsonElement(body).jsonObject
            val data = root["data"] as? JsonArray ?: return defaultFreeBrainModels
            val fetched = data.mapNotNull { element ->
                val model = element as? JsonObject ?: return@mapNotNull null
                val id = model["id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                if (!id.endsWith(":free")) return@mapNotNull null
                val name = model["name"]?.jsonPrimitive?.contentOrNull
                    ?: id.substringAfterLast("/").removeSuffix(":free")
                FreeBrainModel(id, name)
            }
            (fetched + defaultFreeBrainModels).distinctBy { it.id }.take(40)
        } catch (e: Exception) {
            Log.d("GenerationService", "OpenRouter models unavailable: ${e.message}")
            defaultFreeBrainModels
        }
    }

    private fun normalizedFalVideoModelId(modelId: String): String =
        when (modelId) {
            "fal-ai/kling-video/v2.1/pro/text-to-video" -> "fal-ai/kling-video/v2.5-turbo/pro/text-to-video"
            else -> modelId
        }

    private fun mapFalStatus(status: String): String =
        when (status.lowercase()) {
            "completed", "succeeded" -> "succeeded"
            "failed", "error" -> "failed"
            else -> "processing"
        }

    private fun falOutputVideoUrl(body: String): String? {
        val root = runCatching { Json.parseToJsonElement(body) }.getOrNull() ?: return null
        fun search(value: kotlinx.serialization.json.JsonElement): String? {
            when (value) {
                is kotlinx.serialization.json.JsonPrimitive -> {
                    val str = value.content
                    val lower = str.lowercase()
                    if ((lower.startsWith("http://") || lower.startsWith("https://")) &&
                        (lower.contains(".mp4") || lower.contains(".mov") || lower.contains(".webm") || lower.contains("fal.media") || lower.contains("video"))
                    ) return str
                }
                is JsonObject -> {
                    listOf("video", "videos", "output", "data", "file", "url", "content", "result").forEach { key ->
                        value[key]?.let { search(it) }?.let { return it }
                    }
                    value.values.forEach { child -> search(child)?.let { return it } }
                }
                is kotlinx.serialization.json.JsonArray -> {
                    value.forEach { child -> search(child)?.let { return it } }
                }
            }
            return null
        }
        return search(root)
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
