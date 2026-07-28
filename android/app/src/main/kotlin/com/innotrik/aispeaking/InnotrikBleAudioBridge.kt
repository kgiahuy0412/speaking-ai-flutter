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
import android.os.ParcelUuid
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryCodec
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.Locale
import java.util.UUID

@SuppressLint("MissingPermission")
class InnotrikBleAudioBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val CONTROL_CHANNEL = "ailingo_innotrik_ble"
        private const val EVENT_CHANNEL = "ailingo_innotrik_ble/events"
        private const val PCM_CHANNEL = "ailingo_innotrik_ble/pcm"
        private const val PERMISSION_REQUEST_CODE = 7392
        private const val TARGET_MTU = 247
        private const val MAX_RECONNECT_ATTEMPTS = 3
        private val CLIENT_CHARACTERISTIC_CONFIG =
            UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private val methodChannel = MethodChannel(messenger, CONTROL_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val pcmChannel = BasicMessageChannel(messenger, PCM_CHANNEL, BinaryCodec.INSTANCE)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val bluetoothManager =
        activity.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? get() = bluetoothManager.adapter
    private val serviceUuid = UUID.fromString(InnotrikProtocol.SERVICE_UUID)
    private val writeUuid = UUID.fromString(InnotrikProtocol.WRITE_CHARACTERISTIC_UUID)
    private val notifyUuid = UUID.fromString(InnotrikProtocol.NOTIFY_CHARACTERISTIC_UUID)
    private val framer = InnotrikPacketFramer()
    private val scanDevices = linkedMapOf<String, ScannedDevice>()

    private var eventSink: EventChannel.EventSink? = null
    private var phase = "idle"
    private var statusMessage: String? = null
    private var deviceId: String? = null
    private var deviceName: String? = null
    private var packetCount = 0L
    private var invalidPacketCount = 0L
    private var decodedPcmBytes = 0L
    private var permissionResult: MethodChannel.Result? = null
    private var scanResult: MethodChannel.Result? = null
    private var connectResult: MethodChannel.Result? = null
    private var scanCallback: ScanCallback? = null
    private var bluetoothGatt: BluetoothGatt? = null
    private var writeCharacteristic: BluetoothGattCharacteristic? = null
    private var notifyCharacteristic: BluetoothGattCharacteristic? = null
    private var pendingWrite: PendingWrite? = null
    private var decoder: OpusPcmDecoder? = null
    private var captureActive = false
    private var shouldReconnect = false
    private var reconnectAttempts = 0
    private var discoveryStarted = false
    private var disposed = false

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
            "startCapture" -> startCapture(result)
            "stopCapture" -> stopCapture(result)
            "cancelCapture" -> cancelCapture(result)
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
                "unsupported"
            adapter == null -> "unsupported"
            else -> if (phase == "unsupported") "idle" else phase
        }
        statusMessage = when {
            phase == "unsupported" -> "Điện thoại không hỗ trợ Bluetooth Low Energy."
            adapter?.isEnabled != true -> "Bluetooth đang tắt. Hãy bật Bluetooth rồi thử lại."
            else -> statusMessage
        }
        result.success(snapshot())
        emitStatus()
    }

    private fun requiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
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
        phase = "permissionRequired"
        statusMessage = "Cần quyền Thiết bị ở gần/Bluetooth để tìm INNOTRIK."
        emitStatus()
        activity.requestPermissions(requiredPermissions(), PERMISSION_REQUEST_CODE)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        permissionResult?.success(granted)
        permissionResult = null
        phase = if (granted) "idle" else "permissionRequired"
        statusMessage = if (granted) null else "Quyền Bluetooth đã bị từ chối."
        emitStatus()
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
                val pending = this@InnotrikBleAudioBridge.scanResult
                this@InnotrikBleAudioBridge.scanResult = null
                scanCallback = null
                phase = "error"
                statusMessage = "Không quét được Bluetooth (mã $errorCode)."
                emitStatus()
                pending?.error("BLE_SCAN_FAILED", statusMessage, errorCode)
            }
        }
        scanCallback = callback
        scanResult = result
        phase = "scanning"
        statusMessage = null
        emitStatus()
        try {
            adapter!!.bluetoothLeScanner.startScan(callback)
        } catch (error: Throwable) {
            scanResult = null
            scanCallback = null
            fail(result, "BLE_SCAN_FAILED", "Không thể bắt đầu quét: ${error.message}")
            return
        }
        val timeout = (call.argument<Number>("timeoutMs")?.toLong() ?: 5_000L)
            .coerceIn(2_000L, 12_000L)
        mainHandler.postDelayed({ stopScan(complete = true) }, timeout)
    }

    private fun addScanResult(result: ScanResult) {
        val device = result.device ?: return
        val id = device.address ?: return
        val advertisedName = result.scanRecord?.deviceName
        val name = advertisedName ?: runCatching { device.name }.getOrNull().orEmpty()
        val advertisesService = result.scanRecord?.serviceUuids?.any {
            it.uuid == serviceUuid
        } == true
        val normalizedName = name.lowercase(Locale.ROOT)
        val likely = advertisesService ||
            normalizedName.contains("innotrik") ||
            normalizedName.contains("ailingo") ||
            normalizedName.contains("yinluo") ||
            name.contains("音洛")
        val previous = scanDevices[id]
        if (previous == null || result.rssi > previous.rssi) {
            scanDevices[id] = ScannedDevice(id, name, result.rssi, likely)
        }
    }

    private fun stopScan(complete: Boolean) {
        val callback = scanCallback
        if (callback != null) {
            runCatching { adapter?.bluetoothLeScanner?.stopScan(callback) }
        }
        scanCallback = null
        val pending = scanResult
        scanResult = null
        if (complete && pending != null) {
            val devices = scanDevices.values.sortedWith(
                compareByDescending<ScannedDevice> { it.isLikelyInnotrik }
                    .thenByDescending { it.rssi },
            )
            phase = if (bluetoothGatt != null && writeCharacteristic != null) "ready" else "idle"
            statusMessage = if (devices.isEmpty()) {
                "Không tìm thấy thiết bị. Hãy bật INNOTRIK và đặt gần điện thoại."
            } else null
            emitStatus()
            pending.success(devices.map { it.toMap() })
        }
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureBluetoothReady(result)) return
        val id = call.argument<String>("deviceId")?.trim().orEmpty()
        if (id.isEmpty()) {
            result.error("DEVICE_REQUIRED", "Thiếu địa chỉ thiết bị Bluetooth.", null)
            return
        }
        if (connectResult != null) {
            result.error("CONNECT_IN_PROGRESS", "Đang kết nối thiết bị.", null)
            return
        }
        stopScan(complete = true)
        val device = try {
            adapter!!.getRemoteDevice(id)
        } catch (error: Throwable) {
            result.error("INVALID_DEVICE", "Địa chỉ Bluetooth không hợp lệ.", error.message)
            return
        }
        shouldReconnect = true
        reconnectAttempts = 0
        connectResult = result
        connectInternal(device)
        val timeout = (call.argument<Number>("timeoutMs")?.toLong() ?: 15_000L)
            .coerceIn(6_000L, 30_000L)
        mainHandler.postDelayed({
            val pending = connectResult ?: return@postDelayed
            connectResult = null
            pending.error("CONNECT_TIMEOUT", "Kết nối INNOTRIK quá thời gian.", null)
            phase = "error"
            statusMessage = "Kết nối quá thời gian. Hãy tắt/bật thiết bị rồi thử lại."
            emitStatus()
            closeGatt()
        }, timeout)
    }

    private fun connectInternal(device: BluetoothDevice) {
        closeGatt()
        deviceId = device.address
        deviceName = runCatching { device.name }.getOrNull()?.takeIf { it.isNotBlank() }
            ?: scanDevices[device.address]?.name?.takeIf { it.isNotBlank() }
            ?: "INNOTRIK"
        phase = "connecting"
        statusMessage = if (reconnectAttempts > 0) {
            "Đang tự kết nối lại lần $reconnectAttempts/$MAX_RECONNECT_ATTEMPTS…"
        } else null
        discoveryStarted = false
        emitStatus()
        bluetoothGatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(activity, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } else {
            @Suppress("DEPRECATION")
            device.connectGatt(activity, false, gattCallback)
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            mainHandler.post {
                if (gatt !== bluetoothGatt) return@post
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        reconnectAttempts = 0
                        phase = "discovering"
                        statusMessage = null
                        discoveryStarted = false
                        emitStatus()
                        runCatching {
                            gatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
                            if (!gatt.requestMtu(TARGET_MTU)) beginServiceDiscovery(gatt)
                        }.onFailure { beginServiceDiscovery(gatt) }
                        mainHandler.postDelayed({ beginServiceDiscovery(gatt) }, 1_200L)
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> handleDisconnected(status)
                }
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            mainHandler.post { beginServiceDiscovery(gatt) }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            mainHandler.post {
                if (gatt !== bluetoothGatt) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    failConnection("Không đọc được dịch vụ BLE (GATT $status).")
                    return@post
                }
                val service = gatt.getService(serviceUuid)
                val write = service?.getCharacteristic(writeUuid)
                val notify = service?.getCharacteristic(notifyUuid)
                if (service == null || write == null || notify == null) {
                    failConnection(
                        "Thiết bị không có dịch vụ FF12/FF13/FF14 của INNOTRIK.",
                    )
                    return@post
                }
                writeCharacteristic = write
                notifyCharacteristic = notify
                if (!gatt.setCharacteristicNotification(notify, true)) {
                    failConnection("Không bật được kênh nhận audio FF14.")
                    return@post
                }
                val descriptor = notify.getDescriptor(CLIENT_CHARACTERISTIC_CONFIG)
                if (descriptor == null) {
                    markReady()
                    return@post
                }
                val value = if (
                    notify.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0
                ) BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                else BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                val accepted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gatt.writeDescriptor(descriptor, value) == BluetoothGatt.GATT_SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    descriptor.value = value
                    @Suppress("DEPRECATION")
                    gatt.writeDescriptor(descriptor)
                }
                if (!accepted) failConnection("Không đăng ký được thông báo audio FF14.")
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            mainHandler.post {
                if (gatt !== bluetoothGatt) return@post
                if (status == BluetoothGatt.GATT_SUCCESS) markReady()
                else failConnection("Không bật được thông báo audio (GATT $status).")
            }
        }

        @Deprecated("Deprecated in Android 13")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            @Suppress("DEPRECATION")
            handleNotification(characteristic.uuid, characteristic.value ?: ByteArray(0))
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            handleNotification(characteristic.uuid, value)
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            mainHandler.post { handleCharacteristicWrite(status) }
        }
    }

    private fun beginServiceDiscovery(gatt: BluetoothGatt) {
        if (gatt !== bluetoothGatt || discoveryStarted) return
        discoveryStarted = true
        if (!gatt.discoverServices()) {
            failConnection("Không thể bắt đầu đọc dịch vụ BLE.")
        }
    }

    private fun markReady() {
        phase = "ready"
        statusMessage = null
        emitStatus()
        connectResult?.success(null)
        connectResult = null
    }

    private fun failConnection(message: String) {
        phase = "error"
        statusMessage = message
        emitStatus()
        connectResult?.error("INNOTRIK_GATT_ERROR", message, null)
        connectResult = null
        closeGatt()
    }

    private fun handleDisconnected(gattStatus: Int) {
        val wasCapturing = captureActive
        captureActive = false
        decoder?.stop()
        decoder = null
        writeCharacteristic = null
        notifyCharacteristic = null
        pendingWrite?.result?.error(
            "BLE_DISCONNECTED",
            "INNOTRIK đã ngắt kết nối.",
            gattStatus,
        )
        pendingWrite = null
        bluetoothGatt?.close()
        bluetoothGatt = null
        if (shouldReconnect && reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
            reconnectAttempts += 1
            phase = "connecting"
            statusMessage = "Mất kết nối; sẽ tự nối lại…"
            emitStatus()
            val id = deviceId
            mainHandler.postDelayed({
                if (!shouldReconnect || id == null) return@postDelayed
                runCatching { adapter?.getRemoteDevice(id) }
                    .getOrNull()
                    ?.let(::connectInternal)
            }, 1_000L shl (reconnectAttempts - 1))
        } else {
            phase = "error"
            statusMessage = if (wasCapturing) {
                "Mất kết nối INNOTRIK trong lúc thu âm."
            } else {
                "INNOTRIK đã ngắt kết nối (GATT $gattStatus)."
            }
            emitStatus()
            connectResult?.error("BLE_DISCONNECTED", statusMessage, gattStatus)
            connectResult = null
        }
    }

    private fun handleNotification(uuid: UUID, bytes: ByteArray) {
        if (uuid != notifyUuid || bytes.isEmpty()) return
        val packets = framer.append(bytes)
        if (packets.isEmpty() && bytes.size >= InnotrikProtocol.PACKET_LENGTH) {
            invalidPacketCount += 1
        }
        for (packet in packets) {
            val opus = runCatching { InnotrikProtocol.extractOpusPayload(packet) }
                .getOrElse {
                    invalidPacketCount += 1
                    continue
                }
            packetCount += 1
            if (captureActive) decoder?.offer(opus)
        }
        if (packets.isNotEmpty() && (packetCount <= 2 || packetCount % 25L == 0L)) {
            emitStatus()
        }
    }

    private fun startCapture(result: MethodChannel.Result) {
        if (phase != "ready" || bluetoothGatt == null || writeCharacteristic == null) {
            result.error(
                "DEVICE_NOT_READY",
                "Hãy kết nối INNOTRIK và chờ trạng thái Sẵn sàng.",
                null,
            )
            return
        }
        if (captureActive) {
            result.error("CAPTURE_ACTIVE", "Mic INNOTRIK đang thu âm.", null)
            return
        }
        packetCount = 0
        invalidPacketCount = 0
        decodedPcmBytes = 0
        framer.reset()
        val nextDecoder = OpusPcmDecoder(
            onPcm = { pcm ->
                mainHandler.post {
                    if (!captureActive || pcm.isEmpty()) return@post
                    decodedPcmBytes += pcm.size
                    pcmChannel.send(ByteBuffer.wrap(pcm))
                    if (decodedPcmBytes <= pcm.size || decodedPcmBytes % 48_000L < pcm.size) {
                        emitStatus()
                    }
                }
            },
            onFailure = { message ->
                mainHandler.post {
                    captureActive = false
                    phase = "error"
                    statusMessage = message
                    emitStatus()
                }
            },
        )
        try {
            nextDecoder.start()
        } catch (error: Throwable) {
            result.error(
                "OPUS_DECODER_UNAVAILABLE",
                "Điện thoại không khởi tạo được bộ giải mã Opus: ${error.message}",
                null,
            )
            return
        }
        decoder = nextDecoder
        captureActive = true
        writeCommand(
            InnotrikProtocol.START_MICROPHONE_COMMAND,
            PendingWrite.Action.START,
            result,
        )
    }

    private fun stopCapture(result: MethodChannel.Result) {
        if (!captureActive) {
            result.success(null)
            return
        }
        writeCommand(
            InnotrikProtocol.STOP_MICROPHONE_COMMAND,
            PendingWrite.Action.STOP,
            result,
        )
    }

    private fun cancelCapture(result: MethodChannel.Result) {
        if (captureActive && bluetoothGatt != null && writeCharacteristic != null) {
            writeCommand(
                InnotrikProtocol.STOP_MICROPHONE_COMMAND,
                PendingWrite.Action.CANCEL,
                null,
            )
        }
        captureActive = false
        decoder?.stop()
        decoder = null
        phase = if (bluetoothGatt != null && writeCharacteristic != null) "ready" else "idle"
        statusMessage = null
        emitStatus()
        result.success(null)
    }

    private fun writeCommand(
        command: ByteArray,
        action: PendingWrite.Action,
        result: MethodChannel.Result?,
    ) {
        val gatt = bluetoothGatt
        val characteristic = writeCharacteristic
        if (gatt == null || characteristic == null) {
            result?.error("DEVICE_NOT_READY", "Kênh lệnh FF13 chưa sẵn sàng.", null)
            return
        }
        if (pendingWrite != null) {
            result?.error("BLE_WRITE_BUSY", "Đang gửi một lệnh BLE khác.", null)
            return
        }
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        pendingWrite = PendingWrite(action, result)
        val accepted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(
                characteristic,
                command,
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
            ) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            characteristic.value = command
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(characteristic)
        }
        if (!accepted) {
            pendingWrite = null
            if (action == PendingWrite.Action.START) {
                captureActive = false
                decoder?.stop()
                decoder = null
            }
            result?.error("BLE_WRITE_FAILED", "Không gửi được lệnh mic qua FF13.", null)
        }
    }

    private fun handleCharacteristicWrite(status: Int) {
        val pending = pendingWrite ?: return
        pendingWrite = null
        if (status != BluetoothGatt.GATT_SUCCESS) {
            if (pending.action == PendingWrite.Action.START) {
                captureActive = false
                decoder?.stop()
                decoder = null
            }
            pending.result?.error(
                "BLE_WRITE_FAILED",
                "Thiết bị từ chối lệnh mic (GATT $status).",
                status,
            )
            return
        }
        when (pending.action) {
            PendingWrite.Action.START -> {
                phase = "recording"
                statusMessage = null
                emitStatus()
                pending.result?.success(null)
            }
            PendingWrite.Action.STOP -> mainHandler.postDelayed({
                captureActive = false
                decoder?.stop()
                decoder = null
                phase = "ready"
                statusMessage = null
                emitStatus()
                pending.result?.success(null)
            }, 180L)
            PendingWrite.Action.CANCEL -> Unit
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        shouldReconnect = false
        reconnectAttempts = 0
        stopScan(complete = true)
        captureActive = false
        decoder?.stop()
        decoder = null
        pendingWrite?.result?.error("BLE_DISCONNECTED", "Đã ngắt INNOTRIK.", null)
        pendingWrite = null
        closeGatt()
        deviceId = null
        deviceName = null
        phase = "idle"
        statusMessage = null
        emitStatus()
        result.success(null)
    }

    private fun ensureBluetoothReady(result: MethodChannel.Result): Boolean {
        if (!activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE) ||
            adapter == null
        ) {
            fail(result, "BLE_UNSUPPORTED", "Điện thoại không hỗ trợ Bluetooth Low Energy.")
            return false
        }
        if (adapter?.isEnabled != true) {
            fail(result, "BLUETOOTH_DISABLED", "Hãy bật Bluetooth trên điện thoại.")
            return false
        }
        if (!hasPermissions()) {
            fail(result, "BLUETOOTH_PERMISSION", "Chưa cấp quyền Thiết bị ở gần/Bluetooth.")
            return false
        }
        return true
    }

    private fun fail(result: MethodChannel.Result, code: String, message: String) {
        phase = "error"
        statusMessage = message
        emitStatus()
        result.error(code, message, null)
    }

    private fun closeGatt() {
        writeCharacteristic = null
        notifyCharacteristic = null
        discoveryStarted = false
        bluetoothGatt?.runCatching { disconnect() }
        bluetoothGatt?.runCatching { close() }
        bluetoothGatt = null
    }

    private fun snapshot(): Map<String, Any?> = mapOf(
        "type" to "status",
        "phase" to phase,
        "deviceId" to deviceId,
        "deviceName" to deviceName,
        "message" to statusMessage,
        "packetCount" to packetCount,
        "invalidPacketCount" to invalidPacketCount,
        "decodedPcmBytes" to decodedPcmBytes,
        "sampleRate" to OpusPcmDecoder.OUTPUT_SAMPLE_RATE,
    )

    private fun emitStatus() {
        if (disposed) return
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
        stopScan(complete = false)
        permissionResult?.success(false)
        permissionResult = null
        connectResult?.error("BRIDGE_DISPOSED", "Cầu nối BLE đã đóng.", null)
        connectResult = null
        captureActive = false
        decoder?.stop()
        decoder = null
        closeGatt()
        eventSink = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private data class ScannedDevice(
        val id: String,
        val name: String,
        val rssi: Int,
        val isLikelyInnotrik: Boolean,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "id" to id,
            "name" to name,
            "rssi" to rssi,
            "isLikelyInnotrik" to isLikelyInnotrik,
        )
    }

    private data class PendingWrite(
        val action: Action,
        val result: MethodChannel.Result?,
    ) {
        enum class Action { START, STOP, CANCEL }
    }
}
