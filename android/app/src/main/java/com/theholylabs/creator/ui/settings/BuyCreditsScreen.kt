package com.theholylabs.creator.ui.settings

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.models.StoreTransaction
import com.revenuecat.purchases.ui.revenuecatui.ExperimentalPreviewRevenueCatUIPurchasesAPI
import com.revenuecat.purchases.ui.revenuecatui.Paywall
import com.revenuecat.purchases.ui.revenuecatui.PaywallListener
import com.revenuecat.purchases.ui.revenuecatui.PaywallOptions
import com.theholylabs.creator.AppState
import com.theholylabs.creator.AppUiState
import com.theholylabs.creator.services.PurchaseService

@OptIn(ExperimentalPreviewRevenueCatUIPurchasesAPI::class)
@Composable
fun BuyCreditsScreen(
    uiState: AppUiState,
    activity: ComponentActivity,
    appState: AppState,
    onDismiss: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .systemBarsPadding(),
    ) {
        Paywall(
            options = PaywallOptions.Builder(
                dismissRequest = onDismiss,
            ).setListener(object : PaywallListener {
                override fun onPurchaseCompleted(customerInfo: CustomerInfo, storeTransaction: StoreTransaction) {
                    PurchaseService.cacheSubscriptionPlan(activity, customerInfo)
                    appState.fetchCredits()
                    onDismiss()
                }

                override fun onRestoreCompleted(customerInfo: CustomerInfo) {
                    PurchaseService.cacheSubscriptionPlan(activity, customerInfo)
                    appState.fetchCredits()
                }

                override fun onPurchaseError(error: PurchasesError) {
                    // Remote paywall owns the visible store error UI.
                }

                override fun onRestoreError(error: PurchasesError) {
                    // Remote paywall owns the visible store error UI.
                }
            }).build(),
        )
    }
}
