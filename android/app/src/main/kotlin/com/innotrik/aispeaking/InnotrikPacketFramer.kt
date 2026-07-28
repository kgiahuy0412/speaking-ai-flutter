package com.innotrik.aispeaking

/** Reassembles 84-byte INNOTRIK packets across arbitrary BLE notifications. */
class InnotrikPacketFramer {
    private var pending = ByteArray(0)

    fun reset() {
        pending = ByteArray(0)
    }

    fun append(bytes: ByteArray): List<ByteArray> {
        if (bytes.isEmpty()) return emptyList()
        val combined = ByteArray(pending.size + bytes.size)
        pending.copyInto(combined)
        bytes.copyInto(combined, pending.size)

        val packets = mutableListOf<ByteArray>()
        var cursor = 0
        while (cursor < combined.size) {
            val header = findHeader(combined, cursor)
            if (header < 0) {
                val keep = minOf(InnotrikProtocol.HEADER_LENGTH - 1, combined.size - cursor)
                pending = combined.copyOfRange(combined.size - keep, combined.size)
                return packets
            }
            if (combined.size - header < InnotrikProtocol.PACKET_LENGTH) {
                pending = combined.copyOfRange(header, combined.size)
                return packets
            }
            packets += combined.copyOfRange(
                header,
                header + InnotrikProtocol.PACKET_LENGTH,
            )
            cursor = header + InnotrikProtocol.PACKET_LENGTH
        }
        pending = ByteArray(0)
        return packets
    }

    private fun findHeader(bytes: ByteArray, start: Int): Int {
        val header = InnotrikProtocol.AUDIO_PACKET_HEADER
        val last = bytes.size - header.size
        for (index in start..last) {
            var matches = true
            for (headerIndex in header.indices) {
                if (bytes[index + headerIndex] != header[headerIndex]) {
                    matches = false
                    break
                }
            }
            if (matches) return index
        }
        return -1
    }
}
