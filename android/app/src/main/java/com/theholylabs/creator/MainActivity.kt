package com.theholylabs.creator

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.theholylabs.creator.services.AppsFlyerService
import com.theholylabs.creator.services.AuthService
import com.theholylabs.creator.ui.AppNavigation
import com.theholylabs.creator.ui.theme.CreatorAITheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val appState: AppState by viewModels()
    var loginError by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            CreatorAITheme {
                val state by appState.uiState.collectAsState()
                AppNavigation(
                    appState = appState,
                    uiState = state,
                    activity = this,
                    loginError = loginError,
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        AppsFlyerService.start(this)
        appState.loadOfferings()
    }

    @Deprecated("Using legacy onActivityResult for GoogleSignInClient — no Firebase needed")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == AuthService.RC_SIGN_IN) {
            loginError = null
            CoroutineScope(Dispatchers.Main).launch {
                try {
                    val result = AuthService.handleSignInResult(data)
                    appState.setAuth(result.token, result.userId, result.email)
                } catch (e: Exception) {
                    Log.e("MainActivity", "Sign-in failed: ${e.message}")
                    loginError = "Sign-in failed. Please try again."
                }
            }
        }
    }
}
