package com.theholylabs.creator

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.theholylabs.creator.services.PurchaseService
import com.theholylabs.creator.services.SecureStorage
import com.revenuecat.purchases.Package
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.URL
import javax.net.ssl.HttpsURLConnection

data class AppUiState(
    val isAuthenticated: Boolean = false,
    val userId: String? = null,
    val userEmail: String? = null,
    val credits: Int = 0,
    val isLoadingCredits: Boolean = false,
    val hasSeenOnboarding: Boolean = false,
    val offerings: List<Package> = emptyList(),
    val pendingGenerations: List<com.theholylabs.creator.models.Generation> = emptyList()
)

class AppState(application: Application) : AndroidViewModel(application) {

    private val storage = SecureStorage(application)
    private val prefs = application.getSharedPreferences("app_prefs", 0)

    private val _uiState = MutableStateFlow(AppUiState())
    val uiState: StateFlow<AppUiState> = _uiState.asStateFlow()

    val credits: Int get() = _uiState.value.credits
    val userId: String? get() = _uiState.value.userId

    init {
        // Restore saved session
        val token = storage.get("jwt")
        val userId = storage.get("userId")
        val email = storage.get("userEmail")
        val credits = prefs.getInt("user_credits", 10)
        if (!prefs.contains("user_credits")) {
            prefs.edit().putInt("user_credits", 10).apply()
        }
        val hasSeenOnboarding = prefs.getBoolean("hasSeenOnboarding", false)

        _uiState.update {
            it.copy(
                isAuthenticated = token != null,
                userId = userId,
                userEmail = email,
                credits = credits,
                hasSeenOnboarding = hasSeenOnboarding,
            )
        }

        // Load local generations and resume tracking for processing items
        val local = com.theholylabs.creator.services.GenerationService.loadLocalGenerations(application)
        _uiState.update { it.copy(pendingGenerations = local) }
        
        local.filter { it.status == com.theholylabs.creator.models.GenerationStatus.PROCESSING }.forEach { 
            trackGeneration(it.id, it.videoName)
        }

        // Register FCM token on startup if already signed in
        if (userId != null) {
            com.theholylabs.creator.services.FCMService.registerTokenForUser(userId)
        }

        viewModelScope.launch { fetchCredits() }
    }

    fun setAuth(token: String, userId: String, email: String? = null) {
        android.util.Log.d("AppState", "setAuth: userId=$userId email=$email credits=${_uiState.value.credits}")
        storage.put("jwt", token)
        storage.put("userId", userId)
        if (email != null) storage.put("userEmail", email) else storage.remove("userEmail")

        _uiState.update {
            it.copy(
                isAuthenticated = true,
                userId = userId,
                userEmail = email,
            )
        }

        // Cache userId for FCM token refresh
        prefs.edit().putString("cached_user_id", userId).apply()

        PurchaseService.configure(getApplication(), userId)

        // Register FCM token with Firebase.
        com.theholylabs.creator.services.FCMService.registerTokenForUser(userId)

        viewModelScope.launch {
            // Ensure server has at least 10 credits for this user
            ensureServerCredits(userId, 10)
            fetchCredits()
        }
    }

    fun logout() {
        storage.remove("jwt")
        storage.remove("userId")
        storage.remove("userEmail")
        prefs.edit().putInt("user_credits", 0).remove("cached_user_id").apply()

        _uiState.update {
            it.copy(
                isAuthenticated = false,
                userId = null,
                userEmail = null,
                credits = 0,
            )
        }
    }

    fun completeOnboarding() {
        prefs.edit().putBoolean("hasSeenOnboarding", true).apply()
        _uiState.update { it.copy(hasSeenOnboarding = true) }
    }

    fun loadOfferings() {
        viewModelScope.launch {
            val packages = PurchaseService.loadOfferings()
            _uiState.update { it.copy(offerings = packages) }
        }
    }

    fun fetchCredits() {
        val userId = _uiState.value.userId ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingCredits = true) }
            try {
                val serverCredits = fetchCreditsFromServer(userId)
                android.util.Log.d("AppState", "fetchCredits: server=$serverCredits userId=$userId")
                if (serverCredits != null) {
                    // Always sync with server — server is source of truth
                    prefs.edit().putInt("user_credits", serverCredits).apply()
                    _uiState.update { it.copy(credits = serverCredits) }
                }
            } finally {
                _uiState.update { it.copy(isLoadingCredits = false) }
            }
        }
    }

    fun deductCredits(amount: Int) {
        val current = _uiState.value.credits
        val updated = maxOf(0, current - amount)
        prefs.edit().putInt("user_credits", updated).apply()
        _uiState.update { it.copy(credits = updated) }

        // Sync deduction to server
        val userId = _uiState.value.userId ?: return
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val url = URL("${BuildConfig.API_BASE_URL}/api/credits/deduct")
                val conn = url.openConnection() as HttpsURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.doOutput = true
                conn.outputStream.write("""{"userId":"$userId","amount":$amount}""".toByteArray())
                conn.responseCode // trigger request
                conn.disconnect()
            } catch (_: Exception) {}
        }
    }

    fun addCredits(amount: Int) {
        val current = _uiState.value.credits
        val updated = current + amount
        prefs.edit().putInt("user_credits", updated).apply()
        _uiState.update { it.copy(credits = updated) }

        // Also add on server so generation doesn't fail server-side credit check
        val userId = _uiState.value.userId ?: return
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val url = URL("${BuildConfig.API_BASE_URL}/api/credits/add")
                val conn = url.openConnection() as HttpsURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.doOutput = true
                val body = JSONObject().apply {
                    put("userId", userId)
                    put("amount", amount)
                }.toString()
                conn.outputStream.use { it.write(body.toByteArray()) }
                conn.inputStream.bufferedReader().readText()
                conn.disconnect()
            } catch (_: Exception) {}
        }
    }

    private suspend fun ensureServerCredits(userId: String, minCredits: Int) = withContext(Dispatchers.IO) {
        try {
            // Just fetch credits — the worker auto-creates user with FREE_CREDITS if new
            val current = fetchCreditsFromServer(userId)
            android.util.Log.d("AppState", "ensureServerCredits: current=$current")
            // Don't add credits — server handles initial credit allocation
            if (current == null) {
                // Trigger user creation by calling credits/get (worker auto-creates with 10)
                val url = URL("${BuildConfig.API_BASE_URL}/api/credits/get")
                val conn = url.openConnection() as HttpsURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.doOutput = true
                conn.connectTimeout = 5000
                val body = JSONObject().apply {
                    put("userId", userId)
                }.toString()
                conn.outputStream.use { it.write(body.toByteArray()) }
                val resp = conn.inputStream.bufferedReader().readText()
                android.util.Log.d("AppState", "ensureServerCredits: add response=$resp")
                conn.disconnect()
            }
        } catch (e: Exception) {
            android.util.Log.e("AppState", "ensureServerCredits failed: ${e.message}")
        }
    }

    // MARK: - Private

    private suspend fun fetchCreditsFromServer(userId: String): Int? = withContext(Dispatchers.IO) {
        try {
            val url = URL("${BuildConfig.API_BASE_URL}/api/credits/get")
            val conn = url.openConnection() as HttpsURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true

            val body = JSONObject().apply { put("userId", userId) }.toString()
            conn.outputStream.use { it.write(body.toByteArray()) }

            val response = conn.inputStream.bufferedReader().readText()
            conn.disconnect()

            JSONObject(response).optInt("credits", -1).takeIf { it >= 0 }
        } catch (e: Exception) {
            android.util.Log.e("AppState", "Failed to fetch credits: ${e.message}")
            null
        }
    }

    fun trackGeneration(generationId: String, videoName: String = "AI Video") {
        // Skip polling if already completed locally
        val local = com.theholylabs.creator.services.GenerationService.loadLocalGenerations(getApplication())
        val existing = local.find { it.id == generationId }
        if (existing?.status == com.theholylabs.creator.models.GenerationStatus.COMPLETED) return

        viewModelScope.launch(Dispatchers.IO) {
            var isRunning = true
            while (isRunning) {
                val status = com.theholylabs.creator.services.GenerationService.pollAICreate(generationId)
                when (status?.status) {
                    "succeeded" -> {
                        // Download video locally so it survives URL expiration. The user's
                        // generated library is device-local only.
                        var localVideoUrl = status.outputUrl
                        if (!status.outputUrl.isNullOrEmpty()) {
                            try {
                                val destFile = java.io.File(
                                    com.theholylabs.creator.services.FileStorageService.savedVideosDir,
                                    "${generationId}.mp4"
                                )
                                com.theholylabs.creator.services.FileStorageService.downloadFile(status.outputUrl, destFile)
                                if (destFile.exists() && destFile.length() > 1000) {
                                    localVideoUrl = destFile.absolutePath

                                    // Also save to gallery
                                    val contentValues = android.content.ContentValues().apply {
                                        put(android.provider.MediaStore.Video.Media.DISPLAY_NAME, "$videoName.mp4")
                                        put(android.provider.MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                                            put(android.provider.MediaStore.Video.Media.RELATIVE_PATH, "Movies/CreatorAI")
                                            put(android.provider.MediaStore.Video.Media.IS_PENDING, 1)
                                        }
                                    }
                                    val resolver = getApplication<android.app.Application>().contentResolver
                                    val uri = resolver.insert(android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI, contentValues)
                                    if (uri != null) {
                                        resolver.openOutputStream(uri)?.use { output ->
                                            destFile.inputStream().use { input -> input.copyTo(output) }
                                        }
                                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                                            contentValues.clear()
                                            contentValues.put(android.provider.MediaStore.Video.Media.IS_PENDING, 0)
                                            resolver.update(uri, contentValues, null, null)
                                        }
                                    }
                                }
                            } catch (e: Exception) {
                                android.util.Log.e("AppState", "Failed to download generated video: ${e.message}")
                            }
                        }
                        com.theholylabs.creator.services.NotificationService.notifyVideoReady(getApplication(), videoName)
                        com.theholylabs.creator.services.GenerationService.updateGenerationLocal(getApplication(), generationId, com.theholylabs.creator.models.GenerationStatus.COMPLETED, localVideoUrl)
                        fetchCredits()
                        isRunning = false
                    }
                    "failed" -> {
                        com.theholylabs.creator.services.NotificationService.notifyVideoFailed(getApplication(), videoName)
                        com.theholylabs.creator.services.GenerationService.updateGenerationLocal(getApplication(), generationId, com.theholylabs.creator.models.GenerationStatus.FAILED)
                        fetchCredits()
                        isRunning = false
                    }
                    else -> {
                        // Keep polling every 10 seconds
                        kotlinx.coroutines.delay(10000)
                    }
                }
            }
        }
    }

    fun addPendingGeneration(generation: com.theholylabs.creator.models.Generation) {
        com.theholylabs.creator.services.GenerationService.saveGenerationLocal(getApplication(), generation)
        _uiState.update { 
            it.copy(pendingGenerations = com.theholylabs.creator.services.GenerationService.loadLocalGenerations(getApplication()))
        }
    }
}
