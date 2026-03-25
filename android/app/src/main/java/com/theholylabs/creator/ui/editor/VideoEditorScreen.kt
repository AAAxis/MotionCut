package com.theholylabs.creator.ui.editor

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import com.theholylabs.creator.viewmodels.VideoEditorViewModel

enum class EditorTab(val label: String) {
    EDIT("Edit"),
    QUALITY("Quality"),
    MUSIC("Music")
}

class VideoEditorViewModelFactory(
    private val application: Application,
    private val videoUri: String,
    private val videoName: String,
    private val takesJson: String?,
    private val musicUrl: String?,
    private val userId: String?
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        return VideoEditorViewModel(application, videoUri, videoName, takesJson, musicUrl, userId) as T
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
            userId = userId
        )
    )

    val activeTab by viewModel.activeTab.collectAsState()
    val isExporting by viewModel.isExporting.collectAsState()
    val isSaved by viewModel.isSaved.collectAsState()
    val isProcessingModalVisible by viewModel.isProcessingModalVisible.collectAsState()
    val processingStatus by viewModel.processingStatus.collectAsState()
    val processingError by viewModel.processingError.collectAsState()

    // Pre-cache clips on launch
    LaunchedEffect(Unit) {
        viewModel.preCacheClips()
    }

    Box(modifier = Modifier.fillMaxSize()) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(videoName, maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(Icons.Default.Close, contentDescription = "Close")
                    }
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

                // Tab Bar
                EditorTabBar(
                    activeTab = activeTab,
                    onTabSelected = { viewModel.setActiveTab(it) }
                )

                // Tab Content
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 160.dp)
                        .background(Color(0xFF111111))
                ) {
                    when (activeTab) {
                        EditorTab.EDIT -> EditTab(viewModel = viewModel)
                        EditorTab.QUALITY -> QualityTab(viewModel = viewModel)
                        EditorTab.MUSIC -> MusicTab(viewModel = viewModel)
                    }
                }
            }

            // Export Button (fixed at bottom)
            ExportButton(
                isExporting = isExporting,
                isSaved = isSaved,
                onExport = { viewModel.exportVideo() }
            )
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
    } // Box
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
