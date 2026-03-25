package com.theholylabs.creator.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.theholylabs.creator.AppState
import com.theholylabs.creator.services.AvatarItem
import com.theholylabs.creator.services.GenerationService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class CreateMode { REEL, AD }

class CreateViewModel : ViewModel() {
    private val _mode = MutableStateFlow(CreateMode.REEL)
    val mode: StateFlow<CreateMode> = _mode.asStateFlow()

    // Reel state
    private val _reelTopic = MutableStateFlow("")
    val reelTopic = _reelTopic

    private val _selectedModelId = MutableStateFlow("bytedance/seedance-1-lite")
    val selectedModelId = _selectedModelId

    private val _reelAvatarImageURL = MutableStateFlow<String?>(null)
    val reelAvatarImageURL = _reelAvatarImageURL

    private val _reelReferenceVideoURL = MutableStateFlow<String?>(null) // Remote URL after upload
    val reelReferenceVideoURL = _reelReferenceVideoURL

    private val _reelReferenceVideoUri = MutableStateFlow<android.net.Uri?>(null) // Local URI for preview
    val reelReferenceVideoUri = _reelReferenceVideoUri

    private val _uploadedAvatars = MutableStateFlow<List<AvatarItem>>(emptyList())
    val uploadedAvatars = _uploadedAvatars.asStateFlow()

    // Ad state
    private val _adURL = MutableStateFlow("")
    val adURL = _adURL

    private val _adPrompt = MutableStateFlow("")
    val adPrompt = _adPrompt

    private val _adLanguage = MutableStateFlow("en")
    val adLanguage = _adLanguage

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
                prompt = topic,
                imageUrl = _reelAvatarImageURL.value,
                duration = 10,
                userId = appState.userId,
                referenceVideoUrl = remoteVideoUrl
            )

            if (response?.id != null) {
                _reelTopic.value = ""
                _reelReferenceVideoUri.value = null
                
                // Add to pending generations
                appState.addPendingGeneration(
                    com.theholylabs.creator.models.Generation(
                        id = response.id,
                        videoName = topic,
                        status = com.theholylabs.creator.models.GenerationStatus.PROCESSING,
                        createdAt = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US).format(java.util.Date())
                    )
                )
                
                onStarted(response.id)
            } else {
                _errorMessage.value = response?.error ?: "Failed to start generation"
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
            val preview = GenerationService.previewURL(url)
            if (preview != null) {
                onSuccess()
            } else {
                _errorMessage.value = "Failed to load preview"
            }
            _isLoading.value = false
        }
    }

    fun generateAd(appState: AppState, onStarted: (String) -> Unit) {
        val url = _adURL.value.trim()
        if (url.isEmpty()) {
            _errorMessage.value = "Please enter a URL"
            return
        }

        viewModelScope.launch {
            _isLoading.value = true
            val id = GenerationService.generateAd(
                url = url,
                prompt = _adPrompt.value,
                userId = appState.userId ?: "",
                scenes = 5,
                duration = 30,
                style = "modern",
                language = _adLanguage.value
            )
            if (id != null) {
                // Add to pending generations
                appState.addPendingGeneration(
                    com.theholylabs.creator.models.Generation(
                        id = id,
                        videoName = url.replace("https://", "").replace("http://", "").split("/").first(),
                        status = com.theholylabs.creator.models.GenerationStatus.PROCESSING,
                        createdAt = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US).format(java.util.Date())
                    )
                )
                onStarted(id)
            } else {
                _errorMessage.value = "Failed to start ad generation"
            }
            _isLoading.value = false
        }
    }
}
