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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.theholylabs.creator.models.Clip
import com.theholylabs.creator.services.ThumbnailService
import com.theholylabs.creator.viewmodels.VideoEditorViewModel
import kotlinx.coroutines.flow.collect
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

    // Auto-scroll timeline to follow playhead
    val scrollState = rememberScrollState()
    val pixelsPerSecondPx = with(density) { PIXELS_PER_SECOND.dp.toPx() }

    LaunchedEffect(scrollState, pixelsPerSecondPx, totalDuration) {
        snapshotFlow { scrollState.value }
            .collect { offsetPx ->
                val seconds = offsetPx / max(1f, pixelsPerSecondPx)
                val percent = ((seconds / max(0.1, totalDuration)) * 100.0).toFloat()
                viewModel.seekTo(percent.coerceIn(0f, 100f))
            }
    }

    // Scroll to active clip when clip selection changes (not during playback)
    LaunchedEffect(activeClipIndex) {
        if (clips.size <= 1) return@LaunchedEffect
        val activeIdx = activeClipIndex.coerceIn(0, clips.size - 1)
        val precedingPx = clips.take(activeIdx).sumOf {
            clipWidthDp(it).toDouble() + 2.0 // 2dp gap
        }
        val targetPx = with(density) { precedingPx.dp.toPx().toInt() }
        scrollState.animateScrollTo(targetPx)
    }

    Column(modifier = modifier.fillMaxWidth()) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF1C1C1E))
            .padding(vertical = 4.dp)
    ) {
        Row(
            modifier = Modifier
                .horizontalScroll(scrollState)
                .padding(start = screenPaddingDp, end = screenPaddingDp)
                .padding(vertical = 6.dp)
        ) {
            Column {
                // Time ruler
                TimeRuler(totalDuration = totalDuration)

                Spacer(modifier = Modifier.height(4.dp))

                // Video clips row with long-press drag reorder
                var draggedIndex by remember { mutableStateOf(-1) }
                var dragOffsetX by remember { mutableStateOf(0f) }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    modifier = Modifier.height(THUMB_HEIGHT.dp)
                ) {
                    clips.forEachIndexed { index, clip ->
                        val clipW = clipWidthDp(clip, if (clips.size == 1) totalDuration else null)
                        val isDragged = draggedIndex == index

                        Box(
                            modifier = Modifier
                                .zIndex(if (isDragged) 1f else 0f)
                                .graphicsLayer {
                                    if (isDragged) {
                                        translationX = dragOffsetX
                                        alpha = 0.8f
                                        scaleY = 1.05f
                                    }
                                }
                                .pointerInput(index) {
                                    detectTapGestures(
                                        onTap = {
                                            if (index == activeClipIndex && clips.size > 1) {
                                                viewModel.playAllClips()
                                            } else {
                                                viewModel.selectClip(index)
                                            }
                                        },
                                        onLongPress = {
                                            draggedIndex = index
                                            dragOffsetX = 0f
                                        }
                                    )
                                }
                                .then(
                                    if (isDragged) {
                                        Modifier.pointerInput(Unit) {
                                            detectDragGestures(
                                                onDragEnd = {
                                                    draggedIndex = -1
                                                    dragOffsetX = 0f
                                                },
                                                onDragCancel = {
                                                    draggedIndex = -1
                                                    dragOffsetX = 0f
                                                },
                                                onDrag = { change, dragAmount ->
                                                    change.consume()
                                                    dragOffsetX += dragAmount.x
                                                    // Calculate target index based on drag distance
                                                    val avgClipWidth = with(density) { clipW.dp.toPx() }
                                                    val movedSlots = (dragOffsetX / avgClipWidth).toInt()
                                                    val targetIndex = (index + movedSlots).coerceIn(0, clips.size - 1)
                                                    if (targetIndex != index) {
                                                        viewModel.reorderClips(index, targetIndex)
                                                        draggedIndex = targetIndex
                                                        dragOffsetX = 0f
                                                    }
                                                }
                                            )
                                        }
                                    } else Modifier
                                )
                        ) {
                            FilmstripClipView(
                                clip = clip,
                                index = index,
                                isSelected = index == activeClipIndex,
                                isTrimMode = false,
                                clipWidthDp = clipW,
                                onTap = {},
                                onLongPress = {},
                                onTrimStartDelta = {},
                                onTrimEndDelta = {},
                                onRemove = if (clips.size > 1) {{ viewModel.removeClip(index) }} else null
                            )
                        }
                    }

                    // Add clip button — opens stock search directly
                    Box(
                        modifier = Modifier
                            .width(48.dp)
                            .height(THUMB_HEIGHT.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(Color(0xFF2A2A2A))
                            .border(1.dp, Color(0xFFFF9500).copy(alpha = 0.5f), RoundedCornerShape(4.dp))
                            .clickable { viewModel.requestGalleryPick() },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Add,
                            contentDescription = "Add clip",
                            tint = Color(0xFFFF9500),
                            modifier = Modifier.size(24.dp)
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
                    TextTrackRow(clips = clips, fallbackDuration = if (clips.size == 1) totalDuration else null)
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

    // CapCut-style trim bar — full width, clip filmstrip with edge handles
    if (activeClipIndex >= 0 && activeClipIndex < clips.size) {
        val clip = clips[activeClipIndex]
        val dur = clip.beatDuration ?: clip.sourceDuration ?: if (clips.size == 1 && durationMs > 0) durationMs / 1000.0 else 3.0
        val trimmedStart = dur * clip.trimStart / 100.0
        val trimmedEnd = dur * clip.trimEnd / 100.0

        var startPct by remember(activeClipIndex, clip.trimStart) { mutableFloatStateOf(clip.trimStart.toFloat()) }
        var endPct by remember(activeClipIndex, clip.trimEnd) { mutableFloatStateOf(clip.trimEnd.toFloat()) }
        var containerWidth by remember { mutableFloatStateOf(1f) }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0xFF111111))
                .padding(vertical = 4.dp)
        ) {
            // Time labels
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    String.format("%.1fs", dur * startPct / 100),
                    color = Color(0xFFFF9500), fontSize = 11.sp, fontFamily = FontFamily.Monospace
                )
                Text(
                    String.format("%.1fs / %.1fs", dur * (endPct - startPct) / 100, dur),
                    color = Color.Gray, fontSize = 11.sp, fontFamily = FontFamily.Monospace
                )
                Text(
                    String.format("%.1fs", dur * endPct / 100),
                    color = Color(0xFFFF9500), fontSize = 11.sp, fontFamily = FontFamily.Monospace
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            // Trim frame
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .padding(horizontal = 12.dp)
                    .onSizeChanged { containerWidth = it.width.toFloat() }
            ) {
                // Dimmed background (full clip)
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color(0xFF2A2A2A))
                )

                // Active region (trimmed area)
                val leftFraction = startPct / 100f
                val rightFraction = endPct / 100f

                Box(
                    modifier = Modifier
                        .fillMaxHeight()
                        .fillMaxWidth(rightFraction - leftFraction)
                        .offset(x = with(LocalDensity.current) { (containerWidth * leftFraction).toDp() })
                        .clip(RoundedCornerShape(2.dp))
                        .background(Color(0xFF3A3A3C))
                        .border(2.dp, Color(0xFFFF9500), RoundedCornerShape(2.dp))
                )

                // Left handle
                Box(
                    modifier = Modifier
                        .fillMaxHeight()
                        .width(22.dp)
                        .offset(x = with(LocalDensity.current) { (containerWidth * leftFraction).toDp() - 11.dp })
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color(0xFFFF9500))
                        .pointerInput(Unit) {
                            awaitPointerEventScope {
                                while (true) {
                                    val down = awaitPointerEvent(PointerEventPass.Initial)
                                    down.changes.forEach { it.consume() }
                                    val id = down.changes.firstOrNull()?.id ?: continue
                                    while (true) {
                                        val ev = awaitPointerEvent(PointerEventPass.Initial)
                                        val ch = ev.changes.firstOrNull { it.id == id }
                                        if (ch == null || !ch.pressed) break
                                        val dx = ch.position.x - ch.previousPosition.x
                                        val pctDelta = (dx / containerWidth) * 100f
                                        startPct = (startPct + pctDelta).coerceIn(0f, endPct - 5f)
                                        viewModel.updateClipTrimStart(activeClipIndex, startPct.toDouble())
                                        ch.consume()
                                    }
                                }
                            }
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .width(3.dp)
                            .height(20.dp)
                            .clip(RoundedCornerShape(1.dp))
                            .background(Color.White.copy(alpha = 0.8f))
                    )
                }

                // Right handle
                Box(
                    modifier = Modifier
                        .fillMaxHeight()
                        .width(22.dp)
                        .offset(x = with(LocalDensity.current) { (containerWidth * rightFraction).toDp() - 11.dp })
                        .clip(RoundedCornerShape(6.dp))
                        .background(Color(0xFFFF9500))
                        .pointerInput(Unit) {
                            awaitPointerEventScope {
                                while (true) {
                                    val down = awaitPointerEvent(PointerEventPass.Initial)
                                    down.changes.forEach { it.consume() }
                                    val id = down.changes.firstOrNull()?.id ?: continue
                                    while (true) {
                                        val ev = awaitPointerEvent(PointerEventPass.Initial)
                                        val ch = ev.changes.firstOrNull { it.id == id }
                                        if (ch == null || !ch.pressed) break
                                        val dx = ch.position.x - ch.previousPosition.x
                                        val pctDelta = (dx / containerWidth) * 100f
                                        endPct = (endPct + pctDelta).coerceIn(startPct + 5f, 100f)
                                        viewModel.updateClipTrimEnd(activeClipIndex, endPct.toDouble())
                                        ch.consume()
                                    }
                                }
                            }
                        },
                    contentAlignment = Alignment.Center
                ) {
                    Box(
                        modifier = Modifier
                            .width(3.dp)
                            .height(20.dp)
                            .clip(RoundedCornerShape(1.dp))
                            .background(Color.White.copy(alpha = 0.8f))
                    )
                }
            }
        }
    }

    } // Column
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
    isTrimMode: Boolean = false,
    clipWidthDp: Float,
    onTap: () -> Unit,
    onLongPress: () -> Unit = {},
    onTrimStartDelta: (Float) -> Unit,
    onTrimEndDelta: (Float) -> Unit,
    onRemove: (() -> Unit)?
) {
    var thumbnails by remember { mutableStateOf<List<Bitmap>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }

    // Only regenerate thumbnails when URI changes, not on trim drag
    val clipUri = clip.localUri ?: clip.uri
    LaunchedEffect(clipUri) {
        isLoading = true
        val dur = clip.sourceDuration ?: clip.beatDuration ?: 3.0
        val frameCount = max(2, (clipWidthDp / 30).toInt())
        thumbnails = ThumbnailService.generateThumbnails(clipUri, frameCount, dur)
        isLoading = false
    }

    val handleWidth = if (isSelected) 14.dp else 0.dp

    Row(
        modifier = Modifier.height(THUMB_HEIGHT.dp)
    ) {
        // Left trim handle (only in trim mode after long-press)
        if (isTrimMode) {
            TrimHandle(onDelta = onTrimStartDelta)
        }

        // Clip body
        Box(
            modifier = Modifier
                .width(clipWidthDp.dp)
                .height(THUMB_HEIGHT.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(Color(0xFF2A2A2A))
                .then(
                    if (isTrimMode) Modifier.border(2.dp, Color(0xFFFF9500), RoundedCornerShape(4.dp))
                    else if (isSelected) Modifier.border(2.dp, Color.White, RoundedCornerShape(4.dp))
                    else Modifier.border(0.5.dp, Color(0xFF444444), RoundedCornerShape(4.dp))
                )
                .pointerInput(Unit) {
                    detectTapGestures(
                        onTap = { onTap() },
                        onLongPress = { onLongPress() }
                    )
                },
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

        // Right trim handle (only in trim mode after long-press)
        if (isTrimMode) {
            TrimHandle(onDelta = onTrimEndDelta)
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
private fun TextTrackRow(clips: List<Clip>, fallbackDuration: Double? = null) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        modifier = Modifier.height(TEXT_ROW_HEIGHT.dp)
    ) {
        clips.forEach { clip ->
            val w = clipWidthDp(clip, fallbackDuration)
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

@Composable
private fun TrimHandle(onDelta: (Float) -> Unit) {
    Box(
        modifier = Modifier
            .width(20.dp)
            .height(THUMB_HEIGHT.dp)
            .clip(RoundedCornerShape(4.dp))
            .background(Color(0xFFFF9500))
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        val down = awaitPointerEvent(PointerEventPass.Initial)
                        val pointerId = down.changes.firstOrNull()?.id ?: continue
                        down.changes.forEach { it.consume() }

                        // Drag loop
                        while (true) {
                            val event = awaitPointerEvent(PointerEventPass.Initial)
                            val change = event.changes.firstOrNull { it.id == pointerId }
                            if (change == null || !change.pressed) break
                            val dx = change.position.x - change.previousPosition.x
                            if (dx != 0f) onDelta(dx)
                            change.consume()
                        }

                    }
                }
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .width(3.dp)
                .height(18.dp)
                .clip(RoundedCornerShape(1.dp))
                .background(Color.White.copy(alpha = 0.7f))
        )
    }
}

private fun clipWidthDp(clip: Clip, fallbackDuration: Double? = null): Float {
    val dur = clip.beatDuration ?: clip.sourceDuration ?: fallbackDuration ?: 3.0
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
