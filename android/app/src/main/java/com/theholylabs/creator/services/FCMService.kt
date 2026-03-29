package com.theholylabs.creator.services

import android.util.Log
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

class FCMService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "FCMService"

        fun registerTokenForUser(userId: String) {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    val token = FirebaseMessaging.getInstance().token.await()
                    Log.d(TAG, "FCM token: $token")
                    SupabaseService.saveFCMToken(userId, token)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to get FCM token: ${e.message}")
                }
            }
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "New FCM token: $token")
        val userId = getSharedPreferences("app_prefs", 0)
            .getString("cached_user_id", null)
        if (userId != null) {
            CoroutineScope(Dispatchers.IO).launch {
                SupabaseService.saveFCMToken(userId, token)
            }
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        Log.d(TAG, "FCM message received: ${message.data}")
        val title = message.notification?.title ?: message.data["title"] ?: return
        val body = message.notification?.body ?: message.data["body"] ?: ""
        NotificationService.showPushNotification(applicationContext, title, body)
    }
}
