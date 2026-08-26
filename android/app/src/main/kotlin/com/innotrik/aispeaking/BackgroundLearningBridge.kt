package com.innotrik.aispeaking

import android.app.Activity
import android.content.pm.PackageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class BackgroundLearningBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler {
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (
                        activity.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        result.error(
                            "MICROPHONE_PERMISSION_DENIED",
                            "Cần cấp quyền micro trước khi bắt đầu phiên học nền.",
                            null,
                        )
                        return@setMethodCallHandler
                    }
                    try {
                        BackgroundLearningService.start(activity)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error(
                            "BACKGROUND_SESSION_START_FAILED",
                            error.localizedMessage,
                            null,
                        )
                    }
                }
                "stop" -> {
                    BackgroundLearningService.stop(activity)
                    result.success(null)
                }
                "isActive" -> result.success(BackgroundLearningService.running)
                else -> result.notImplemented()
            }
        }
        eventChannel.setStreamHandler(this)
        BackgroundLearningService.listener = { reason ->
            activity.runOnUiThread {
                eventSink?.success(
                    mapOf(
                        "type" to "background.stopped",
                        "reason" to reason,
                    ),
                )
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        if (BackgroundLearningService.listener != null) {
            BackgroundLearningService.listener = null
        }
        eventSink = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    companion object {
        private const val METHOD_CHANNEL = "ailingo_background_learning"
        private const val EVENT_CHANNEL = "ailingo_background_learning/events"
    }
}
