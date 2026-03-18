package com.theholylabs.creator.services

import android.app.Activity
import android.content.Context
import android.util.Log
import com.theholylabs.creator.BuildConfig
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.Offerings
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.interfaces.LogInCallback
import com.revenuecat.purchases.interfaces.PurchaseCallback
import com.revenuecat.purchases.interfaces.ReceiveCustomerInfoCallback
import com.revenuecat.purchases.interfaces.ReceiveOfferingsCallback
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
 */
object PurchaseService {

    private const val REVENUECAT_API_KEY = "goog_IxIDNZhbWfBYOKZtrLcMrXjQidL"

    private val creditAmounts = mapOf(
        "credits_100" to 100,
        "credits_200" to 200,
        "credits_300" to 300,
    )

    private var isConfigured = false

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

    fun configure(context: Context, userId: String) {
        if (!isConfigured) {
            Purchases.configure(
                PurchasesConfiguration.Builder(context, REVENUECAT_API_KEY)
                    .appUserID(userId)
                    .build()
            )
            Purchases.sharedInstance.updatedCustomerInfoListener =
                UpdatedCustomerInfoListener { _ -> }
            isConfigured = true
            Log.d("PurchaseService", "Configured for user: $userId")
        } else {
            Purchases.sharedInstance.logIn(userId, object : LogInCallback {
                override fun onReceived(customerInfo: CustomerInfo, created: Boolean) {
                    Log.d("PurchaseService", "Logged in: $userId")
                }
                override fun onError(error: PurchasesError) {
                    Log.e("PurchaseService", "Login error: $error")
                }
            })
        }
    }

    suspend fun loadOfferings(): List<Package> = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.getOfferings(object : ReceiveOfferingsCallback {
            override fun onReceived(offerings: Offerings) {
                cont.resume(offerings.current?.availablePackages ?: emptyList())
            }
            override fun onError(error: PurchasesError) {
                Log.e("PurchaseService", "Failed to load offerings: $error")
                cont.resume(emptyList())
            }
        })
    }

    suspend fun purchase(
        activity: Activity,
        pkg: Package,
        userId: String,
        onCreditsRefresh: suspend () -> Unit,
    ): Boolean = suspendCancellableCoroutine { cont ->
        val params = PurchaseParams.Builder(activity, pkg).build()
        Purchases.sharedInstance.purchase(params, object : PurchaseCallback {
            override fun onCompleted(storeTransaction: StoreTransaction, customerInfo: CustomerInfo) {
                val productId = storeTransaction.productIds.firstOrNull() ?: ""
                val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
                scope.launch {
                    handlePurchaseCompleted(productId, userId)
                    onCreditsRefresh()
                }
                cont.resume(true)
            }
            override fun onError(error: PurchasesError, userCancelled: Boolean) {
                if (!userCancelled) Log.e("PurchaseService", "Purchase error: $error")
                cont.resume(false)
            }
        })
    }

    suspend fun restorePurchases(): Boolean = suspendCancellableCoroutine { cont ->
        Purchases.sharedInstance.restorePurchases(object : ReceiveCustomerInfoCallback {
            override fun onReceived(customerInfo: CustomerInfo) {
                cont.resume(true)
            }
            override fun onError(error: PurchasesError) {
                Log.e("PurchaseService", "Restore failed: $error")
                cont.resume(false)
            }
        })
    }

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
