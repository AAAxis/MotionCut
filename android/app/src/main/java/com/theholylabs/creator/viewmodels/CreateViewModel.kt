package com.theholylabs.creator.viewmodels

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.util.UnstableApi
import com.theholylabs.creator.AppState
import com.theholylabs.creator.models.PRESET_AI_MODELS
import com.theholylabs.creator.services.AvatarItem
import com.theholylabs.creator.services.GenerationService
import com.theholylabs.creator.services.LocalReelGenerator
import com.theholylabs.creator.services.LocalScraperService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class CreateMode { REEL, AD }
enum class AdVideoSource { STOCK, AI }

@UnstableApi
class CreateViewModel(application: Application) : AndroidViewModel(application) {
    private val _mode = MutableStateFlow(CreateMode.AD)
    val mode: StateFlow<CreateMode> = _mode.asStateFlow()

    // Reel state
    private val _reelTopic = MutableStateFlow("")
    val reelTopic = _reelTopic

    private val _selectedModelId = MutableStateFlow(PRESET_AI_MODELS.firstOrNull()?.id ?: "fal-ai/kling-video/v2.6/pro/text-to-video")
    val selectedModelId = _selectedModelId

    private val _reelAvatarImageURL = MutableStateFlow<String?>(null)
    val reelAvatarImageURL = _reelAvatarImageURL

    private val _reelReferenceVideoURL = MutableStateFlow<String?>(null) // Remote URL after upload
    val reelReferenceVideoURL = _reelReferenceVideoURL

    private val _reelReferenceVideoUri = MutableStateFlow<android.net.Uri?>(null) // Local URI for preview
    val reelReferenceVideoUri = _reelReferenceVideoUri

    private val _uploadedAvatars = MutableStateFlow<List<AvatarItem>>(emptyList())
    val uploadedAvatars = _uploadedAvatars.asStateFlow()

    // Last generation result (for opening editor)
    private val _lastTakesJson = MutableStateFlow<String?>(null)
    val lastTakesJson: StateFlow<String?> = _lastTakesJson.asStateFlow()
    private val _lastMusicPath = MutableStateFlow<String?>(null)
    val lastMusicPath: StateFlow<String?> = _lastMusicPath.asStateFlow()

    fun clearLastResult() { _lastTakesJson.value = null; _lastMusicPath.value = null }

    // Ad state
    private val _adURL = MutableStateFlow("")
    val adURL = _adURL

    private val _adPrompt = MutableStateFlow("")
    val adPrompt = _adPrompt

    private val _adLanguage = MutableStateFlow("en")
    val adLanguage = _adLanguage

    // Ad video source toggle (Stock vs AI)
    private val _adVideoSource = MutableStateFlow(AdVideoSource.STOCK)
    val adVideoSource = _adVideoSource.asStateFlow()

    fun setAdVideoSource(source: AdVideoSource) { _adVideoSource.value = source }

    val STOCK_FOOTAGE_COST = 0

    fun getSelectedModelCost(): Int = 0

    // Free reel state
    private val _freeReelLanguage = MutableStateFlow("en")
    val freeReelLanguage = _freeReelLanguage

    private val _generationProgress = MutableStateFlow<LocalReelGenerator.GenerationProgress?>(null)
    val generationProgress = _generationProgress.asStateFlow()

    // Switch to library after generation
    private val _switchToLibrary = MutableStateFlow(false)
    val switchToLibrary = _switchToLibrary.asStateFlow()
    fun clearSwitchToLibrary() { _switchToLibrary.value = false }

    // Common
    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage = _errorMessage.asStateFlow()

    fun setMode(newMode: CreateMode) {
        _mode.value = newMode
    }

    fun loadAvatars(userId: String) {
        viewModelScope.launch {
            val list = GenerationService.fetchAvatars(userId)
            _uploadedAvatars.value = list
        }
    }

    fun uploadAvatar(byteArray: ByteArray, userId: String) {
        viewModelScope.launch {
            _isLoading.value = true
            val response = GenerationService.uploadAvatarImage(byteArray, "avatar_${System.currentTimeMillis()}.jpg", userId)
            if (response != null) {
                _reelAvatarImageURL.value = "${com.theholylabs.creator.BuildConfig.API_BASE_URL}${response.url}"
                _selectedModelId.value = response.id
                loadAvatars(userId)
            }
            _isLoading.value = false
        }
    }

    fun selectModel(id: String, imageUrl: String? = null) {
        _selectedModelId.value = id
        _reelAvatarImageURL.value = imageUrl
    }

    fun generateReel(appState: AppState, referenceVideoBytes: ByteArray?, onStarted: (String) -> Unit) {
        val topic = _reelTopic.value.trim()
        if (topic.isEmpty()) {
            _errorMessage.value = "Please enter a topic"
            return
        }

        // Server-side credit check handles this; skip local check
        // to avoid stale local values blocking generation

        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null

            // Scrape topic if it looks like a URL for richer prompts
            var enrichedTopic = topic
            if (topic.startsWith("http") || topic.contains(".com") || topic.contains(".io")) {
                val scraped = LocalScraperService.scrape(topic)
                if (scraped != null) {
                    enrichedTopic = scraped.toPromptContext()
                }
            }

            var remoteVideoUrl: String? = null
            if (referenceVideoBytes != null) {
                val uploadResponse = GenerationService.uploadReferenceVideo(
                    referenceVideoBytes,
                    "ref_${System.currentTimeMillis()}.mp4",
                    appState.userId ?: "demo-user"
                )
                if (uploadResponse != null) {
                    remoteVideoUrl = "${com.theholylabs.creator.BuildConfig.API_BASE_URL}${uploadResponse.url}"
                } else {
                    _errorMessage.value = "Failed to upload reference video"
                    _isLoading.value = false
                    return@launch
                }
            }
            
            val response = GenerationService.startAICreate(
                modelId = _selectedModelId.value,
                prompt = enrichedTopic,
                imageUrl = _reelAvatarImageURL.value,
                duration = 10,
                userId = appState.userId,
                referenceVideoUrl = remoteVideoUrl,
                context = getApplication()
            )

            if (response?.id != null) {
                _reelTopic.value = ""
                _reelReferenceVideoUri.value = null

                val gen = com.theholylabs.creator.models.Generation(
                    id = response.id,
                    videoName = topic,
                    status = com.theholylabs.creator.models.GenerationStatus.PROCESSING,
                    createdAt = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US).format(java.util.Date()),
                    userId = appState.userId
                )

                // Add to pending generations
                appState.addPendingGeneration(gen)

                onStarted(response.id)
            } else {
                _errorMessage.value = response?.error ?: "Failed to start generation"
            }
            _isLoading.value = false
        }
    }

    fun generateFreeReel(appState: AppState, onStarted: (String) -> Unit) {
        // Use URL + prompt as topic for stock footage generation
        val urlPart = _adURL.value.trim()
        val promptPart = _adPrompt.value.trim()
        val topic = listOf(promptPart, urlPart).filter { it.isNotEmpty() }.joinToString(" - ")
        if (promptPart.isEmpty()) {
            _errorMessage.value = "Please describe what your video is about"
            return
        }

        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null
            _generationProgress.value = LocalReelGenerator.GenerationProgress("Starting...", 0f)

            // Scrape URL if provided for better script context
            var enrichedTopic = topic
            if (urlPart.isNotEmpty() && (urlPart.startsWith("http") || urlPart.contains("."))) {
                _generationProgress.value = LocalReelGenerator.GenerationProgress("Scraping page...", 0.05f)
                val scraped = LocalScraperService.scrape(urlPart)
                if (scraped != null) {
                    enrichedTopic = scraped.toPromptContext() +
                        if (promptPart.isNotEmpty()) ". Direction: $promptPart" else ""
                }
            }

            val result = LocalReelGenerator.generate(
                context = getApplication(),
                topic = enrichedTopic,
                language = _adLanguage.value,
                clipCount = if (_adVideoSource.value == AdVideoSource.AI) 4 else 6,
                aiModelId = _selectedModelId.value,
                sourceMode = if (_adVideoSource.value == AdVideoSource.AI) "ai" else "stock",
                userId = appState.userId,
                onProgress = { progress ->
                    _generationProgress.value = progress
                }
            )

            if (result.success && result.generationId != null) {
                _reelTopic.value = ""
                _adPrompt.value = ""
                _adURL.value = ""
                _generationProgress.value = null

                // Store takes for editor navigation
                _lastTakesJson.value = result.takesJson
                _lastMusicPath.value = result.voiceoverPath

                // Save generation to library with takesJson so user can open it later
                val gen = com.theholylabs.creator.models.Generation(
                    id = result.generationId,
                    videoName = topic,
                    videoUri = result.videoPath,
                    status = com.theholylabs.creator.models.GenerationStatus.COMPLETED,
                    createdAt = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US).format(java.util.Date()),
                    userId = appState.userId,
                    takesJson = result.takesJson,
                    musicPath = result.voiceoverPath
                )
                appState.addPendingGeneration(gen)

                // Switch to library tab
                _switchToLibrary.value = true
            } else {
                _errorMessage.value = result.error ?: "Generation failed"
                _generationProgress.value = null
            }

            _isLoading.value = false
        }
    }

    fun previewAd(onSuccess: () -> Unit) {
        val url = _adURL.value.trim()
        if (url.isEmpty()) {
            _errorMessage.value = "Please enter a URL"
            return
        }

        viewModelScope.launch {
            _isLoading.value = true
            // Try local scraper first, fall back to backend
            val scraped = LocalScraperService.scrape(url)
            if (scraped != null) {
                onSuccess()
            } else {
                // Fallback to backend preview
                val preview = GenerationService.previewURL(url)
                if (preview != null) {
                    onSuccess()
                } else {
                    _errorMessage.value = "Failed to load preview"
                }
            }
            _isLoading.value = false
        }
    }

    fun generateAd(appState: AppState, onStarted: (String) -> Unit) {
        val url = _adURL.value.trim()
        val prompt = _adPrompt.value.trim()
        if (prompt.isEmpty()) {
            _errorMessage.value = "Please describe what your video is about"
            return
        }

        viewModelScope.launch {
            _isLoading.value = true

            // Scrape locally and enrich the prompt sent to backend
            var enrichedPrompt = _adPrompt.value
            if (url.isNotEmpty()) {
                val scraped = LocalScraperService.scrape(url)
                if (scraped != null) {
                    val context = scraped.toPromptContext()
                    enrichedPrompt = if (enrichedPrompt.isNotEmpty()) "$context. $enrichedPrompt" else context
                }
            }

            val id = GenerationService.generateAd(
                url = url,
                prompt = enrichedPrompt,
                userId = appState.userId ?: "",
                scenes = 5,
                duration = 30,
                style = "modern",
                language = _adLanguage.value
            )
            if (id != null) {
                val gen = com.theholylabs.creator.models.Generation(
                    id = id,
                    videoName = url.replace("https://", "").replace("http://", "").split("/").first(),
                    status = com.theholylabs.creator.models.GenerationStatus.PROCESSING,
                    createdAt = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US).format(java.util.Date()),
                    userId = appState.userId
                )

                // Add to pending generations
                appState.addPendingGeneration(gen)

                onStarted(id)
            } else {
                _errorMessage.value = "Failed to start ad generation"
            }
            _isLoading.value = false
        }
    }
}
