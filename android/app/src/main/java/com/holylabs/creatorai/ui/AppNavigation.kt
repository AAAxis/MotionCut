package com.holylabs.creatorai.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.fragment.app.FragmentActivity
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.holylabs.creatorai.AppState
import com.holylabs.creatorai.AppUiState
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
    activity: androidx.activity.ComponentActivity,
) {
    val navController = rememberNavController()
    val scope = rememberCoroutineScope()

    val startDestination = if (uiState.isAuthenticated) Routes.SETTINGS else Routes.LOGIN

    NavHost(navController = navController, startDestination = startDestination) {

        composable(Routes.LOGIN) {
            LoginScreen(
                onLoginSuccess = { token, userId, email ->
                    appState.setAuth(token, userId, email)
                    navController.navigate(Routes.SETTINGS) {
                        popUpTo(Routes.LOGIN) { inclusive = true }
                    }
                }
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
                    appState.logout()
                    navController.navigate(Routes.LOGIN) {
                        popUpTo(Routes.SETTINGS) { inclusive = true }
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
