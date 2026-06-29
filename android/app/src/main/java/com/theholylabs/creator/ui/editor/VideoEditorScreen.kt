package com.theholylabs.creator.ui.editor

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import com.theholylabs.creator.models.PRESET_AI_MODELS
import com.theholylabs.creator.viewmodels.VideoEditorViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class EditorTab(val label: String) {
    SUBTITLES("Subs"),
    MUSIC("Music")
}

class VideoEditorViewModelFactory(
    private val application: Application,
    private val videoUri: String,
    private val videoName: String,
    private val takesJson: String?,
    private val musicUrl: String?,
    private val userId: String?,
    private val generationId: String?
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return VideoEditorViewModel(application, videoUri, videoName, takesJson, musicUrl, userId, generationId) as T
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoEditorScreen(
    videoUri: String,
    videoName: String,
    takesJson: String?,
    musicUrl: String?,
    userId: String?,
    generationId: String? = null,
    onClose: () -> Unit
) {
    val context = LocalContext.current
    val viewModel: VideoEditorViewModel = viewModel(
        factory = VideoEditorViewModelFactory(
            application = context.applicationContext as Application,
            videoUri = videoUri,
            videoName = videoName,
            takesJson = takesJson,
            musicUrl = musicUrl,
            userId = userId,
            generationId = generationId
        )
    )

    val activeTab by viewModel.activeTab.collectAsState()
    val isExporting by viewModel.isExporting.collectAsState()
    val isSaved by viewModel.isSaved.collectAsState()
    val isProcessingModalVisible by viewModel.isProcessingModalVisible.collectAsState()
    val processingStatus by viewModel.processingStatus.collectAsState()
    val processingError by viewModel.processingError.collectAsState()
    val showAddClipSheet by viewModel.showAddClipSheet.collectAsState()
    val showPexelsSearch by viewModel.showPexelsSearch.collectAsState()
    val pexelsQuery by viewModel.pexelsQuery.collectAsState()
    val pexelsResults by viewModel.pexelsResults.collectAsState()
    val pexelsLoading by viewModel.pexelsLoading.collectAsState()
    val isDownloadingClip by viewModel.isDownloadingClip.collectAsState()
    val showBottomSheet by viewModel.showBottomSheet.collectAsState()

    // Video picker — copy to local file so thumbnails and export work
    val scope = rememberCoroutineScope()
    val videoPickerLauncher = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.GetContent()
    ) { uri ->
        uri?.let { selectedUri ->
            scope.launch(kotlinx.coroutines.Dispatchers.IO) {
                val localFile = java.io.File(
                    context.cacheDir,
                    "gallery_${System.currentTimeMillis()}.mp4"
                )
                context.contentResolver.openInputStream(selectedUri)?.use { input ->
                    localFile.outputStream().use { output -> input.copyTo(output) }
                }
                if (localFile.exists() && localFile.length() > 0) {
                    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
                        viewModel.addClipFromUri(localFile.absolutePath)
                        viewModel.hideAddClipSheet()
                    }
                }
            }
        }
    }

    // Pre-cache clips on launch
    LaunchedEffect(Unit) {
        viewModel.preCacheClips()
    }

    // Gallery pick trigger from timeline "+" button
    val galleryPickRequested by viewModel.requestGalleryPick.collectAsState()
    LaunchedEffect(galleryPickRequested) {
        if (galleryPickRequested) {
            videoPickerLauncher.launch("video/*")
            viewModel.clearGalleryPickRequest()
        }
    }

    // Auto-close editor after save
    LaunchedEffect(isSaved) {
        if (isSaved) {
            kotlinx.coroutines.delay(1200)
            onClose()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(videoName, maxLines = 1, fontSize = 16.sp) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Default.Close, contentDescription = "Close")
                    }
                },
                actions = {
                    // Save/Export button in top bar
                    Button(
                        onClick = { viewModel.exportVideo() },
                        enabled = !isExporting,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFFFF9500),
                            contentColor = Color.White
                        ),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp),
                        shape = RoundedCornerShape(20.dp),
                        modifier = Modifier.height(34.dp)
                    ) {
                        if (isExporting) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), color = Color.White, strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Default.Save, contentDescription = null, modifier = Modifier.size(16.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Save", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Black,
                    titleContentColor = Color.White,
                    navigationIconContentColor = Color.White
                )
            )
        },
        containerColor = Color.Black
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
        ) {
            // Scrollable content
            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
            ) {
                // Video Preview
                VideoPreviewSection(viewModel = viewModel)

                // Multi-track Timeline
                ClipsTimelineView(viewModel = viewModel)

                // Clip action bar (always visible)
                ClipActionBar(viewModel = viewModel)

            }

        }
    }

    // Processing Modal Overlay
    if (isProcessingModalVisible) {
        ProcessingModal(
            status = processingStatus,
            error = processingError,
            onDismiss = { viewModel.dismissProcessingModal() }
        )
    }
    // Downloading clip dialog
    if (isDownloadingClip) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = {},
            title = null,
            text = {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(32.dp),
                        color = Color(0xFFFF9500),
                        strokeWidth = 3.dp
                    )
                    Text("Downloading clip...", color = Color.White, fontSize = 16.sp)
                }
            },
            confirmButton = {},
            containerColor = Color(0xFF1C1C1E),
            textContentColor = Color.White
        )
    }

    // Add Clip Bottom Sheet
    if (showAddClipSheet) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { viewModel.hideAddClipSheet() },
            title = { Text("Add Clip") },
            text = {
                Column(verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp)) {
                    androidx.compose.material3.Button(
                        onClick = {
                            videoPickerLauncher.launch("video/*")
                        },
                        modifier = Modifier.fillMaxWidth(),
                        colors = androidx.compose.material3.ButtonDefaults.buttonColors(containerColor = Color(0xFFFF9500))
                    ) {
                        Text("From Device")
                    }
                    androidx.compose.material3.OutlinedButton(
                        onClick = { viewModel.showPexelsSearch() },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Search Stock Videos")
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { viewModel.hideAddClipSheet() }) {
                    Text("Cancel")
                }
            },
            containerColor = Color(0xFF1C1C1E),
            titleContentColor = Color.White,
            textContentColor = Color.White
        )
    }

    // Subs/Music Bottom Sheet
    if (showBottomSheet) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { viewModel.showBottomSheet(false) },
            title = { Text(if (activeTab == EditorTab.SUBTITLES) "Subtitles" else "Music") },
            text = {
                when (activeTab) {
                    EditorTab.SUBTITLES -> SubtitlesTab(viewModel = viewModel)
                    EditorTab.MUSIC -> MusicTab(viewModel = viewModel)
                }
            },
            confirmButton = {
                TextButton(onClick = { viewModel.showBottomSheet(false) }) {
                    Text("Done", color = Color(0xFFFF9500))
                }
            },
            containerColor = Color(0xFF1C1C1E),
            titleContentColor = Color.White,
            textContentColor = Color.White
        )
    }

    // Pexels Search Dialog
    val pexelsReplaceMode by viewModel.pexelsReplaceMode.collectAsState()
    if (showPexelsSearch) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { viewModel.hidePexelsSearch() },
            title = { Text(if (pexelsReplaceMode) "Replace Clip" else "Search Stock Videos") },
            text = {
                Column(verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp)) {
                    androidx.compose.material3.OutlinedTextField(
                        value = pexelsQuery,
                        onValueChange = { viewModel.setPexelsQuery(it) },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("e.g. city, nature, business...", color = Color.DarkGray) },
                        singleLine = true,
                        trailingIcon = {
                            androidx.compose.material3.IconButton(
                                onClick = { viewModel.searchPexels() },
                                enabled = pexelsQuery.isNotBlank() && !pexelsLoading
                            ) {
                                if (pexelsLoading) {
                                    CircularProgressIndicator(modifier = Modifier.size(18.dp), color = Color(0xFFFF9500), strokeWidth = 2.dp)
                                } else {
                                    Icon(
                                        imageVector = Icons.Default.Search,
                                        contentDescription = "Search",
                                        tint = if (pexelsQuery.isNotBlank()) Color(0xFFFF9500) else Color.Gray
                                    )
                                }
                            }
                        },
                        colors = androidx.compose.material3.TextFieldDefaults.colors(
                            focusedContainerColor = Color(0xFF2A2A2A),
                            unfocusedContainerColor = Color(0xFF2A2A2A),
                            focusedTextColor = Color.White,
                            unfocusedTextColor = Color.White,
                            focusedIndicatorColor = Color(0xFFFF9500),
                            unfocusedIndicatorColor = Color(0xFF3A3A3C)
                        ),
                        shape = RoundedCornerShape(10.dp)
                    )

                    // Results
                    if (pexelsResults.isNotEmpty()) {
                        Text("${pexelsResults.size} results", color = Color.Gray, fontSize = 12.sp)

                        Column(
                            modifier = Modifier.heightIn(max = 300.dp).verticalScroll(rememberScrollState()),
                            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)
                        ) {
                            pexelsResults.forEach { result ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(8.dp))
                                        .background(Color(0xFF2A2A2A))
                                        .clickable {
                                            if (pexelsReplaceMode) {
                                                viewModel.replaceClipFromPexels(result.videoUrl, result.duration.toDouble())
                                            } else {
                                                viewModel.addClipFromPexels(result.videoUrl, result.duration.toDouble())
                                            }
                                            viewModel.hidePexelsSearch()
                                        }
                                        .padding(8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp)
                                ) {
                                    // Video thumbnail
                                    Box(
                                        modifier = Modifier
                                            .size(width = 64.dp, height = 48.dp)
                                            .clip(RoundedCornerShape(6.dp))
                                            .background(Color(0xFF3A3A3C)),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        if (result.thumbnailUrl != null) {
                                            coil.compose.AsyncImage(
                                                model = result.thumbnailUrl,
                                                contentDescription = null,
                                                contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                                                modifier = Modifier.fillMaxSize()
                                            )
                                        } else {
                                            Text(
                                                text = if (result.height > result.width) "9:16" else "16:9",
                                                color = Color(0xFFFF9500),
                                                fontSize = 12.sp,
                                                fontWeight = FontWeight.Bold
                                            )
                                        }
                                    }
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text("${result.width}x${result.height}", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                                        Text("${result.duration}s", color = Color.Gray, fontSize = 12.sp)
                                    }
                                    Icon(
                                        imageVector = Icons.Default.Add,
                                        contentDescription = "Add",
                                        tint = Color(0xFFFF9500)
                                    )
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { viewModel.hidePexelsSearch() }) {
                    Text("Cancel")
                }
            },
            containerColor = Color(0xFF1C1C1E),
            titleContentColor = Color.White,
            textContentColor = Color.White
        )
    }

    // AI Clip Generation
    val showAiPrompt by viewModel.showAiPrompt.collectAsState()
    val aiPrompt by viewModel.aiPrompt.collectAsState()
    val aiGenerating by viewModel.aiGenerating.collectAsState()
    val aiStatus by viewModel.aiStatus.collectAsState()

    if (showAiPrompt) {
        var selectedModelId by remember(showAiPrompt) { mutableStateOf(PRESET_AI_MODELS.firstOrNull()?.id.orEmpty()) }
        var voiceoverMode by remember(showAiPrompt) { mutableStateOf("none") }
        var language by remember(showAiPrompt) { mutableStateOf("en") }

        AiClipDialog(
            prompt = aiPrompt,
            selectedModelId = selectedModelId,
            voiceoverMode = voiceoverMode,
            language = language,
            onPromptChange = viewModel::setAiPrompt,
            onModelSelect = { selectedModelId = it },
            onVoiceoverModeChange = { voiceoverMode = it },
            onLanguageChange = { language = it },
            onDismiss = { viewModel.hideAiPrompt() },
            onGenerate = {
                viewModel.generateAiAd(selectedModelId, "ai", "standard", voiceoverMode, language)
            }
        )
    }

    // AI generation status banner
    if (aiGenerating) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color(0xFF9C27B0).copy(alpha = 0.15f))
                .padding(horizontal = 16.dp, vertical = 10.dp),
            contentAlignment = Alignment.Center
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp)
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    color = Color(0xFF9C27B0),
                    strokeWidth = 2.dp
                )
                Text(aiStatus, color = Color.White, fontSize = 13.sp)
            }
        }
    }

    } // Box
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AiClipDialog(
    prompt: String,
    selectedModelId: String,
    voiceoverMode: String,
    language: String,
    onPromptChange: (String) -> Unit,
    onModelSelect: (String) -> Unit,
    onVoiceoverModeChange: (String) -> Unit,
    onLanguageChange: (String) -> Unit,
    onDismiss: () -> Unit,
    onGenerate: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF1C1C1E),
        contentColor = Color.White,
        dragHandle = {
            Box(
                modifier = Modifier
                    .padding(top = 10.dp, bottom = 6.dp)
                    .size(width = 42.dp, height = 4.dp)
                    .clip(RoundedCornerShape(999.dp))
                    .background(Color.White.copy(alpha = 0.28f))
            )
        }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .imePadding()
                .padding(horizontal = 20.dp)
                .padding(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Create Ad", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Color.White)
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.White)
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                OutlinedTextField(
                    value = prompt,
                    onValueChange = onPromptChange,
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Describe the ad you want to create") },
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color(0xFF9C27B0),
                        cursorColor = Color(0xFF9C27B0),
                        focusedTextColor = Color.White,
                        unfocusedTextColor = Color.White
                    ),
                    minLines = 3
                )

                Text("Model", color = Color.Gray, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                PRESET_AI_MODELS.forEach { model ->
                    FilterChip(
                        selected = model.id == selectedModelId,
                        onClick = { onModelSelect(model.id) },
                        label = {
                            Text(model.name, fontWeight = FontWeight.SemiBold)
                        },
                        leadingIcon = {
                            if (model.id == selectedModelId) {
                                Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(18.dp))
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = Color(0xFF9C27B0).copy(alpha = 0.25f),
                            selectedLabelColor = Color.White,
                            labelColor = Color.White
                        )
                    )
                }

                AiOptionRow(
                    title = "Audio",
                    options = listOf("none" to "No audio", "elevenlabs" to "Voice"),
                    selected = voiceoverMode,
                    onSelect = onVoiceoverModeChange
                )
                AiOptionRow(
                    title = "Language",
                    options = listOf(
                        "en" to "English",
                        "he" to "Hebrew",
                        "ru" to "Russian",
                        "es" to "Spanish",
                        "de" to "German",
                        "fr" to "French",
                        "pt" to "Portuguese"
                    ),
                    selected = language,
                    onSelect = onLanguageChange
                )
            }

            Button(
                onClick = onGenerate,
                enabled = prompt.isNotBlank() && selectedModelId.isNotBlank(),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp),
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF9C27B0))
            ) {
                Text("Build Ad", color = Color.White, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun AiOptionRow(
    title: String,
    options: List<Pair<String, String>>,
    selected: String,
    onSelect: (String) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, color = Color.Gray, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            options.forEach { (id, label) ->
                FilterChip(
                    selected = selected == id,
                    onClick = { onSelect(id) },
                    label = { Text(label) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = Color(0xFF9C27B0).copy(alpha = 0.25f),
                        selectedLabelColor = Color.White,
                        labelColor = Color.White
                    )
                )
            }
        }
    }
}

@Composable
fun ClipActionBar(viewModel: VideoEditorViewModel) {
    val clips by viewModel.clips.collectAsState()
    val activeClipIndex by viewModel.activeClipIndex.collectAsState()
    val hasClip = activeClipIndex in clips.indices

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF1A1A1A))
            .padding(horizontal = 12.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)
    ) {
        // Nav
        if (clips.size > 1 && activeClipIndex > 0) {
            BottomActionButton(Icons.Default.ChevronLeft, "Prev") { viewModel.selectClip(activeClipIndex - 1) }
        }

        BottomActionButton(Icons.Default.ContentCut, "Cut", enabled = hasClip) { viewModel.splitClipAtPlayhead() }
        if (clips.size > 1) {
            BottomActionButton(Icons.Default.Delete, "Del", color = Color(0xFFFF4444), enabled = hasClip) { viewModel.removeClip(activeClipIndex) }
        }
        BottomActionButton(Icons.Default.SwapHoriz, "Pexels", color = Color(0xFFFF9500), enabled = hasClip) { viewModel.showPexelsSearchForReplace() }
        BottomActionButton(Icons.Default.AutoAwesome, "AI", color = Color(0xFF9C27B0)) { viewModel.showAiPrompt() }
        BottomActionButton(Icons.Default.Subtitles, "Subs") { viewModel.setActiveTab(EditorTab.SUBTITLES); viewModel.showBottomSheet(true) }
        BottomActionButton(Icons.Default.MusicNote, "Mus") { viewModel.setActiveTab(EditorTab.MUSIC); viewModel.showBottomSheet(true) }

        if (clips.size > 1 && activeClipIndex < clips.size - 1) {
            BottomActionButton(Icons.Default.ChevronRight, "Next") { viewModel.selectClip(activeClipIndex + 1) }
        }
    }
}

@Composable
private fun BottomActionButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    color: Color = Color.White,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    Column(
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            tint = if (enabled) color else Color.Gray.copy(alpha = 0.4f),
            modifier = Modifier.size(20.dp)
        )
        Text(
            text = label,
            color = if (enabled) color else Color.Gray.copy(alpha = 0.4f),
            fontSize = 10.sp,
            fontWeight = FontWeight.Medium
        )
    }
}

@Composable
fun EditorTabBar(
    activeTab: EditorTab,
    onTabSelected: (EditorTab) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color(0xFF1A1A1A))
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)
    ) {
        EditorTab.entries.forEach { tab ->
            val isActive = tab == activeTab
            FilterChip(
                selected = isActive,
                onClick = { onTabSelected(tab) },
                label = { Text(tab.label) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = Color(0xFFFF9500),
                    selectedLabelColor = Color.Black,
                    containerColor = Color(0xFF2A2A2A),
                    labelColor = Color.White
                )
            )
        }
    }
}

@Composable
fun ExportButton(
    isExporting: Boolean,
    isSaved: Boolean,
    onExport: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.Black)
            .padding(16.dp)
    ) {
        Button(
            onClick = onExport,
            enabled = !isExporting,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = Color(0xFFFF9500),
                contentColor = Color.Black,
                disabledContainerColor = Color(0xFF555555)
            )
        ) {
            if (isExporting) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    color = Color.Black,
                    strokeWidth = 2.dp
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Exporting...")
            } else if (isSaved) {
                Text("Saved!")
            } else {
                Text("Export")
            }
        }
    }
}
