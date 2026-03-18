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

        viewModelScope.launch { fetchCredits() }
    }

    fun setAuth(token: String, userId: String, email: String? = null) {
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

        PurchaseService.configure(getApplication(), userId)
        viewModelScope.launch { fetchCredits() }
    }

    fun logout() {
        storage.remove("jwt")
        storage.remove("userId")
        storage.remove("userEmail")
        prefs.edit().putInt("user_credits", 0).apply()

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
                val credits = fetchCreditsFromServer(userId)
                if (credits != null) {
                    prefs.edit().putInt("user_credits", credits).apply()
                    _uiState.update { it.copy(credits = credits) }
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
        viewModelScope.launch(Dispatchers.IO) {
            var isRunning = true
            while (isRunning) {
                val status = com.theholylabs.creator.services.GenerationService.pollAICreate(generationId)
                when (status?.status) {
                    "succeeded" -> {
                        com.theholylabs.creator.services.NotificationService.notifyVideoReady(getApplication(), videoName)
                        com.theholylabs.creator.services.GenerationService.updateGenerationLocal(getApplication(), generationId, com.theholylabs.creator.models.GenerationStatus.COMPLETED, status.outputUrl)
                        fetchCredits() // Refresh credits after success
                        isRunning = false
                    }
                    "failed" -> {
                        com.theholylabs.creator.services.NotificationService.notifyVideoFailed(getApplication(), videoName)
                        com.theholylabs.creator.services.GenerationService.updateGenerationLocal(getApplication(), generationId, com.theholylabs.creator.models.GenerationStatus.FAILED)
                        fetchCredits() // Refresh credits as they might be refunded
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
