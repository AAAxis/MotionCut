package com.theholylabs.creator.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.theholylabs.creator.viewmodels.VideoEditorViewModel

@Composable
fun EditTab(
    viewModel: VideoEditorViewModel,
    modifier: Modifier = Modifier
) {
    val clips by viewModel.clips.collectAsState()
    val activeClipIndex by viewModel.activeClipIndex.collectAsState()

    val selectedClip = if (activeClipIndex in clips.indices) clips[activeClipIndex] else null

    Column(
        modifier = modifier.padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (selectedClip != null) {
            // Clip info
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                val displayName = selectedClip.text?.takeIf { it.isNotEmpty() }
                    ?: selectedClip.name.takeIf { it.isNotEmpty() }
                    ?: "Clip ${activeClipIndex + 1}"

                Text(
                    text = displayName,
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )

                Text(
                    text = "${activeClipIndex + 1}/${clips.size}",
                    color = Color.Gray,
                    fontSize = 12.sp
                )
            }

            // Action chips in one row
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // Navigation
                if (clips.size > 1 && activeClipIndex > 0) {
                    item {
                        ActionChip(
                            icon = Icons.Default.ChevronLeft,
                            label = "Prev",
                            onClick = { viewModel.selectClip(activeClipIndex - 1) }
                        )
                    }
                }
                if (clips.size > 1 && activeClipIndex < clips.size - 1) {
                    item {
                        ActionChip(
                            icon = Icons.Default.ChevronRight,
                            label = "Next",
                            onClick = { viewModel.selectClip(activeClipIndex + 1) }
                        )
                    }
                }

                // Actions
                item {
                    ActionChip(
                        icon = Icons.Default.ContentCut,
                        label = "Cut",
                        onClick = { viewModel.splitClipAtPlayhead() }
                    )
                }
                item {
                    ActionChip(
                        icon = Icons.Default.ContentCopy,
                        label = "Duplicate",
                        onClick = { viewModel.duplicateClip(activeClipIndex) }
                    )
                }
                if (clips.size > 1) {
                    item {
                        ActionChip(
                            icon = Icons.Default.Delete,
                            label = "Delete",
                            color = Color(0xFFFF4444),
                            onClick = { viewModel.removeClip(activeClipIndex) }
                        )
                    }
                }

                // Preview all
                if (clips.size > 1) {
                    item {
                        ActionChip(
                            icon = Icons.Default.PlayArrow,
                            label = "Preview",
                            color = Color(0xFFFF9500),
                            onClick = { viewModel.playAllClips() }
                        )
                    }
                }
            }
        } else {
            Text(
                text = "No clip selected",
                color = Color.Gray,
                fontSize = 15.sp
            )
        }
    }
}

@Composable
private fun ActionChip(
    icon: ImageVector,
    label: String,
    color: Color = Color.White,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .height(36.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(Color(0xFF2A2A2A))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            tint = color,
            modifier = Modifier.size(16.dp)
        )
        Text(
            text = label,
            color = color,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium
        )
    }
}
