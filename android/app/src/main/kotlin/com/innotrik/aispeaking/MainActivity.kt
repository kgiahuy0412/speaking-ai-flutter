package com.innotrik.aispeaking

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.StatFs
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
    private var aiv0BleControlBridge: Aiv0BleControlBridge? = null
    private var hfpAudioBridge: HfpAudioBridge? = null
    private var voicePromptBridge: VoicePromptBridge? = null

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
        aiv0BleControlBridge =
            Aiv0BleControlBridge(
                this,
                flutterEngine.dartExecutor.binaryMessenger,
            )
        hfpAudioBridge =
            HfpAudioBridge(
                this,
                flutterEngine.dartExecutor.binaryMessenger,
            )
        voicePromptBridge =
            VoicePromptBridge(
                this,
                flutterEngine.dartExecutor.binaryMessenger,
            )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "device.clientId" -> result.success(clientId())
                "device.hardwareInfo" -> result.success(hardwareInfo())
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
        aiv0BleControlBridge?.dispose()
        aiv0BleControlBridge = null
        hfpAudioBridge?.dispose()
        hfpAudioBridge = null
        voicePromptBridge?.dispose()
        voicePromptBridge = null
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
        if (
            aiv0BleControlBridge?.onRequestPermissionsResult(
                requestCode,
                grantResults,
            ) == true
        ) {
            return
        }
        if (
            hfpAudioBridge?.onRequestPermissionsResult(
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

    private fun hardwareInfo(): Map<String, Any> {
        val activityManager =
            getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)

        val storage = StatFs(filesDir.absolutePath)
        val hardware =
            mutableMapOf<String, Any>(
                "manufacturer" to Build.MANUFACTURER,
                "brand" to Build.BRAND,
                "model" to Build.MODEL,
                "androidVersion" to Build.VERSION.RELEASE,
                "sdkInt" to Build.VERSION.SDK_INT,
                "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
                "totalRamBytes" to memoryInfo.totalMem,
                "availableRamBytes" to memoryInfo.availMem,
                "totalStorageBytes" to storage.totalBytes,
                "availableStorageBytes" to storage.availableBytes,
            )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            hardware["socManufacturer"] = Build.SOC_MANUFACTURER
            hardware["socModel"] = Build.SOC_MODEL
        }

        return hardware
    }

    private fun protocolInfo(): Map<String, Any> =
        mapOf(
            "architecture" to "HFP_AUDIO_PLUS_BLE_CONTROL",
            "controlServiceUuid" to Aiv0BleProtocol.CONTROL_SERVICE,
            "buttonEventUuid" to Aiv0BleProtocol.BUTTON_EVENT,
            "appStateUuid" to Aiv0BleProtocol.APP_STATE,
            "batteryServiceUuid" to Aiv0BleProtocol.BATTERY_SERVICE,
            "batteryLevelUuid" to Aiv0BleProtocol.BATTERY_LEVEL,
            "deviceInformationServiceUuid" to
                Aiv0BleProtocol.DEVICE_INFORMATION_SERVICE,
            "firmwareRevisionUuid" to Aiv0BleProtocol.FIRMWARE_REVISION,
            "audioTransport" to "HFP",
            "legacyBleAudioEnabledByDefault" to false,
        )
}
