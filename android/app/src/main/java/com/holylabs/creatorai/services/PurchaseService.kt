package com.holylabs.creatorai.services

import android.app.Activity
import android.content.Context
import android.util.Log
import com.holylabs.creatorai.BuildConfig
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.models.StoreTransaction
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.URL
import java.util.UUID
import javax.net.ssl.HttpsURLConnection
import kotlin.coroutines.resume

/**
 * RevenueCat in-app purchases for consumable credits.
 * Mirrors iOS PurchaseService.swift.
 *
 * Key difference from iOS: purchase() requires an Activity reference
 * for the Google Play billing sheet.
 */
object PurchaseService {

    // TODO: Replace with your Android RevenueCat API key from the dashboard (goog_...)
    private const val REVENUECAT_API_KEY = "goog_REPLACE_WITH_YOUR_KEY"

    private val creditAmounts = mapOf(
        "credits_100" to 100,
        "credits_200" to 200,
        "credits_300" to 300,
    )

    private var isConfigured = false

    /**
     * Called from Application.onCreate() with stored userId or anonymous fallback.
     * Mirrors iOS AppState.init() RevenueCat configuration block.
     */
    fun configureOnAppStart(context: Context) {
        val storage = SecureStorage(context)
        val userId = storage.get("userId")
            ?: run {
                val prefs = context.getSharedPreferences("app_prefs", 0)
                prefs.getString("RevenueCatAnonymousId", null)
                    ?: UUID.randomUUID().toString().also { id ->
                        prefs.edit().putString("RevenueCatAnonymousId", id).apply()
                    }
            }
        configure(context, userId)
    }

    /**
     * Configure (or re-login) RevenueCat for a given user.
     * Called on app start and after sign-in.
     */
    fun configure(context: Context, userId: String) {
        if (!isConfigured) {
            Purchases.configure(
                PurchasesConfiguration.Builder(context, REVENUECAT_API_KEY)
                    .appUserID(userId)
                    .build()
            )
            Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { _ ->
                // Credits are server-side — no subscription tracking needed
            }
            isConfigured = true
            Log.d("PurchaseService", "Configured for user: $userId")
        } else {
            Purchases.sharedInstance.logIn(userId) { _, _, error ->
                if (error != null) Log.e("PurchaseService", "Login error: $error")
                else Log.d("PurchaseService", "Logged in: $userId")
            }
        }
    }

    /**
     * Load available packages from RevenueCat.
     * Call from onResume / AppState.loadOfferings().
     */
    suspend fun loadOfferings(): List<Package> = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.getOfferings(
            onError = { error ->
                Log.e("PurchaseService", "Failed to load offerings: $error")
                cont.resume(emptyList())
            },
            onSuccess = { offerings ->
                cont.resume(offerings.current?.availablePackages ?: emptyList())
            }
        )
    }

    /**
     * Purchase a package and sync credits to the server.
     * Returns true on success, false if cancelled.
     *
     * Requires Activity for Google Play billing sheet — no equivalent restriction on iOS.
     */
    suspend fun purchase(
        activity: Activity,
        pkg: Package,
        userId: String,
        onCreditsRefresh: suspend () -> Unit,
    ): Boolean = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.purchaseWith(
            purchaseParams = com.revenuecat.purchases.PurchaseParams.Builder(activity, pkg).build(),
            onError = { error, userCancelled ->
                if (userCancelled) {
                    cont.resume(false)
                } else {
                    Log.e("PurchaseService", "Purchase error: $error")
                    cont.resume(false)
                }
            },
            onSuccess = { storeTransaction, _ ->
                val productId = storeTransaction.productIds.firstOrNull() ?: ""
                // Fire-and-forget credits sync
                val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
                scope.launch {
                    handlePurchaseCompleted(productId, userId)
                    onCreditsRefresh()
                }
                cont.resume(true)
            }
        )
    }

    /**
     * Restore purchases (non-consumables / subscriptions — consumables can't be restored on Android).
     */
    suspend fun restorePurchases(): Boolean = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.restorePurchasesWith(
            onError = { error ->
                Log.e("PurchaseService", "Restore failed: $error")
                cont.resume(false)
            },
            onSuccess = { _ -> cont.resume(true) }
        )
    }

    // MARK: - Private

    private suspend fun handlePurchaseCompleted(productId: String, userId: String) {
        val credits = creditAmounts[productId] ?: 100
        Log.d("PurchaseService", "Purchase: $productId → +$credits credits")
        addCreditsOnServer(userId, productId, credits)
    }

    private suspend fun addCreditsOnServer(userId: String, productId: String, amount: Int) =
        withContext(Dispatchers.IO) {
            try {
                val url = URL("${BuildConfig.API_BASE_URL}/api/credits/add")
                val conn = url.openConnection() as HttpsURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.doOutput = true

                val body = JSONObject().apply {
                    put("userId", userId)
                    put("productId", productId)
                    put("amount", amount)
                }.toString()

                conn.outputStream.use { it.write(body.toByteArray()) }
                conn.inputStream.close()
                conn.disconnect()
            } catch (e: Exception) {
                Log.e("PurchaseService", "Failed to add credits on server: ${e.message}")
            }
        }
}
