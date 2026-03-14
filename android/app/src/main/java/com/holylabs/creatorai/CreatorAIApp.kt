package com.holylabs.creatorai

import android.app.Application
import com.holylabs.creatorai.services.AppsFlyerService
import com.holylabs.creatorai.services.PurchaseService

class CreatorAIApp : Application() {

    override fun onCreate() {
        super.onCreate()

        // Configure AppsFlyer (mirrors iOS AppDelegate.didFinishLaunchingWithOptions)
        AppsFlyerService.configure(this)

        // Configure RevenueCat with stored userId (or anonymous fallback)
        PurchaseService.configureOnAppStart(this)
    }
}
