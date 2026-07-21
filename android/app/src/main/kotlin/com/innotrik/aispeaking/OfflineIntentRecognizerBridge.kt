package com.innotrik.aispeaking

import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryCodec
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer

/**
 * Stable Flutter/native boundary for the BLE offline recognizer.
 *
 * The bridge deliberately reports unavailable until a Vietnamese intent model
 * and the INNOTRIK Opus decoder are installed. Flutter then falls back to
 * OpenAI Realtime without routing phone-microphone traffic through this path.
 */
class OfflineIntentRecognizerBridge(
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private val methodChannel =
        MethodChannel(messenger, "ailingo_offline_intent")
    private val eventChannel =
        EventChannel(messenger, "ailingo_offline_intent/events")
    private val pcmChannel =
        BasicMessageChannel<ByteBuffer?>(
            messenger,
            "ailingo_offline_intent/pcm",
            BinaryCodec.INSTANCE,
        )

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        pcmChannel.setMessageHandler { _, reply -> reply.reply(null) }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "isAvailable" -> result.success(false)
            "start" ->
                result.error(
                    "OFFLINE_MODEL_NOT_INSTALLED",
                    "Vietnamese BLE intent model is not installed.",
                    null,
                )
            "stop" -> result.success(null)
            "cancel", "dispose" -> result.success(true)
            else -> result.notImplemented()
        }
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) = Unit

    override fun onCancel(arguments: Any?) = Unit

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        pcmChannel.setMessageHandler(null)
    }
}
