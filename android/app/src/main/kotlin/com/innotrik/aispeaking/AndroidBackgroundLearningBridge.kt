package com.innotrik.aispeaking

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AndroidBackgroundLearningBridge(
    private val host: HomiAndroidHost,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 7412
    }

    private val methodChannel = MethodChannel(messenger, "ailingo_background_learning")
    private val eventChannel = EventChannel(messenger, "ailingo_background_learning/events")
    private val appContext = host.applicationContext
    private val companionDeviceManager = HomiCompanionDeviceManager(host)
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
                BackgroundLearningService.start(
                    appContext,
                    startedWhileVisible = host.currentActivity != null,
                ),
            )
            "stop" -> {
                BackgroundLearningService.stop(appContext)
                result.success(null)
            }
            "setActiveLearning" -> {
                val active = call.argument<Boolean>("active") == true
                BackgroundLearningService.setActiveLearning(
                    appContext,
                    active,
                )
                result.success(null)
            }
            "isActive" -> result.success(BackgroundLearningService.isActive())
            "requestNotificationPermission" -> requestNotificationPermission(result)
            "companion.status" -> result.success(
                companionDeviceManager.status(call.argument<String>("deviceId")),
            )
            "companion.associate" -> companionDeviceManager.associate(
                call.argument<String>("deviceId"),
                result,
            )
            else -> result.notImplemented()
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (
            appContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
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
        if (!host.requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST_CODE,
            )
        ) {
            notificationPermissionResult = null
            result.error(
                "VISIBLE_ACTIVITY_REQUIRED",
                "Hãy mở HOMI để cấp quyền thông báo cho phiên học nền.",
                null,
            )
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        notificationPermissionResult?.success(granted)
        notificationPermissionResult = null
        return true
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
        companionDeviceManager.onActivityResult(requestCode, resultCode, data)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        BackgroundLearningService.removeListener(serviceListener)
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
