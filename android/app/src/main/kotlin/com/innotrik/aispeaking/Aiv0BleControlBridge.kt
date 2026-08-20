package com.innotrik.aispeaking

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets
import java.util.Locale

@SuppressLint("MissingPermission")
class Aiv0BleControlBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val CONTROL_CHANNEL = "ailingo_aiv0_ble_control"
        private const val EVENT_CHANNEL = "ailingo_aiv0_ble_control/events"
        private const val PERMISSION_REQUEST_CODE = 7395
        private const val MAX_RECONNECT_ATTEMPTS = 5
        private const val DUPLICATE_WINDOW_MS = 750L
        private const val TAG = "Aiv0BleControl"
    }

    private val methodChannel = MethodChannel(messenger, CONTROL_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val bluetoothManager =
        activity.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? get() = bluetoothManager.adapter
    private val scanDevices = linkedMapOf<String, ScannedDevice>()

    private var eventSink: EventChannel.EventSink? = null
    private var phase = "idle"
    private var message: String? = null
    private var deviceId: String? = null
    private var deviceName: String? = null
    private var writeMode: String? = null
    private var batteryPercent: Int? = null
    private var firmwareRevision: String? = null
    private var lastRawHex: String? = null
    private var packetCount = 0L
    private var invalidPacketCount = 0L
    private var duplicatePacketCount = 0L
    private var reconnectCount = 0L
    private var lastPacketAt = 0L

    private var permissionResult: MethodChannel.Result? = null
    private var scanResult: MethodChannel.Result? = null
    private var connectResult: MethodChannel.Result? = null
    private var pendingWriteResult: MethodChannel.Result? = null
    private var scanCallback: ScanCallback? = null
    private var bluetoothGatt: BluetoothGatt? = null
    private var buttonCharacteristic: BluetoothGattCharacteristic? = null
    private var stateCharacteristic: BluetoothGattCharacteristic? = null
    private var batteryCharacteristic: BluetoothGattCharacteristic? = null
    private var firmwareCharacteristic: BluetoothGattCharacteristic? = null
    private var shouldReconnect = false
    private var reconnectAttempts = 0
    private var disposed = false
    private val connectionTimeout = Runnable {
        if (phase == "connecting" || phase == "reconnecting") {
            failConnection("Kết nối/đọc GATT của H20 quá thời gian 15 giây.")
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(result)
            "requestPermissions" -> requestPermissions(result)
            "scan" -> scan(call, result)
            "connect" -> connect(call, result)
            "disconnect" -> disconnect(result)
            "sendAppState" -> sendAppState(call, result)
            "status" -> result.success(snapshot())
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        events?.success(snapshot())
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun initialize(result: MethodChannel.Result) {
        phase = when {
            !activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE) ->
                "disabled"
            adapter == null -> "disabled"
            else -> if (phase == "disabled") "idle" else phase
        }
        message = when {
            phase == "disabled" -> "Điện thoại không hỗ trợ Bluetooth Low Energy."
            adapter?.isEnabled != true -> "Bluetooth đang tắt."
            else -> message
        }
        result.success(snapshot())
        emitStatus()
    }

    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun hasPermissions(): Boolean = requiredPermissions().all {
        activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (hasPermissions()) {
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("PERMISSION_IN_PROGRESS", "Đang chờ cấp quyền Bluetooth.", null)
            return
        }
        permissionResult = result
        message = "Cần quyền Thiết bị ở gần/Bluetooth để tìm H20."
        emitStatus()
        activity.requestPermissions(requiredPermissions(), PERMISSION_REQUEST_CODE)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        permissionResult?.success(granted)
        permissionResult = null
        phase = if (granted) "idle" else "error"
        message = if (granted) null else "Quyền Bluetooth đã bị từ chối."
        emitStatus()
        return true
    }

    private fun ensureBluetoothReady(result: MethodChannel.Result): Boolean {
        if (adapter == null || !activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            result.error("BLE_UNSUPPORTED", "Điện thoại không hỗ trợ BLE.", null)
            return false
        }
        if (adapter?.isEnabled != true) {
            result.error("BLUETOOTH_DISABLED", "Bluetooth đang tắt.", null)
            return false
        }
        if (!hasPermissions()) {
            result.error("PERMISSION_REQUIRED", "Cần cấp quyền Bluetooth trước.", null)
            return false
        }
        return true
    }

    private fun scan(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureBluetoothReady(result)) return
        if (scanResult != null) {
            result.error("SCAN_IN_PROGRESS", "Đang quét thiết bị Bluetooth.", null)
            return
        }
        stopScan(complete = true)
        scanDevices.clear()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                addScanResult(scanResult)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach(::addScanResult)
            }

            override fun onScanFailed(errorCode: Int) {
                val pending = this@Aiv0BleControlBridge.scanResult
                this@Aiv0BleControlBridge.scanResult = null
                scanCallback = null
                phase = "error"
                message = "Không quét được Bluetooth (mã $errorCode)."
                emitStatus()
                pending?.error("BLE_SCAN_FAILED", message, errorCode)
            }
        }
        scanCallback = callback
        scanResult = result
        phase = "scanning"
        message = null
        emitStatus()
        try {
            adapter!!.bluetoothLeScanner.startScan(callback)
        } catch (error: Throwable) {
            scanResult = null
            scanCallback = null
            phase = "error"
            message = "Không thể bắt đầu quét: ${error.message}"
            emitStatus()
            result.error("BLE_SCAN_FAILED", message, null)
            return
        }
        val timeout = (call.argument<Number>("timeoutMs")?.toLong() ?: 8_000L)
            .coerceIn(2_000L, 15_000L)
        mainHandler.postDelayed({ stopScan(complete = true) }, timeout)
    }

    private fun addScanResult(result: ScanResult) {
        val device = result.device ?: return
        val id = device.address ?: return
        val advertisedName = result.scanRecord?.deviceName
        val name = advertisedName ?: runCatching { device.name }.getOrNull().orEmpty()
        val advertisesControlService = result.scanRecord?.serviceUuids?.any {
            it.uuid == Aiv0BleProtocol.controlServiceUuid
        } == true
        val normalizedName = name.lowercase(Locale.ROOT)
        val likely = advertisesControlService ||
            normalizedName.contains("h20") ||
            normalizedName.contains("aiv0") ||
            normalizedName.contains("innotrik")
        val previous = scanDevices[id]
        if (previous == null || result.rssi > previous.rssi) {
            scanDevices[id] = ScannedDevice(id, name.ifBlank { "H20" }, result.rssi, likely)
        }
    }

    private fun stopScan(complete: Boolean) {
        scanCallback?.let { callback ->
            runCatching { adapter?.bluetoothLeScanner?.stopScan(callback) }
        }
        scanCallback = null
        val pending = scanResult
        scanResult = null
        if (complete && pending != null) {
            val devices = scanDevices.values.sortedWith(
                compareByDescending<ScannedDevice> { it.likely }
                    .thenByDescending { it.rssi },
            )
            phase = if (stateCharacteristic != null) "connected" else "idle"
            message = if (devices.isEmpty()) "Không tìm thấy H20/AIV0." else null
            emitStatus()
            pending.success(devices.map { it.toMap() })
        }
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureBluetoothReady(result)) return
        val requestedId = call.argument<String>("deviceId")?.trim().orEmpty()
        if (requestedId.isEmpty()) {
            result.error("DEVICE_REQUIRED", "Thiếu địa chỉ thiết bị BLE.", null)
            return
        }
        if (connectResult != null) {
            result.error("CONNECT_IN_PROGRESS", "Đang kết nối BLE.", null)
            return
        }
        stopScan(complete = true)
        shouldReconnect = false
        closeGatt()
        val device = runCatching { adapter!!.getRemoteDevice(requestedId) }.getOrNull()
        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "Không tìm thấy thiết bị $requestedId.", null)
            return
        }
        deviceId = requestedId
        deviceName = runCatching { device.name }.getOrNull()
            ?: scanDevices[requestedId]?.name
            ?: "H20"
        shouldReconnect = true
        reconnectAttempts = 0
        connectResult = result
        phase = "connecting"
        message = "Đang xác nhận BLE Control 9E3B0001…"
        emitStatus()
        openGatt(device)
    }

    private fun openGatt(device: BluetoothDevice) {
        mainHandler.removeCallbacks(connectionTimeout)
        val opened = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(activity, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(activity, false, gattCallback)
            }
        }.getOrElse { error ->
            failConnection("Không thể mở GATT H20: ${error.message}")
            return
        }
        bluetoothGatt = opened
        mainHandler.postDelayed(connectionTimeout, 15_000L)
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            mainHandler.post {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        bluetoothGatt = gatt
                        reconnectAttempts = 0
                        phase = "connecting"
                        message = "Đang đọc dịch vụ BLE Control…"
                        emitStatus()
                        if (!gatt.discoverServices()) {
                            failConnection("Không thể bắt đầu đọc GATT services.")
                        }
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> handleDisconnected(gatt, status)
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            mainHandler.post {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    failConnection("Không đọc được GATT services (mã $status).")
                    return@post
                }
                val service = gatt.getService(Aiv0BleProtocol.controlServiceUuid)
                val button = service?.getCharacteristic(Aiv0BleProtocol.buttonEventUuid)
                val state = service?.getCharacteristic(Aiv0BleProtocol.appStateUuid)
                if (service == null || button == null || state == null) {
                    failConnection(
                        "Thiết bị không có đủ 9E3B0001/0002/0003. V1 không dùng FF12/FF13/FF14.",
                    )
                    return@post
                }
                val supportsIndicate =
                    button.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0
                if (!supportsIndicate) {
                    failConnection("9E3B0002 chưa hỗ trợ Indicate.")
                    return@post
                }
                val supportsWrite =
                    state.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0
                val supportsWriteWithoutResponse =
                    state.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
                if (!supportsWrite && !supportsWriteWithoutResponse) {
                    failConnection("9E3B0003 không có thuộc tính ghi.")
                    return@post
                }
                writeMode = if (supportsWrite) "withResponse" else "withoutResponse"
                Log.i(
                    TAG,
                    "GATT verified: service=9E3B0001 button=indicate state=$writeMode",
                )
                buttonCharacteristic = button
                stateCharacteristic = state
                batteryCharacteristic = gatt
                    .getService(Aiv0BleProtocol.batteryServiceUuid)
                    ?.getCharacteristic(Aiv0BleProtocol.batteryLevelUuid)
                firmwareCharacteristic = gatt
                    .getService(Aiv0BleProtocol.deviceInformationServiceUuid)
                    ?.getCharacteristic(Aiv0BleProtocol.firmwareRevisionUuid)

                if (!gatt.setCharacteristicNotification(button, true)) {
                    failConnection("Không thể đăng ký Indicate 9E3B0002.")
                    return@post
                }
                val descriptor = button.getDescriptor(Aiv0BleProtocol.clientCharacteristicConfigUuid)
                if (descriptor == null) {
                    failConnection("9E3B0002 thiếu CCCD 2902.")
                    return@post
                }
                val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gatt.writeDescriptor(
                        descriptor,
                        BluetoothGattDescriptor.ENABLE_INDICATION_VALUE,
                    ) == android.bluetooth.BluetoothStatusCodes.SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    descriptor.value = BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                    @Suppress("DEPRECATION")
                    gatt.writeDescriptor(descriptor)
                }
                if (!started) failConnection("Không thể bật Indicate 9E3B0002.")
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            mainHandler.post {
                if (descriptor.uuid != Aiv0BleProtocol.clientCharacteristicConfigUuid) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    failConnection("Không bật được Indicate 9E3B0002 (mã $status).")
                    return@post
                }
                phase = "connected"
                mainHandler.removeCallbacks(connectionTimeout)
                message = if (writeMode == "withoutResponse") {
                    "Đã kết nối. ODM cần bổ sung Write with response cho 9E3B0003."
                } else {
                    "Đã kết nối BLE Control AIV0."
                }
                connectResult?.success(snapshot())
                connectResult = null
                emitStatus()
                readOptionalCharacteristics(gatt)
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            @Suppress("DEPRECATION")
            handleCharacteristicChanged(characteristic.uuid, characteristic.value ?: byteArrayOf())
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            handleCharacteristicChanged(characteristic.uuid, value)
        }

        @Deprecated("Deprecated in Java")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            @Suppress("DEPRECATION")
            handleCharacteristicRead(gatt, characteristic, characteristic.value ?: byteArrayOf(), status)
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
            status: Int,
        ) {
            handleCharacteristicRead(gatt, characteristic, value, status)
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (characteristic.uuid != Aiv0BleProtocol.appStateUuid) return
            mainHandler.post {
                val pending = pendingWriteResult
                pendingWriteResult = null
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    pending?.success(null)
                } else {
                    pending?.error("BLE_WRITE_FAILED", "Ghi APP State thất bại (mã $status).", null)
                }
            }
        }
    }

    private fun handleCharacteristicChanged(uuid: java.util.UUID, value: ByteArray) {
        if (uuid != Aiv0BleProtocol.buttonEventUuid) return
        mainHandler.post {
            packetCount += 1
            val hex = value.toHex()
            val now = android.os.SystemClock.elapsedRealtime()
            val receivedAtEpochMs = System.currentTimeMillis()
            val duplicate = hex == lastRawHex && now - lastPacketAt <= DUPLICATE_WINDOW_MS
            if (duplicate) duplicatePacketCount += 1
            if (value.size != 12) invalidPacketCount += 1
            lastRawHex = hex
            lastPacketAt = now
            Log.i(
                TAG,
                "Button Event device=$deviceId len=${value.size} duplicate=$duplicate raw=$hex",
            )
            emitStatus()
            eventSink?.success(
                mapOf(
                    "type" to "button",
                    "deviceId" to deviceId,
                    "bytes" to value.map { it.toInt() and 0xFF },
                    "duplicate" to duplicate,
                    "receivedAtEpochMs" to receivedAtEpochMs,
                ),
            )
        }
    }

    private fun readOptionalCharacteristics(gatt: BluetoothGatt) {
        val battery = batteryCharacteristic
        if (battery != null && gatt.readCharacteristic(battery)) return
        val firmware = firmwareCharacteristic
        if (firmware != null) gatt.readCharacteristic(firmware)
    }

    private fun handleCharacteristicRead(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
        status: Int,
    ) {
        mainHandler.post {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                when (characteristic.uuid) {
                    Aiv0BleProtocol.batteryLevelUuid -> {
                        batteryPercent = value.firstOrNull()?.toInt()?.and(0xFF)?.coerceIn(0, 100)
                    }
                    Aiv0BleProtocol.firmwareRevisionUuid -> {
                        firmwareRevision = String(value, StandardCharsets.UTF_8).trim().ifBlank { null }
                    }
                }
                emitStatus()
            }
            if (characteristic.uuid == Aiv0BleProtocol.batteryLevelUuid) {
                firmwareCharacteristic?.let { gatt.readCharacteristic(it) }
            }
        }
    }

    private fun sendAppState(call: MethodCall, result: MethodChannel.Result) {
        val gatt = bluetoothGatt
        val characteristic = stateCharacteristic
        if (phase != "connected" || gatt == null || characteristic == null) {
            result.error("NOT_CONNECTED", "BLE Control AIV0 chưa kết nối.", null)
            return
        }
        val values = call.argument<List<Number>>("bytes")
        val bytes = values?.map { (it.toInt() and 0xFF).toByte() }?.toByteArray()
        if (bytes == null || bytes.isEmpty()) {
            result.error("INVALID_PACKET", "APP State rỗng.", null)
            return
        }
        val withResponse =
            characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0
        characteristic.writeType = if (withResponse) {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        }
        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(characteristic, bytes, characteristic.writeType) ==
                android.bluetooth.BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            characteristic.value = bytes
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(characteristic)
        }
        if (!started) {
            result.error("BLE_WRITE_FAILED", "Không thể bắt đầu ghi APP State.", null)
            return
        }
        Log.i(TAG, "APP State write mode=$writeMode raw=${bytes.toHex()}")
        if (withResponse) {
            pendingWriteResult?.error("BLE_WRITE_REPLACED", "APP State mới đã thay thế gói cũ.", null)
            pendingWriteResult = result
        } else {
            result.success(null)
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        shouldReconnect = false
        reconnectAttempts = 0
        connectResult?.error("CONNECT_CANCELLED", "Đã hủy kết nối.", null)
        connectResult = null
        closeGatt()
        phase = "idle"
        message = "Đã ngắt BLE Control AIV0."
        emitStatus()
        result.success(null)
    }

    private fun handleDisconnected(gatt: BluetoothGatt, status: Int) {
        mainHandler.removeCallbacks(connectionTimeout)
        if (bluetoothGatt === gatt) bluetoothGatt = null
        runCatching { gatt.close() }
        clearCharacteristics()
        if (!shouldReconnect || disposed) {
            phase = "idle"
            message = "BLE Control đã ngắt kết nối."
            emitStatus()
            return
        }
        if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
            phase = "error"
            message = "Không thể tự kết nối lại H20 sau $MAX_RECONNECT_ATTEMPTS lần."
            connectResult?.error("RECONNECT_FAILED", message, status)
            connectResult = null
            emitStatus()
            return
        }
        reconnectAttempts += 1
        reconnectCount += 1
        phase = "reconnecting"
        message = "Đang kết nối lại H20 ($reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)…"
        Log.w(TAG, "Reconnect $reconnectAttempts/$MAX_RECONNECT_ATTEMPTS status=$status")
        emitStatus()
        val delay = (1_000L shl (reconnectAttempts - 1)).coerceAtMost(8_000L)
        mainHandler.postDelayed({
            val id = deviceId ?: return@postDelayed
            val device = runCatching { adapter?.getRemoteDevice(id) }.getOrNull()
            if (device == null) {
                phase = "error"
                message = "Không còn tìm thấy H20 đã ghép nối."
                emitStatus()
            } else {
                openGatt(device)
            }
        }, delay)
    }

    private fun failConnection(reason: String) {
        mainHandler.removeCallbacks(connectionTimeout)
        shouldReconnect = false
        phase = "error"
        message = reason
        connectResult?.error("AIV0_PROTOCOL_MISMATCH", reason, snapshot())
        connectResult = null
        emitStatus()
        closeGatt()
    }

    private fun clearCharacteristics() {
        buttonCharacteristic = null
        stateCharacteristic = null
        batteryCharacteristic = null
        firmwareCharacteristic = null
        writeMode = null
    }

    private fun closeGatt() {
        val gatt = bluetoothGatt
        bluetoothGatt = null
        clearCharacteristics()
        if (gatt != null) {
            runCatching { gatt.disconnect() }
            runCatching { gatt.close() }
        }
    }

    private fun snapshot(): Map<String, Any?> = mapOf(
        "type" to "status",
        "phase" to phase,
        "message" to message,
        "deviceId" to deviceId,
        "deviceName" to deviceName,
        "writeMode" to writeMode,
        "batteryPercent" to batteryPercent,
        "firmwareRevision" to firmwareRevision,
        "lastRawHex" to lastRawHex,
        "packetCount" to packetCount,
        "invalidPacketCount" to invalidPacketCount,
        "duplicatePacketCount" to duplicatePacketCount,
        "reconnectCount" to reconnectCount,
    )

    private fun emitStatus() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post(::emitStatus)
            return
        }
        eventSink?.success(snapshot())
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        shouldReconnect = false
        mainHandler.removeCallbacksAndMessages(null)
        stopScan(complete = false)
        connectResult?.error("DISPOSED", "BLE Control đã đóng.", null)
        connectResult = null
        pendingWriteResult?.error("DISPOSED", "BLE Control đã đóng.", null)
        pendingWriteResult = null
        permissionResult?.error("DISPOSED", "BLE Control đã đóng.", null)
        permissionResult = null
        closeGatt()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    private data class ScannedDevice(
        val id: String,
        val name: String,
        val rssi: Int,
        val likely: Boolean,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "id" to id,
            "name" to name,
            "rssi" to rssi,
            "isLikelyAiv0" to likely,
        )
    }

    private fun ByteArray.toHex(): String = joinToString(" ") {
        (it.toInt() and 0xFF).toString(16).padStart(2, '0').uppercase(Locale.ROOT)
    }
}
