package com.innotrik.aispeaking

import java.util.UUID

object Aiv0BleProtocol {
    const val CONTROL_SERVICE = "9E3B0001-4A7C-4D6F-8B21-5C17A2D94010"
    const val BUTTON_EVENT = "9E3B0002-4A7C-4D6F-8B21-5C17A2D94010"
    const val APP_STATE = "9E3B0003-4A7C-4D6F-8B21-5C17A2D94010"
    const val BATTERY_SERVICE = "0000180F-0000-1000-8000-00805F9B34FB"
    const val BATTERY_LEVEL = "00002A19-0000-1000-8000-00805F9B34FB"
    const val DEVICE_INFORMATION_SERVICE = "0000180A-0000-1000-8000-00805F9B34FB"
    const val FIRMWARE_REVISION = "00002A26-0000-1000-8000-00805F9B34FB"
    const val CLIENT_CHARACTERISTIC_CONFIG = "00002902-0000-1000-8000-00805F9B34FB"

    val controlServiceUuid: UUID = UUID.fromString(CONTROL_SERVICE)
    val buttonEventUuid: UUID = UUID.fromString(BUTTON_EVENT)
    val appStateUuid: UUID = UUID.fromString(APP_STATE)
    val batteryServiceUuid: UUID = UUID.fromString(BATTERY_SERVICE)
    val batteryLevelUuid: UUID = UUID.fromString(BATTERY_LEVEL)
    val deviceInformationServiceUuid: UUID = UUID.fromString(DEVICE_INFORMATION_SERVICE)
    val firmwareRevisionUuid: UUID = UUID.fromString(FIRMWARE_REVISION)
    val clientCharacteristicConfigUuid: UUID = UUID.fromString(CLIENT_CHARACTERISTIC_CONFIG)
}
