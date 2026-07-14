package com.theholylabs.creator.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.MusicOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.media3.ui.AspectRatioFrameLayout
import com.theholylabs.creator.viewmodels.VideoEditorViewModel

@Composable
fun VideoPreviewSection(
    viewModel: VideoEditorViewModel,
    modifier: Modifier = Modifier
) {
    val isPlaying by viewModel.isPlaying.collectAsState()
    val isMuted by viewModel.isMuted.collectAsState()
    val currentTimeMs by viewModel.currentTimeMs.collectAsState()
    val durationMs by viewModel.durationMs.collectAsState()
    val clips by viewModel.clips.collectAsState()
    val activeClipIndex by viewModel.activeClipIndex.collectAsState()
    val aspectRatio by viewModel.aspectRatio.collectAsState()
    val selectedMusic by viewModel.selectedMusic.collectAsState()
    val clipsCached by viewModel.clipsCached.collectAsState()
    val isPreparingSelectedClip by viewModel.isPreparingSelectedClip.collectAsState()

    val maxDimDp = 280.dp
    val density = LocalDensity.current

    val (previewWidth, previewHeight) = remember(aspectRatio) {
        when (aspectRatio) {
            "9:16" -> Pair(maxDimDp * 9f / 16f, maxDimDp)
            "16:9" -> Pair(maxDimDp, maxDimDp * 9f / 16f)
            "4:5" -> Pair(maxDimDp * 4f / 5f, maxDimDp)
            else -> Pair(maxDimDp, maxDimDp) // 1:1
        }
    }

    Column(
        modifier = modifier.padding(vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Video Player
        Box(
            modifier = Modifier
                .size(width = previewWidth, height = previewHeight)
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFF1C1C1E))
                .clickable { viewModel.togglePlayPause() },
            contentAlignment = Alignment.Center
        ) {
            viewModel.videoPlayer?.takeUnless { isPreparingSelectedClip }?.let { player ->
                AndroidView(
                    factory = { ctx ->
                        PlayerView(ctx).apply {
                            this.player = player
                            useController = false
                            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                            setBackgroundColor(android.graphics.Color.parseColor("#1C1C1E"))
                        }
                    },
                    update = { view ->
                        view.player = player
                    },
                    modifier = Modifier.fillMaxSize()
                )
            }

            if (isPreparingSelectedClip || (viewModel.videoPlayer == null && !clipsCached)) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(28.dp),
                        color = Color(0xFFFF9500),
                        strokeWidth = 2.dp
                    )
                    Text(
                        text = "Loading video...",
                        color = Color.White.copy(alpha = 0.72f),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
            }

            // Draggable subtitle overlay
            val burnSubtitles by viewModel.burnSubtitles.collectAsState()
            val subtitleY by viewModel.subtitleYPosition.collectAsState()

            if (burnSubtitles && activeClipIndex >= 0 && activeClipIndex < clips.size) {
                val text = clips[activeClipIndex].text
                if (!text.isNullOrEmpty()) {
                    var containerHeightPx by remember { mutableFloatStateOf(0f) }

                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .onSizeChanged { containerHeightPx = it.height.toFloat() }
                    ) {
                        Text(
                            text = text,
                            color = Color.White,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            textAlign = TextAlign.Center,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp)
                                .offset(y = previewHeight * (subtitleY - 0.5f))
                                .background(Color.Black.copy(alpha = 0.4f), RoundedCornerShape(6.dp))
                                .padding(horizontal = 12.dp, vertical = 4.dp)
                                .pointerInput(Unit) {
                                    detectDragGestures { _, dragAmount ->
                                        if (containerHeightPx > 0) {
                                            val delta = dragAmount.y / containerHeightPx
                                            viewModel.setSubtitleYPosition(subtitleY + delta)
                                        }
                                    }
                                }
                        )
                    }
                }
            }

            // Play/pause overlay
            if (!isPlaying) {
                Icon(
                    imageVector = Icons.Default.PlayArrow,
                    contentDescription = "Play",
                    tint = Color.White.copy(alpha = 0.8f),
                    modifier = Modifier.size(48.dp)
                )
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Controls Row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Mute button
            IconButton(
                onClick = { viewModel.toggleMute() },
                modifier = Modifier.size(36.dp)
            ) {
                Icon(
                    imageVector = if (isMuted) Icons.Default.VolumeOff else Icons.Default.VolumeUp,
                    contentDescription = if (isMuted) "Unmute" else "Mute",
                    tint = Color.Gray,
                    modifier = Modifier.size(20.dp)
                )
            }

            // Play/pause button
            IconButton(
                onClick = { viewModel.togglePlayPause() },
                modifier = Modifier.size(36.dp)
            ) {
                Icon(
                    imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = if (isPlaying) "Pause" else "Play",
                    tint = Color.White,
                    modifier = Modifier.size(22.dp)
                )
            }

            Spacer(modifier = Modifier.width(8.dp))

            // Time display
            Text(
                text = viewModel.formatTime(currentTimeMs),
                color = Color.Gray,
                fontSize = 13.sp,
                fontFamily = FontFamily.Monospace
            )
            Text(
                text = " / ",
                color = Color(0xFF555555),
                fontSize = 13.sp
            )
            Text(
                text = viewModel.formatTime(durationMs),
                color = Color.Gray,
                fontSize = 13.sp,
                fontFamily = FontFamily.Monospace
            )

            Spacer(modifier = Modifier.weight(1f))

            // Remove voiceover/music button
            if (selectedMusic != null) {
                IconButton(
                    onClick = { viewModel.clearMusic() },
                    modifier = Modifier.size(36.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.MusicOff,
                        contentDescription = "Remove voiceover",
                        tint = Color(0xFFFF9500),
                        modifier = Modifier.size(20.dp)
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Timeline Scrubber
        var scrubberWidth by remember { mutableFloatStateOf(1f) }
        val progress = if (durationMs > 0) currentTimeMs.toFloat() / durationMs.toFloat() else 0f

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .height(6.dp)
                .clip(RoundedCornerShape(3.dp))
                .background(Color(0xFF333333))
                .onSizeChanged { scrubberWidth = it.width.toFloat() }
                .pointerInput(Unit) {
                    detectTapGestures { offset ->
                        val pct = (offset.x / scrubberWidth * 100f).coerceIn(0f, 100f)
                        viewModel.seekTo(pct)
                    }
                }
                .pointerInput(Unit) {
                    detectHorizontalDragGestures { change, _ ->
                        val pct = (change.position.x / scrubberWidth * 100f).coerceIn(0f, 100f)
                        viewModel.seekTo(pct)
                    }
                }
        ) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(fraction = progress.coerceIn(0f, 1f))
                    .clip(RoundedCornerShape(3.dp))
                    .background(Color(0xFFFF9500))
            )
        }
    }
}
