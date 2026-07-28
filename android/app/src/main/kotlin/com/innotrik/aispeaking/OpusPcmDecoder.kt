package com.innotrik.aispeaking

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.ArrayDeque
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Decodes raw Opus access units with the Android platform codec and emits
 * mono PCM16 at 24 kHz, matching the Flutter Realtime/Batch contract.
 */
class OpusPcmDecoder(
    private val onPcm: (ByteArray) -> Unit,
    private val onFailure: (String) -> Unit,
) {
    companion object {
        const val CODEC_SAMPLE_RATE = 48_000
        const val OUTPUT_SAMPLE_RATE = 24_000
        const val CHANNEL_COUNT = 1
        private const val MAX_PENDING_PACKETS = 250
    }

    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var codec: MediaCodec? = null
    private val packets = ArrayDeque<ByteArray>()
    private var presentationTimeUs = 0L
    private var sourceSampleRate = CODEC_SAMPLE_RATE
    private var carriedSample: Short? = null
    @Volatile private var running = false
    private var pumpScheduled = false

    fun start() {
        if (running) return
        val decoder = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_AUDIO_OPUS)
        val format = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_OPUS,
            CODEC_SAMPLE_RATE,
            CHANNEL_COUNT,
        ).apply {
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 4_096)
            setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            setByteBuffer("csd-0", opusHead())
            setByteBuffer("csd-1", nativeLongBuffer(6_500_000L))
            setByteBuffer("csd-2", nativeLongBuffer(80_000_000L))
        }
        decoder.configure(format, null, null, 0)
        decoder.start()

        val decoderThread = HandlerThread("InnotrikOpusDecoder").also { it.start() }
        thread = decoderThread
        handler = Handler(decoderThread.looper)
        codec = decoder
        packets.clear()
        presentationTimeUs = 0L
        sourceSampleRate = CODEC_SAMPLE_RATE
        carriedSample = null
        running = true
    }

    fun offer(packet: ByteArray) {
        if (!running || packet.isEmpty()) return
        val immutable = packet.copyOf()
        handler?.post {
            if (!running) return@post
            if (packets.size >= MAX_PENDING_PACKETS) {
                packets.removeFirst()
            }
            packets.addLast(immutable)
            pump()
        }
    }

    fun stop() {
        if (!running && codec == null) return
        running = false
        val latch = CountDownLatch(1)
        val decoderHandler = handler
        if (decoderHandler == null) {
            releaseCodec()
            return
        }
        decoderHandler.post {
            try {
                while (packets.isNotEmpty()) {
                    if (!queueOnePacket()) break
                }
                drainOutput()
            } catch (_: Throwable) {
                // The primary decode failure is already reported by pump().
            } finally {
                releaseCodec()
                latch.countDown()
            }
        }
        latch.await(900, TimeUnit.MILLISECONDS)
        thread?.quitSafely()
        thread = null
        handler = null
    }

    private fun pump() {
        pumpScheduled = false
        if (codec == null) return
        try {
            while (packets.isNotEmpty() && queueOnePacket()) {
                drainOutput()
            }
            drainOutput()
            if (packets.isNotEmpty() && running && !pumpScheduled) {
                pumpScheduled = true
                handler?.postDelayed({ pump() }, 3)
            }
        } catch (error: Throwable) {
            running = false
            packets.clear()
            onFailure("Không giải mã được Opus INNOTRIK: ${error.message ?: error.javaClass.simpleName}")
        }
    }

    private fun queueOnePacket(): Boolean {
        val decoder = codec ?: return false
        val inputIndex = decoder.dequeueInputBuffer(0)
        if (inputIndex < 0) return false
        val payload = packets.removeFirst()
        val input = decoder.getInputBuffer(inputIndex) ?: return false
        input.clear()
        input.put(payload)
        decoder.queueInputBuffer(
            inputIndex,
            0,
            payload.size,
            presentationTimeUs,
            0,
        )
        val samples = opusPacketSampleCount(payload, CODEC_SAMPLE_RATE)
        presentationTimeUs += samples * 1_000_000L / CODEC_SAMPLE_RATE
        return true
    }

    private fun drainOutput() {
        val decoder = codec ?: return
        val info = MediaCodec.BufferInfo()
        while (true) {
            when (val outputIndex = decoder.dequeueOutputBuffer(info, 0)) {
                MediaCodec.INFO_TRY_AGAIN_LATER -> return
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    sourceSampleRate = decoder.outputFormat.getInteger(
                        MediaFormat.KEY_SAMPLE_RATE,
                    )
                }
                else -> if (outputIndex >= 0) {
                    val output = decoder.getOutputBuffer(outputIndex)
                    if (output != null && info.size > 0) {
                        output.position(info.offset)
                        output.limit(info.offset + info.size)
                        val pcm = ByteArray(info.size)
                        output.get(pcm)
                        val normalized = resampleTo24Khz(pcm, sourceSampleRate)
                        if (normalized.isNotEmpty()) onPcm(normalized)
                    }
                    decoder.releaseOutputBuffer(outputIndex, false)
                }
            }
        }
    }

    private fun resampleTo24Khz(pcm: ByteArray, sampleRate: Int): ByteArray {
        if (sampleRate == OUTPUT_SAMPLE_RATE) return pcm
        if (sampleRate != CODEC_SAMPLE_RATE || pcm.size < 2) {
            throw IllegalStateException("Opus decoder trả PCM $sampleRate Hz; cần 24/48 kHz")
        }

        val samples = ArrayList<Short>((pcm.size / 4) + 1)
        var offset = 0
        var first = carriedSample
        if (first != null && pcm.size >= 2) {
            val second = readShort(pcm, 0)
            samples += ((first.toInt() + second.toInt()) / 2).toShort()
            first = null
            offset = 2
        }
        while (offset + 3 < pcm.size) {
            val a = readShort(pcm, offset)
            val b = readShort(pcm, offset + 2)
            samples += ((a.toInt() + b.toInt()) / 2).toShort()
            offset += 4
        }
        carriedSample = if (offset + 1 < pcm.size) readShort(pcm, offset) else first
        val output = ByteArray(samples.size * 2)
        samples.forEachIndexed { index, sample ->
            output[index * 2] = (sample.toInt() and 0xFF).toByte()
            output[index * 2 + 1] = ((sample.toInt() shr 8) and 0xFF).toByte()
        }
        return output
    }

    private fun readShort(bytes: ByteArray, offset: Int): Short {
        return ((bytes[offset].toInt() and 0xFF) or
            ((bytes[offset + 1].toInt() and 0xFF) shl 8)).toShort()
    }

    private fun releaseCodec() {
        packets.clear()
        codec?.runCatching { stop() }
        codec?.runCatching { release() }
        codec = null
        carriedSample = null
    }

    private fun opusHead(): ByteBuffer {
        val bytes = ByteArray(19)
        "OpusHead".encodeToByteArray().copyInto(bytes)
        bytes[8] = 1
        bytes[9] = CHANNEL_COUNT.toByte()
        val preSkip = 312
        bytes[10] = (preSkip and 0xFF).toByte()
        bytes[11] = ((preSkip shr 8) and 0xFF).toByte()
        val rate = CODEC_SAMPLE_RATE
        bytes[12] = (rate and 0xFF).toByte()
        bytes[13] = ((rate shr 8) and 0xFF).toByte()
        bytes[14] = ((rate shr 16) and 0xFF).toByte()
        bytes[15] = ((rate shr 24) and 0xFF).toByte()
        return ByteBuffer.wrap(bytes)
    }

    private fun nativeLongBuffer(value: Long): ByteBuffer {
        return ByteBuffer.allocate(8).order(ByteOrder.nativeOrder()).putLong(value).apply {
            flip()
        }
    }

    private fun opusPacketSampleCount(packet: ByteArray, sampleRate: Int): Long {
        if (packet.isEmpty()) return sampleRate / 50L
        val toc = packet[0].toInt() and 0xFF
        val samplesPerFrame = when {
            toc and 0x80 != 0 -> (sampleRate shl ((toc shr 3) and 0x3)) / 400
            toc and 0x60 == 0x60 -> sampleRate / (100 shr ((toc shr 3) and 0x3))
            else -> sampleRate / (50 shr ((toc shr 3) and 0x3))
        }
        val frames = when (toc and 0x3) {
            0 -> 1
            1, 2 -> 2
            else -> if (packet.size > 1) packet[1].toInt() and 0x3F else 1
        }
        val total = samplesPerFrame * frames
        return total.coerceIn(sampleRate / 400, sampleRate * 120 / 1000).toLong()
    }
}
