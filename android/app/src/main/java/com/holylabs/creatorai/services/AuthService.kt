package com.holylabs.creatorai.services

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInAccount
import com.google.android.gms.auth.api.signin.GoogleSignInClient
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.gotrue.Auth
import io.github.jan.supabase.gotrue.auth
import io.github.jan.supabase.gotrue.providers.Google
import io.github.jan.supabase.gotrue.providers.builtin.IDToken
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Google Sign-In (legacy GoogleSignInClient) → Supabase.
 * No Firebase / google-services.json needed — uses Web Client ID directly.
 */
object AuthService {

    private const val SUPABASE_URL = "https://uhpuqiptxcjluwsetoev.supabase.co"
    private const val SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVocHVxaXB0eGNqbHV3c2V0b2V2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTcwOTE4OTYsImV4cCI6MjA3MjY2Nzg5Nn0.D_t-dyA4Z192kAU97Oi79At_IDT_5putusXrR0bQ6z8"
    private const val GOOGLE_WEB_CLIENT_ID = "482450515497-ttkljbevgt6bg4sqil9hklk1vol1d0fn.apps.googleusercontent.com"

    const val RC_SIGN_IN = 9001

    private val supabase by lazy {
        createSupabaseClient(SUPABASE_URL, SUPABASE_ANON_KEY) {
            install(Auth)
        }
    }

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

    /**
     * Call from Activity.onActivityResult() after the Google Sign-In intent returns.
     * Passes the ID token to Supabase and returns AuthResult.
     */
    suspend fun handleSignInResult(data: Intent?): AuthResult {
        val task = GoogleSignIn.getSignedInAccountFromIntent(data)
        val account: GoogleSignInAccount = task.getResult(ApiException::class.java)
        val idToken = account.idToken ?: throw Exception("No ID token from Google")

        supabase.auth.signInWith(IDToken) {
            provider = Google
            this.idToken = idToken
        }

        val session = supabase.auth.currentSessionOrNull()
            ?: throw Exception("No Supabase session after sign-in")

        Log.d("AuthService", "Signed in: ${session.user?.id}")

        return AuthResult(
            token = session.accessToken,
            userId = session.user?.id ?: throw Exception("No user ID"),
            email = session.user?.email,
        )
    }

    suspend fun signOut(context: Context) {
        try {
            getGoogleSignInClient(context).signOut()
            supabase.auth.signOut()
        } catch (e: Exception) {
            Log.e("AuthService", "Sign out error: ${e.message}")
        }
    }
}
