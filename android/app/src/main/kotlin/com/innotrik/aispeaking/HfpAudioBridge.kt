package com.innotrik.aispeaking

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Routes Android speech recognition through a Bluetooth Classic HFP/SCO mic.
 *
 * Public Android APIs do not let third-party apps connect the HFP profile.
 * This bridge lists paired HFP-capable devices, opens Bluetooth Settings when
 * the chosen profile is not connected yet, and selects the connected SCO input.
 */
class HfpAudioBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val CONTROL_CHANNEL = "ailingo_hfp_audio"
        private const val EVENT_CHANNEL = "ailingo_hfp_audio/events"
        private const val PERMISSION_REQUEST_CODE = 7393

        private val HFP_UUIDS =
            setOf(
                UUID.fromString("00001108-0000-1000-8000-00805f9b34fb"),
                UUID.fromString("0000111e-0000-1000-8000-00805f9b34fb"),
                UUID.fromString("00001112-0000-1000-8000-00805f9b34fb"),
                UUID.fromString("0000111f-0000-1000-8000-00805f9b34fb"),
            )
    }

    private val methodChannel = MethodChannel(messenger, CONTROL_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val bluetoothManager =
        activity.getSystemService(BluetoothManager::class.java)
    private val adapter: BluetoothAdapter? = bluetoothManager?.adapter
    private val audioManager =
        activity.getSystemService(AudioManager::class.java)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null
    private var headset: BluetoothHeadset? = null
    private var selectedDevice: BluetoothDevice? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingAudioRouteResult: MethodChannel.Result? = null
    private var phase = "idle"
    private var statusMessage: String? = null
    private var routeActive = false
    private var previousAudioMode = AudioManager.MODE_NORMAL
    private var disposed = false

    private val audioRouteTimeout =
        Runnable {
            val pending = pendingAudioRouteResult ?: return@Runnable
            pendingAudioRouteResult = null
            pending.error(
                "HFP_ROUTE_TIMEOUT",
                "Android không mở được đường mic HFP/SCO trong thời gian cho phép.",
                null,
            )
            stopAudioRouteInternal()
            phase = "error"
            statusMessage =
                "Không mở được mic HFP/SCO. Hãy ngắt và kết nối lại tai nghe."
            emitStatus()
        }

    private val bluetoothReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(
                context: Context?,
                intent: Intent?,
            ) {
                when (intent?.action) {
                    BluetoothHeadset.ACTION_AUDIO_STATE_CHANGED -> {
                        when (
                            intent.getIntExtra(
                                BluetoothProfile.EXTRA_STATE,
                                BluetoothHeadset.STATE_AUDIO_DISCONNECTED,
                            )
                        ) {
                            BluetoothHeadset.STATE_AUDIO_CONNECTED ->
                                completePendingAudioRoute()
                            BluetoothHeadset.STATE_AUDIO_DISCONNECTED -> {
                                if (routeActive) {
                                    routeActive = false
                                    refreshSelectedDeviceStatus()
                                }
                            }
                        }
                    }
                    BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED ->
                        refreshSelectedDeviceStatus()
                }
            }
        }

    private val profileListener =
        object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(
                profile: Int,
                proxy: BluetoothProfile,
            ) {
                if (profile != BluetoothProfile.HEADSET || disposed) return
                headset = proxy as? BluetoothHeadset
                refreshSelectedDeviceStatus()
            }

            override fun onServiceDisconnected(profile: Int) {
                if (profile != BluetoothProfile.HEADSET) return
                headset = null
                if (routeActive) {
                    stopAudioRouteInternal()
                }
                phase = "idle"
                statusMessage = "Dịch vụ HFP vừa ngắt kết nối."
                emitStatus()
            }
        }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        adapter?.let { bluetoothAdapter ->
            runCatching {
                bluetoothAdapter.getProfileProxy(
                    activity,
                    profileListener,
                    BluetoothProfile.HEADSET,
                )
            }
        }
        val filter =
            IntentFilter().apply {
                addAction(BluetoothHeadset.ACTION_AUDIO_STATE_CHANGED)
                addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(
                bluetoothReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            activity.registerReceiver(bluetoothReceiver, filter)
        }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "initialize" -> initialize(result)
            "requestPermissions" -> requestPermissions(result)
            "findDevices" -> findDevices(result)
            "connect" -> connect(call, result)
            "disconnect" -> disconnect(result)
            "startAudioRoute" -> startAudioRoute(result)
            "stopAudioRoute" -> {
                stopAudioRouteInternal()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        if (!hasBluetoothFeature()) {
            phase = "unsupported"
            statusMessage = "Điện thoại không hỗ trợ Bluetooth HFP."
        } else if (adapter?.isEnabled != true) {
            phase = "error"
            statusMessage = "Hãy bật Bluetooth trên điện thoại."
        } else if (!hasConnectPermission()) {
            phase = "permissionRequired"
            statusMessage = "Cần quyền Thiết bị ở gần/Bluetooth."
        } else {
            refreshSelectedDeviceStatus()
        }
        result.success(snapshot())
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (hasConnectPermission()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error(
                "BLUETOOTH_PERMISSION_PENDING",
                "Ứng dụng đang chờ cấp quyền Bluetooth.",
                null,
            )
            return
        }
        pendingPermissionResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
            PERMISSION_REQUEST_CODE,
        )
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val pending = pendingPermissionResult
        pendingPermissionResult = null
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        if (granted) {
            phase = "idle"
            statusMessage = null
            emitStatus()
        } else {
            phase = "permissionRequired"
            statusMessage = "Cần quyền Thiết bị ở gần/Bluetooth để dùng HFP."
            emitStatus()
        }
        pending?.success(granted)
        return true
    }

    private fun findDevices(result: MethodChannel.Result) {
        if (!ensureBluetoothReady(result)) return
        phase = "scanning"
        statusMessage = "Đang tìm thiết bị HFP đã ghép đôi…"
        emitStatus()
        try {
            val connectedAddresses = connectedHeadsets().map { it.address }.toSet()
            val devices =
                adapter
                    ?.bondedDevices
                    .orEmpty()
                    .filter { device -> isLikelyHfp(device, connectedAddresses) }
                    .sortedWith(
                        compareByDescending<BluetoothDevice> {
                            connectedAddresses.contains(it.address)
                        }.thenBy { safeName(it).lowercase() },
                    )
                    .map { device ->
                        mapOf(
                            "id" to device.address,
                            "name" to safeName(device),
                            "isConnected" to connectedAddresses.contains(device.address),
                        )
                    }
            refreshSelectedDeviceStatus()
            result.success(devices)
        } catch (error: SecurityException) {
            fail(result, "BLUETOOTH_PERMISSION", "Chưa cấp quyền Bluetooth.")
        }
    }

    private fun connect(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (!ensureBluetoothReady(result)) return
        val deviceId = call.argument<String>("deviceId")?.trim().orEmpty()
        if (deviceId.isEmpty()) {
            fail(result, "HFP_DEVICE_REQUIRED", "Chưa chọn thiết bị HFP.")
            return
        }
        phase = "connecting"
        statusMessage = "Đang kiểm tra kết nối HFP…"
        emitStatus()
        try {
            val device = adapter?.bondedDevices?.firstOrNull { it.address == deviceId }
            if (device == null) {
                fail(
                    result,
                    "HFP_DEVICE_NOT_PAIRED",
                    "Thiết bị HFP chưa được ghép đôi với điện thoại.",
                )
                return
            }
            selectedDevice = device
            if (!isHeadsetConnected(device)) {
                phase = "idle"
                statusMessage =
                    "Hãy kết nối thiết bị trong Cài đặt Bluetooth, rồi quay lại bấm Tìm HFP."
                emitStatus()
                runCatching {
                    activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                }
                result.error("HFP_NOT_CONNECTED", statusMessage, null)
                return
            }
            phase = "ready"
            statusMessage = "HFP đã kết nối; mic Bluetooth sẵn sàng."
            emitStatus()
            result.success(snapshot())
        } catch (error: SecurityException) {
            fail(result, "BLUETOOTH_PERMISSION", "Chưa cấp quyền Bluetooth.")
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        stopAudioRouteInternal()
        selectedDevice = null
        phase = "idle"
        statusMessage = null
        emitStatus()
        result.success(null)
    }

    private fun startAudioRoute(result: MethodChannel.Result) {
        if (!ensureBluetoothReady(result)) return
        if (pendingAudioRouteResult != null) {
            result.error(
                "HFP_ROUTE_PENDING",
                "Android đang mở đường mic HFP/SCO.",
                null,
            )
            return
        }
        val device = selectedDevice
        if (device == null || !isHeadsetConnected(device)) {
            fail(
                result,
                "HFP_NOT_CONNECTED",
                "Hãy kết nối thiết bị HFP trước khi bắt đầu nhận diện.",
            )
            return
        }

        previousAudioMode = audioManager.mode
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val communicationDevice =
                    audioManager.availableCommunicationDevices.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO &&
                            addressesMatch(it.address, device.address)
                    } ?: audioManager.availableCommunicationDevices.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                    }
                val routed = communicationDevice != null &&
                    audioManager.setCommunicationDevice(communicationDevice)
                if (!routed) {
                    audioManager.mode = previousAudioMode
                    fail(
                        result,
                        "HFP_ROUTE_FAILED",
                        "Android chưa mở được đường mic HFP/SCO. Hãy ngắt và kết nối lại tai nghe.",
                    )
                    return
                }
                routeActive = true
                phase = "recording"
                statusMessage = "Đang dùng mic HFP/SCO để nhận diện."
                emitStatus()
                result.success(null)
            } else {
                pendingAudioRouteResult = result
                phase = "discovering"
                statusMessage = "Đang mở đường mic HFP/SCO…"
                emitStatus()
                @Suppress("DEPRECATION")
                audioManager.startBluetoothSco()
                @Suppress("DEPRECATION")
                run { audioManager.isBluetoothScoOn = true }
                mainHandler.postDelayed(audioRouteTimeout, 5000L)
            }
    }

    private fun completePendingAudioRoute() {
        val pending = pendingAudioRouteResult ?: return
        pendingAudioRouteResult = null
        mainHandler.removeCallbacks(audioRouteTimeout)
        routeActive = true
        phase = "recording"
        statusMessage = "Đang dùng mic HFP/SCO để nhận diện."
        emitStatus()
        pending.success(null)
    }

    private fun stopAudioRouteInternal() {
        pendingAudioRouteResult?.let { pending ->
            pendingAudioRouteResult = null
            mainHandler.removeCallbacks(audioRouteTimeout)
            pending.error(
                "HFP_ROUTE_CANCELLED",
                "Đã dừng trước khi đường mic HFP/SCO sẵn sàng.",
                null,
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION")
            audioManager.stopBluetoothSco()
            @Suppress("DEPRECATION")
            run { audioManager.isBluetoothScoOn = false }
        }
        if (routeActive) {
            audioManager.mode = previousAudioMode
        }
        routeActive = false
        if (selectedDevice != null && isHeadsetConnected(selectedDevice!!)) {
            phase = "ready"
            statusMessage = "HFP đã kết nối; mic Bluetooth sẵn sàng."
        } else {
            phase = "idle"
            statusMessage = null
        }
        emitStatus()
    }

    private fun refreshSelectedDeviceStatus() {
        val selected = selectedDevice
        if (routeActive && selected != null && isHeadsetConnected(selected)) {
            phase = "recording"
            statusMessage = "Đang dùng mic HFP/SCO để nhận diện."
        } else if (selected != null && isHeadsetConnected(selected)) {
            phase = "ready"
            statusMessage = "HFP đã kết nối; mic Bluetooth sẵn sàng."
        } else {
            phase = "idle"
            if (selected != null) {
                statusMessage = "Thiết bị HFP chưa kết nối trong hệ thống."
            } else if (statusMessage?.startsWith("Đang tìm") == true) {
                statusMessage = null
            }
        }
        emitStatus()
    }

    private fun connectedHeadsets(): List<BluetoothDevice> =
        try {
            headset?.connectedDevices.orEmpty()
        } catch (_: SecurityException) {
            emptyList()
        }

    private fun isHeadsetConnected(device: BluetoothDevice): Boolean {
        val profileConnected = connectedHeadsets().any { it.address == device.address }
        if (profileConnected) return true
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return audioManager.availableCommunicationDevices.any {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO &&
                addressesMatch(it.address, device.address)
        }
    }

    private fun isLikelyHfp(
        device: BluetoothDevice,
        connectedAddresses: Set<String>,
    ): Boolean {
        if (connectedAddresses.contains(device.address)) return true
        val hasHfpUuid = device.uuids?.any { HFP_UUIDS.contains(it.uuid) } == true
        if (hasHfpUuid) return true
        return device.bluetoothClass?.majorDeviceClass ==
            android.bluetooth.BluetoothClass.Device.Major.AUDIO_VIDEO
    }

    private fun safeName(device: BluetoothDevice): String =
        try {
            device.name?.trim().takeUnless { it.isNullOrEmpty() } ?: device.address
        } catch (_: SecurityException) {
            device.address
        }

    private fun addressesMatch(
        first: String?,
        second: String?,
    ): Boolean =
        !first.isNullOrBlank() &&
            !second.isNullOrBlank() &&
            first.equals(second, ignoreCase = true)

    private fun hasBluetoothFeature(): Boolean =
        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)

    private fun hasConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    private fun ensureBluetoothReady(result: MethodChannel.Result): Boolean {
        if (!hasBluetoothFeature() || adapter == null) {
            fail(result, "HFP_UNSUPPORTED", "Điện thoại không hỗ trợ Bluetooth HFP.")
            return false
        }
        if (adapter.isEnabled != true) {
            fail(result, "BLUETOOTH_DISABLED", "Hãy bật Bluetooth trên điện thoại.")
            return false
        }
        if (!hasConnectPermission()) {
            fail(result, "BLUETOOTH_PERMISSION", "Chưa cấp quyền Bluetooth.")
            return false
        }
        return true
    }

    private fun fail(
        result: MethodChannel.Result,
        code: String,
        message: String,
    ) {
        phase = "error"
        statusMessage = message
        emitStatus()
        result.error(code, message, null)
    }

    private fun snapshot(): Map<String, Any?> =
        mapOf(
            "type" to "status",
            "phase" to phase,
            "deviceId" to selectedDevice?.address,
            "deviceName" to selectedDevice?.let(::safeName),
            "message" to statusMessage,
            "sampleRate" to 16000,
            "routeActive" to routeActive,
            "inputDeviceName" to activeScoDeviceName(AudioManager.GET_DEVICES_INPUTS),
            "outputDeviceName" to activeScoDeviceName(AudioManager.GET_DEVICES_OUTPUTS),
            "audioRoute" to if (routeActive) "HFP/SCO two-way" else "system/default",
        )

    private fun activeScoDeviceName(direction: Int): String? {
        if (!routeActive) return null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val communicationDevice = audioManager.communicationDevice
            if (communicationDevice?.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) {
                return communicationDevice.productName?.toString()
                    ?.trim()
                    ?.takeUnless { it.isEmpty() }
                    ?: selectedDevice?.let(::safeName)
            }
        }
        return audioManager.getDevices(direction)
            .firstOrNull { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO }
            ?.productName
            ?.toString()
            ?.trim()
            ?.takeUnless { it.isEmpty() }
            ?: selectedDevice?.let(::safeName)
    }

    private fun emitStatus() {
        if (!disposed) {
            activity.runOnUiThread { eventSink?.success(snapshot()) }
        }
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        eventSink = events
        events?.success(snapshot())
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        if (disposed) return
        stopAudioRouteInternal()
        disposed = true
        pendingPermissionResult?.error(
            "HFP_DISPOSED",
            "Ứng dụng đã dừng trước khi nhận quyền Bluetooth.",
            null,
        )
        pendingPermissionResult = null
        mainHandler.removeCallbacks(audioRouteTimeout)
        runCatching { activity.unregisterReceiver(bluetoothReceiver) }
        headset?.let { adapter?.closeProfileProxy(BluetoothProfile.HEADSET, it) }
        headset = null
        eventSink = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}
