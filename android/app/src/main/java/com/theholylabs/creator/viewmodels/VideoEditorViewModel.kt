package com.theholylabs.creator.viewmodels

import android.app.Application
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.common.C
import com.theholylabs.creator.models.Clip
import com.theholylabs.creator.models.MusicTrack
import com.theholylabs.creator.services.FileStorageService
import com.theholylabs.creator.ui.editor.EditorTab
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

class VideoEditorViewModel(
    application: Application,
    private val videoUri: String,
    private val videoName: String,
    private val takesJson: String?,
    private val musicUrl: String?,
    private val userId: String?,
    private val existingGenerationId: String? = null
) : AndroidViewModel(application) {

    // Clips
    private val _clips = MutableStateFlow<List<Clip>>(emptyList())
    val clips: StateFlow<List<Clip>> = _clips.asStateFlow()

    private val _activeClipIndex = MutableStateFlow(0)
    val activeClipIndex: StateFlow<Int> = _activeClipIndex.asStateFlow()

    private val _clipsCached = MutableStateFlow(false)
    val clipsCached: StateFlow<Boolean> = _clipsCached.asStateFlow()

    // Playback
    private val _isPlaying = MutableStateFlow(true)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _isMuted = MutableStateFlow(false)
    val isMuted: StateFlow<Boolean> = _isMuted.asStateFlow()

    private val _currentTimeMs = MutableStateFlow(0L)
    val currentTimeMs: StateFlow<Long> = _currentTimeMs.asStateFlow()

    private val _durationMs = MutableStateFlow(0L)
    val durationMs: StateFlow<Long> = _durationMs.asStateFlow()

    // Quality
    private val _aspectRatio = MutableStateFlow("9:16")
    val aspectRatio: StateFlow<String> = _aspectRatio.asStateFlow()

    private val _exportQuality = MutableStateFlow("original")
    val exportQuality: StateFlow<String> = _exportQuality.asStateFlow()

    private val _addCaptionsViaCloud = MutableStateFlow(false)
    val addCaptionsViaCloud: StateFlow<Boolean> = _addCaptionsViaCloud.asStateFlow()

    private val _burnSubtitles = MutableStateFlow(false)
    val burnSubtitles: StateFlow<Boolean> = _burnSubtitles.asStateFlow()

    // Subtitle position as fraction of video dimensions (0.0 to 1.0)
    // Default: centered horizontally, near bottom
    private val _subtitleYPosition = MutableStateFlow(0.80f)
    val subtitleYPosition: StateFlow<Float> = _subtitleYPosition.asStateFlow()

    fun setSubtitleYPosition(y: Float) {
        _subtitleYPosition.value = y.coerceIn(0.05f, 0.95f)
    }

    // Bottom sheet for subs/music
    private val _showBottomSheet = MutableStateFlow(false)
    val showBottomSheet: StateFlow<Boolean> = _showBottomSheet.asStateFlow()
    fun showBottomSheet(show: Boolean) { _showBottomSheet.value = show }

    // Add clip sheet
    private val _showAddClipSheet = MutableStateFlow(false)
    val showAddClipSheet: StateFlow<Boolean> = _showAddClipSheet.asStateFlow()

    private val _showPexelsSearch = MutableStateFlow(false)
    val showPexelsSearch: StateFlow<Boolean> = _showPexelsSearch.asStateFlow()

    private val _pexelsQuery = MutableStateFlow("")
    val pexelsQuery: StateFlow<String> = _pexelsQuery.asStateFlow()

    private val _pexelsResults = MutableStateFlow<List<com.theholylabs.creator.services.PexelsVideoResult>>(emptyList())
    val pexelsResults: StateFlow<List<com.theholylabs.creator.services.PexelsVideoResult>> = _pexelsResults.asStateFlow()

    private val _pexelsLoading = MutableStateFlow(false)
    val pexelsLoading: StateFlow<Boolean> = _pexelsLoading.asStateFlow()

    private val _isDownloadingClip = MutableStateFlow(false)
    val isDownloadingClip: StateFlow<Boolean> = _isDownloadingClip.asStateFlow()

    // AI clip generation
    private val _showAiPrompt = MutableStateFlow(false)
    val showAiPrompt: StateFlow<Boolean> = _showAiPrompt.asStateFlow()

    private val _aiPrompt = MutableStateFlow("")
    val aiPrompt: StateFlow<String> = _aiPrompt.asStateFlow()

    private val _aiGenerating = MutableStateFlow(false)
    val aiGenerating: StateFlow<Boolean> = _aiGenerating.asStateFlow()

    private val _aiStatus = MutableStateFlow("")
    val aiStatus: StateFlow<String> = _aiStatus.asStateFlow()

    fun showAiPrompt() { _showAiPrompt.value = true }
    fun hideAiPrompt() { _showAiPrompt.value = false; _aiPrompt.value = "" }
    fun setAiPrompt(text: String) { _aiPrompt.value = text }

    fun generateAiClip() {
        val prompt = _aiPrompt.value.trim()
        if (prompt.isEmpty()) return
        _aiGenerating.value = true
        _aiStatus.value = "Starting AI generation..."
        _showAiPrompt.value = false

        viewModelScope.launch {
            try {
                // Start generation on server
                val response = com.theholylabs.creator.services.GenerationService.startAICreate(
                    modelId = "fal-ai/pixverse/v4/text-to-video",
                    prompt = prompt,
                    imageUrl = null,
                    duration = 5,
                    userId = userId,
                )
                if (response?.id == null || response.error != null) {
                    _aiStatus.value = response?.error ?: "Failed to start"
                    _aiGenerating.value = false
                    return@launch
                }

                // Poll for completion
                _aiStatus.value = "Generating video..."
                val genId = response.id
                var outputUrl: String? = null
                while (outputUrl == null) {
                    kotlinx.coroutines.delay(5000)
                    val status = com.theholylabs.creator.services.GenerationService.pollAICreate(genId)
                    when (status?.status) {
                        "succeeded" -> outputUrl = status.outputUrl
                        "failed" -> {
                            _aiStatus.value = "Generation failed"
                            _aiGenerating.value = false
                            return@launch
                        }
                    }
                }

                // Download and add to timeline
                _aiStatus.value = "Downloading clip..."
                val cacheFile = java.io.File(
                    getApplication<android.app.Application>().cacheDir,
                    "ai_clip_${System.currentTimeMillis()}.mp4"
                )
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    com.theholylabs.creator.services.FileStorageService.downloadFile(outputUrl, cacheFile)
                }
                addClipFromUri(cacheFile.absolutePath, 5.0)
                _aiStatus.value = ""
                _aiPrompt.value = ""
            } catch (e: Exception) {
                _aiStatus.value = "Error: ${e.message}"
            }
            _aiGenerating.value = false
        }
    }

    // Music
    private val _selectedMusic = MutableStateFlow<MusicTrack?>(null)
    val selectedMusic: StateFlow<MusicTrack?> = _selectedMusic.asStateFlow()

    private val _musicVolume = MutableStateFlow(0.5f)
    val musicVolume: StateFlow<Float> = _musicVolume.asStateFlow()

    // Processing
    private val _isExporting = MutableStateFlow(false)
    val isExporting: StateFlow<Boolean> = _isExporting.asStateFlow()

    private val _isSaved = MutableStateFlow(false)
    val isSaved: StateFlow<Boolean> = _isSaved.asStateFlow()

    private val _processingStatus = MutableStateFlow("idle")
    val processingStatus: StateFlow<String> = _processingStatus.asStateFlow()

    private val _processingError = MutableStateFlow<String?>(null)
    val processingError: StateFlow<String?> = _processingError.asStateFlow()

    private val _isProcessingModalVisible = MutableStateFlow(false)
    val isProcessingModalVisible: StateFlow<Boolean> = _isProcessingModalVisible.asStateFlow()

    // Editor
    private val _activeTab = MutableStateFlow(EditorTab.SUBTITLES)
    val activeTab: StateFlow<EditorTab> = _activeTab.asStateFlow()

    // Player
    var videoPlayer: ExoPlayer? = null
        private set
    var musicPlayer: ExoPlayer? = null
        private set

    private val handler = Handler(Looper.getMainLooper())
    private val positionUpdateRunnable = object : Runnable {
        override fun run() {
            videoPlayer?.let { player ->
                _currentTimeMs.value = player.currentPosition
                val dur = player.duration
                if (dur != C.TIME_UNSET && dur > 0) {
                    _durationMs.value = dur
                }
            }
            handler.postDelayed(this, 100L)
        }
    }

    private val isReelMode: Boolean
        get() = _clips.value.any { it.beatDuration != null } && _clips.value.size > 1

    init {
        parseClips()
        setupPlayer()
        loadMusicFromUrl()
        // Auto-enable subtitles if clips have text (admaker reels)
        if (_clips.value.any { !it.text.isNullOrBlank() }) {
            _burnSubtitles.value = true
        }
    }

    private fun parseClips() {
        android.util.Log.d("VideoEditor", "parseClips: takesJson=${takesJson?.take(100)}... length=${takesJson?.length}")
        if (!takesJson.isNullOrEmpty()) {
            try {
                val json = Json { ignoreUnknownKeys = true }
                val arr = Json.parseToJsonElement(takesJson).jsonArray
                val parsed = arr.mapIndexed { i, element ->
                    val obj = element.jsonObject
                    Clip(
                        id = obj["id"]?.jsonPrimitive?.intOrNull ?: (System.currentTimeMillis().toInt() + i),
                        uri = obj["uri"]?.jsonPrimitive?.content ?: "",
                        name = obj["name"]?.jsonPrimitive?.content ?: "Take ${i + 1}",
                        mimeType = obj["mimeType"]?.jsonPrimitive?.content ?: "video/mp4",
                        trimStart = obj["trimStart"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                        trimEnd = obj["trimEnd"]?.jsonPrimitive?.doubleOrNull ?: 100.0,
                        beatDuration = obj["beatDuration"]?.jsonPrimitive?.doubleOrNull,
                        sourceDuration = obj["sourceDuration"]?.jsonPrimitive?.doubleOrNull,
                        text = obj["text"]?.jsonPrimitive?.content,
                        localUri = obj["localUri"]?.jsonPrimitive?.content
                    )
                }
                _clips.value = parsed
            } catch (e: Exception) {
                _clips.value = listOf(Clip(id = 1, uri = videoUri, name = videoName))
            }
        } else if (videoUri.isNotEmpty()) {
            _clips.value = listOf(Clip(id = 1, uri = videoUri, name = videoName))
        }
    }

    private fun setupPlayer() {
        val clips = _clips.value
        if (clips.isEmpty()) return

        val context = getApplication<Application>()
        // Build player with video renderer ONLY — no audio renderers at all
        val videoOnlyRenderersFactory = androidx.media3.exoplayer.RenderersFactory { handler, videoListener, audioListener, textOutput, metadataOutput ->
            arrayOf(
                androidx.media3.exoplayer.video.MediaCodecVideoRenderer(
                    context,
                    androidx.media3.exoplayer.mediacodec.MediaCodecSelector.DEFAULT,
                    0,
                    handler,
                    videoListener,
                    50
                )
            )
        }
        val player = ExoPlayer.Builder(context, videoOnlyRenderersFactory).build()
        val firstClip = clips.first()
        val uri = firstClip.localUri ?: firstClip.uri

        player.setMediaItem(MediaItem.fromUri(uri))
        player.prepare()
        player.playWhenReady = true

        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) {
                    player.seekTo(0)
                    if (_isPlaying.value) player.play()
                }
            }
        })

        videoPlayer = player
        startPositionUpdates()
    }

    private fun loadMusicFromUrl() {
        if (musicUrl.isNullOrEmpty()) return
        val context = getApplication<Application>()
        val file = File(musicUrl)
        if (!file.exists()) return

        // Release any existing music player first
        musicPlayer?.stop()
        musicPlayer?.release()
        musicPlayer = null

        android.util.Log.e("AUDIO_DEBUG", "Creating musicPlayer VM=${System.identityHashCode(this@VideoEditorViewModel)} file=${file.absolutePath}", Exception("STACK"))

        val player = ExoPlayer.Builder(context).build()
        player.setMediaItem(MediaItem.fromUri(file.absolutePath))
        player.repeatMode = Player.REPEAT_MODE_OFF
        player.volume = _musicVolume.value
        player.prepare()
        if (_isPlaying.value) player.play()
        musicPlayer = player

        // Set a placeholder music track so the UI shows it
        _selectedMusic.value = MusicTrack(
            id = "restored",
            name = file.nameWithoutExtension,
            file = file.absolutePath
        )
    }

    private fun startPositionUpdates() {
        handler.removeCallbacks(positionUpdateRunnable)
        handler.post(positionUpdateRunnable)
    }

    // Playback Controls

    fun togglePlayPause() {
        val playing = !_isPlaying.value
        _isPlaying.value = playing
        if (playing) {
            videoPlayer?.play()
            musicPlayer?.play()
        } else {
            videoPlayer?.pause()
            musicPlayer?.pause()
        }
    }

    fun toggleMute() {
        val muted = !_isMuted.value
        _isMuted.value = muted
        musicPlayer?.volume = if (muted) 0f else _musicVolume.value
    }

    fun seekTo(percentage: Float) {
        val dur = _durationMs.value
        if (dur <= 0) return
        val posMs = ((percentage / 100f) * dur).toLong()
        videoPlayer?.seekTo(posMs)
        _currentTimeMs.value = posMs
    }

    // Clip Management

    fun selectClip(index: Int) {
        val clips = _clips.value
        if (index < 0 || index >= clips.size) return
        _activeClipIndex.value = index

        val clip = clips[index]
        val uri = clip.localUri ?: clip.uri

        videoPlayer?.let { player ->
            player.setMediaItem(MediaItem.fromUri(uri))
            player.prepare()
            player.volume = 0f
            if (_isPlaying.value) player.play()
        }
        _currentTimeMs.value = 0
    }

    // Debounce trim updates to avoid recomposition storm during drag
    private var pendingTrimJob: kotlinx.coroutines.Job? = null

    fun updateClipTrimStart(index: Int, value: Double) {
        pendingTrimJob?.cancel()
        pendingTrimJob = viewModelScope.launch {
            kotlinx.coroutines.delay(16) // ~1 frame
            val clips = _clips.value.toMutableList()
            if (index < 0 || index >= clips.size) return@launch
            clips[index] = clips[index].copy(trimStart = value)
            _clips.value = clips
        }
    }

    fun updateClipTrimEnd(index: Int, value: Double) {
        pendingTrimJob?.cancel()
        pendingTrimJob = viewModelScope.launch {
            kotlinx.coroutines.delay(16)
            val clips = _clips.value.toMutableList()
            if (index < 0 || index >= clips.size) return@launch
            clips[index] = clips[index].copy(trimEnd = value)
            _clips.value = clips
        }
    }

    fun removeClip(index: Int) {
        val clips = _clips.value.toMutableList()
        if (index < 0 || index >= clips.size) return
        clips.removeAt(index)
        _clips.value = clips

        val newIndex = if (_activeClipIndex.value >= clips.size) {
            max(0, clips.size - 1)
        } else {
            _activeClipIndex.value
        }
        _activeClipIndex.value = newIndex

        if (clips.isNotEmpty()) {
            selectClip(newIndex)
        }
    }

    fun duplicateClip(index: Int) {
        val clips = _clips.value.toMutableList()
        if (index < 0 || index >= clips.size) return
        val nextId = (clips.maxOfOrNull { it.id } ?: 0) + 1
        val copy = clips[index].copy(id = nextId)
        clips.add(index + 1, copy)
        _clips.value = clips
        _activeClipIndex.value = index + 1
    }

    fun splitClipAtPlayhead() {
        val clips = _clips.value.toMutableList()
        val idx = _activeClipIndex.value
        if (idx < 0 || idx >= clips.size) return

        val clip = clips[idx]
        val player = videoPlayer ?: return

        // 1. Pause player to avoid stutter during state mutation
        val wasPlaying = _isPlaying.value
        player.pause()
        _isPlaying.value = false

        // 2. Get actual playhead position as percentage of clip
        val currentPos = player.currentPosition
        val duration = player.duration
        if (duration <= 0) return

        val playheadPct = (currentPos.toDouble() / duration.toDouble()) * 100.0
        // Map playhead to trim range
        val trimRange = clip.trimEnd - clip.trimStart
        val splitPct = clip.trimStart + (playheadPct / 100.0) * trimRange

        // Guard: don't split at edges (< 5% from either end)
        if (splitPct - clip.trimStart < 5.0 || clip.trimEnd - splitPct < 5.0) return

        val nextId = (clips.maxOfOrNull { it.id } ?: 0) + 1

        val firstHalf = clip.copy(trimEnd = splitPct)
        val secondHalf = clip.copy(id = nextId, trimStart = splitPct)

        // 3. Update state atomically
        clips[idx] = firstHalf
        clips.add(idx + 1, secondHalf)
        _clips.value = clips

        // 4. Select second half and seek to its start
        _activeClipIndex.value = idx + 1
        player.seekTo(0)

        // Resume if was playing
        if (wasPlaying) {
            player.play()
            _isPlaying.value = true
        }
    }

    fun reorderClips(from: Int, to: Int) {
        if (from == to) return
        val clips = _clips.value.toMutableList()
        if (from < 0 || to < 0 || from >= clips.size || to >= clips.size) return
        val clip = clips.removeAt(from)
        clips.add(to, clip)
        _clips.value = clips
        _activeClipIndex.value = to
    }

    fun playAllClips() {
        if (!isReelMode) return
        // Build a playlist of all clips
        val context = getApplication<Application>()
        val player = videoPlayer ?: return
        val clips = _clips.value

        val mediaItems = clips.map { clip ->
            val uri = clip.localUri ?: clip.uri
            MediaItem.fromUri(uri)
        }

        player.setMediaItems(mediaItems)
        player.prepare()
        _activeClipIndex.value = -1
        if (_isPlaying.value) player.play()
    }

    // Quality

    fun setAspectRatio(ratio: String) {
        _aspectRatio.value = ratio
    }

    fun setExportQuality(quality: String) {
        _exportQuality.value = quality
    }

    fun setAddCaptionsViaCloud(enabled: Boolean) {
        _addCaptionsViaCloud.value = enabled
    }

    fun setBurnSubtitles(enabled: Boolean) {
        _burnSubtitles.value = enabled
    }

    fun updateClipText(index: Int, text: String) {
        val updated = _clips.value.toMutableList()
        if (index in updated.indices) {
            updated[index] = updated[index].copy(text = text)
            _clips.value = updated
        }
    }

    fun generateSubtitles() {
        val updated = _clips.value.mapIndexed { index, clip ->
            if (clip.text.isNullOrBlank()) {
                clip.copy(text = "Scene ${index + 1}")
            } else clip
        }
        _clips.value = updated
    }

    fun showAddClipSheet() { _showAddClipSheet.value = true }
    fun hideAddClipSheet() { _showAddClipSheet.value = false }

    // Gallery pick request
    private val _requestGalleryPick = MutableStateFlow(false)
    val requestGalleryPick: StateFlow<Boolean> = _requestGalleryPick.asStateFlow()
    fun requestGalleryPick() { _requestGalleryPick.value = true }
    fun clearGalleryPickRequest() { _requestGalleryPick.value = false }

    fun showPexelsSearch() {
        _showAddClipSheet.value = false
        _showPexelsSearch.value = true
    }
    fun hidePexelsSearch() {
        _showPexelsSearch.value = false
        _pexelsResults.value = emptyList()
        _pexelsQuery.value = ""
        _pexelsReplaceMode.value = false
    }
    fun setPexelsQuery(q: String) { _pexelsQuery.value = q }

    fun searchPexels() {
        val q = _pexelsQuery.value.trim()
        if (q.isEmpty()) return
        _pexelsLoading.value = true
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            val results = com.theholylabs.creator.services.PexelsService.searchVideos(q, perPage = 10, orientation = "portrait")
            _pexelsResults.value = results
            _pexelsLoading.value = false
        }
    }

    fun addClipFromUri(uri: String, duration: Double = 0.0) {
        // Try to get actual duration from the video
        val actualDuration = if (duration > 0) duration else {
            try {
                val retriever = android.media.MediaMetadataRetriever()
                if (uri.startsWith("content://")) {
                    retriever.setDataSource(getApplication(), android.net.Uri.parse(uri))
                } else {
                    retriever.setDataSource(uri)
                }
                val durationMs = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 5000
                retriever.release()
                durationMs / 1000.0
            } catch (_: Exception) { 5.0 }
        }

        val newClip = com.theholylabs.creator.models.Clip(
            id = _clips.value.size,
            uri = uri,
            localUri = uri,
            name = "Clip ${_clips.value.size + 1}",
            sourceDuration = actualDuration,
            beatDuration = actualDuration
        )
        _clips.value = _clips.value + newClip
        selectClip(_clips.value.size - 1)
    }

    fun addClipFromPexels(videoUrl: String, duration: Double) {
        _isDownloadingClip.value = true
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            try {
                val cacheFile = java.io.File(getApplication<Application>().cacheDir, "pexels_${System.currentTimeMillis()}.mp4")
                com.theholylabs.creator.services.FileStorageService.downloadFile(videoUrl, cacheFile)
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
                    addClipFromUri(cacheFile.absolutePath, duration)
                    _isDownloadingClip.value = false
                }
            } catch (e: Exception) {
                android.util.Log.e("VideoEditor", "Failed to download Pexels clip: ${e.message}")
                _isDownloadingClip.value = false
            }
        }
    }

    fun replaceClipFromPexels(videoUrl: String, duration: Double) {
        _isDownloadingClip.value = true
        val replaceIndex = _activeClipIndex.value
        viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            try {
                val cacheFile = java.io.File(getApplication<Application>().cacheDir, "pexels_${System.currentTimeMillis()}.mp4")
                com.theholylabs.creator.services.FileStorageService.downloadFile(videoUrl, cacheFile)
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
                    val clips = _clips.value.toMutableList()
                    if (replaceIndex in clips.indices) {
                        val oldClip = clips[replaceIndex]
                        clips[replaceIndex] = oldClip.copy(
                            uri = cacheFile.absolutePath,
                            localUri = cacheFile.absolutePath,
                            sourceDuration = duration,
                            beatDuration = oldClip.beatDuration ?: duration
                        )
                        _clips.value = clips
                        selectClip(replaceIndex)
                    }
                    _isDownloadingClip.value = false
                }
            } catch (e: Exception) {
                android.util.Log.e("VideoEditor", "Failed to replace Pexels clip: ${e.message}")
                _isDownloadingClip.value = false
            }
        }
    }

    // Track whether Pexels search is in replace mode
    private val _pexelsReplaceMode = MutableStateFlow(false)
    val pexelsReplaceMode: StateFlow<Boolean> = _pexelsReplaceMode.asStateFlow()

    fun showPexelsSearchForReplace() {
        _pexelsReplaceMode.value = true
        _showPexelsSearch.value = true
    }

    // Music

    fun setMusicVolume(volume: Float) {
        _musicVolume.value = volume
        musicPlayer?.volume = volume
    }

    fun selectMusicTrack(track: MusicTrack) {
        _selectedMusic.value = track
        val context = getApplication<Application>()

        musicPlayer?.release()
        val player = ExoPlayer.Builder(context).build()
        player.setMediaItem(MediaItem.fromUri(track.file))
        player.repeatMode = Player.REPEAT_MODE_ALL
        player.volume = _musicVolume.value
        player.prepare()
        if (_isPlaying.value) player.play()
        musicPlayer = player
    }

    fun clearMusic() {
        _selectedMusic.value = null
        musicPlayer?.release()
        musicPlayer = null
    }

    // Tab

    fun setActiveTab(tab: EditorTab) {
        _activeTab.value = tab
    }

    // Pre-cache

    fun preCacheClips() {
        if (_clipsCached.value) return
        viewModelScope.launch {
            val clips = _clips.value.toMutableList()
            var changed = false

            for (i in clips.indices) {
                val clip = clips[i]
                if (!isRemoteUrl(clip.uri) || clip.localUri != null) continue

                val localFile = File(FileStorageService.clipCacheDir, "take_${clip.id}_$i.mp4")
                if (FileStorageService.fileExists(localFile)) {
                    clips[i] = clip.copy(localUri = localFile.absolutePath)
                    changed = true
                    continue
                }

                try {
                    withContext(Dispatchers.IO) {
                        FileStorageService.downloadFile(clip.uri, localFile)
                    }
                    clips[i] = clip.copy(localUri = localFile.absolutePath)
                    changed = true
                } catch (e: Exception) {
                    // Continue with remote URL
                }
            }

            if (changed) {
                _clips.value = clips
            }
            _clipsCached.value = true
        }
    }

    // Export

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    fun exportVideo() {
        if (_isExporting.value) return
        _isExporting.value = true
        _processingStatus.value = "processing"
        _isProcessingModalVisible.value = true

        viewModelScope.launch {
            val context = getApplication<Application>()
            val renderClips = withContext(Dispatchers.IO) {
                _clips.value.map { c ->
                    val uri = c.localUri ?: c.uri
                    val clip = c.copy(uri = uri)
                    // Probe sourceDuration if missing — needed by Transformer for clipping
                    if (clip.sourceDuration == null || clip.sourceDuration <= 0.0) {
                        try {
                            val retriever = android.media.MediaMetadataRetriever()
                            if (uri.startsWith("content://")) {
                                retriever.setDataSource(context, android.net.Uri.parse(uri))
                            } else {
                                retriever.setDataSource(uri)
                            }
                            val durMs = retriever.extractMetadata(
                                android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
                            )?.toLongOrNull() ?: 0L
                            retriever.release()
                            if (durMs > 0) clip.copy(sourceDuration = durMs / 1000.0) else clip
                        } catch (_: Exception) { clip }
                    } else clip
                }
            }

            val result = com.theholylabs.creator.services.BackgroundRenderService.startExport(
                context = context,
                videoName = videoName,
                clips = renderClips,
                aspectRatio = _aspectRatio.value,
                exportQuality = _exportQuality.value,
                userId = userId,
                selectedMusic = _selectedMusic.value,
                musicVolume = _musicVolume.value,
                addCaptionsViaCloud = _addCaptionsViaCloud.value,
                burnSubtitles = _burnSubtitles.value,
                subtitleYPosition = _subtitleYPosition.value,
                existingGenerationId = existingGenerationId,
                onStatusUpdate = { status ->
                    _processingStatus.value = when (status) {
                        com.theholylabs.creator.models.GenerationStatus.PROCESSING -> "processing"
                        com.theholylabs.creator.models.GenerationStatus.COMPLETED,
                        com.theholylabs.creator.models.GenerationStatus.SAVED -> "completed"
                        com.theholylabs.creator.models.GenerationStatus.FAILED -> "failed"
                    }
                },
                onProgress = { msg ->
                    // Could expose as a flow if needed
                }
            )

            if (result != null) {
                _isSaved.value = true
                _processingStatus.value = "completed"
            } else {
                _processingStatus.value = "failed"
                _processingError.value = "Video render failed. Please try again."
            }
            _isExporting.value = false
        }
    }

    fun dismissProcessingModal() {
        _isProcessingModalVisible.value = false
    }

    // Helpers

    private fun isRemoteUrl(uri: String): Boolean {
        return uri.startsWith("http://") || uri.startsWith("https://")
    }

    fun formatTime(ms: Long): String {
        if (ms <= 0) return "0:00"
        val totalSecs = (ms / 1000).toInt()
        val mins = totalSecs / 60
        val secs = totalSecs % 60
        return String.format("%d:%02d", mins, secs)
    }

    override fun onCleared() {
        super.onCleared()
        handler.removeCallbacks(positionUpdateRunnable)
        videoPlayer?.release()
        videoPlayer = null
        musicPlayer?.release()
        musicPlayer = null
    }
}
