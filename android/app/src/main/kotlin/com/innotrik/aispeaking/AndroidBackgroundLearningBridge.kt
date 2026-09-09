package com.innotrik.aispeaking

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AndroidBackgroundLearningBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 7412
    }

    private val methodChannel = MethodChannel(messenger, "ailingo_background_learning")
    private val eventChannel = EventChannel(messenger, "ailingo_background_learning/events")
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var notificationPermissionResult: MethodChannel.Result? = null
    private val serviceListener: (Map<String, Any?>) -> Unit = { payload ->
        mainHandler.post { eventSink?.success(payload) }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        BackgroundLearningService.addListener(serviceListener)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> result.success(
                BackgroundLearningService.start(activity.applicationContext),
            )
            "stop" -> {
                BackgroundLearningService.stop(activity.applicationContext)
                result.success(null)
            }
            "setActiveLearning" -> {
                val active = call.argument<Boolean>("active") == true
                BackgroundLearningService.setActiveLearning(
                    activity.applicationContext,
                    active,
                )
                result.success(null)
            }
            "isActive" -> result.success(BackgroundLearningService.isActive())
            "requestNotificationPermission" -> requestNotificationPermission(result)
            else -> result.notImplemented()
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.error(
                "PERMISSION_IN_PROGRESS",
                "Đang chờ cấp quyền thông báo cho phiên học nền.",
                null,
            )
            return
        }
        notificationPermissionResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST_CODE,
        )
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        notificationPermissionResult?.success(granted)
        notificationPermissionResult = null
        return true
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        BackgroundLearningService.removeListener(serviceListener)
        BackgroundLearningService.stop(activity.applicationContext)
        notificationPermissionResult?.error(
            "BACKGROUND_BRIDGE_DISPOSED",
            "Ứng dụng đã đóng trước khi nhận quyền thông báo.",
            null,
        )
        notificationPermissionResult = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }
}
