package com.innotrik.aispeaking

object InnotrikProtocol {
    const val SERVICE_UUID = "0000ff12-0000-1000-8000-00805f9b34fb"
    const val WRITE_CHARACTERISTIC_UUID = "0000ff13-0000-1000-8000-00805f9b34fb"
    const val NOTIFY_CHARACTERISTIC_UUID = "0000ff14-0000-1000-8000-00805f9b34fb"
    const val OTA_WRITE_CHARACTERISTIC_UUID = "0000ff15-0000-1000-8000-00805f9b34fb"
    const val AUTH_SERVICE_UUID = "0000ff10-0000-1000-8000-00805f9b34fb"
    const val AUTH_CHARACTERISTIC_UUID = "0000fff1-0000-1000-8000-00805f9b34fb"

    const val PACKET_LENGTH = 84
    const val HEADER_LENGTH = 4
    const val OPUS_PAYLOAD_LENGTH = 80

    val START_MICROPHONE_COMMAND =
        byteArrayOf(0x55, 0xAA.toByte(), 0xA5.toByte(), 0x59)
    val STOP_MICROPHONE_COMMAND =
        byteArrayOf(0x55, 0xAA.toByte(), 0xA5.toByte(), 0x58)
    val AUDIO_PACKET_HEADER = START_MICROPHONE_COMMAND

    fun extractOpusPayload(packet: ByteArray): ByteArray {
        require(packet.size == PACKET_LENGTH) {
            "Expected $PACKET_LENGTH bytes, received ${packet.size}."
        }
        require(
            packet
                .copyOfRange(0, HEADER_LENGTH)
                .contentEquals(AUDIO_PACKET_HEADER),
        ) {
            "Invalid INNOTRIK audio packet header."
        }
        return packet.copyOfRange(HEADER_LENGTH, PACKET_LENGTH)
    }
}
