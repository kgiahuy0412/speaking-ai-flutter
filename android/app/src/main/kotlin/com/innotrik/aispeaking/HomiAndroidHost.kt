package com.innotrik.aispeaking

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.lang.ref.WeakReference
import java.util.concurrent.Executor

/**
 * Process-scoped Android host used by bridges that must outlive MainActivity.
 *
 * Long-lived Bluetooth, speech and audio objects use [applicationContext].
 * Operations that must show system UI resolve the currently attached Activity
 * at call time, so a destroyed FlutterActivity is never retained.
 */
class HomiAndroidHost(context: Context) {
    val applicationContext: Context = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var activityReference: WeakReference<Activity>? = null

    val currentActivity: Activity?
        get() = activityReference?.get()?.takeUnless { it.isFinishing || it.isDestroyed }

    val mainExecutor: Executor =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            applicationContext.mainExecutor
        } else {
            Executor { command -> mainHandler.post(command) }
        }

    fun attach(activity: Activity) {
        activityReference = WeakReference(activity)
    }

    fun detach(activity: Activity) {
        if (activityReference?.get() === activity) {
            activityReference = null
        }
    }

    fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }

    fun requestPermissions(permissions: Array<String>, requestCode: Int): Boolean {
        val activity = currentActivity ?: return false
        activity.requestPermissions(permissions, requestCode)
        return true
    }

    fun startVisibleActivity(intent: Intent): Boolean {
        val activity = currentActivity ?: return false
        activity.startActivity(intent)
        return true
    }
}
