package com.theholylabs.creator.services

import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInClient
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.GoogleAuthProvider
import com.theholylabs.creator.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/**
 * Firebase Auth for sign-in + FCM.
 * User saved directly to Supabase app_users table.
 */
object AuthService {

    private const val TAG = "AuthService"

    // Web client ID (client_type: 3) from google-services.json
    private const val GOOGLE_WEB_CLIENT_ID =
        "918788275830-d98he7rtcdo4s3pgcfbjr9bf9thh2n1g.apps.googleusercontent.com"

    const val RC_SIGN_IN = 9001

    data class AuthResult(
        val token: String,
        val userId: String,
        val email: String?,
    )

    fun getGoogleSignInClient(context: Context): GoogleSignInClient {
        val gso = GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
            .requestIdToken(GOOGLE_WEB_CLIENT_ID)
            .requestEmail()
            .build()
        return GoogleSignIn.getClient(context, gso)
    }

    suspend fun handleSignInResult(data: Intent?): AuthResult {
        val task = GoogleSignIn.getSignedInAccountFromIntent(data)
        val account = task.getResult(ApiException::class.java)
        val googleIdToken = account.idToken ?: throw Exception("No ID token from Google")

        // Sign into Firebase
        val credential = GoogleAuthProvider.getCredential(googleIdToken, null)
        val authResult = FirebaseAuth.getInstance()
            .signInWithCredential(credential).await()
        val user = authResult.user ?: throw Exception("Firebase sign-in returned no user")

        val token = user.getIdToken(false).await()
            .token ?: throw Exception("No Firebase ID token")

        Log.d(TAG, "Firebase sign-in OK: uid=${user.uid} email=${user.email}")

        // Register user via Worker (uses service key to bypass Supabase RLS)
        registerUserViaWorker(
            userId = user.uid,
            email = user.email,
            displayName = user.displayName,
            avatarUrl = user.photoUrl?.toString()
        )

        return AuthResult(
            token = token,
            userId = user.uid,
            email = user.email,
        )
    }

    private suspend fun registerUserViaWorker(
        userId: String,
        email: String?,
        displayName: String?,
        avatarUrl: String?
    ) = withContext(Dispatchers.IO) {
        try {
            val url = URL("${BuildConfig.API_BASE_URL}/api/auth/token")
            val body = JSONObject().apply {
                put("externalId", userId)
                put("platform", "android")
                if (email != null) put("email", email)
                if (displayName != null) put("displayName", displayName)
                if (avatarUrl != null) put("avatarUrl", avatarUrl)
            }
            val conn = url.openConnection() as HttpsURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true
            conn.outputStream.bufferedWriter().use { it.write(body.toString()) }
            val status = conn.responseCode
            Log.d(TAG, "Worker register user: $status")
            conn.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Worker register failed: ${e.message}")
        }
    }

    suspend fun signOut(context: Context) {
        try {
            getGoogleSignInClient(context).signOut()
            FirebaseAuth.getInstance().signOut()
        } catch (e: Exception) {
            Log.e(TAG, "Sign out error: ${e.message}")
        }
    }
}
