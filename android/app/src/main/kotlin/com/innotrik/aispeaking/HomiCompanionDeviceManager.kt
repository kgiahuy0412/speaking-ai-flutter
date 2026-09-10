package com.innotrik.aispeaking

import android.app.Activity
import android.bluetooth.le.ScanFilter
import android.companion.AssociationRequest
import android.companion.BluetoothLeDeviceFilter
import android.companion.CompanionDeviceManager
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Parent-visible association flow for the H20 companion device. */
class HomiCompanionDeviceManager(private val host: HomiAndroidHost) {
    companion object {
        const val ASSOCIATION_REQUEST_CODE = 7420
    }

    private val context = host.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingResult: MethodChannel.Result? = null
    private var pendingDeviceId: String? = null

    private val manager: CompanionDeviceManager?
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.getSystemService(CompanionDeviceManager::class.java)
        } else {
            null
        }

    fun status(deviceId: String?): Map<String, Any?> {
        val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_COMPANION_DEVICE_SETUP)
        val normalizedId = deviceId?.trim()?.takeIf { it.isNotEmpty() }
        val associations = if (supported) associatedAddresses() else emptyList()
        return mapOf(
            "supported" to supported,
            "associated" to (normalizedId != null && associations.any {
                it.equals(normalizedId, ignoreCase = true)
            }),
            "deviceId" to normalizedId,
            "associations" to associations,
        )
    }

    @Suppress("DEPRECATION")
    fun associate(deviceId: String?, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            !context.packageManager.hasSystemFeature(PackageManager.FEATURE_COMPANION_DEVICE_SETUP)
        ) {
            result.success(status(deviceId))
            return
        }
        val normalizedId = deviceId?.trim()?.takeIf { it.isNotEmpty() }
        if (normalizedId != null && associatedAddresses().any {
                it.equals(normalizedId, ignoreCase = true)
            }
        ) {
            observePresence(normalizedId)
            result.success(status(normalizedId))
            return
        }
        if (host.currentActivity == null) {
            result.error(
                "VISIBLE_ACTIVITY_REQUIRED",
                "Hãy mở HOMI để phụ huynh xác nhận thiết bị H20.",
                null,
            )
            return
        }
        if (pendingResult != null) {
            result.error(
                "COMPANION_ASSOCIATION_PENDING",
                "Android đang chờ phụ huynh xác nhận H20.",
                null,
            )
            return
        }

        val scanFilterBuilder = ScanFilter.Builder()
        if (normalizedId != null) scanFilterBuilder.setDeviceAddress(normalizedId)
        val deviceFilter = BluetoothLeDeviceFilter.Builder()
            .setScanFilter(scanFilterBuilder.build())
            .build()
        val request = AssociationRequest.Builder()
            .addDeviceFilter(deviceFilter)
            .setSingleDevice(true)
            .build()
        pendingResult = result
        pendingDeviceId = normalizedId
        manager?.associate(
            request,
            object : CompanionDeviceManager.Callback() {
                override fun onDeviceFound(chooserLauncher: IntentSender) {
                    val activity = host.currentActivity
                    if (activity == null) {
                        failPending(
                            "VISIBLE_ACTIVITY_REQUIRED",
                            "Màn hình HOMI đã đóng trước khi xác nhận H20.",
                        )
                        return
                    }
                    try {
                        activity.startIntentSenderForResult(
                            chooserLauncher,
                            ASSOCIATION_REQUEST_CODE,
                            null,
                            0,
                            0,
                            0,
                        )
                    } catch (error: IntentSender.SendIntentException) {
                        failPending(
                            "COMPANION_ASSOCIATION_FAILED",
                            error.message ?: "Không mở được màn hình xác nhận H20.",
                        )
                    }
                }

                override fun onFailure(error: CharSequence?) {
                    failPending(
                        "COMPANION_ASSOCIATION_FAILED",
                        error?.toString() ?: "Android không thể đăng ký H20.",
                    )
                }
            },
            mainHandler,
        ) ?: failPending(
            "COMPANION_ASSOCIATION_UNAVAILABLE",
            "Thiết bị không hỗ trợ Companion Device Manager.",
        )
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != ASSOCIATION_REQUEST_CODE) return false
        val pending = pendingResult
        val requestedDeviceId = pendingDeviceId
        pendingResult = null
        pendingDeviceId = null
        if (resultCode != Activity.RESULT_OK) {
            pending?.error(
                "COMPANION_ASSOCIATION_CANCELLED",
                "Phụ huynh chưa xác nhận đăng ký H20.",
                null,
            )
            return true
        }
        val associatedId = requestedDeviceId ?: extractDeviceAddress(data)
        if (associatedId != null) observePresence(associatedId)
        pending?.success(status(associatedId))
        return true
    }

    @Suppress("DEPRECATION")
    private fun associatedAddresses(): List<String> = runCatching {
        manager?.associations?.toList().orEmpty()
    }.getOrDefault(emptyList())

    @Suppress("DEPRECATION")
    private fun observePresence(deviceId: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        runCatching { manager?.startObservingDevicePresence(deviceId) }
    }

    @Suppress("DEPRECATION")
    private fun extractDeviceAddress(data: Intent?): String? {
        if (data == null) return null
        val device = data.getParcelableExtra<android.bluetooth.BluetoothDevice>(
            CompanionDeviceManager.EXTRA_DEVICE,
        )
        return device?.address
    }

    private fun failPending(code: String, message: String) {
        val pending = pendingResult
        pendingResult = null
        pendingDeviceId = null
        pending?.error(code, message, null)
    }
}
