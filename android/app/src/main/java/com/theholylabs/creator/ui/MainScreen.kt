package com.theholylabs.creator.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.VideoCameraBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.theholylabs.creator.AppState
import com.theholylabs.creator.AppUiState
import com.theholylabs.creator.ui.library.LibraryScreen
import com.theholylabs.creator.ui.settings.SettingsScreen

@Composable
fun MainScreen(
    appState: AppState,
    uiState: AppUiState,
    onBuyCredits: () -> Unit,
    onRestorePurchases: () -> Unit,
    onRedeemCode: () -> Unit,
    onNavigateToStatus: (String) -> Unit,
    onLogout: () -> Unit,
    onPlayVideo: (String) -> Unit,
    onShareVideo: (String) -> Unit,
    onEditVideo: (videoUri: String, videoName: String, takesJson: String?, musicUrl: String?, generationId: String?) -> Unit = { _, _, _, _, _ -> }
) {
    var selectedScreen by remember { mutableIntStateOf(0) } // 0 Library, 1 Settings

    Scaffold(
        bottomBar = {
            Surface(
                color = MaterialTheme.colorScheme.background.copy(alpha = 0.96f),
                tonalElevation = 8.dp
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Button(
                        onClick = {
                            onEditVideo("", "Editor", null, null, null)
                        },
                        modifier = Modifier
                            .weight(1f)
                            .height(56.dp),
                        shape = RoundedCornerShape(16.dp),
                        contentPadding = PaddingValues(horizontal = 18.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary
                        )
                    ) {
                        Icon(Icons.Default.VideoCameraBack, contentDescription = null, modifier = Modifier.size(22.dp))
                        Spacer(modifier = Modifier.width(10.dp))
                        Text("Open Editor", style = MaterialTheme.typography.titleMedium)
                    }

                }
            }
        }
    ) { innerPadding ->
        Surface(modifier = Modifier.padding(innerPadding)) {
            when (selectedScreen) {
                0 -> LibraryScreen(
                    uiState = uiState,
                    onProfileClick = { selectedScreen = 1 },
                    onPlay = onPlayVideo,
                    onShare = onShareVideo,
                    onEdit = { url, name, takes, music, genId -> onEditVideo(url, name, takes, music, genId) }
                )
                1 -> SettingsScreen(
                    uiState = uiState,
                    appState = appState,
                    onBuyCredits = onBuyCredits,
                    onRestorePurchases = onRestorePurchases,
                    onRedeemCode = onRedeemCode,
                    onClose = { selectedScreen = 0 },
                    onLogout = onLogout
                )
            }
        }
    }
}
