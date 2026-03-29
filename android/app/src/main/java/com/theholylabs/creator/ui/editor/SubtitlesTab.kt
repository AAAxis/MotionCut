package com.theholylabs.creator.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.theholylabs.creator.viewmodels.VideoEditorViewModel

@Composable
fun SubtitlesTab(
    viewModel: VideoEditorViewModel,
    modifier: Modifier = Modifier
) {
    val clips by viewModel.clips.collectAsState()
    val burnSubtitles by viewModel.burnSubtitles.collectAsState()

    Column(
        modifier = modifier.padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Burn subtitles switch
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column {
                Text(
                    text = "Burn Subtitles",
                    color = Color.White,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = "Overlay text on video during export",
                    color = Color.Gray,
                    fontSize = 12.sp
                )
            }

            Switch(
                checked = burnSubtitles,
                onCheckedChange = {
                    viewModel.setBurnSubtitles(it)
                    if (it) viewModel.generateSubtitles()
                },
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Color.White,
                    checkedTrackColor = Color(0xFFFF9500),
                    uncheckedThumbColor = Color.White,
                    uncheckedTrackColor = Color(0xFF3A3A3C),
                    uncheckedBorderColor = Color(0xFF555555)
                )
            )
        }

        // Clip text list (only show when enabled)
        if (burnSubtitles) {
            HorizontalDivider(color = Color(0xFF333333))

            clips.forEachIndexed { index, clip ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color(0xFF2A2A2A))
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(24.dp)
                            .clip(RoundedCornerShape(6.dp))
                            .background(Color(0xFFFF9500).copy(alpha = 0.2f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "${index + 1}",
                            color = Color(0xFFFF9500),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    OutlinedTextField(
                        value = clip.text ?: "",
                        onValueChange = { newText -> viewModel.updateClipText(index, newText) },
                        modifier = Modifier.weight(1f),
                        textStyle = androidx.compose.ui.text.TextStyle(color = Color.White, fontSize = 14.sp),
                        placeholder = { Text("Subtitle text...", color = Color.DarkGray, fontSize = 14.sp) },
                        singleLine = true,
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = Color.Transparent,
                            unfocusedContainerColor = Color.Transparent,
                            focusedIndicatorColor = Color(0xFFFF9500),
                            unfocusedIndicatorColor = Color(0xFF3A3A3C)
                        )
                    )
                }
            }
        }
    }
}
