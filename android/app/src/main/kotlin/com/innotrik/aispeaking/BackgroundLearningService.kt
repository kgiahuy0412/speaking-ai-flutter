package com.innotrik.aispeaking

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Keeps an explicitly-started HOMI/H20 learning session eligible to receive
 * BLE MAIN events while the Flutter activity is covered or the screen locks.
 *
 * The service never opens the microphone itself. A physical MAIN event only
 * grants a short CPU lease; the existing turn controller still owns prompt,
 * HFP/SCO activation, capture and cleanup.
 */
class BackgroundLearningService : Service() {
    companion object {
        private const val CHANNEL_ID = "homi_background_learning"
        private const val NOTIFICATION_ID = 2084
        private const val ACTION_START = "com.innotrik.aispeaking.background.START"
        private const val ACTION_STOP = "com.innotrik.aispeaking.background.STOP"
        private const val EXTRA_STARTED_WHILE_VISIBLE = "startedWhileVisible"
        private const val TURN_WAKE_TIMEOUT_MS = 45_000L
        private const val ACTIVE_LEARNING_WAKE_TIMEOUT_MS = 30 * 60_000L
        private const val TAG = "BackgroundLearning"
        private const val RUNTIME_PREFERENCES = "homi_android_runtime"
        private const val SESSION_REQUESTED = "background_session_requested"
        private const val ACTIVE_LEARNING_REQUESTED = "active_learning_requested"
        private const val MICROPHONE_SESSION_ELIGIBLE = "microphone_session_eligible"

        @Volatile
        private var active = false

        @Volatile
        private var instance: BackgroundLearningService? = null

        @Volatile
        private var activeLearningRequested = false

        private val listeners = CopyOnWriteArraySet<(Map<String, Any?>) -> Unit>()

        private fun preferences(context: Context) =
            context.applicationContext.getSharedPreferences(
                RUNTIME_PREFERENCES,
                Context.MODE_PRIVATE,
            )

        fun wasRequested(context: Context): Boolean =
            preferences(context).getBoolean(SESSION_REQUESTED, false)

        fun start(
            context: Context,
            startedWhileVisible: Boolean = true,
        ): Boolean = runCatching {
            preferences(context).edit()
                .putBoolean(SESSION_REQUESTED, true)
                .apply {
                    if (startedWhileVisible) {
                        putBoolean(MICROPHONE_SESSION_ELIGIBLE, true)
                    }
                }
                .apply()
            if (active) {
                if (startedWhileVisible) {
                    instance?.enableMicrophoneWhileVisible()
                }
                instance?.updateActiveLearningLease(activeLearningRequested)
                return@runCatching true
            }
            val intent = Intent(context, BackgroundLearningService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_STARTED_WHILE_VISIBLE, startedWhileVisible)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            true
        }.getOrDefault(false)

        fun startFromCompanion(context: Context): Boolean {
            if (!wasRequested(context)) return false
            return start(context, startedWhileVisible = false)
        }

        fun stop(context: Context) {
            activeLearningRequested = false
            preferences(context).edit()
                .putBoolean(SESSION_REQUESTED, false)
                .putBoolean(ACTIVE_LEARNING_REQUESTED, false)
                .putBoolean(MICROPHONE_SESSION_ELIGIBLE, false)
                .apply()
            val running = instance
            if (running != null) {
                running.stopSession("explicit_stop")
            } else {
                context.stopService(Intent(context, BackgroundLearningService::class.java))
            }
        }

        fun isActive(): Boolean = active

        fun setActiveLearning(context: Context, enabled: Boolean) {
            activeLearningRequested = enabled
            preferences(context).edit()
                .putBoolean(ACTIVE_LEARNING_REQUESTED, enabled)
                .apply()
            if (enabled && !active) {
                start(context, startedWhileVisible = false)
            }
            instance?.updateActiveLearningLease(enabled)
        }

        /** Called only after a validated H20 button notification. */
        fun notePhysicalMain() {
            instance?.beginBoundedTurnLease()
        }

        fun addListener(listener: (Map<String, Any?>) -> Unit) {
            listeners.add(listener)
        }

        fun removeListener(listener: (Map<String, Any?>) -> Unit) {
            listeners.remove(listener)
        }

        private fun emit(type: String, reason: String? = null) {
            val payload = mapOf<String, Any?>("type" to type, "reason" to reason)
            listeners.forEach { listener -> listener(payload) }
        }
    }

    private var turnWakeLock: PowerManager.WakeLock? = null
    private var activeLearningWakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        activeLearningRequested = preferences(this)
            .getBoolean(ACTIVE_LEARNING_REQUESTED, false)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSession("notification_stop")
            return START_NOT_STICKY
        }
        if (!wasRequested(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        val microphoneEligible =
            intent?.getBooleanExtra(EXTRA_STARTED_WHILE_VISIBLE, false) == true ||
                preferences(this).getBoolean(MICROPHONE_SESSION_ELIGIBLE, false)
        var microphoneActive = microphoneEligible
        val started = runCatching {
            startAsForeground(allowMicrophone = microphoneEligible)
        }.recoverCatching {
            // Android 14 can reject a microphone type when a companion-presence
            // callback recreated the process in the background. Keep BLE/audio
            // alive and wait for the next visible user action before opening mic.
            microphoneActive = false
            startAsForeground(allowMicrophone = false)
        }.isSuccess
        if (!started) {
            active = false
            emit("background.stopped", "foreground_service_unavailable")
            stopSelf()
            return START_NOT_STICKY
        }
        active = true
        HomiAndroidRuntime.onBackgroundSessionStarted(this)
        updateActiveLearningLease(activeLearningRequested)
        emit(
            "background.resumable",
            if (microphoneActive) null else "microphone_requires_visible_resume",
        )
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        releaseTurnWakeLock()
        releaseActiveLearningWakeLock()
        instance = null
        val wasActive = active
        active = false
        if (wasActive) {
            emit("background.stopped", "service_destroyed")
        }
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "Flutter task removed; foreground HOMI runtime remains requested")
        super.onTaskRemoved(rootIntent)
    }

    private fun stopSession(reason: String) {
        releaseTurnWakeLock()
        releaseActiveLearningWakeLock()
        activeLearningRequested = false
        preferences(this).edit()
            .putBoolean(SESSION_REQUESTED, false)
            .putBoolean(ACTIVE_LEARNING_REQUESTED, false)
            .putBoolean(MICROPHONE_SESSION_ELIGIBLE, false)
            .apply()
        val wasActive = active
        active = false
        HomiAndroidRuntime.onBackgroundSessionStopped()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
        if (wasActive) {
            emit("background.stopped", reason)
        }
    }

    private fun startAsForeground(allowMicrophone: Boolean) {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            var serviceTypes = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            if (allowMicrophone && hasRecordAudioPermission()) {
                serviceTypes = serviceTypes or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            if (hasBluetoothRuntimePermission()) {
                serviceTypes = serviceTypes or ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            }
            startForeground(NOTIFICATION_ID, notification, serviceTypes)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    /**
     * A sticky/companion restart may only use connected-device/media types
     * while no Activity is visible. Once the parent opens HOMI again, promote
     * the already-running service to microphone type before another turn.
     */
    private fun enableMicrophoneWhileVisible() {
        if (!active || !hasRecordAudioPermission()) return
        runCatching { startAsForeground(allowMicrophone = true) }
            .onSuccess { emit("background.resumable", null) }
            .onFailure {
                Log.w(TAG, "Could not promote visible session to microphone type", it)
            }
    }

    private fun hasRecordAudioPermission(): Boolean =
        checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun hasBluetoothRuntimePermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun beginBoundedTurnLease() {
        if (!active) return
        releaseTurnWakeLock()
        val powerManager = getSystemService(PowerManager::class.java)
        turnWakeLock = powerManager
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:H20MainTurn")
            .apply {
                setReferenceCounted(false)
                acquire(TURN_WAKE_TIMEOUT_MS)
            }
    }

    private fun releaseTurnWakeLock() {
        val wakeLock = turnWakeLock
        turnWakeLock = null
        if (wakeLock?.isHeld == true) {
            runCatching { wakeLock.release() }
        }
    }

    private fun updateActiveLearningLease(enabled: Boolean) {
        if (!enabled || !active) {
            releaseActiveLearningWakeLock()
            return
        }
        if (activeLearningWakeLock?.isHeld == true) return
        val powerManager = getSystemService(PowerManager::class.java)
        activeLearningWakeLock = powerManager
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:ActiveLesson")
            .apply {
                setReferenceCounted(false)
                acquire(ACTIVE_LEARNING_WAKE_TIMEOUT_MS)
            }
        Log.i(TAG, "Active lesson wake lease acquired")
    }

    private fun releaseActiveLearningWakeLock() {
        val wakeLock = activeLearningWakeLock
        activeLearningWakeLock = null
        if (wakeLock?.isHeld == true) {
            runCatching { wakeLock.release() }
        }
        Log.i(TAG, "Active lesson wake lease released")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Phiên học với H20",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Giữ kết nối H20 trong một phiên học đang hoạt động."
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openAppIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, BackgroundLearningService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("HOMI đang hoạt động")
            .setContentText("H20, âm thanh và phiên học đang được duy trì.")
            .setContentIntent(openAppIntent)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_pause,
                    "Dừng",
                    stopIntent,
                ).build(),
            )
            .build()
    }
}
