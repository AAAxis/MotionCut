package com.theholylabs.creator.services

import android.net.Uri
import android.util.Log
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.storage.FirebaseStorage
import com.theholylabs.creator.models.Generation
import kotlinx.coroutines.tasks.await
import java.io.File

/**
 * Firebase-backed user, action, generation, and video persistence.
 */
object FirebaseDataService {

    private const val TAG = "FirebaseDataService"
    private val db: FirebaseFirestore by lazy { FirebaseFirestore.getInstance() }
    private val storage: FirebaseStorage by lazy { FirebaseStorage.getInstance() }

    suspend fun upsertUser(
        userId: String,
        email: String?,
        displayName: String? = null,
        avatarUrl: String? = null
    ) {
        val data = mutableMapOf<String, Any?>(
            "uid" to userId,
            "email" to email?.trim()?.lowercase(),
            "displayName" to displayName,
            "photoURL" to avatarUrl,
            "platform" to "android",
            "updatedAt" to FieldValue.serverTimestamp(),
            "createdAt" to FieldValue.serverTimestamp()
        )

        try {
            db.collection("users").document(userId).set(data, com.google.firebase.firestore.SetOptions.merge()).await()
            email?.trim()?.lowercase()?.takeIf { it.isNotBlank() }?.let { emailKey ->
                db.collection("userEmails").document(emailKey).set(
                    mapOf(
                        "email" to emailKey,
                        "uid" to userId,
                        "platform" to "android",
                        "updatedAt" to FieldValue.serverTimestamp()
                    ),
                    com.google.firebase.firestore.SetOptions.merge()
                ).await()
            }
            logUserAction(userId, "user.upsert", mapOf("email" to email))
        } catch (e: Exception) {
            Log.e(TAG, "Upsert user failed: ${e.message}")
        }
    }

    suspend fun saveFCMToken(userId: String, token: String) {
        try {
            db.collection("users").document(userId).set(
                mapOf(
                    "fcmToken" to token,
                    "platform" to "android",
                    "updatedAt" to FieldValue.serverTimestamp()
                ),
                com.google.firebase.firestore.SetOptions.merge()
            ).await()
            logUserAction(userId, "fcm.token.save")
        } catch (e: Exception) {
            Log.e(TAG, "Save FCM token failed: ${e.message}")
        }
    }

    suspend fun logUserAction(userId: String, action: String, data: Map<String, Any?> = emptyMap()) {
        try {
            val payload = data.toMutableMap()
            payload["action"] = action
            payload["platform"] = "android"
            payload["createdAt"] = FieldValue.serverTimestamp()
            db.collection("users")
                .document(userId)
                .collection("actions")
                .add(payload)
                .await()
        } catch (e: Exception) {
            Log.e(TAG, "Log action failed: ${e.message}")
        }
    }

    @Deprecated(
        "User-generated library videos are local-only. Do not upload them to Firebase.",
        level = DeprecationLevel.ERROR
    )
    suspend fun uploadVideoFile(userId: String, file: File, generationId: String): String? {
        if (!file.exists() || file.length() <= 0) return null

        return try {
            val ref = storage.reference.child("users/$userId/videos/$generationId.mp4")
            ref.putFile(Uri.fromFile(file)).await()
            val url = ref.downloadUrl.await().toString()
            db.collection("videos").document(generationId).set(
                mapOf(
                    "id" to generationId,
                    "userId" to userId,
                    "videoUrl" to url,
                    "storagePath" to ref.path,
                    "size" to file.length(),
                    "contentType" to "video/mp4",
                    "platform" to "android",
                    "updatedAt" to FieldValue.serverTimestamp(),
                    "createdAt" to FieldValue.serverTimestamp()
                ),
                com.google.firebase.firestore.SetOptions.merge()
            ).await()
            logUserAction(userId, "video.upload", mapOf("generationId" to generationId, "size" to file.length()))
            url
        } catch (e: Exception) {
            Log.e(TAG, "Upload video failed: ${e.message}")
            null
        }
    }

    @Deprecated(
        "User-generated library metadata is local-only. Do not sync generations to Firebase.",
        level = DeprecationLevel.ERROR
    )
    suspend fun upsertGeneration(gen: Generation, firebaseVideoUrl: String? = null) {
        val userId = gen.userId ?: return
        val data = mutableMapOf<String, Any?>(
            "id" to gen.id,
            "userId" to userId,
            "videoName" to gen.videoName,
            "videoUri" to gen.videoUri,
            "videoUrl" to (firebaseVideoUrl ?: gen.resultVideoUrl),
            "status" to gen.status.name.lowercase(),
            "createdAtString" to gen.createdAt,
            "updatedAt" to FieldValue.serverTimestamp(),
            "platform" to "android",
            "takesJson" to gen.takesJson,
            "musicPath" to gen.musicPath
        )
        if (firebaseVideoUrl != null) data["firebaseVideoUrl"] = firebaseVideoUrl

        try {
            db.collection("users")
                .document(userId)
                .collection("generations")
                .document(gen.id)
                .set(data, com.google.firebase.firestore.SetOptions.merge())
                .await()
            logUserAction(userId, "generation.upsert", mapOf("generationId" to gen.id, "status" to gen.status.name.lowercase()))
        } catch (e: Exception) {
            Log.e(TAG, "Upsert generation failed: ${e.message}")
        }
    }

    @Deprecated(
        "User-generated library metadata is local-only. Delete local generation storage instead.",
        level = DeprecationLevel.ERROR
    )
    suspend fun deleteGeneration(userId: String, id: String) {
        try {
            db.collection("users")
                .document(userId)
                .collection("generations")
                .document(id)
                .delete()
                .await()
            storage.reference.child("users/$userId/videos/$id.mp4").delete().await()
            logUserAction(userId, "generation.delete", mapOf("generationId" to id))
        } catch (e: Exception) {
            Log.e(TAG, "Delete generation failed: ${e.message}")
        }
    }
}
