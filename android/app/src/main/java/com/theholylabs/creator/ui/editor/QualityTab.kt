package com.theholylabs.creator.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.theholylabs.creator.viewmodels.VideoEditorViewModel

private val aspectRatios = listOf("9:16", "16:9", "1:1", "4:5")
private val qualities = listOf(
    "original" to "Original",
    "high" to "High",
    "medium" to "Medium",
    "low" to "Low"
)

@Composable
fun QualityTab(
    viewModel: VideoEditorViewModel,
    modifier: Modifier = Modifier
) {
    val currentRatio by viewModel.aspectRatio.collectAsState()
    val currentQuality by viewModel.exportQuality.collectAsState()

    Column(
        modifier = modifier.padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp)
    ) {
        // Aspect Ratio
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                text = "Aspect Ratio",
                color = Color.White,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold
            )

            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                aspectRatios.forEach { ratio ->
                    val isSelected = ratio == currentRatio
                    val (iconW, iconH) = ratioIconSize(ratio)

                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(12.dp))
                            .background(
                                if (isSelected) Color(0xFFFF9500).copy(alpha = 0.08f)
                                else Color(0xFF2A2A2A)
                            )
                            .border(
                                width = 1.5.dp,
                                color = if (isSelected) Color(0xFFFF9500) else Color(0xFF444444),
                                shape = RoundedCornerShape(12.dp)
                            )
                            .clickable { viewModel.setAspectRatio(ratio) }
                            .padding(vertical = 12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        // Ratio icon
                        Box(
                            modifier = Modifier
                                .size(width = iconW, height = iconH)
                                .border(
                                    width = 1.5.dp,
                                    color = if (isSelected) Color(0xFFFF9500) else Color.Gray,
                                    shape = RoundedCornerShape(3.dp)
                                )
                        )

                        Text(
                            text = ratio,
                            color = if (isSelected) Color(0xFFFF9500) else Color.White,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
            }
        }

        // Export Quality
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                text = "Export Quality",
                color = Color.White,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold
            )

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                qualities.forEach { (id, label) ->
                    val isSelected = id == currentQuality
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(
                                if (isSelected) Color(0xFFFF9500).copy(alpha = 0.05f)
                                else Color.Transparent
                            )
                            .clickable { viewModel.setExportQuality(id) }
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = if (isSelected) Icons.Default.CheckCircle else Icons.Outlined.Circle,
                            contentDescription = null,
                            tint = if (isSelected) Color(0xFFFF9500) else Color.Gray,
                            modifier = Modifier.size(20.dp)
                        )

                        Spacer(modifier = Modifier.width(10.dp))

                        Text(
                            text = label,
                            color = Color.White,
                            fontSize = 15.sp
                        )

                        Spacer(modifier = Modifier.weight(1f))

                        if (id == "original") {
                            Text(
                                text = "Best",
                                color = Color(0xFFFF9500),
                                fontSize = 11.sp,
                                fontWeight = FontWeight.Medium,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(50))
                                    .background(Color(0xFFFF9500).copy(alpha = 0.1f))
                                    .padding(horizontal = 8.dp, vertical = 3.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun ratioIconSize(ratio: String): Pair<Dp, Dp> {
    return when (ratio) {
        "9:16" -> 18.dp to 30.dp
        "16:9" -> 30.dp to 18.dp
        "1:1" -> 24.dp to 24.dp
        "4:5" -> 20.dp to 25.dp
        else -> 24.dp to 24.dp
    }
}
