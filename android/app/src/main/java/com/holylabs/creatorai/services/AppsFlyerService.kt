package com.holylabs.creatorai.services

import android.content.Context
import com.appsflyer.AppsFlyerConversionListener
import com.appsflyer.AppsFlyerLib
import com.holylabs.creatorai.BuildConfig

/**
 * AppsFlyer attribution tracking.
 * Mirrors iOS AppsFlyerService.swift.
 *
 * Key difference from iOS: no ATT dialog needed on Android.
 * AppsFlyer uses install referrer API for attribution instead.
 */
object AppsFlyerService : AppsFlyerConversionListener {

    private const val DEV_KEY = "GbYoDDZzgatShWKfu2nwiJ"
    // Android App ID is set in the AppsFlyer dashboard — no equivalent of appleAppID needed here

    fun configure(context: Context) {
        AppsFlyerLib.getInstance().apply {
            init(DEV_KEY, this@AppsFlyerService, context)
            setDebugLog(BuildConfig.DEBUG)
        }
        android.util.Log.d("AppsFlyer", "SDK configured")
    }

    /**
     * Call from Activity.onResume() — mirrors iOS didBecomeActive notification handler.
     */
    fun start(context: Context) {
        AppsFlyerLib.getInstance().start(context)
        android.util.Log.d("AppsFlyer", "SDK started")
    }

    fun logEvent(context: Context, eventName: String, params: Map<String, Any> = emptyMap()) {
        AppsFlyerLib.getInstance().logEvent(context, eventName, params)
    }

    // MARK: - AppsFlyerConversionListener

    override fun onConversionDataSuccess(data: Map<String, Any>) {
        android.util.Log.d("AppsFlyer", "Conversion data: $data")
    }

    override fun onConversionDataFail(error: String) {
        android.util.Log.e("AppsFlyer", "Conversion data error: $error")
    }

    override fun onAppOpenAttribution(data: Map<String, String>) {
        android.util.Log.d("AppsFlyer", "App open attribution: $data")
    }

    override fun onAttributionFailure(error: String) {
        android.util.Log.e("AppsFlyer", "Attribution failure: $error")
    }
}
