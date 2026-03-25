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
        modifier = modifier.padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        if (selectedClip != null) {
            // Clip info header
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Movie,
                    contentDescription = null,
                    tint = Color(0xFFFF9500),
                    modifier = Modifier.size(16.dp)
                )

                val displayName = selectedClip.text?.takeIf { it.isNotEmpty() }
                    ?: selectedClip.name.takeIf { it.isNotEmpty() }
                    ?: "Take ${activeClipIndex + 1}"

                Text(
                    text = displayName,
                    color = Color.White,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )

                Text(
                    text = "Clip ${activeClipIndex + 1} of ${clips.size}",
                    color = Color.Gray,
                    fontSize = 12.sp
                )
            }

            // Navigation (if multiple clips)
            if (clips.size > 1) {
                HorizontalDivider(color = Color(0xFF333333))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Previous
                    TextButton(
                        onClick = {
                            val prev = activeClipIndex - 1
                            if (prev >= 0) viewModel.selectClip(prev)
                        },
                        enabled = activeClipIndex > 0
                    ) {
                        Icon(
                            Icons.Default.ChevronLeft,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                        Text("Previous", fontSize = 14.sp)
                    }

                    // Preview All
                    Button(
                        onClick = { viewModel.playAllClips() },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFFFF9500).copy(alpha = 0.1f),
                            contentColor = Color(0xFFFF9500)
                        ),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)
                    ) {
                        Icon(
                            Icons.Default.PlayArrow,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Preview All", fontSize = 14.sp)
                    }

                    // Next
                    TextButton(
                        onClick = {
                            val next = activeClipIndex + 1
                            if (next < clips.size) viewModel.selectClip(next)
                        },
                        enabled = activeClipIndex < clips.size - 1
                    ) {
                        Text("Next", fontSize = 14.sp)
                        Icon(
                            Icons.Default.ChevronRight,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
            }

            // Clip Actions
            HorizontalDivider(color = Color(0xFF333333))

            Text(
                text = "Clip Actions",
                color = Color.Gray,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold
            )

            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item {
                    EditActionButton(
                        icon = Icons.Default.ContentCut,
                        label = "Cut",
                        onClick = { viewModel.splitClipAtPlayhead() }
                    )
                }
                item {
                    EditActionButton(
                        icon = Icons.Default.ContentCopy,
                        label = "Duplicate",
                        onClick = { viewModel.duplicateClip(activeClipIndex) }
                    )
                }
                if (clips.size > 1) {
                    item {
                        EditActionButton(
                            icon = Icons.Default.Delete,
                            label = "Delete",
                            isDestructive = true,
                            onClick = { viewModel.removeClip(activeClipIndex) }
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
private fun EditActionButton(
    icon: ImageVector,
    label: String,
    isDestructive: Boolean = false,
    onClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .width(68.dp)
            .height(50.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(Color(0xFF2A2A2A))
            .clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            tint = if (isDestructive) Color.Red else Color.White,
            modifier = Modifier.size(18.dp)
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = label,
            color = if (isDestructive) Color.Red else Color.White,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1
        )
    }
}
