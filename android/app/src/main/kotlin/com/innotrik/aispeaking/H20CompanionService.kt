package com.innotrik.aispeaking

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the Flutter process and H20 BLE control path responsive while the
 * screen is off. Android still owns phone-call/alarm priority through audio
 * focus; Dart pauses and restores the current learning state around it.
 */
class H20CompanionService : Service() {
    companion object {
        private const val CHANNEL_ID = "h20_background_assistant"
        private const val NOTIFICATION_ID = 2020
        private const val WAKE_LOCK_TAG = "innotrik:H20Companion"

        fun start(context: Context) {
            val intent = Intent(context, H20CompanionService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, H20CompanionService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startAsForeground()
        val powerManager = getSystemService(PowerManager::class.java)
        wakeLock =
            powerManager
                ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
                ?.apply {
                    setReferenceCounted(false)
                    acquire()
                }
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        // A transient OEM/process reclaim must not silently remove the wake
        // lock that keeps MAIN responsive while the screen is off. Android
        // may recreate this service later with a null intent.
        startAsForeground()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        wakeLock?.let { lock ->
            if (lock.isHeld) {
                lock.release()
            }
        }
        wakeLock = null
        super.onDestroy()
    }

    private fun startAsForeground() {
        val launchIntent = Intent(this, MainActivity::class.java)
        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val notification =
            Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("INNOTRIK đang kết nối H20")
                .setContentText("Sẵn sàng nhận nút MAIN khi màn hình tắt")
                .setContentIntent(pendingIntent)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setOngoing(true)
                .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "Kết nối H20 nền",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Giữ kết nối nút MAIN và âm thanh H20 khi tắt màn hình"
                setShowBadge(false)
            }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }
}
