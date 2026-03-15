package com.holylabs.creatorai.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.holylabs.creatorai.AppState
import com.holylabs.creatorai.AppUiState
import com.holylabs.creatorai.MainActivity
import com.holylabs.creatorai.ui.auth.LoginScreen
import com.holylabs.creatorai.ui.settings.BuyCreditsScreen
import com.holylabs.creatorai.ui.settings.SettingsScreen
import kotlinx.coroutines.launch

object Routes {
    const val LOGIN = "login"
    const val SETTINGS = "settings"
    const val BUY_CREDITS = "buy_credits"
}

@Composable
fun AppNavigation(
    appState: AppState,
    uiState: AppUiState,
    activity: MainActivity,
    loginError: String?,
) {
    val navController = rememberNavController()
    val scope = rememberCoroutineScope()

    // React to auth state changes — navigate after onActivityResult sets auth
    val startDestination = if (uiState.isAuthenticated) Routes.SETTINGS else Routes.LOGIN

    NavHost(navController = navController, startDestination = startDestination) {

        composable(Routes.LOGIN) {
            LoginScreen(
                activity = activity,
                errorMessage = loginError,
            )
        }

        composable(Routes.SETTINGS) {
            SettingsScreen(
                uiState = uiState,
                onBuyCredits = { navController.navigate(Routes.BUY_CREDITS) },
                onRestorePurchases = {
                    scope.launch {
                        com.holylabs.creatorai.services.PurchaseService.restorePurchases()
                        appState.fetchCredits()
                    }
                },
                onLogout = {
                    scope.launch {
                        com.holylabs.creatorai.services.AuthService.signOut(activity)
                        appState.logout()
                        navController.navigate(Routes.LOGIN) {
                            popUpTo(Routes.SETTINGS) { inclusive = true }
                        }
                    }
                }
            )
        }

        composable(Routes.BUY_CREDITS) {
            BuyCreditsScreen(
                uiState = uiState,
                activity = activity,
                appState = appState,
                onDismiss = { navController.popBackStack() }
            )
        }
    }
}
