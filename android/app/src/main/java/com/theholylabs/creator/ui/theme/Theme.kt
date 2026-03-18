package com.theholylabs.creator.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Primary Colors: Vibrant Orange/Yellow (matches iOS accent)
val PrimaryOrange = Color(0xFFFF9500) // Vibrant System Orange
val PrimaryYellow = Color(0xFFFFCC00) // System Yellow
val PrimaryPurple = Color(0xFF7C3AED) // iOS Fallback

private val DarkColors = darkColorScheme(
    primary = PrimaryOrange,
    onPrimary = Color.Black,
    secondary = PrimaryYellow,
    onSecondary = Color.Black,
    background = Color(0xFF000000), // True black backdrop
    surface = Color(0xFF1C1C1E),    // Elevated dark gray (iOS dark surface)
    onBackground = Color.White,
    onSurface = Color.White,
    surfaceVariant = Color(0xFF2C2C2E),
    onSurfaceVariant = Color.Gray,
    error = Color(0xFFFF453A),      // System Red
    outline = Color(0xFF38383A)
)

@Composable
fun CreatorAITheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColors,
        content = content,
    )
}
