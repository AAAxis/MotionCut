package com.theholylabs.creator.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Launch
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.theholylabs.creator.AppState
import com.theholylabs.creator.AppUiState
import com.theholylabs.creator.services.FalCreditBalance
import com.theholylabs.creator.services.FreeBrainModel
import com.theholylabs.creator.services.GenerationService
import com.theholylabs.creator.services.PurchaseService
import com.theholylabs.creator.services.SecureStorage

@Composable
fun SettingsScreen(
    uiState: AppUiState,
    appState: AppState? = null,
    onBuyCredits: () -> Unit,
    onRestorePurchases: () -> Unit,
    onRedeemCode: () -> Unit,
    onClose: () -> Unit = {},
    onLogout: () -> Unit,
) {
    val context = LocalContext.current
    val secureStorage = remember { SecureStorage(context) }
    val currentPlan = PurchaseService.currentPlan(context)
    val isPro = currentPlan.isActive
    var falKey by remember { mutableStateOf(secureStorage.get("FAL_API_KEY").orEmpty()) }
    var falBalance by remember { mutableStateOf<FalCreditBalance?>(null) }
    var freeBrainModels by remember { mutableStateOf(GenerationService.defaultFreeBrainModels) }
    var selectedBrainModelId by remember {
        mutableStateOf(secureStorage.get("OPENROUTER_FREE_MODEL_ID") ?: GenerationService.defaultFreeBrainModels.first().id)
    }
    var brainMenuExpanded by remember { mutableStateOf(false) }
    var emailTapCount by remember { mutableIntStateOf(0) }

    LaunchedEffect(falKey) {
        falBalance = if (falKey.isBlank()) null else GenerationService.fetchFalCreditBalance(context)
    }

    LaunchedEffect(Unit) {
        freeBrainModels = GenerationService.fetchOpenRouterFreeBrainModels()
        if (freeBrainModels.none { it.id == selectedBrainModelId }) {
            val first = freeBrainModels.first()
            selectedBrainModelId = first.id
            secureStorage.put("AI_SCENARIO_MODE", "openrouter")
            secureStorage.put("OPENROUTER_FREE_MODEL_ID", first.id)
            secureStorage.put("OPENROUTER_FREE_MODEL_NAME", first.name)
        }
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .systemBarsPadding() // Fixed safe area for top and bottom
            .padding(24.dp),
        verticalArrangement = Arrangement.Top,
    ) {
        Spacer(modifier = Modifier.height(48.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Settings",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
            )
            IconButton(onClick = onClose) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "Close settings",
                    tint = Color.White
                )
            }
        }

        Spacer(modifier = Modifier.height(32.dp))

        // Account card
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
                Row(
                    modifier = Modifier.weight(1f),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Default.AccountCircle,
                        contentDescription = null,
                        tint = Color.Gray,
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column {
                        Text(
                            text = uiState.userEmail ?: "Account",
                            color = Color.White,
                            fontWeight = FontWeight.Medium,
                            modifier = Modifier.clickable {
                                emailTapCount++
                                if (emailTapCount >= 10) {
                                    appState?.addCredits(10)
                                    emailTapCount = 0
                                }
                            },
                        )
                        Text(
                            text = if (isPro) currentPlan.name.lowercase().replaceFirstChar { it.uppercase() } else "Free",
                            color = Color.Gray,
                            fontSize = 12.sp,
                        )
                    }
                }
                ProBadge(
                    enabled = isPro,
                    onClick = if (isPro) null else onBuyCredits,
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // AI Brain
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    text = "AI Brain",
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "Used for scripts, captions, cuts, and timeline decisions.",
                    color = Color.Gray,
                    fontSize = 12.sp,
                )

                Spacer(modifier = Modifier.height(12.dp))

                Text(
                    text = "Model",
                    color = Color.Gray,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(modifier = Modifier.height(6.dp))

                Box {
                    val selectedBrainModel = freeBrainModels.firstOrNull { it.id == selectedBrainModelId }
                        ?: GenerationService.defaultFreeBrainModels.first()
                    Text(
                        text = selectedBrainModel.name,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(10.dp))
                            .clickable { brainMenuExpanded = true }
                            .padding(horizontal = 12.dp, vertical = 12.dp)
                    )
                    DropdownMenu(
                        expanded = brainMenuExpanded,
                        onDismissRequest = { brainMenuExpanded = false }
                    ) {
                        freeBrainModels.forEach { model ->
                            DropdownMenuItem(
                                text = { Text(model.name) },
                                onClick = {
                                    selectedBrainModelId = model.id
                                    secureStorage.put("AI_SCENARIO_MODE", "openrouter")
                                    secureStorage.put("OPENROUTER_FREE_MODEL_ID", model.id)
                                    secureStorage.put("OPENROUTER_FREE_MODEL_NAME", model.name)
                                    brainMenuExpanded = false
                                }
                            )
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Video providers
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "Video providers",
                                color = Color.White,
                                fontWeight = FontWeight.SemiBold,
                            )
                            falBalance?.let { balance ->
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = balance.displayText(),
                                    color = Color.White,
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 12.sp,
                                    modifier = Modifier
                                        .background(Color(0xFFFF6B35), RoundedCornerShape(999.dp))
                                        .padding(horizontal = 10.dp, vertical = 4.dp)
                                )
                            }
                        }
                        Text(
                            text = "Use your own fal.ai key on any plan.",
                            color = Color.Gray,
                            fontSize = 12.sp,
                        )
                    }
                    IconButton(
                        onClick = {
                            val intent = android.content.Intent(
                                android.content.Intent.ACTION_VIEW,
                                android.net.Uri.parse("https://fal.ai/dashboard/keys")
                            )
                            context.startActivity(intent)
                        }
                    ) {
                        Icon(Icons.Default.Launch, contentDescription = "Open fal.ai", tint = MaterialTheme.colorScheme.primary)
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))

                OutlinedTextField(
                    value = falKey,
                    onValueChange = {
                        falKey = it
                        if (it.isBlank()) {
                            secureStorage.remove("FAL_API_KEY")
                        } else {
                            secureStorage.put("FAL_API_KEY", it.trim())
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("fal.ai key") },
                    singleLine = true,
                )
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        if (!uiState.userId.isNullOrBlank() || !uiState.userEmail.isNullOrBlank()) {
            Divider(color = Color(0xFF2A2A2A))
            Spacer(modifier = Modifier.height(8.dp))

            TextButton(
                onClick = onLogout,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = "Sign Out",
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

@Composable
private fun ProBadge(
    enabled: Boolean,
    onClick: (() -> Unit)?,
) {
    val modifier = Modifier
        .background(Color(0xFFFF6B35), RoundedCornerShape(999.dp))
        .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
        .padding(horizontal = 12.dp, vertical = 6.dp)

    Text(
        text = "Pro",
        color = Color.White,
        fontWeight = FontWeight.Bold,
        fontSize = 12.sp,
        modifier = modifier,
        maxLines = 1,
    )
}

private fun FalCreditBalance.displayText(): String {
    val amount = if (currentBalance % 1.0 == 0.0) {
        currentBalance.toInt().toString()
    } else {
        String.format(java.util.Locale.US, "%.2f", currentBalance)
    }
    return if (currency.equals("USD", ignoreCase = true)) "$$amount" else "$amount $currency"
}
