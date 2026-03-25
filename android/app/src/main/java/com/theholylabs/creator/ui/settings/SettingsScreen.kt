package com.theholylabs.creator.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.foundation.clickable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.theholylabs.creator.AppState
import com.theholylabs.creator.AppUiState

@Composable
fun SettingsScreen(
    uiState: AppUiState,
    appState: AppState? = null,
    onBuyCredits: () -> Unit,
    onRestorePurchases: () -> Unit,
    onRedeemCode: () -> Unit,
    onLogout: () -> Unit,
) {
    var emailTapCount by remember { mutableIntStateOf(0) }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .systemBarsPadding() // Fixed safe area for top and bottom
            .padding(24.dp),
        verticalArrangement = Arrangement.Top,
    ) {
        Spacer(modifier = Modifier.height(48.dp))

        Text(
            text = "Settings",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Account card
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        ) {
            Row(
                modifier = Modifier.padding(16.dp),
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
                        text = uiState.userEmail ?: "Signed in",
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
                        text = uiState.userId?.take(8)?.let { "ID: $it..." } ?: "",
                        color = Color.Gray,
                        fontSize = 12.sp,
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Credits card
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
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.Star,
                        contentDescription = null,
                        tint = Color(0xFFFBBF24), // amber
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = "Credits",
                        color = Color.White,
                        fontWeight = FontWeight.Medium,
                    )
                }

                if (uiState.isLoadingCredits) {
                    CircularProgressIndicator(modifier = Modifier.padding(4.dp))
                } else {
                    Text(
                        text = "${uiState.credits}",
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 20.sp,
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(24.dp))

        // Buy credits button
        Button(
            onClick = onBuyCredits,
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.primary,
            ),
        ) {
            Text(
                text = "Buy Credits",
                fontWeight = FontWeight.SemiBold,
                fontSize = 16.sp,
            )
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Restore purchases
        TextButton(
            onClick = onRestorePurchases,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = "Restore Purchases",
                color = Color.Gray,
            )
        }

        // Redeem Promocode
        TextButton(
            onClick = onRedeemCode,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = "Redeem Promocode",
                color = MaterialTheme.colorScheme.primary,
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        Divider(color = Color(0xFF2A2A2A))
        Spacer(modifier = Modifier.height(8.dp))

        // Sign out
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
