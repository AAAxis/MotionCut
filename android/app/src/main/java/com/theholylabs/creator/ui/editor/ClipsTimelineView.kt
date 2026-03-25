package com.theholylabs.creator.ui.editor

import android.graphics.Bitmap
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.theholylabs.creator.models.Clip
import com.theholylabs.creator.services.ThumbnailService
import com.theholylabs.creator.viewmodels.VideoEditorViewModel
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.random.Random

private const val THUMB_HEIGHT = 52f
private const val MUSIC_ROW_HEIGHT = 36f
private const val TEXT_ROW_HEIGHT = 28f
private const val TIME_RULER_HEIGHT = 22f
private const val MIN_CLIP_WIDTH = 60f
private const val PIXELS_PER_SECOND = 50f

@Composable
fun ClipsTimelineView(
    viewModel: VideoEditorViewModel,
    modifier: Modifier = Modifier
) {
    val clips by viewModel.clips.collectAsState()
    val activeClipIndex by viewModel.activeClipIndex.collectAsState()
    val durationMs by viewModel.durationMs.collectAsState()
    val selectedMusic by viewModel.selectedMusic.collectAsState()

    val density = LocalDensity.current
    val screenWidthDp = LocalConfiguration.current.screenWidthDp
    val screenPaddingDp = (screenWidthDp / 2).dp

    val totalDuration = remember(clips, durationMs) {
        if (clips.size > 1) {
            clips.sumOf { it.beatDuration ?: it.sourceDuration ?: 3.0 }
        } else {
            if (durationMs > 0) durationMs / 1000.0 else (clips.firstOrNull()?.sourceDuration ?: clips.firstOrNull()?.beatDuration ?: 3.0)
        }
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(Color(0xFF1C1C1E))
            .padding(vertical = 4.dp)
    ) {
        // Scrollable content
        Row(
            modifier = Modifier
                .horizontalScroll(rememberScrollState())
                .padding(start = screenPaddingDp, end = screenPaddingDp)
                .padding(vertical = 6.dp)
        ) {
            Column(
                modifier = Modifier.clickable {
                    if (clips.size > 1) viewModel.playAllClips()
                }
            ) {
                // Time ruler
                TimeRuler(totalDuration = totalDuration)

                Spacer(modifier = Modifier.height(4.dp))

                // Video clips row
                Row(
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    modifier = Modifier.height(THUMB_HEIGHT.dp)
                ) {
                    clips.forEachIndexed { index, clip ->
                        FilmstripClipView(
                            clip = clip,
                            index = index,
                            isSelected = index == activeClipIndex,
                            clipWidthDp = clipWidthDp(clip),
                            onTap = {
                                if (index == activeClipIndex && clips.size > 1) {
                                    viewModel.playAllClips()
                                } else {
                                    viewModel.selectClip(index)
                                }
                            },
                            onTrimStartDelta = { deltaDp ->
                                handleTrimDrag(viewModel, index, true, deltaDp, clip)
                            },
                            onTrimEndDelta = { deltaDp ->
                                handleTrimDrag(viewModel, index, false, deltaDp, clip)
                            },
                            onRemove = if (clips.size > 1) {{ viewModel.removeClip(index) }} else null
                        )
                    }
                }

                Spacer(modifier = Modifier.height(6.dp))

                // Music waveform row
                if (selectedMusic != null) {
                    MusicWaveformRow(
                        musicName = selectedMusic?.name ?: "Music",
                        totalDuration = totalDuration
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                }

                // Text track row
                val hasText = clips.any { !it.text.isNullOrEmpty() }
                if (hasText) {
                    TextTrackRow(clips = clips)
                }
            }
        }

        // Center playhead
        Box(
            modifier = Modifier
                .fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Canvas(
                modifier = Modifier
                    .width(12.dp)
                    .fillMaxHeight()
            ) {
                // Triangle
                val triangleWidth = 12.dp.toPx()
                val triangleHeight = 7.dp.toPx()
                val path = Path().apply {
                    moveTo(size.width / 2, 0f)
                    lineTo(size.width / 2 + triangleWidth / 2, triangleHeight)
                    lineTo(size.width / 2 - triangleWidth / 2, triangleHeight)
                    close()
                }
                drawPath(path, Color.White)

                // Vertical line
                drawLine(
                    color = Color.White,
                    start = Offset(size.width / 2, triangleHeight),
                    end = Offset(size.width / 2, size.height),
                    strokeWidth = 1.5.dp.toPx()
                )
            }
        }
    }
}

@Composable
private fun TimeRuler(totalDuration: Double) {
    val interval = if (totalDuration < 10) 1.0 else 2.0
    val tickCount = (totalDuration / interval).toInt() + 1

    Row(
        modifier = Modifier.height(TIME_RULER_HEIGHT.dp)
    ) {
        for (i in 0 until tickCount) {
            val sec = i * interval
            Box(
                modifier = Modifier
                    .width((interval * PIXELS_PER_SECOND).dp)
                    .height(TIME_RULER_HEIGHT.dp),
                contentAlignment = Alignment.CenterStart
            ) {
                Text(
                    text = formatRulerTime(sec),
                    color = Color.Gray.copy(alpha = 0.6f),
                    fontSize = 9.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
        }
    }
}

@Composable
private fun FilmstripClipView(
    clip: Clip,
    index: Int,
    isSelected: Boolean,
    clipWidthDp: Float,
    onTap: () -> Unit,
    onTrimStartDelta: (Float) -> Unit,
    onTrimEndDelta: (Float) -> Unit,
    onRemove: (() -> Unit)?
) {
    val scope = rememberCoroutineScope()
    var thumbnails by remember { mutableStateOf<List<Bitmap>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }

    LaunchedEffect(clip.localUri ?: clip.uri) {
        isLoading = true
        val uri = clip.localUri ?: clip.uri
        val dur = clip.sourceDuration ?: clip.beatDuration ?: 3.0
        val frameCount = max(2, (clipWidthDp / 30).toInt())
        thumbnails = ThumbnailService.generateThumbnails(uri, frameCount, dur)
        isLoading = false
    }

    val handleWidth = if (isSelected) 14.dp else 0.dp

    Row(
        modifier = Modifier.height(THUMB_HEIGHT.dp)
    ) {
        // Left trim handle
        if (isSelected) {
            Box(
                modifier = Modifier
                    .width(14.dp)
                    .height(THUMB_HEIGHT.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(Color.White)
                    .pointerInput(Unit) {
                        detectDragGestures { _, dragAmount ->
                            onTrimStartDelta(dragAmount.x)
                        }
                    },
                contentAlignment = Alignment.Center
            ) {
                Box(
                    modifier = Modifier
                        .width(3.dp)
                        .height(18.dp)
                        .clip(RoundedCornerShape(1.dp))
                        .background(Color.Black.copy(alpha = 0.4f))
                )
            }
        }

        // Clip body
        Box(
            modifier = Modifier
                .width(clipWidthDp.dp)
                .height(THUMB_HEIGHT.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(Color(0xFF2A2A2A))
                .then(
                    if (isSelected) Modifier.border(2.dp, Color.White, RoundedCornerShape(4.dp))
                    else Modifier.border(0.5.dp, Color(0xFF444444), RoundedCornerShape(4.dp))
                )
                .clickable { onTap() },
            contentAlignment = Alignment.Center
        ) {
            if (isLoading || thumbnails.isEmpty()) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 1.5.dp,
                    color = Color(0xFFFF9500)
                )
            } else {
                Row(modifier = Modifier.fillMaxSize()) {
                    thumbnails.forEach { bitmap ->
                        val frameWidth = clipWidthDp / thumbnails.size
                        Canvas(
                            modifier = Modifier
                                .width(frameWidth.dp)
                                .fillMaxHeight()
                        ) {
                            drawImage(
                                image = bitmap.asImageBitmap(),
                                dstOffset = IntOffset.Zero,
                                dstSize = IntSize(size.width.roundToInt(), size.height.roundToInt())
                            )
                        }
                    }
                }
            }
        }

        // Right trim handle
        if (isSelected) {
            Box(
                modifier = Modifier
                    .width(14.dp)
                    .height(THUMB_HEIGHT.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(Color.White)
                    .pointerInput(Unit) {
                        detectDragGestures { _, dragAmount ->
                            onTrimEndDelta(dragAmount.x)
                        }
                    },
                contentAlignment = Alignment.Center
            ) {
                Box(
                    modifier = Modifier
                        .width(3.dp)
                        .height(18.dp)
                        .clip(RoundedCornerShape(1.dp))
                        .background(Color.Black.copy(alpha = 0.4f))
                )
            }
        }
    }
}

@Composable
private fun MusicWaveformRow(musicName: String, totalDuration: Double) {
    val barWidth = max(60f, (totalDuration * PIXELS_PER_SECOND).toFloat())
    val blueColor = Color(0xFF4A90D9)

    Box(
        modifier = Modifier
            .width(barWidth.dp)
            .height(MUSIC_ROW_HEIGHT.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(blueColor.copy(alpha = 0.2f))
            .border(1.dp, blueColor.copy(alpha = 0.5f), RoundedCornerShape(4.dp))
    ) {
        // Waveform bars
        Canvas(modifier = Modifier.fillMaxSize()) {
            val barCount = max(1, (size.width / 3f).toInt())
            for (i in 0 until barCount) {
                val phase = i.toFloat() / barCount
                val envelope = (kotlin.math.sin(phase * Math.PI) * 0.6 + 0.2).toFloat()
                val noise = Random.nextFloat() * 0.6f + 0.4f
                val barH = size.height * envelope * noise
                val x = i * 3f
                drawRect(
                    color = blueColor.copy(alpha = 0.6f),
                    topLeft = Offset(x, size.height - barH),
                    size = androidx.compose.ui.geometry.Size(2f, barH)
                )
            }
        }

        // Music label
        Row(
            modifier = Modifier
                .padding(horizontal = 8.dp)
                .align(Alignment.CenterStart),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(
                imageVector = Icons.Default.MusicNote,
                contentDescription = null,
                tint = blueColor,
                modifier = Modifier.size(10.dp)
            )
            Text(
                text = musicName,
                color = blueColor,
                fontSize = 9.sp,
                maxLines = 1
            )
        }
    }
}

@Composable
private fun TextTrackRow(clips: List<Clip>) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        modifier = Modifier.height(TEXT_ROW_HEIGHT.dp)
    ) {
        clips.forEach { clip ->
            val w = clipWidthDp(clip)
            val text = clip.text ?: ""
            val hasContent = text.isNotEmpty()

            Box(
                modifier = Modifier
                    .width(w.dp)
                    .height(TEXT_ROW_HEIGHT.dp)
                    .clip(RoundedCornerShape(4.dp))
                    .background(if (hasContent) Color(0xFFFF9500).copy(alpha = 0.2f) else Color.Transparent)
                    .then(
                        if (hasContent) Modifier.border(0.5.dp, Color(0xFFFF9500).copy(alpha = 0.4f), RoundedCornerShape(4.dp))
                        else Modifier
                    ),
                contentAlignment = Alignment.CenterStart
            ) {
                if (hasContent) {
                    Text(
                        text = text,
                        color = Color(0xFFFF9500),
                        fontSize = 8.sp,
                        maxLines = 1,
                        modifier = Modifier.padding(horizontal = 6.dp)
                    )
                }
            }
        }
    }
}

private fun clipWidthDp(clip: Clip): Float {
    val dur = clip.beatDuration ?: clip.sourceDuration ?: 3.0
    val trimmedDur = dur * (clip.trimEnd - clip.trimStart) / 100.0
    return max(MIN_CLIP_WIDTH.toDouble(), trimmedDur * PIXELS_PER_SECOND).toFloat()
}

private fun handleTrimDrag(viewModel: VideoEditorViewModel, index: Int, isStart: Boolean, deltaPx: Float) {
    // No clip ref needed - read from viewModel
}

private fun handleTrimDrag(viewModel: VideoEditorViewModel, index: Int, isStart: Boolean, deltaPx: Float, clip: Clip) {
    val dur = clip.beatDuration ?: clip.sourceDuration ?: 3.0
    val totalWidthPx = dur * PIXELS_PER_SECOND
    val pctChange = (deltaPx / totalWidthPx) * 100.0
    if (isStart) {
        val newVal = max(0.0, min(clip.trimEnd - 5, clip.trimStart + pctChange))
        viewModel.updateClipTrimStart(index, newVal)
    } else {
        val newVal = max(clip.trimStart + 5, min(100.0, clip.trimEnd + pctChange))
        viewModel.updateClipTrimEnd(index, newVal)
    }
}

private fun formatRulerTime(seconds: Double): String {
    val m = (seconds / 60).toInt()
    val s = (seconds % 60).toInt()
    val ms = ((seconds % 1) * 10).toInt()
    return if (m > 0) String.format("%02d:%02d", m, s)
    else String.format("00:%02d.%d", s, ms)
}
