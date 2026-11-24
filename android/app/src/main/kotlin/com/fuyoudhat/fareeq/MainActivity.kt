package com.fuyoudhat.fareeq

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // High-priority channel so SOS and meeting-point pushes pop up
        // even when the app is closed.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "sos_alerts",
                "Alerts (SOS, meeting point)",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.description = "Urgent messages from your travel group"
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }
}
