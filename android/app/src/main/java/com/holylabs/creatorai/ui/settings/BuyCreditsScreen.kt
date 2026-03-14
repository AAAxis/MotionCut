package com.holylabs.creatorai.ui.settings

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.holylabs.creatorai.AppState
import com.holylabs.creatorai.AppUiState
import com.holylabs.creatorai.services.PurchaseService
import com.revenuecat.purchases.Package
import kotlinx.coroutines.launch

@Composable
fun BuyCreditsScreen(
    uiState: AppUiState,
    activity: ComponentActivity,
    appState: AppState,
    onDismiss: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var isPurchasing by remember { mutableStateOf(false) }
    var purchasingPackageId by remember { mutableStateOf<String?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
    ) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Buy Credits",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
            IconButton(onClick = onDismiss) {
                Icon(Icons.Default.Close, contentDescription = "Close", tint = Color.Gray)
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Current balance: ${uiState.credits} credits",
            color = Color.Gray,
            fontSize = 14.sp,
        )

        Spacer(modifier = Modifier.height(32.dp))

        if (uiState.offerings.isEmpty()) {
            // Loading state
            Column(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                Spacer(modifier = Modifier.height(16.dp))
                Text("Loading packages...", color = Color.Gray)
            }
        } else {
            uiState.offerings.forEach { pkg ->
                CreditPackageCard(
                    pkg = pkg,
                    isPurchasing = isPurchasing && purchasingPackageId == pkg.identifier,
                    isDisabled = isPurchasing,
                    onClick = {
                        scope.launch {
                            isPurchasing = true
                            purchasingPackageId = pkg.identifier
                            try {
                                val userId = uiState.userId ?: return@launch
                                PurchaseService.purchase(
                                    activity = activity,
                                    pkg = pkg,
                                    userId = userId,
                                    onCreditsRefresh = { appState.fetchCredits() },
                                )
                            } finally {
                                isPurchasing = false
                                purchasingPackageId = null
                            }
                        }
                    }
                )
                Spacer(modifier = Modifier.height(12.dp))
            }
        }
    }
}

@Composable
private fun CreditPackageCard(
    pkg: Package,
    isPurchasing: Boolean,
    isDisabled: Boolean,
    onClick: () -> Unit,
) {
    val product = pkg.product
    val title = product.title.ifBlank { pkg.identifier }
    val price = product.price.formatted

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column {
                Text(
                    text = title,
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 16.sp,
                )
                Text(
                    text = price,
                    color = Color.Gray,
                    fontSize = 14.sp,
                )
            }

            Button(
                onClick = onClick,
                enabled = !isDisabled,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                ),
            ) {
                if (isPurchasing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        color = Color.White,
                        strokeWidth = 2.dp,
                    )
                } else {
                    Text("Buy", fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}
