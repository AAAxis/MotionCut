package com.theholylabs.creator

import android.app.Application
import com.theholylabs.creator.services.AppsFlyerService
import com.theholylabs.creator.services.PurchaseService

class CreatorAIApp : Application() {

    override fun onCreate() {
        super.onCreate()

        // Configure AppsFlyer (mirrors iOS AppDelegate.didFinishLaunchingWithOptions)
        AppsFlyerService.configure(this)

        // Configure RevenueCat with stored userId (or anonymous fallback)
        PurchaseService.configureOnAppStart(this)

        // Create notification channel
        com.theholylabs.creator.services.NotificationService.createNotificationChannel(this)
    }
}
