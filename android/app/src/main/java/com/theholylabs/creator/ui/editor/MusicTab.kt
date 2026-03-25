package com.theholylabs.creator.ui.editor

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.theholylabs.creator.models.MusicTrack
import com.theholylabs.creator.viewmodels.VideoEditorViewModel
import java.io.File
import java.util.UUID

@Composable
fun MusicTab(
    viewModel: VideoEditorViewModel,
    modifier: Modifier = Modifier
) {
    val selectedMusic by viewModel.selectedMusic.collectAsState()
    val musicVolume by viewModel.musicVolume.collectAsState()
    val context = LocalContext.current

    val filePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult

        // Copy to temp file
        val inputStream = context.contentResolver.openInputStream(uri) ?: return@rememberLauncherForActivityResult
        val fileName = uri.lastPathSegment?.substringAfterLast('/') ?: "music"
        val tempFile = File(context.cacheDir, "user-music-${UUID.randomUUID()}.m4a")
        tempFile.outputStream().use { out -> inputStream.copyTo(out) }
        inputStream.close()

        val trackName = fileName
            .substringBeforeLast(".")
            .replace("_", " ")
            .replace("-", " ")

        val track = MusicTrack(
            id = "user-${UUID.randomUUID()}",
            name = trackName,
            file = tempFile.absolutePath
        )
        viewModel.selectMusicTrack(track)
    }

    Column(
        modifier = modifier.padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Selected Music Banner
        if (selectedMusic != null) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color(0xFF2A2A2A))
                    .border(1.dp, Color(0xFFFF9500).copy(alpha = 0.3f), RoundedCornerShape(12.dp))
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Music icon
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(Color(0xFFFF9500).copy(alpha = 0.12f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.MusicNote,
                        contentDescription = null,
                        tint = Color(0xFFFF9500),
                        modifier = Modifier.size(16.dp)
                    )
                }

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = selectedMusic!!.name,
                        color = Color.White,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1
                    )
                    Text(
                        text = "Currently playing",
                        color = Color.Gray,
                        fontSize = 12.sp
                    )
                }

                IconButton(onClick = { viewModel.clearMusic() }) {
                    Icon(
                        imageVector = Icons.Default.Cancel,
                        contentDescription = "Remove music",
                        tint = Color.Gray,
                        modifier = Modifier.size(20.dp)
                    )
                }
            }

            // Volume Slider
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text("Volume", color = Color.Gray, fontSize = 14.sp)
                    Text(
                        text = "${(musicVolume * 100).toInt()}%",
                        color = Color.Gray,
                        fontSize = 14.sp,
                        fontFamily = FontFamily.Monospace
                    )
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Icon(
                        Icons.Default.VolumeDown,
                        contentDescription = null,
                        tint = Color.Gray,
                        modifier = Modifier.size(14.dp)
                    )

                    Slider(
                        value = musicVolume,
                        onValueChange = { viewModel.setMusicVolume(it) },
                        modifier = Modifier.weight(1f),
                        colors = SliderDefaults.colors(
                            thumbColor = Color(0xFFFF9500),
                            activeTrackColor = Color(0xFFFF9500)
                        )
                    )

                    Icon(
                        Icons.Default.VolumeUp,
                        contentDescription = null,
                        tint = Color.Gray,
                        modifier = Modifier.size(14.dp)
                    )
                }
            }
        }

        // Action Buttons
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            // Add Music
            Button(
                onClick = {
                    filePicker.launch(arrayOf("audio/*"))
                },
                modifier = Modifier.weight(1f),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFFFF9500).copy(alpha = 0.1f),
                    contentColor = Color(0xFFFF9500)
                ),
                shape = RoundedCornerShape(12.dp),
                contentPadding = PaddingValues(vertical = 13.dp)
            ) {
                Icon(Icons.Default.AddCircle, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = if (selectedMusic != null) "Change" else "Add Music",
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            // Extract
            Button(
                onClick = { /* TODO: Extract audio from video - Phase 6 enhancement */ },
                modifier = Modifier.weight(1f),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF4A90D9).copy(alpha = 0.1f),
                    contentColor = Color(0xFF4A90D9)
                ),
                shape = RoundedCornerShape(12.dp),
                contentPadding = PaddingValues(vertical = 13.dp)
            ) {
                Icon(Icons.Default.GraphicEq, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Extract", fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            }
        }

        // Hint
        if (selectedMusic == null) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    Icons.Default.Info,
                    contentDescription = null,
                    tint = Color.Gray,
                    modifier = Modifier.size(13.dp)
                )
                Text(
                    text = "Add a file or extract audio from your video clips",
                    color = Color.Gray,
                    fontSize = 13.sp
                )
            }
        }
    }
}
