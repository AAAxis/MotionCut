package com.theholylabs.creator.ui.auth

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.theholylabs.creator.MainActivity
import com.theholylabs.creator.services.AuthService

data class OnboardingStep(
    val title: String,
    val description: String,
    val icon: ImageVector
)

val purposeSteps = listOf(
    OnboardingStep(
        title = "Create Short Videos",
        description = "Turn ideas into reels. Pick a topic, get AI-suggested clips and beats, then make your video in minutes.",
        icon = Icons.Default.Movie
    ),
    OnboardingStep(
        title = "Edit & Add Music",
        description = "Trim clips, add a soundtrack, and style your video. Everything you need is in one place.",
        icon = Icons.Default.LibraryMusic
    ),
    OnboardingStep(
        title = "Save & Share",
        description = "Export to your Library, save to Photos, or share with friends. Your creations, your way.",
        icon = Icons.Default.Share
    )
)

@Composable
fun OnboardingScreen(
    activity: MainActivity,
    onComplete: () -> Unit,
    errorMessage: String? = null
) {
    var currentStep by remember { mutableIntStateOf(0) }
    val showLogin = currentStep == purposeSteps.size

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .systemBarsPadding() // Fixed safe area for top (notch) and bottom
                .padding(26.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.weight(1f))

            AnimatedContent(
                targetState = currentStep,
                transitionSpec = { fadeIn() togetherWith fadeOut() },
                label = "onboarding_content"
            ) { step ->
                if (step < purposeSteps.size) {
                    val data = purposeSteps[step]
                    PurposeStep(data = data)
                } else {
                    LoginStepView(
                        activity = activity,
                        onSkip = onComplete,
                        errorMessage = errorMessage
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            if (!showLogin) {
                // Step Indicators
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(bottom = 40.dp)
                ) {
                    purposeSteps.indices.forEach { index ->
                        Box(
                            modifier = Modifier
                                .size(8.dp)
                                .background(
                                    color = if (index == currentStep) MaterialTheme.colorScheme.primary else Color(0xFF38383A),
                                    shape = CircleShape
                                )
                        )
                    }
                }

                Button(
                    onClick = { currentStep++ },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp),
                    shape = RoundedCornerShape(28.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = Color.White
                    )
                ) {
                    Text("Next", fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                }
                Spacer(modifier = Modifier.height(20.dp))
            }
        }
    }
}

@Composable
private fun PurposeStep(data: OnboardingStep) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(120.dp)
                .background(MaterialTheme.colorScheme.surface, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = data.icon,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.primary
            )
        }

        Spacer(modifier = Modifier.height(40.dp))

        Text(
            text = data.title,
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = data.description,
            fontSize = 16.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            lineHeight = 22.sp,
            modifier = Modifier.padding(horizontal = 8.dp)
        )
    }
}

@Composable
private fun LoginStepView(
    activity: MainActivity,
    onSkip: () -> Unit,
    errorMessage: String?
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            modifier = Modifier
                .size(100.dp)
                .background(MaterialTheme.colorScheme.surface, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.Cloud,
                contentDescription = null,
                modifier = Modifier.size(44.dp),
                tint = MaterialTheme.colorScheme.primary
            )
        }

        Spacer(modifier = Modifier.height(32.dp))

        Text(
            text = "Keep your data safe",
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(12.dp))

        Text(
            text = "Sign in to sync your library across devices. You can skip and sign in later from Profile.",
            fontSize = 15.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            lineHeight = 20.sp,
            modifier = Modifier.padding(horizontal = 8.dp)
        )

        Spacer(modifier = Modifier.height(36.dp))

        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            // Google Sign In Button
            var isSigningIn by remember { mutableStateOf(false) }
            val buttonScale by androidx.compose.animation.core.animateFloatAsState(
                targetValue = if (isSigningIn) 0.95f else 1f,
                animationSpec = androidx.compose.animation.core.spring(
                    dampingRatio = 0.4f,
                    stiffness = 400f
                ),
                label = "button_scale"
            )

            Button(
                onClick = {
                    isSigningIn = true
                    val client = AuthService.getGoogleSignInClient(activity)
                    activity.startActivityForResult(client.signInIntent, AuthService.RC_SIGN_IN)
                },
                enabled = !isSigningIn,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp)
                    .graphicsLayer { scaleX = buttonScale; scaleY = buttonScale },
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    contentColor = Color.White,
                    disabledContainerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.7f),
                    disabledContentColor = Color.White.copy(alpha = 0.7f)
                )
            ) {
                if (isSigningIn) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        color = Color.White,
                        strokeWidth = 2.dp
                    )
                } else {
                    Icon(Icons.Default.Movie, contentDescription = null, modifier = Modifier.size(20.dp))
                }
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    if (isSigningIn) "Signing in..." else "Continue with Google",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            // Reset signing in state when returning from Google sign-in
            LaunchedEffect(errorMessage) {
                if (errorMessage != null) isSigningIn = false
            }

            TextButton(
                onClick = onSkip,
                modifier = Modifier.padding(top = 8.dp)
            ) {
                Text(
                    text = "Skip for now",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        errorMessage?.let { error ->
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = error,
                color = MaterialTheme.colorScheme.error,
                fontSize = 14.sp,
                textAlign = TextAlign.Center
            )
        }
    }
}
