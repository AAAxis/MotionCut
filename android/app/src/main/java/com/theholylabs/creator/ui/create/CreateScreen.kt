package com.theholylabs.creator.ui.create

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.VideoFile
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.theholylabs.creator.AppState
import com.theholylabs.creator.AppUiState
import com.theholylabs.creator.BuildConfig
import androidx.media3.common.util.UnstableApi
import com.theholylabs.creator.models.LANGUAGES
import com.theholylabs.creator.models.PRESET_AI_MODELS
import com.theholylabs.creator.viewmodels.CreateMode
import com.theholylabs.creator.viewmodels.CreateViewModel
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

@UnstableApi
@Composable
fun CreateScreen(
    appState: AppState,
    uiState: AppUiState,
    onBuyCredits: () -> Unit,
    onNavigateToStatus: (String) -> Unit,
    onEditVideo: (videoUri: String, videoName: String, takesJson: String?, musicUrl: String?, generationId: String?) -> Unit = { _, _, _, _, _ -> },
    onSwitchToLibrary: () -> Unit = {},
    vm: CreateViewModel = viewModel()
) {
    val mode by vm.mode.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val errorMessage by vm.errorMessage.collectAsState()
    val lastTakesJson by vm.lastTakesJson.collectAsState()
    val lastMusicPath by vm.lastMusicPath.collectAsState()
    val switchToLibrary by vm.switchToLibrary.collectAsState()

    LaunchedEffect(switchToLibrary) {
        if (switchToLibrary) {
            vm.clearSwitchToLibrary()
            onSwitchToLibrary()
        }
    }

    // Clear stale takes data after generation (no longer auto-opening editor)
    LaunchedEffect(lastTakesJson) {
        if (lastTakesJson != null) {
            vm.clearLastResult()
        }
    }

    LaunchedEffect(uiState.userId) {
        uiState.userId?.let { vm.loadAvatars(it) }
    }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
                .verticalScroll(rememberScrollState())
        ) {
            Spacer(modifier = Modifier.height(16.dp))
            
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "Create",
                    fontSize = 29.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )

                Button(
                    onClick = onBuyCredits,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFFFF9500).copy(alpha = 0.12f),
                        contentColor = Color(0xFFFF9500)
                    ),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                    modifier = Modifier.height(36.dp),
                    shape = RoundedCornerShape(18.dp)
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Default.Bolt,
                            contentDescription = null,
                            modifier = Modifier.size(14.dp)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = if (uiState.credits >= 0) "${uiState.credits}" else "∞",
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Mode Toggle
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF1C1C1E), RoundedCornerShape(14.dp))
                    .padding(4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                listOf(CreateMode.REEL, CreateMode.AD).forEach { m ->
                    val selected = mode == m
                    Button(
                        onClick = { vm.setMode(m) },
                        modifier = Modifier
                            .weight(1f)
                            .height(44.dp),
                        shape = RoundedCornerShape(11.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (selected) Color(0xFFFF9500) else Color.Transparent,
                            contentColor = if (selected) Color.White else Color.Gray
                        ),
                        contentPadding = PaddingValues(0.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = if (m == CreateMode.REEL) Icons.Default.Bolt else Icons.Default.Movie,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(modifier = Modifier.width(6.dp))
                            Text(
                                text = if (m == CreateMode.REEL) "AI Influencer" else "Video Ad",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Mode Content
            when (mode) {
                CreateMode.REEL -> ReelCreatorView(vm, appState, onNavigateToStatus)
                CreateMode.AD -> AdCreatorView(vm, appState, onNavigateToStatus)
            }
            
            if (errorMessage != null) {
                Text(
                    text = errorMessage!!,
                    color = MaterialTheme.colorScheme.error,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(vertical = 16.dp)
                )
            }

            Spacer(modifier = Modifier.height(100.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReelCreatorView(vm: CreateViewModel, appState: AppState, onNavigateToStatus: (String) -> Unit) {
    val topic by vm.reelTopic.collectAsState()
    val selectedId by vm.selectedModelId.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val uploadedAvatars by vm.uploadedAvatars.collectAsState()
    val referenceVideoUri by vm.reelReferenceVideoUri.collectAsState()

    val context = LocalContext.current
    var referenceVideoBytes by remember { mutableStateOf<ByteArray?>(null) }
    var referenceVideoThumbnail by remember { mutableStateOf<Bitmap?>(null) }

    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let {
            val inputStream = context.contentResolver.openInputStream(it)
            val bitmap = BitmapFactory.decodeStream(inputStream)
            val outputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 85, outputStream)
            vm.uploadAvatar(outputStream.toByteArray(), appState.userId ?: "demo-user")
        }
    }

    val videoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let {
            vm.reelReferenceVideoUri.value = it
            val inputStream = context.contentResolver.openInputStream(it)
            referenceVideoBytes = inputStream?.readBytes()
        }
    }

    // Generate thumbnail when reference video changes
    LaunchedEffect(referenceVideoUri) {
        if (referenceVideoUri != null) {
            referenceVideoThumbnail = withContext(Dispatchers.IO) {
                try {
                    val retriever = MediaMetadataRetriever()
                    retriever.setDataSource(context, referenceVideoUri)
                    val frame = retriever.getFrameAtTime(500_000L)
                    retriever.release()
                    frame
                } catch (e: Exception) { null }
            }
        } else {
            referenceVideoThumbnail = null
        }
    }

    Column(modifier = Modifier.fillMaxWidth()) {
        SectionLabel("TOPIC / CONCEPT")

        // Combined chatbox: text field + reference video inside one container
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0xFF1C1C1E), RoundedCornerShape(14.dp))
                .border(1.dp, Color(0xFF3A3A3C), RoundedCornerShape(14.dp))
                .padding(horizontal = 14.dp, vertical = 10.dp)
        ) {
            BasicTextField(
                value = topic,
                onValueChange = { vm.reelTopic.value = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 80.dp),
                textStyle = androidx.compose.ui.text.TextStyle(
                    color = Color.White,
                    fontSize = 16.sp
                ),
                decorationBox = { innerTextField ->
                    Box {
                        if (topic.isEmpty()) {
                            Text(
                                "e.g. traveling without eSIM, hustle culture, Monday motivation...",
                                color = Color.DarkGray,
                                fontSize = 16.sp
                            )
                        }
                        innerTextField()
                    }
                }
            )

            if (referenceVideoUri != null) {
                Spacer(modifier = Modifier.height(10.dp))
                HorizontalDivider(color = Color(0xFF3A3A3C))
                Spacer(modifier = Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(width = 80.dp, height = 56.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0xFF2C2C2E)),
                        contentAlignment = Alignment.Center
                    ) {
                        if (referenceVideoThumbnail != null) {
                            androidx.compose.foundation.Image(
                                bitmap = referenceVideoThumbnail!!.asImageBitmap(),
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.fillMaxSize()
                            )
                        } else {
                            Icon(Icons.Default.Movie, contentDescription = null, tint = Color.Gray, modifier = Modifier.size(28.dp))
                        }
                    }
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Movement reference", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                        Text(
                            referenceVideoUri!!.lastPathSegment ?: "video.mp4",
                            fontSize = 11.sp,
                            color = Color.Gray,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
                        )
                    }
                    IconButton(onClick = {
                        vm.reelReferenceVideoUri.value = null
                        referenceVideoBytes = null
                    }) {
                        Icon(Icons.Default.Clear, contentDescription = "Remove", tint = Color.Gray, modifier = Modifier.size(20.dp))
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))
            HorizontalDivider(color = Color(0xFF3A3A3C))
            Spacer(modifier = Modifier.height(8.dp))

            // Attachment button row inside chatbox
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(
                    onClick = { videoPickerLauncher.launch("video/*") },
                    modifier = Modifier.size(36.dp)
                ) {
                    Icon(
                        Icons.Default.VideoFile,
                        contentDescription = "Add movement video",
                        tint = Color(0xFFFF9500),
                        modifier = Modifier.size(22.dp)
                    )
                }
                Text(
                    "Add movement video (optional)",
                    fontSize = 12.sp,
                    color = Color.Gray,
                    modifier = Modifier
                        .clickable { videoPickerLauncher.launch("video/*") }
                        .weight(1f)
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        SectionLabel("AI MODEL")

        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(vertical = 8.dp)
        ) {
            items(PRESET_AI_MODELS) { model ->
                val isSelected = selectedId == model.id
                AvatarThumbnail(
                    isSelected = isSelected,
                    imageUrl = model.imageURL,
                    label = model.name.split(" ").last(),
                    onClick = { vm.selectModel(model.id) }
                )
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = { vm.generateReel(appState, referenceVideoBytes, onNavigateToStatus) },
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            shape = RoundedCornerShape(16.dp),
            enabled = !isLoading,
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF9500))
        ) {
            if (isLoading) {
                CircularProgressIndicator(modifier = Modifier.size(24.dp), color = Color.White)
            } else {
                Icon(Icons.Default.Bolt, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                val reelCost = remember(selectedId) { vm.getSelectedModelCost() }
                Text("Generate Reel \u00b7 $reelCost credits", fontWeight = FontWeight.Bold, fontSize = 17.sp)
            }
        }
    }
}

@Composable
fun AvatarThumbnail(isSelected: Boolean, imageUrl: String, label: String, onClick: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .width(80.dp)
            .clickable { onClick() }
    ) {
        Box(
            modifier = Modifier
                .size(70.dp)
                .clip(CircleShape)
                .border(
                    2.dp,
                    if (isSelected) Color(0xFFFF9500) else Color.Transparent,
                    CircleShape
                )
        ) {
            AsyncImage(
                model = imageUrl,
                contentDescription = label,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = label,
            fontSize = 11.sp,
            color = if (isSelected) Color.White else Color.Gray,
            fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@UnstableApi
@Composable
fun AdCreatorView(vm: CreateViewModel, appState: AppState, onNavigateToStatus: (String) -> Unit) {
    val url by vm.adURL.collectAsState()
    val prompt by vm.adPrompt.collectAsState()
    val selectedLang by vm.adLanguage.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val adSource by vm.adVideoSource.collectAsState()
    val progress by vm.generationProgress.collectAsState()

    Column(modifier = Modifier.fillMaxWidth()) {

        SectionLabel("DESCRIBE CONCEPT")

        OutlinedTextField(
            value = prompt,
            onValueChange = { newValue ->
                vm.adPrompt.value = newValue
                // Auto-detect URLs in the text
                val urlRegex = Regex("""https?://\S+|www\.\S+|\S+\.\w{2,}/\S*""")
                val found = urlRegex.find(newValue)
                if (found != null) {
                    val detectedUrl = found.value.let { if (!it.startsWith("http")) "https://$it" else it }
                    vm.adURL.value = detectedUrl
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .height(120.dp),
            placeholder = { Text("Describe your video or paste a link\ne.g. A 30-second promo for our sneaker line https://example.com", color = Color.DarkGray) },
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Color(0xFF1C1C1E),
                unfocusedContainerColor = Color(0xFF1C1C1E),
                focusedTextColor = Color.White,
                unfocusedTextColor = Color.White,
                focusedIndicatorColor = Color(0xFF3A3A3C),
                unfocusedIndicatorColor = Color(0xFF3A3A3C)
            ),
            shape = RoundedCornerShape(14.dp)
        )

        // Show detected URL chip
        if (url.isNotEmpty()) {
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color(0xFFFF9500).copy(alpha = 0.1f))
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Link detected: ", color = Color.Gray, fontSize = 12.sp)
                Text(
                    text = url.take(40) + if (url.length > 40) "..." else "",
                    color = Color(0xFFFF9500),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        Spacer(modifier = Modifier.height(20.dp))

        SectionLabel("VOICEOVER LANGUAGE")

        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(LANGUAGES) { lang ->
                val isSelected = selectedLang == lang.id
                Button(
                    onClick = { vm.adLanguage.value = lang.id },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (isSelected) Color(0xFFFF9500).copy(alpha = 0.1f) else Color(0xFF1C1C1E),
                        contentColor = if (isSelected) Color(0xFFFF9500) else Color.White
                    ),
                    modifier = Modifier.height(40.dp),
                    shape = RoundedCornerShape(12.dp),
                    border = BorderStroke(1.dp, if (isSelected) Color(0xFFFF9500) else Color(0xFF3A3A3C))
                ) {
                    Text(text = "${flagEmoji(lang.flag)} ${lang.label}", fontSize = 14.sp)
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Progress indicator for Stock mode
        if (adSource == com.theholylabs.creator.viewmodels.AdVideoSource.STOCK && progress != null) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 16.dp)
            ) {
                Text(
                    text = progress!!.step,
                    fontSize = 14.sp,
                    color = Color(0xFFFF9500),
                    modifier = Modifier.padding(bottom = 6.dp)
                )
                LinearProgressIndicator(
                    progress = { progress!!.progress },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(4.dp),
                    color = Color(0xFFFF9500),
                    trackColor = Color(0xFF1C1C1E),
                )
            }
        }

        Button(
            onClick = {
                vm.generateFreeReel(appState, onNavigateToStatus)
            },
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            enabled = !isLoading && prompt.isNotBlank(),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF9500))
        ) {
            if (isLoading) {
                CircularProgressIndicator(modifier = Modifier.size(24.dp), color = Color.White)
                if (adSource == com.theholylabs.creator.viewmodels.AdVideoSource.STOCK && progress != null) {
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(progress?.step ?: "Generating...", fontWeight = FontWeight.Bold, fontSize = 15.sp)
                }
            } else {
                val cost = if (adSource == com.theholylabs.creator.viewmodels.AdVideoSource.STOCK) vm.STOCK_FOOTAGE_COST else vm.getSelectedModelCost()
                Text("Generate Video \u00b7 $cost credits", fontWeight = FontWeight.Bold, fontSize = 17.sp)
            }
        }
    }
}

@Composable
fun SectionLabel(text: String) {
    Text(
        text = text,
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        color = Color.Gray,
        letterSpacing = 0.5.sp,
        modifier = Modifier.padding(bottom = 8.dp)
    )
}

private fun flagEmoji(code: String): String {
    val base = 127397
    return code.uppercase().map { it.code + base }.map { Character.toChars(it) }.joinToString("") { String(it) }
}
