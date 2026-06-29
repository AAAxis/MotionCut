package com.theholylabs.creator.ui.library

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import coil.decode.VideoFrameDecoder
import coil.request.ImageRequest
import coil.request.videoFrameMillis
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import com.theholylabs.creator.AppUiState
import com.theholylabs.creator.models.Generation
import com.theholylabs.creator.models.GenerationStatus
import com.theholylabs.creator.services.FileStorageService
import com.theholylabs.creator.viewmodels.LibraryViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(
    uiState: AppUiState,
    vm: LibraryViewModel = viewModel(),
    importRequest: Int = 0,
    onProfileClick: () -> Unit = {},
    onPlay: (String) -> Unit,
    onShare: (String) -> Unit,
    onEdit: (videoUrl: String, videoName: String, takesJson: String?, musicUrl: String?, generationId: String?) -> Unit = { _, _, _, _, _ -> }
) {
    val generations by vm.generations.collectAsState()
    val isLoading by vm.isLoading.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val videoImportLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let { selectedUri ->
            scope.launch {
                val savedFile = withContext(Dispatchers.IO) {
                    val id = UUID.randomUUID().toString()
                    val dest = File(FileStorageService.savedVideosDir, "$id.mp4")
                    context.contentResolver.openInputStream(selectedUri)?.use { input ->
                        dest.outputStream().use { output -> input.copyTo(output) }
                    }
                    if (dest.exists() && dest.length() > 0) dest else null
                }
                savedFile?.let {
                    onEdit(it.absolutePath, it.nameWithoutExtension, null, null, null)
                }
            }
        }
    }

    LaunchedEffect(Unit) {
        vm.loadGenerations()
    }

    LaunchedEffect(importRequest) {
        if (importRequest > 0) {
            videoImportLauncher.launch("video/*")
        }
    }

    val pullRefreshState = rememberPullToRefreshState()

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        PullToRefreshBox(
            isRefreshing = isLoading,
            onRefresh = { vm.loadGenerations() },
            state = pullRefreshState,
            modifier = Modifier.fillMaxSize()
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 26.dp, vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Library",
                        fontSize = 29.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    IconButton(
                        onClick = onProfileClick,
                        modifier = Modifier
                            .size(44.dp)
                            .clip(RoundedCornerShape(22.dp))
                            .background(MaterialTheme.colorScheme.surface)
                    ) {
                        Icon(
                            imageVector = Icons.Default.AccountCircle,
                            contentDescription = "Profile",
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(30.dp)
                        )
                    }
                }

                if (isLoading && generations.isEmpty()) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color(0xFFFF9500))
                    }
                } else if (generations.isEmpty()) {
                    EmptyLibrary()
                } else {
                    GenerationsList(
                        generations = generations,
                        vm = vm,
                        userId = uiState.userId ?: "",
                        onPlay = onPlay,
                        onShare = onShare,
                        onEdit = onEdit
                    )
                }
            }
        }
    }
}

@Composable
fun EmptyLibrary() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(26.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.Movie,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = Color.DarkGray
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "No videos yet",
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White
        )
        Text(
            text = "Create your first video to see it here",
            fontSize = 14.sp,
            color = Color.Gray,
            modifier = Modifier.padding(top = 8.dp)
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GenerationsList(
    generations: List<Generation>,
    vm: LibraryViewModel,
    userId: String,
    onPlay: (String) -> Unit,
    onShare: (String) -> Unit,
    onEdit: (videoUrl: String, videoName: String, takesJson: String?, musicUrl: String?, generationId: String?) -> Unit = { _, _, _, _, _ -> }
) {
    LazyColumn(
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize()
    ) {
        items(generations, key = { it.id }) { gen ->
            GenerationListItem(
                gen = gen,
                onDelete = { vm.deleteGeneration(gen.id, userId) },
                onTap = { if (gen.status == GenerationStatus.COMPLETED || gen.status == GenerationStatus.SAVED) (gen.resultVideoUrl ?: gen.videoUri)?.let { onEdit(it, gen.displayName, gen.takesJson, gen.musicPath, gen.id) } },
                onShare = { (gen.resultVideoUrl ?: gen.videoUri)?.let(onShare) }
            )
        }
    }
}

@Composable
fun GenerationListItem(
    gen: Generation,
    onDelete: () -> Unit,
    onTap: () -> Unit,
    onShare: () -> Unit
) {
    val context = LocalContext.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xFF1C1C1E))
            .clickable(onClick = onTap)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(width = 90.dp, height = 60.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Color.Black),
            contentAlignment = Alignment.Center
        ) {
            if (gen.status == GenerationStatus.PROCESSING) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    strokeWidth = 2.dp,
                    color = Color(0xFFFF9500)
                )
            } else if ((gen.resultVideoUrl ?: gen.videoUri) != null) {
                AsyncImage(
                    model = ImageRequest.Builder(context)
                        .data(gen.resultVideoUrl ?: gen.videoUri)
                        .videoFrameMillis(500)
                        .decoderFactory { result, options, _ -> VideoFrameDecoder(result.source, options) }
                        .crossfade(true)
                        .build(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
                Icon(
                    imageVector = Icons.Default.Edit,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.8f),
                    modifier = Modifier.size(24.dp)
                )
            } else {
                Icon(
                    imageVector = Icons.Default.Movie,
                    contentDescription = null,
                    tint = Color.DarkGray
                )
            }
        }

        Spacer(modifier = Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = gen.displayName,
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = gen.createdAt.take(10),
                color = Color.Gray,
                fontSize = 12.sp
            )
        }

        IconButton(onClick = onShare) {
            Icon(Icons.Default.Share, contentDescription = "Share", tint = Color.Gray)
        }

        IconButton(onClick = onDelete) {
            Icon(Icons.Default.Delete, contentDescription = "Delete", tint = Color.Gray)
        }
    }
}

@Composable
fun StatusBadge(status: GenerationStatus, modifier: Modifier = Modifier) {
    when (status) {
        GenerationStatus.PROCESSING -> {
            CircularProgressIndicator(
                modifier = modifier.size(20.dp),
                strokeWidth = 2.dp,
                color = Color(0xFFFF9500)
            )
        }
        GenerationStatus.COMPLETED, GenerationStatus.SAVED -> {
            Surface(
                modifier = modifier.size(22.dp),
                color = Color(0xFF4CD964),
                shape = androidx.compose.foundation.shape.CircleShape
            ) {
                Icon(
                    imageVector = Icons.Default.Check,
                    contentDescription = "Completed",
                    tint = Color.Black,
                    modifier = Modifier.padding(4.dp)
                )
            }
        }
        GenerationStatus.FAILED -> {
            Icon(
                imageVector = Icons.Default.Error,
                contentDescription = "Failed",
                tint = Color(0xFFFF3B30),
                modifier = modifier.size(22.dp)
            )
        }
    }
}
