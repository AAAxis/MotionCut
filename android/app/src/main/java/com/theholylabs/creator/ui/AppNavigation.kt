package com.theholylabs.creator.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.LaunchedEffect
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.theholylabs.creator.AppState
import com.theholylabs.creator.AppUiState
import com.theholylabs.creator.MainActivity
import com.theholylabs.creator.ui.auth.OnboardingScreen
import com.theholylabs.creator.ui.settings.BuyCreditsScreen
import kotlinx.coroutines.launch

object Routes {
    const val LOGIN = "login"
    const val MAIN = "main"
    const val BUY_CREDITS = "buy_credits"
    const val STATUS = "status/{id}"
    const val VIDEO_PLAYER = "video_player"
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

    // Handle navigation logic when auth state or onboarding changes
    LaunchedEffect(uiState.isAuthenticated, uiState.hasSeenOnboarding) {
        if (uiState.hasSeenOnboarding) {
            navController.navigate(Routes.MAIN) {
                popUpTo(Routes.LOGIN) { inclusive = true }
            }
        }
    }

    val startDestination = if (!uiState.hasSeenOnboarding) Routes.LOGIN else Routes.MAIN

    NavHost(navController = navController, startDestination = startDestination) {

        composable(Routes.LOGIN) {
            OnboardingScreen(
                activity = activity,
                onComplete = {
                    appState.completeOnboarding()
                    if (uiState.isAuthenticated) {
                        navController.navigate(Routes.MAIN) {
                            popUpTo(Routes.LOGIN) { inclusive = true }
                        }
                    }
                },
                errorMessage = loginError
            )
        }

        composable(Routes.MAIN) {
            MainScreen(
                appState = appState,
                uiState = uiState,
                onBuyCredits = { navController.navigate(Routes.BUY_CREDITS) },
                onRestorePurchases = {
                    scope.launch {
                        com.theholylabs.creator.services.PurchaseService.restorePurchases()
                        appState.fetchCredits()
                    }
                },
                onRedeemCode = {
                    val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse("https://play.google.com/redeem"))
                    activity.startActivity(intent)
                },
                onNavigateToStatus = { id ->
                    navController.navigate("status/$id")
                },
                onLogout = {
                    scope.launch {
                        com.theholylabs.creator.services.AuthService.signOut(activity)
                        appState.logout()
                        navController.navigate(Routes.LOGIN) {
                            popUpTo(Routes.MAIN) { inclusive = true }
                        }
                    }
                },
                onPlayVideo = { url ->
                    val encodedUrl = java.net.URLEncoder.encode(url, "UTF-8")
                    navController.navigate("video_player?url=$encodedUrl")
                },
                onShareVideo = { url ->
                    val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(android.content.Intent.EXTRA_TEXT, url)
                    }
                    activity.startActivity(android.content.Intent.createChooser(intent, "Share Video"))
                }
            )
        }

        composable(
            route = "video_player?url={url}",
            arguments = listOf(androidx.navigation.navArgument("url") { type = androidx.navigation.NavType.StringType })
        ) { backStackEntry ->
            val url = backStackEntry.arguments?.getString("url") ?: ""
            com.theholylabs.creator.ui.library.VideoPlayerScreen(
                videoUrl = url,
                onBack = { navController.popBackStack() }
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

        composable(Routes.STATUS) { backStackEntry ->
            val id = backStackEntry.arguments?.getString("id") ?: ""
            com.theholylabs.creator.ui.status.GenerationStatusScreen(
                generationId = id,
                appState = appState,
                onBack = { 
                    appState.fetchCredits()
                    navController.popBackStack(Routes.MAIN, false) 
                }
            )
        }
    }
}
