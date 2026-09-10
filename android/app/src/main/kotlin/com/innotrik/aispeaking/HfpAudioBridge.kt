package com.innotrik.aispeaking

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
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
    private val host: HomiAndroidHost,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val CONTROL_CHANNEL = "ailingo_hfp_audio"
        private const val EVENT_CHANNEL = "ailingo_hfp_audio/events"
        private const val PERMISSION_REQUEST_CODE = 7393
        private const val AUDIO_ROUTE_SETTLE_MS = 300L
        private const val EXTERNAL_AUDIO_DRAIN_MS = 350L
        private const val READY_CUE_DURATION_MS = 170
        private const val READY_CUE_COMPLETION_MS = 230L
        private const val PROMPT_ROUTE_HANDOFF_TIMEOUT_MS = 2_500L
        private const val TAG = "HomiHfpAudio"

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
    private val appContext = host.applicationContext
    private val bluetoothManager =
        appContext.getSystemService(BluetoothManager::class.java)
    private val adapter: BluetoothAdapter? = bluetoothManager?.adapter
    private val audioManager =
        appContext.getSystemService(AudioManager::class.java)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val routeAudioFocusListener =
        AudioManager.OnAudioFocusChangeListener { change ->
            mainHandler.post { handleRouteAudioFocusChange(change) }
        }

    private var eventSink: EventChannel.EventSink? = null
    private var headset: BluetoothHeadset? = null
    private var selectedDevice: BluetoothDevice? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingAudioRouteResult: MethodChannel.Result? = null
    private var pendingRouteOpen: Runnable? = null
    private var pendingRouteReady: Runnable? = null
    private var readyCueArmed = false
    private var readyCueGenerator: ToneGenerator? = null
    private var readyCueCompletion: Runnable? = null
    private var adoptedPromptFocusRelease: (() -> Unit)? = null
    private var promptRouteHandoffTimeout: Runnable? = null
    private var activeMainTurnId: String? = null
    private var routeAudioFocusRequest: AudioFocusRequest? = null
    private var routeAudioFocusRequested = false
    private var mutedUncooperativeMedia = false
    private var phase = "idle"
    private var statusMessage: String? = null
    private var routeActive = false
    private var ownsCommunicationRoute = false
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
                    BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED ->
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
                autoSelectConnectedHeadsetIfNeeded()
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
                    appContext,
                    profileListener,
                    BluetoothProfile.HEADSET,
                )
            }
        }
        val filter =
            IntentFilter().apply {
                addAction(BluetoothHeadset.ACTION_AUDIO_STATE_CHANGED)
                addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
                addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(
                bluetoothReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("DEPRECATION")
            appContext.registerReceiver(bluetoothReceiver, filter)
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
            "openMediaAudioSettings" -> openMediaAudioSettings(result)
            "startAudioRoute" -> startAudioRoute(result)
            "stopAudioRoute" -> {
                // The ready cue is armed before the speech input releases its
                // previous lease. Preserve that one-shot notification across
                // the stale cleanup; an actual pending route stop still clears
                // it in stopAudioRouteInternal().
                val preserveArmedCue = readyCueArmed && pendingAudioRouteResult == null
                val preserveAdoptedPromptHandoff =
                    preserveArmedCue &&
                        adoptedPromptFocusRelease != null &&
                        promptRouteHandoffTimeout != null
                if (preserveAdoptedPromptHandoff) {
                    Log.d(TAG, "ignored stale route stop during prompt-to-microphone handoff")
                } else if (
                    activeMainTurnId != null &&
                        routeActive &&
                        pendingAudioRouteResult == null &&
                        !readyCueArmed
                ) {
                    retainAudioRouteForMainTurn()
                } else {
                    stopAudioRouteInternal(clearArmedCue = !preserveArmedCue)
                }
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
            autoSelectConnectedHeadsetIfNeeded()
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
        if (!host.requestPermissions(
                arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                PERMISSION_REQUEST_CODE,
            )
        ) {
            pendingPermissionResult = null
            result.error(
                "VISIBLE_ACTIVITY_REQUIRED",
                "Hãy mở HOMI để cấp quyền Bluetooth trước khi tiếp tục.",
                null,
            )
        }
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
                host.startVisibleActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
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

    private fun openMediaAudioSettings(result: MethodChannel.Result) {
        val activity = host.currentActivity
        if (activity == null) {
            result.error(
                "VISIBLE_ACTIVITY_REQUIRED",
                "Hãy mở HOMI để thay đổi Âm thanh đa phương tiện của H20.",
                null,
            )
            return
        }
        val selected = selectedDevice
        val detailIntents = selected?.let { device ->
            // AOSP-based devices normally expose the android.settings action,
            // while MIUI 14 exposes the same screen under com.android.settings.
            // Supplying both the address and parcelable device keeps this
            // compatible with the two fragment implementations.
            listOf(
                "com.android.settings.BLUETOOTH_DEVICE_DETAIL_SETTINGS",
                "android.settings.BLUETOOTH_DEVICE_DETAIL_SETTINGS",
            ).map { action ->
                Intent(action).apply {
                    putExtra("device_address", device.address)
                    putExtra(BluetoothDevice.EXTRA_DEVICE, device)
                }
            }
        }.orEmpty()
        val openedDetails = detailIntents.any { intent ->
            intent.resolveActivity(appContext.packageManager) != null &&
                host.startVisibleActivity(intent)
        }
        if (!openedDetails) {
            val openedBluetooth =
                host.startVisibleActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
            if (!openedBluetooth) {
                result.error(
                    "BLUETOOTH_SETTINGS_UNAVAILABLE",
                    "Android không mở được trang cài đặt Bluetooth.",
                    null,
                )
                return
            }
        }
        result.success(null)
    }

    private fun startAudioRoute(result: MethodChannel.Result) {
        if (!ensureBluetoothReady(result)) return
        if (routeActive && ownsCommunicationRoute) {
            cancelPromptRouteHandoffTimeout()
            phase = "recording"
            statusMessage = "Đang dùng mic HFP/SCO để nhận diện."
            emitStatus()
            pendingAudioRouteResult = result
            completeAudioRouteStart(result)
            return
        }
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

        pendingAudioRouteResult = result
        phase = "discovering"
        statusMessage = "Đang dành quyền âm thanh trước khi mở mic HFP/SCO…"
        emitStatus()
        if (!requestRouteAudioFocus()) {
            pendingAudioRouteResult = null
            fail(
                result,
                "HFP_AUDIO_FOCUS_DENIED",
                "Ứng dụng khác đang giữ quyền âm thanh; chưa thể mở mic H20.",
            )
            return
        }

        previousAudioMode = audioManager.mode
        lateinit var openRoute: Runnable
        openRoute = Runnable {
            if (pendingRouteOpen === openRoute) {
                pendingRouteOpen = null
            }
            if (pendingAudioRouteResult !== result || !routeAudioFocusRequested) {
                return@Runnable
            }
            openAudioRouteAfterFocus(device, result)
        }
        pendingRouteOpen = openRoute
        // Do not select SCO while another app is still draining its media
        // buffer. This bounded pause is generic Android behaviour and does not
        // depend on the foreground application's package name.
        mainHandler.postDelayed(openRoute, EXTERNAL_AUDIO_DRAIN_MS)
    }

    private fun openAudioRouteAfterFocus(
        device: BluetoothDevice,
        result: MethodChannel.Result,
    ) {
        suppressUncooperativeMediaAudioIfNeeded()
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
                pendingAudioRouteResult = null
                audioManager.mode = previousAudioMode
                abandonRouteAudioFocus()
                restoreUncooperativeMediaAudio()
                fail(
                    result,
                    "HFP_ROUTE_FAILED",
                    "Android chưa mở được đường mic HFP/SCO. Hãy ngắt và kết nối lại tai nghe.",
                )
                return
            }
            ownsCommunicationRoute = true
            routeActive = true
            phase = "recording"
            statusMessage = "Đang dùng mic HFP/SCO để nhận diện."
            emitStatus()
            Log.d(TAG, "recording route selected after exclusive focus")
            scheduleAudioRouteReady(result)
        } else {
            ownsCommunicationRoute = true
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
        mainHandler.removeCallbacks(audioRouteTimeout)
        routeActive = true
        phase = "recording"
        statusMessage = "Đang dùng mic HFP/SCO để nhận diện."
        emitStatus()
        scheduleAudioRouteReady(pending)
    }

    private fun scheduleAudioRouteReady(result: MethodChannel.Result) {
        pendingRouteReady?.let(mainHandler::removeCallbacks)
        lateinit var complete: Runnable
        complete = Runnable {
            if (pendingRouteReady === complete) {
                pendingRouteReady = null
            }
            if (pendingAudioRouteResult !== result) return@Runnable
            completeAudioRouteStart(result)
        }
        pendingRouteReady = complete
        mainHandler.postDelayed(complete, AUDIO_ROUTE_SETTLE_MS)
    }

    private fun completeAudioRouteStart(result: MethodChannel.Result) {
        if (pendingAudioRouteResult !== result) return
        val ownsTurnAudio =
            routeAudioFocusRequested ||
                adoptedPromptFocusRelease != null ||
                activeMainTurnId != null
        if (!routeActive || !ownsCommunicationRoute || !ownsTurnAudio) {
            pendingAudioRouteResult = null
            readyCueArmed = false
            result.error(
                "HFP_ROUTE_INTERRUPTED",
                "Đường mic H20 bị gián đoạn trước khi sẵn sàng.",
                null,
            )
            return
        }
        if (!readyCueArmed) {
            pendingAudioRouteResult = null
            result.success(null)
            return
        }

        readyCueArmed = false
        val generator = try {
            ToneGenerator(AudioManager.STREAM_VOICE_CALL, 100).also {
                readyCueGenerator = it
            }
        } catch (error: RuntimeException) {
            Log.w(TAG, "unable to create ready cue; continuing with microphone", error)
            pendingAudioRouteResult = null
            result.success(null)
            return
        }
        if (!generator.startTone(ToneGenerator.TONE_PROP_BEEP, READY_CUE_DURATION_MS)) {
            generator.release()
            readyCueGenerator = null
            Log.w(TAG, "unable to start ready cue; continuing with microphone")
            pendingAudioRouteResult = null
            result.success(null)
            return
        }
        Log.d(TAG, "ready cue started on active microphone HFP/SCO route")
        lateinit var completion: Runnable
        completion = Runnable {
            if (readyCueCompletion === completion) {
                readyCueCompletion = null
            }
            readyCueGenerator?.stopTone()
            readyCueGenerator?.release()
            readyCueGenerator = null
            if (pendingAudioRouteResult !== result) return@Runnable
            pendingAudioRouteResult = null
            Log.d(TAG, "ready cue finished; microphone route remains active")
            result.success(null)
        }
        readyCueCompletion = completion
        mainHandler.postDelayed(completion, READY_CUE_COMPLETION_MS)
    }

    private fun stopAudioRouteInternal(clearArmedCue: Boolean = true) {
        pendingRouteOpen?.let(mainHandler::removeCallbacks)
        pendingRouteOpen = null
        pendingRouteReady?.let(mainHandler::removeCallbacks)
        pendingRouteReady = null
        readyCueCompletion?.let(mainHandler::removeCallbacks)
        readyCueCompletion = null
        readyCueGenerator?.stopTone()
        readyCueGenerator?.release()
        readyCueGenerator = null
        if (clearArmedCue) readyCueArmed = false
        cancelPromptRouteHandoffTimeout()
        pendingAudioRouteResult?.let { pending ->
            pendingAudioRouteResult = null
            mainHandler.removeCallbacks(audioRouteTimeout)
            pending.error(
                "HFP_ROUTE_CANCELLED",
                "Đã dừng trước khi đường mic HFP/SCO sẵn sàng.",
                null,
            )
        }
        if (ownsCommunicationRoute) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.clearCommunicationDevice()
            } else {
                @Suppress("DEPRECATION")
                audioManager.stopBluetoothSco()
                @Suppress("DEPRECATION")
                run { audioManager.isBluetoothScoOn = false }
            }
            audioManager.mode = previousAudioMode
        }
        ownsCommunicationRoute = false
        routeActive = false
        adoptedPromptFocusRelease?.let { release ->
            adoptedPromptFocusRelease = null
            release()
        }
        // Returning focus after MODE_NORMAL prevents the interrupted app from
        // resuming into the H20 communication route.
        abandonRouteAudioFocus()
        restoreUncooperativeMediaAudio()
        if (selectedDevice != null && isHeadsetConnected(selectedDevice!!)) {
            phase = "ready"
            statusMessage = "HFP đã kết nối; mic Bluetooth sẵn sàng."
        } else {
            phase = "idle"
            statusMessage = null
        }
        emitStatus()
    }

    /**
     * Arms a one-shot child-facing notification. The tone is emitted only
     * after the next microphone route is confirmed, so it never owns, delays,
     * or closes the route by itself.
     */
    fun armReadyCue(): Boolean {
        if (disposed) return false
        autoSelectConnectedHeadsetIfNeeded()
        val device = selectedDevice
        if (
            adapter?.isEnabled != true ||
                !hasConnectPermission() ||
                device == null ||
                !isHeadsetConnected(device)
        ) {
            return false
        }
        readyCueArmed = true
        Log.d(TAG, "ready cue armed for next confirmed microphone route")
        return true
    }

    fun cancelArmedReadyCue() {
        readyCueArmed = false
    }

    fun beginMainTurn(): String {
        activeMainTurnId?.let { return it }
        val turnId = UUID.randomUUID().toString()
        activeMainTurnId = turnId
        Log.d(TAG, "MAIN audio turn started id=$turnId")
        return turnId
    }

    fun endMainTurn(expectedTurnId: String?) {
        val activeTurnId = activeMainTurnId ?: return
        if (!expectedTurnId.isNullOrBlank() && expectedTurnId != activeTurnId) {
            Log.d(TAG, "ignored stale MAIN audio turn end id=$expectedTurnId")
            return
        }
        activeMainTurnId = null
        Log.d(TAG, "MAIN audio turn ended id=$activeTurnId")
        stopAudioRouteInternal(clearArmedCue = true)
    }

    private fun retainAudioRouteForMainTurn() {
        readyCueCompletion?.let(mainHandler::removeCallbacks)
        readyCueCompletion = null
        readyCueGenerator?.stopTone()
        readyCueGenerator?.release()
        readyCueGenerator = null
        cancelPromptRouteHandoffTimeout()
        adoptedPromptFocusRelease?.let { release ->
            adoptedPromptFocusRelease = null
            release()
        }
        abandonRouteAudioFocus()
        phase = "handoff"
        statusMessage = "Đang giữ HFP/SCO cho lượt MAIN hiện tại."
        emitStatus()
        Log.d(TAG, "retained HFP/SCO route inside active MAIN turn")
    }

    /**
     * Transfers a prompt's already-open HFP route and exclusive focus to the
     * following microphone turn. This avoids a clear/setCommunicationDevice
     * cycle between assistant speech and recognition on slow MIUI audio stacks.
     */
    fun adoptPromptRouteForMicrophone(
        previousMode: Int,
        releasePromptFocus: () -> Unit,
    ): Boolean {
        if (disposed || ownsCommunicationRoute || routeActive) return false
        val routedToBluetooth =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.communicationDevice?.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            } else {
                @Suppress("DEPRECATION")
                audioManager.isBluetoothScoOn
            }
        if (!routedToBluetooth) return false

        this.previousAudioMode = previousMode
        ownsCommunicationRoute = true
        routeActive = true
        adoptedPromptFocusRelease = releasePromptFocus
        phase = "handoff"
        statusMessage = "Đang chuyển trực tiếp từ trợ lý sang mic H20…"
        emitStatus()
        schedulePromptRouteHandoffTimeout()
        Log.d(TAG, "adopted prompt HFP/SCO route for microphone without reopening")
        return true
    }

    private fun schedulePromptRouteHandoffTimeout() {
        cancelPromptRouteHandoffTimeout()
        lateinit var timeout: Runnable
        timeout = Runnable {
            if (promptRouteHandoffTimeout === timeout) {
                promptRouteHandoffTimeout = null
            }
            if (adoptedPromptFocusRelease == null || pendingAudioRouteResult != null) {
                return@Runnable
            }
            Log.w(TAG, "prompt-to-microphone handoff expired; releasing HFP/SCO")
            stopAudioRouteInternal(clearArmedCue = true)
        }
        promptRouteHandoffTimeout = timeout
        mainHandler.postDelayed(timeout, PROMPT_ROUTE_HANDOFF_TIMEOUT_MS)
    }

    private fun cancelPromptRouteHandoffTimeout() {
        promptRouteHandoffTimeout?.let(mainHandler::removeCallbacks)
        promptRouteHandoffTimeout = null
    }

    private fun routeAudioAttributes(): AudioAttributes =
        AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .build()

    private fun requestRouteAudioFocus(): Boolean {
        abandonRouteAudioFocus()
        val requestResult =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val request =
                    AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                        .setAudioAttributes(routeAudioAttributes())
                        .setWillPauseWhenDucked(true)
                        .setOnAudioFocusChangeListener(routeAudioFocusListener, mainHandler)
                        .build()
                routeAudioFocusRequest = request
                audioManager.requestAudioFocus(request)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    routeAudioFocusListener,
                    AudioManager.STREAM_VOICE_CALL,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE,
                )
            }
        routeAudioFocusRequested =
            requestResult == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (!routeAudioFocusRequested) {
            routeAudioFocusRequest = null
        }
        Log.d(
            TAG,
            "recording focus result=$requestResult granted=$routeAudioFocusRequested " +
                "musicActive=${audioManager.isMusicActive}",
        )
        return routeAudioFocusRequested
    }

    private fun handleRouteAudioFocusChange(change: Int) {
        Log.d(TAG, "recording focus changed=$change routeActive=$routeActive")
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> routeAudioFocusRequested = true
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK,
            -> {
                if (pendingAudioRouteResult != null && !routeActive) {
                    statusMessage = "Ứng dụng khác vừa giành quyền âm thanh; đã đóng mic H20."
                    stopAudioRouteInternal()
                } else if (routeActive) {
                    // SpeechRecognizer legitimately takes focus from the
                    // short cue/route owner when capture begins. Keep the HFP
                    // communication device selected; closing it here cuts off
                    // the very microphone that requested the handoff.
                    routeAudioFocusRequested = false
                    Log.d(TAG, "focus handed to active recorder; keeping HFP/SCO route")
                }
            }
        }
    }

    private fun abandonRouteAudioFocus() {
        if (!routeAudioFocusRequested && routeAudioFocusRequest == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            routeAudioFocusRequest?.let(audioManager::abandonAudioFocusRequest)
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(routeAudioFocusListener)
        }
        routeAudioFocusRequest = null
        routeAudioFocusRequested = false
        Log.d(TAG, "recording focus abandoned after route release")
    }

    /**
     * Exclusive focus is advisory for a few third-party players. If one still
     * renders after the drain window, temporarily mute only STREAM_MUSIC so its
     * samples cannot enter H20 SCO. Calls and alarms are never muted, and an
     * existing user mute is left untouched.
     */
    private fun suppressUncooperativeMediaAudioIfNeeded() {
        if (
            mutedUncooperativeMedia ||
                !audioManager.isMusicActive ||
                audioManager.isStreamMute(AudioManager.STREAM_MUSIC)
        ) {
            return
        }
        try {
            audioManager.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                AudioManager.ADJUST_MUTE,
                0,
            )
            mutedUncooperativeMedia =
                audioManager.isStreamMute(AudioManager.STREAM_MUSIC)
            Log.d(TAG, "fallback media mute applied=$mutedUncooperativeMedia")
        } catch (error: SecurityException) {
            Log.w(TAG, "permission denied while muting uncooperative media", error)
        } catch (error: RuntimeException) {
            Log.w(TAG, "unable to mute uncooperative media", error)
        }
    }

    private fun restoreUncooperativeMediaAudio() {
        if (!mutedUncooperativeMedia) return
        mutedUncooperativeMedia = false
        try {
            audioManager.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                AudioManager.ADJUST_UNMUTE,
                0,
            )
            Log.d(TAG, "fallback media mute restored after recording route release")
        } catch (error: SecurityException) {
            Log.w(TAG, "permission denied while restoring media mute", error)
        } catch (error: RuntimeException) {
            Log.w(TAG, "unable to restore media mute", error)
        }
    }

    private fun refreshSelectedDeviceStatus() {
        autoSelectConnectedHeadsetIfNeeded()
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

    /**
     * Native bridges live longer than the Flutter screen but are recreated when
     * Android replaces the process. Recover the already-connected H20 here so a
     * background MAIN turn does not silently fall back to the phone microphone
     * merely because the parent settings sheet has not been reopened.
     */
    private fun autoSelectConnectedHeadsetIfNeeded() {
        if (selectedDevice != null || !hasConnectPermission()) return
        val connected = connectedHeadsets()
        selectedDevice =
            connected.firstOrNull {
                safeName(it).contains("H20", ignoreCase = true)
            } ?: connected.singleOrNull()
        if (selectedDevice != null) {
            Log.d(TAG, "restored connected HFP device=${safeName(selectedDevice!!)}")
        }
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
        appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)

    private fun hasConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            appContext.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
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
            "mediaAudioConnected" to selectedDeviceHasA2dpOutput(),
            "platformManufacturer" to Build.MANUFACTURER,
            "platformModel" to Build.MODEL,
            "platformApiLevel" to Build.VERSION.SDK_INT,
            "platformSystemVersion" to Build.VERSION.RELEASE,
            "profileProxyAvailable" to (headset != null),
            "profileConnected" to selectedDevice?.let(::isHeadsetConnected),
            "connectedHeadsets" to connectedHeadsetSnapshots(),
            "bondedHfpCandidates" to bondedHfpCandidateSnapshots(),
            "availableCommunicationDevices" to availableCommunicationDeviceSnapshots(),
            "communicationDevice" to currentCommunicationDeviceSnapshot(),
            "audioMode" to audioManager.mode,
            "ownsCommunicationRoute" to ownsCommunicationRoute,
            "routeAudioFocusRequested" to routeAudioFocusRequested,
        )

    private fun connectedHeadsetSnapshots(): List<Map<String, Any?>> =
        connectedHeadsets().map(::bluetoothDeviceSnapshot)

    private fun bondedHfpCandidateSnapshots(): List<Map<String, Any?>> {
        if (!hasConnectPermission()) return emptyList()
        return try {
            val connectedAddresses = connectedHeadsets().map { it.address }.toSet()
            adapter?.bondedDevices.orEmpty()
                .filter { isLikelyHfp(it, connectedAddresses) }
                .map(::bluetoothDeviceSnapshot)
        } catch (_: SecurityException) {
            emptyList()
        }
    }

    private fun bluetoothDeviceSnapshot(device: BluetoothDevice): Map<String, Any?> =
        mapOf(
            "id" to runCatching { device.address }.getOrNull(),
            "name" to safeName(device),
            "connected" to isHeadsetConnected(device),
            "bondState" to runCatching { device.bondState }.getOrNull(),
            "majorClass" to runCatching {
                device.bluetoothClass?.majorDeviceClass
            }.getOrNull(),
            "uuids" to runCatching {
                device.uuids?.map { it.uuid.toString() }.orEmpty()
            }.getOrDefault(emptyList()),
        )

    private fun availableCommunicationDeviceSnapshots(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return emptyList()
        return audioManager.availableCommunicationDevices.map(::audioDeviceSnapshot)
    }

    private fun currentCommunicationDeviceSnapshot(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return audioManager.communicationDevice?.let(::audioDeviceSnapshot)
    }

    private fun audioDeviceSnapshot(device: AudioDeviceInfo): Map<String, Any?> =
        mapOf(
            "id" to device.id,
            "type" to device.type,
            "typeName" to audioDeviceTypeName(device.type),
            "name" to device.productName?.toString(),
            "address" to device.address,
            "isSource" to device.isSource,
            "isSink" to device.isSink,
        )

    private fun audioDeviceTypeName(type: Int): String =
        when (type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "BLUETOOTH_SCO"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "BLUETOOTH_A2DP"
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "BUILTIN_EARPIECE"
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "BUILTIN_MIC"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "BUILTIN_SPEAKER"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "WIRED_HEADSET"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "WIRED_HEADPHONES"
            else -> "TYPE_$type"
        }

    private fun selectedDeviceHasA2dpOutput(): Boolean {
        val selected = selectedDevice ?: return false
        val selectedName = safeName(selected)
        return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { output ->
            output.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP &&
                (addressesMatch(output.address, selected.address) ||
                    output.productName?.toString()?.trim()
                        ?.equals(selectedName, ignoreCase = true) == true)
        }
    }

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
            host.runOnMain { eventSink?.success(snapshot()) }
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

    fun onBackgroundSessionStopped() {
        host.runOnMain {
            activeMainTurnId = null
            stopAudioRouteInternal()
        }
    }

    fun dispose() {
        if (disposed) return
        activeMainTurnId = null
        stopAudioRouteInternal()
        disposed = true
        pendingPermissionResult?.error(
            "HFP_DISPOSED",
            "Ứng dụng đã dừng trước khi nhận quyền Bluetooth.",
            null,
        )
        pendingPermissionResult = null
        mainHandler.removeCallbacks(audioRouteTimeout)
        pendingRouteOpen?.let(mainHandler::removeCallbacks)
        pendingRouteOpen = null
        pendingRouteReady?.let(mainHandler::removeCallbacks)
        pendingRouteReady = null
        runCatching { appContext.unregisterReceiver(bluetoothReceiver) }
        headset?.let { adapter?.closeProfileProxy(BluetoothProfile.HEADSET, it) }
        headset = null
        eventSink = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}
