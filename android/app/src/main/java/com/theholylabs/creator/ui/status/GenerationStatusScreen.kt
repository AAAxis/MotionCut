package com.theholylabs.creator.ui.status

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.theholylabs.creator.AppState
import com.theholylabs.creator.services.GenerationService
import com.theholylabs.creator.services.NotificationService
import kotlinx.coroutines.delay

@Composable
fun GenerationStatusScreen(
    generationId: String,
    appState: AppState,
    onBack: () -> Unit
) {
    var status by remember { mutableStateOf("processing") }
    var resultUrl by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var hasNotified by remember { mutableStateOf(false) }

    val context = LocalContext.current
    
    // Notification permission launcher
    var hasNotificationPermission by remember {
        mutableStateOf(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
            } else {
                true
            }
        )
    }

    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        hasNotificationPermission = isGranted
    }

    // Auto-request notification permission on enter
    LaunchedEffect(Unit) {
        if (!hasNotificationPermission && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    LaunchedEffect(generationId) {
        while (status == "processing" || status == "starting" || status == "queued") {
            val update = GenerationService.pollAICreate(generationId)
            if (update != null) {
                status = update.status ?: "processing"
                resultUrl = update.outputUrl
                error = update.error
                
                if (status == "succeeded" && !hasNotified) {
                    NotificationService.notifyVideoReady(context, "AI Video")
                    hasNotified = true
                    break
                } else if (status == "failed" && !hasNotified) {
                    NotificationService.notifyVideoFailed(context, "AI Video")
                    hasNotified = true
                    break
                }
            }
            delay(5000)
        }
    }

    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = "Generating Video",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
            
            Spacer(modifier = Modifier.height(8.dp))
            
            Text(
                text = "ID: $generationId",
                fontSize = 12.sp,
                color = Color.Gray
            )

            Spacer(modifier = Modifier.height(32.dp))
            
            if (status == "succeeded") {
                Text("Video Ready!", color = Color.Green, fontSize = 20.sp)
                Button(
                    onClick = onBack,
                    modifier = Modifier.padding(top = 24.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF9500))
                ) {
                    Text("Go to Library")
                }
            } else if (status == "failed" || error != null) {
                Text("Generation Failed", color = Color.Red, fontSize = 20.sp)
                Text(text = error ?: "Something went wrong. Your credits will be refunded.", color = Color.Gray, modifier = Modifier.padding(top = 8.dp), textAlign = TextAlign.Center)
                Button(onClick = onBack, modifier = Modifier.padding(top = 24.dp)) {
                    Text("Back")
                }
            } else {
                CircularProgressIndicator(modifier = Modifier.size(64.dp), color = Color(0xFFFF9500))
                
                Spacer(modifier = Modifier.height(24.dp))
                
                Text(
                    text = "This takes about 1-2 minutes...",
                    color = Color.Gray,
                    textAlign = TextAlign.Center
                )

                Spacer(modifier = Modifier.height(48.dp))

                Button(
                    onClick = {
                        appState.trackGeneration(generationId)
                        onBack()
                    },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = 0.1f))
                ) {
                    Text("Continue in background", color = Color.White)
                }
            }
        }
    }
}
