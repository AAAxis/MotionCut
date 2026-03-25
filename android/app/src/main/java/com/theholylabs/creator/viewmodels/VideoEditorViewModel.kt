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
    private val userId: String?
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
    private val _activeTab = MutableStateFlow(EditorTab.EDIT)
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
            handler.postDelayed(this, 250L)
        }
    }

    private val isReelMode: Boolean
        get() = _clips.value.any { it.beatDuration != null } && _clips.value.size > 1

    init {
        parseClips()
        setupPlayer()
    }

    private fun parseClips() {
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
                        text = obj["text"]?.jsonPrimitive?.content
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
        val player = ExoPlayer.Builder(context).build()
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
        videoPlayer?.volume = if (muted) 0f else 1f
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
            if (_isPlaying.value) player.play()
        }
        _currentTimeMs.value = 0
    }

    fun updateClipTrimStart(index: Int, value: Double) {
        val clips = _clips.value.toMutableList()
        if (index < 0 || index >= clips.size) return
        clips[index] = clips[index].copy(trimStart = value)
        _clips.value = clips
    }

    fun updateClipTrimEnd(index: Int, value: Double) {
        val clips = _clips.value.toMutableList()
        if (index < 0 || index >= clips.size) return
        clips[index] = clips[index].copy(trimEnd = value)
        _clips.value = clips
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
        val splitPct = (clip.trimStart + clip.trimEnd) / 2.0
        val nextId = (clips.maxOfOrNull { it.id } ?: 0) + 1

        val firstHalf = clip.copy(trimEnd = splitPct)
        val secondHalf = clip.copy(id = nextId, trimStart = splitPct)

        clips[idx] = firstHalf
        clips.add(idx + 1, secondHalf)
        _clips.value = clips
        _activeClipIndex.value = idx + 1
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
            val renderClips = _clips.value.map { c ->
                c.copy(uri = c.localUri ?: c.uri)
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
