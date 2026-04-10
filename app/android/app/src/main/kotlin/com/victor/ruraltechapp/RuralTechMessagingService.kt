package com.victor.ruraltechapp

import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class RuralTechMessagingService : FirebaseMessagingService() {
    companion object {
        var latestToken: String? = null
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        latestToken = token
        Handler(Looper.getMainLooper()).post {
            MainActivity.channel?.invokeMethod("onTokenRefresh", token)
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val data = HashMap<String, Any>(message.data)
        Handler(Looper.getMainLooper()).post {
            MainActivity.channel?.invokeMethod("onMessage", data)
        }
    }
}
