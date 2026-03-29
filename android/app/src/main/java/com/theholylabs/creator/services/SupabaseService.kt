package com.theholylabs.creator.services

import android.util.Log
import com.theholylabs.creator.models.Generation
import com.theholylabs.creator.models.GenerationStatus
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.storage.Storage
import io.github.jan.supabase.storage.storage
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Supabase client for database and storage.
 * Auth is handled by Firebase — Supabase stores data only.
 */
object SupabaseService {

    private const val TAG = "SupabaseService"

    const val SUPABASE_URL = "https://xxcllmzflnwzqiaslyou.supabase.co"
    const val SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh4Y2xsbXpmbG53enFpYXNseW91Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyMDM1NDcsImV4cCI6MjA4OTc3OTU0N30.VbAv5UEC6n1ZyXFvjLshVOp9ZKN5_Rq8fEznoEqFsKY"

    val client: SupabaseClient by lazy {
        createSupabaseClient(SUPABASE_URL, SUPABASE_ANON_KEY) {
            install(Postgrest)
            install(Storage)
        }
    }

    // ── App Users (Firebase UID + FCM token) ─────────────────────────────

    // ── App Users ─────────────────────────────────────────────────────────

    @Serializable
    private data class AppUserRow(
        val id: String,
        val email: String? = null,
        @SerialName("display_name") val displayName: String? = null,
        @SerialName("avatar_url") val avatarUrl: String? = null,
        @SerialName("fcm_token") val fcmToken: String? = null,
        val platform: String = "android"
    )

    suspend fun upsertUser(userId: String, email: String?, displayName: String? = null, avatarUrl: String? = null) {
        val row = AppUserRow(id = userId, email = email, displayName = displayName, avatarUrl = avatarUrl)
        try {
            client.from("app_users").upsert(row)
            Log.d(TAG, "Upserted user $userId ($email)")
        } catch (e: Exception) {
            Log.e(TAG, "Upsert user failed: ${e.message}")
        }
    }

    suspend fun saveFCMToken(userId: String, token: String) {
        try {
            client.from("app_users").update(
                mapOf("fcm_token" to token, "platform" to "android")
            ) {
                filter { eq("id", userId) }
            }
            Log.d(TAG, "Saved FCM token for user $userId")
        } catch (e: Exception) {
            Log.e(TAG, "Save FCM token failed: ${e.message}")
        }
    }

    // ── Storage ──────────────────────────────────────────────────────────

    private const val VIDEO_BUCKET = "videos"

    suspend fun uploadVideo(videoBytes: ByteArray, generationId: String): String? {
        val storagePath = "renders/$generationId.mp4"
        return try {
            client.storage.from(VIDEO_BUCKET).upload(storagePath, videoBytes, upsert = true)
            val publicUrl = client.storage.from(VIDEO_BUCKET).publicUrl(storagePath)
            Log.d(TAG, "Uploaded video: $publicUrl")
            publicUrl
        } catch (e: Exception) {
            Log.e(TAG, "Upload failed: ${e.message}")
            null
        }
    }

    suspend fun deleteVideo(generationId: String) {
        val storagePath = "renders/$generationId.mp4"
        try {
            client.storage.from(VIDEO_BUCKET).delete(storagePath)
        } catch (e: Exception) {
            Log.e(TAG, "Delete video failed: ${e.message}")
        }
    }

    // ── Database (generations table) ────────────────────────────────────

    @Serializable
    data class GenerationRow(
        val id: String,
        val video_name: String,
        val video_storage_path: String? = null,
        val status: String,
        val created_at: String,
        val user_id: String? = null,
        val music_id: String? = null,
        val music_name: String? = null,
        val music_volume: Double? = null,
        val takes_json: String? = null,
        val music_file: String? = null
    )

    @Serializable
    private data class UpsertRow(
        val id: String,
        val video_name: String,
        val video_storage_path: String? = null,
        val status: String,
        val created_at: String,
        val user_id: String? = null
    )

    suspend fun upsertGeneration(gen: Generation, remoteVideoUrl: String? = null) {
        val row = UpsertRow(
            id = gen.id,
            video_name = gen.videoName,
            video_storage_path = remoteVideoUrl ?: gen.resultVideoUrl,
            status = gen.status.name.lowercase(),
            created_at = gen.createdAt,
            user_id = gen.userId
        )
        try {
            client.from("generations").upsert(row)
            Log.d(TAG, "Upserted generation ${gen.id}")
        } catch (e: Exception) {
            if (isTableNotFound(e)) {
                Log.w(TAG, "Generations table not in schema; skipping sync.")
            } else {
                Log.e(TAG, "Upsert failed: ${e.message}")
            }
        }
    }

    suspend fun fetchGenerations(userId: String): List<Generation> {
        return try {
            val rows: List<GenerationRow> = client.from("generations")
                .select {
                    filter { eq("user_id", userId) }
                    order("created_at", io.github.jan.supabase.postgrest.query.Order.DESCENDING)
                }
                .decodeList()

            rows.map { row ->
                Generation(
                    id = row.id,
                    videoName = row.video_name,
                    videoUri = null,
                    resultVideoUrl = row.video_storage_path,
                    status = try {
                        GenerationStatus.valueOf(row.status.uppercase())
                    } catch (_: Exception) {
                        GenerationStatus.SAVED
                    },
                    createdAt = row.created_at,
                    userId = row.user_id
                )
            }
        } catch (e: Exception) {
            if (isTableNotFound(e)) {
                Log.w(TAG, "Generations table not in schema; using local data only.")
            } else {
                Log.e(TAG, "Fetch failed: ${e.message}")
            }
            emptyList()
        }
    }

    suspend fun deleteGeneration(id: String) {
        try {
            client.from("generations").delete {
                filter { eq("id", id) }
            }
        } catch (e: Exception) {
            if (!isTableNotFound(e)) {
                Log.e(TAG, "Delete row failed: ${e.message}")
            }
        }
    }

    private fun isTableNotFound(error: Exception): Boolean {
        val msg = error.message ?: ""
        return msg.contains("Could not find the table") || msg.contains("PGRST205")
    }
}
