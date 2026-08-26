package com.innotrik.aispeaking

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterFragmentActivity() {
    private val methodChannelName = "ailingo_platform"
    private val eventChannelName = "ailingo_platform/events"
    private var speechRecognizerBridge: AndroidSpeechRecognizerBridge? = null
    private var offlineIntentRecognizerBridge: OfflineIntentRecognizerBridge? = null
    private var innotrikBleAudioBridge: InnotrikBleAudioBridge? = null
    private var aiv0BleControlBridge: Aiv0BleControlBridge? = null
    private var hfpAudioBridge: HfpAudioBridge? = null
    private var voicePromptBridge: VoicePromptBridge? = null
    private var backgroundLearningBridge: BackgroundLearningBridge? = null
    private val clientIdentityStore by lazy { AndroidClientIdentityStore(this) }
    private val installationCredentialStore by lazy {
        AndroidInstallationCredentialStore(this)
    }

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
        backgroundLearningBridge =
            BackgroundLearningBridge(
                this,
                flutterEngine.dartExecutor.binaryMessenger,
            )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "device.clientId" -> result.success(clientIdentityStore.getOrCreate())
                "device.resetClientId" -> result.success(clientIdentityStore.reset())
                "auth.credentials.read" ->
                    result.success(installationCredentialStore.read())
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
                "auth.credentials.clear" ->
                    result.success(installationCredentialStore.clear())
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
        backgroundLearningBridge?.dispose()
        backgroundLearningBridge = null
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

private class AndroidClientIdentityStore(
    private val context: Context,
) {
    private val preferences =
        context.getSharedPreferences("homi_client_identity", Context.MODE_PRIVATE)

    fun getOrCreate(): String {
        val stored = preferences.getString("client_id", null)?.trim()
        if (!stored.isNullOrEmpty()) return stored
        val legacyAndroidId =
            Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ANDROID_ID,
            )
        val migrated =
            if (legacyAndroidId.isNullOrBlank()) create() else "android_$legacyAndroidId"
        return migrated.also {
            preferences.edit().putString("client_id", it).apply()
        }
    }

    fun reset(): Boolean {
        preferences.edit().putString("client_id", create()).apply()
        return true
    }

    private fun create() = "android_${UUID.randomUUID().toString().lowercase()}"
}

private class AndroidInstallationCredentialStore(
    context: Context,
) {
    private val preferences =
        context.getSharedPreferences("homi_installation_auth", Context.MODE_PRIVATE)
    private val keyAlias = "homi.installation.credentials.v1"

    fun read(): String? {
        val encrypted = preferences.getString("encrypted", null) ?: return null
        val iv = preferences.getString("iv", null) ?: return null
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                encryptionKey(),
                GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)),
            )
            String(
                cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP)),
                Charsets.UTF_8,
            )
        } catch (_: Exception) {
            clear()
            null
        }
    }

    fun write(value: String): Boolean {
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, encryptionKey())
            val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
            preferences
                .edit()
                .putString("encrypted", Base64.encodeToString(encrypted, Base64.NO_WRAP))
                .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                .commit()
        } catch (_: Exception) {
            false
        }
    }

    fun clear(): Boolean = preferences.edit().clear().commit()

    private fun encryptionKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(keyAlias, null) as? SecretKey)?.let { return it }
        val generator =
            KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                "AndroidKeyStore",
            )
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey()
    }
}
