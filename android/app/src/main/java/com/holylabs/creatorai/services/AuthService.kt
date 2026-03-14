package com.holylabs.creatorai.services

import android.content.Context
import android.util.Log
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.gotrue.Auth
import io.github.jan.supabase.gotrue.auth
import io.github.jan.supabase.gotrue.providers.Google
import io.github.jan.supabase.gotrue.providers.builtin.IDToken

/**
 * Google Sign-In + Supabase auth.
 * Replaces iOS Apple Sign-In + Supabase flow.
 * Same backend JWT token model — no backend changes needed.
 */
object AuthService {

    // TODO: Fill in from your Supabase project settings
    private const val SUPABASE_URL = "https://REPLACE.supabase.co"
    private const val SUPABASE_ANON_KEY = "REPLACE_WITH_ANON_KEY"

    // TODO: Fill in from Google Cloud Console (OAuth 2.0 Web Client ID)
    private const val GOOGLE_WEB_CLIENT_ID = "REPLACE_WITH_WEB_CLIENT_ID.apps.googleusercontent.com"

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

    /**
     * Sign in with Google via Credential Manager → Supabase.
     * Returns AuthResult on success, throws on failure.
     */
    suspend fun signInWithGoogle(context: Context): AuthResult {
        // Step 1: Get Google ID token via Credential Manager
        val googleIdOption = GetGoogleIdOption.Builder()
            .setFilterByAuthorizedAccounts(false)
            .setServerClientId(GOOGLE_WEB_CLIENT_ID)
            .build()

        val request = GetCredentialRequest.Builder()
            .addCredentialOption(googleIdOption)
            .build()

        val credentialManager = CredentialManager.create(context)
        val result = credentialManager.getCredential(context, request)
        val googleCredential = GoogleIdTokenCredential.createFrom(result.credential.data)
        val idToken = googleCredential.idToken

        // Step 2: Sign in to Supabase with the Google ID token
        supabase.auth.signInWith(IDToken) {
            provider = Google
            this.idToken = idToken
        }

        val session = supabase.auth.currentSessionOrNull()
            ?: throw Exception("No session after Google sign-in")

        Log.d("AuthService", "Signed in: ${session.user?.id}")

        return AuthResult(
            token = session.accessToken,
            userId = session.user?.id ?: throw Exception("No user ID in session"),
            email = session.user?.email,
        )
    }

    suspend fun signOut() {
        try {
            supabase.auth.signOut()
        } catch (e: Exception) {
            Log.e("AuthService", "Sign out error: ${e.message}")
        }
    }
}
