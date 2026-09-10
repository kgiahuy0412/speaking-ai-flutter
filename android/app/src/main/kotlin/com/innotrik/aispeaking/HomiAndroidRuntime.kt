package com.innotrik.aispeaking

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Owns the Flutter engine and native bridges for the lifetime of the process. */
object HomiAndroidRuntime {
    private const val ENGINE_ID = "homi_shared_engine"

    @Volatile
    private var engine: FlutterEngine? = null
    private var bridges: BridgeRegistry? = null
    private lateinit var host: HomiAndroidHost

    fun initialize(context: Context) {
        if (!::host.isInitialized) {
            host = HomiAndroidHost(context)
        }
    }

    fun attachActivity(activity: Activity) {
        initialize(activity.applicationContext)
        host.attach(activity)
    }

    fun detachActivity(activity: Activity) {
        if (::host.isInitialized) host.detach(activity)
    }

    @Synchronized
    fun getOrCreateEngine(context: Context): FlutterEngine {
        initialize(context)
        engine?.let { return it }
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let {
            engine = it
            return it
        }

        val created = FlutterEngine(host.applicationContext)
        bridges = BridgeRegistry(host, created)
        created.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, created)
        engine = created
        return created
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean =
        bridges?.onPermissionResult(requestCode, grantResults) == true

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
        bridges?.onActivityResult(requestCode, resultCode, data) == true

    fun onBackgroundSessionStarted(context: Context) {
        getOrCreateEngine(context)
        bridges?.onBackgroundSessionStarted()
    }

    fun onBackgroundSessionStopped() {
        bridges?.onBackgroundSessionStopped()
    }

    private class BridgeRegistry(
        private val host: HomiAndroidHost,
        flutterEngine: FlutterEngine,
    ) {
        private val messenger = flutterEngine.dartExecutor.binaryMessenger
        private val speechRecognizerBridge = AndroidSpeechRecognizerBridge(host, messenger)
        private val homiOfflineSpeechBridge = HomiOfflineSpeechBridge(host, messenger)
        private val offlineIntentRecognizerBridge = OfflineIntentRecognizerBridge(messenger)
        private val innotrikBleAudioBridge = InnotrikBleAudioBridge(host, messenger)
        private val aiv0BleControlBridge = Aiv0BleControlBridge(host, messenger)
        private val hfpAudioBridge = HfpAudioBridge(host, messenger)
        private val voicePromptBridge = VoicePromptBridge(
            host.applicationContext,
            messenger,
            hfpAudioBridge,
        )
        private val backgroundLearningBridge = AndroidBackgroundLearningBridge(host, messenger)
        private val installationCredentialStore =
            AndroidInstallationCredentialStore(host.applicationContext)
        private val clientIdentityStore = AndroidClientIdentityStore(host.applicationContext)

        init {
            registerPlatformChannels()
        }

        fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean =
            backgroundLearningBridge.onRequestPermissionsResult(requestCode, grantResults) ||
                speechRecognizerBridge.onRequestPermissionsResult(requestCode, grantResults) ||
                innotrikBleAudioBridge.onRequestPermissionsResult(requestCode, grantResults) ||
                aiv0BleControlBridge.onRequestPermissionsResult(requestCode, grantResults) ||
                hfpAudioBridge.onRequestPermissionsResult(requestCode, grantResults)

        fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
            backgroundLearningBridge.onActivityResult(requestCode, resultCode, data)

        fun onBackgroundSessionStarted() {
            aiv0BleControlBridge.onBackgroundSessionStarted()
        }

        fun onBackgroundSessionStopped() {
            speechRecognizerBridge.onBackgroundSessionStopped()
            homiOfflineSpeechBridge.onBackgroundSessionStopped()
            innotrikBleAudioBridge.onBackgroundSessionStopped()
            aiv0BleControlBridge.onBackgroundSessionStopped()
            hfpAudioBridge.onBackgroundSessionStopped()
            voicePromptBridge.stopForBackgroundSession()
        }

        private fun registerPlatformChannels() {
            MethodChannel(messenger, "ailingo_platform").setMethodCallHandler { call, result ->
                when (call.method) {
                    "device.clientId" -> result.success(clientIdentityStore.getOrCreate())
                    "device.resetClientId" -> result.success(clientIdentityStore.reset())
                    "auth.credentials.read" -> result.success(installationCredentialStore.read())
                    "auth.credentials.write" -> {
                        val encoded = call.arguments as? String
                        if (encoded.isNullOrBlank()) {
                            result.error(
                                "invalid_credentials",
                                "Installation credential không hợp lệ.",
                                null,
                            )
                        } else {
                            result.success(installationCredentialStore.write(encoded))
                        }
                    }
                    "auth.credentials.clear" -> result.success(installationCredentialStore.clear())
                    "device.hardwareInfo" -> result.success(hardwareInfo())
                    "device.protocolInfo" -> result.success(protocolInfo())
                    "ble.isSupported" -> result.success(
                        host.applicationContext.packageManager.hasSystemFeature(
                            PackageManager.FEATURE_BLUETOOTH_LE,
                        ),
                    )
                    else -> result.notImplemented()
                }
            }

            EventChannel(messenger, "ailingo_platform/events").setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        events?.success(
                            mapOf(
                                "type" to "device.bridgeReady",
                                "bleSupported" to host.applicationContext.packageManager
                                    .hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE),
                            ),
                        )
                    }

                    override fun onCancel(arguments: Any?) = Unit
                },
            )
        }

        private fun hardwareInfo(): Map<String, Any> {
            val context = host.applicationContext
            val activityManager =
                context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            val storage = StatFs(context.filesDir.absolutePath)
            return mutableMapOf<String, Any>(
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
            ).apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    this["socManufacturer"] = Build.SOC_MANUFACTURER
                    this["socModel"] = Build.SOC_MODEL
                }
            }
        }

        private fun protocolInfo(): Map<String, Any> = mapOf(
            "architecture" to "HFP_AUDIO_PLUS_BLE_CONTROL",
            "controlServiceUuid" to Aiv0BleProtocol.CONTROL_SERVICE,
            "buttonEventUuid" to Aiv0BleProtocol.BUTTON_EVENT,
            "appStateUuid" to Aiv0BleProtocol.APP_STATE,
            "batteryServiceUuid" to Aiv0BleProtocol.BATTERY_SERVICE,
            "batteryLevelUuid" to Aiv0BleProtocol.BATTERY_LEVEL,
            "deviceInformationServiceUuid" to Aiv0BleProtocol.DEVICE_INFORMATION_SERVICE,
            "firmwareRevisionUuid" to Aiv0BleProtocol.FIRMWARE_REVISION,
            "audioTransport" to "HFP",
            "legacyBleAudioEnabledByDefault" to false,
        )
    }
}
