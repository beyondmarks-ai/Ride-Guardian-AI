package com.gndec.rideguardian

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

class MainActivity : FlutterActivity() {
    private val channelName = "rideguardian/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(
                "guardian_alerts", "Guardian safety alerts", NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "SOS alerts and guardian invitations" })
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val intent = Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        .putExtra("guardian_notification", true)
                        .putExtra("guardian_notification_kind", call.argument<String>("kind") ?: "SOS")
                    val pending = PendingIntent.getActivity(this, (call.argument<String>("id") ?: "guardian").hashCode(), intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                    val note = NotificationCompat.Builder(this, "guardian_alerts")
                        .setSmallIcon(android.R.drawable.ic_dialog_alert)
                        .setContentTitle(call.argument<String>("title") ?: "RideGuardian alert")
                        .setContentText(call.argument<String>("body") ?: "Open Family for details")
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                        .setAutoCancel(true).setContentIntent(pending).build()
                    manager.notify((call.argument<String>("id") ?: "guardian").hashCode(), note)
                    result.success(null)
                }
                "consumeOpened" -> {
                    val opened = if (intent.getBooleanExtra("guardian_notification", false)) intent.getStringExtra("guardian_notification_kind") ?: "SOS" else null
                    intent.removeExtra("guardian_notification")
                    intent.removeExtra("guardian_notification_kind")
                    result.success(opened)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("guardian_notification", false)) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, channelName).invokeMethod("opened", intent.getStringExtra("guardian_notification_kind") ?: "SOS")
            }
            intent.removeExtra("guardian_notification")
            intent.removeExtra("guardian_notification_kind")
        }
    }
}
