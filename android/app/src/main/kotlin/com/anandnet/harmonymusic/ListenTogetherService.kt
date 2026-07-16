package com.anandnet.harmonymusic

import android.app.*
import android.content.Intent
import android.os.Build
import android.os.IBinder

class ListenTogetherService : Service() {
    companion object { const val CHANNEL_ID = "listen_together"; const val NOTIFICATION_ID = 4207 }
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.listen_together_notification_channel),
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)
        startForeground(NOTIFICATION_ID, notification.setSmallIcon(applicationInfo.icon)
            .setContentTitle(getString(R.string.listen_together_notification_title))
            .setContentText(getString(R.string.listen_together_notification_text))
            .setOngoing(true).setContentIntent(pending).build())
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
