package com.innotrik.aispeaking

import android.content.pm.PackageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "ailingo_platform"
    private val eventChannelName = "ailingo_platform/events"
    private var speechRecognizerBridge: AndroidSpeechRecognizerBridge? = null
    private var offlineIntentRecognizerBridge: OfflineIntentRecognizerBridge? = null
    private var innotrikBleAudioBridge: InnotrikBleAudioBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        speechRecognizerBridge =
            AndroidSpeechRecognizerBridge(
                this,
                flutterEngine.dartExecutor.binaryMessenger,
            )
        offlineIntentRecognizerBridge =
            OfflineIntentRecognizerBridge(
                flutterEngine.dartExecutor.binaryMessenger,
            )
        innotrikBleAudioBridge =
            InnotrikBleAudioBridge(
                this,
                flutterEngine.dartExecutor.binaryMessenger,
            )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "device.clientId" -> result.success(clientId())
                "device.protocolInfo" -> result.success(protocolInfo())
                "ble.isSupported" ->
                    result.success(
                        packageManager.hasSystemFeature(
                            PackageManager.FEATURE_BLUETOOTH_LE,
                        ),
                    )
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eventChannelName,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    events?.success(
                        mapOf(
                            "type" to "device.bridgeReady",
                            "bleSupported" to
                                packageManager.hasSystemFeature(
                                    PackageManager.FEATURE_BLUETOOTH_LE,
                                ),
                        ),
                    )
                }

                override fun onCancel(arguments: Any?) = Unit
            },
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        speechRecognizerBridge?.dispose()
        speechRecognizerBridge = null
        offlineIntentRecognizerBridge?.dispose()
        offlineIntentRecognizerBridge = null
        innotrikBleAudioBridge?.dispose()
        innotrikBleAudioBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (
            speechRecognizerBridge?.onRequestPermissionsResult(
                requestCode,
                grantResults,
            ) == true
        ) {
            return
        }
        if (
            innotrikBleAudioBridge?.onRequestPermissionsResult(
                requestCode,
                grantResults,
            ) == true
        ) {
            return
        }

        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults,
        )
    }

    private fun clientId(): String {
        val androidId =
            Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ANDROID_ID,
            )
        return "android_$androidId"
    }

    private fun protocolInfo(): Map<String, Any> =
        mapOf(
            "serviceUuid" to InnotrikProtocol.SERVICE_UUID,
            "writeCharacteristicUuid" to
                InnotrikProtocol.WRITE_CHARACTERISTIC_UUID,
            "notifyCharacteristicUuid" to
                InnotrikProtocol.NOTIFY_CHARACTERISTIC_UUID,
            "packetLength" to InnotrikProtocol.PACKET_LENGTH,
            "opusPayloadLength" to InnotrikProtocol.OPUS_PAYLOAD_LENGTH,
            "startCommand" to
                InnotrikProtocol.START_MICROPHONE_COMMAND.map {
                    byte -> byte.toInt() and 0xFF
                },
            "stopCommand" to
                InnotrikProtocol.STOP_MICROPHONE_COMMAND.map {
                    byte -> byte.toInt() and 0xFF
                },
        )
}
