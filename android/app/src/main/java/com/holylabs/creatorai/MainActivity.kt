package com.holylabs.creatorai

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.holylabs.creatorai.services.AppsFlyerService
import com.holylabs.creatorai.services.PurchaseService
import com.holylabs.creatorai.ui.AppNavigation
import com.holylabs.creatorai.ui.theme.CreatorAITheme

class MainActivity : ComponentActivity() {

    private val appState: AppState by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            CreatorAITheme {
                val state by appState.uiState.collectAsState()
                AppNavigation(appState = appState, uiState = state, activity = this)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Start AppsFlyer on every foreground (mirrors iOS onReceive didBecomeActive)
        AppsFlyerService.start(this)
        // Reload offerings in case they changed
        appState.loadOfferings()
    }
}
