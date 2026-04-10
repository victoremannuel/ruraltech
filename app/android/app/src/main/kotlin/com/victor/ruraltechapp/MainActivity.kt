package com.victor.ruraltechapp

import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "com.victor.ruraltechapp/push"
        var channel: MethodChannel? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ensureFirebaseInit()

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getToken" -> {
                    FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                        if (task.isSuccessful) {
                            val token = task.result
                            RuralTechMessagingService.latestToken = token
                            result.success(token)
                        } else {
                            result.success(RuralTechMessagingService.latestToken)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ensureFirebaseInit() {
        if (FirebaseApp.getApps(this).isNotEmpty()) return
        val res = resources
        val projectId = res.getString(R.string.fcm_project_id)
        if (projectId.startsWith("PREENCHER")) return
        FirebaseApp.initializeApp(
            this,
            FirebaseOptions.Builder()
                .setProjectId(projectId)
                .setApplicationId(res.getString(R.string.fcm_application_id))
                .setApiKey(res.getString(R.string.fcm_api_key))
                .setGcmSenderId(res.getString(R.string.fcm_sender_id))
                .build()
        )
    }
}
