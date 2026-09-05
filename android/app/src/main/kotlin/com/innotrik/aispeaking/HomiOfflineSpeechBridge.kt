package com.innotrik.aispeaking

import android.app.Activity
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Isolated bridge for HOMI's app-owned Vosk model.
 *
 * It intentionally uses a different channel from AndroidSpeechRecognizerBridge
 * so conversation ASR and voice navigation keep their existing system service.
 */
class HomiOfflineSpeechBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, channelName)
    private val executor = Executors.newSingleThreadExecutor()
    private val disposed = AtomicBoolean(false)
    private val recognitionGeneration = AtomicInteger(0)
    private val modelLock = Any()
    private var loadedModelId: String? = null
    private var loadedModel: Model? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "model.status" -> {
                val spec = requestedModel(call)
                if (spec == null) {
                    unsupportedLocale(result)
                } else {
                    result.success(HomiOfflineSpeechModel.status(activity, spec))
                }
            }
            "model.requestDownload" -> {
                val spec = requestedModel(call)
                if (spec == null) {
                    unsupportedLocale(result)
                } else {
                    val payload =
                        HomiOfflineSpeechModel.scheduleDownload(activity, spec).toMutableMap()
                    payload["state"] =
                        if (HomiOfflineSpeechModel.isInstalled(activity, spec)) {
                            "installed"
                        } else {
                            "requested"
                        }
                    result.success(payload)
                }
            }
            "model.cancelDownload" -> {
                val locale = call.argument<String>("locale")
                val spec = locale?.let { HomiOfflineSpeechModels.forLocale(it) }
                if (locale != null && spec == null) {
                    unsupportedLocale(result)
                } else {
                    HomiOfflineSpeechModel.cancelDownload(activity, spec)
                    result.success(true)
                }
            }
            "recognizeFile" -> recognizeFile(call, result)
            "cancel" -> {
                recognitionGeneration.incrementAndGet()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun recognizeFile(call: MethodCall, result: MethodChannel.Result) {
        if (disposed.get()) {
            result.error("OFFLINE_SPEECH_DISPOSED", "Bộ nhận diện đã đóng.", null)
            return
        }
        val spec = requestedModel(call)
        if (spec == null) {
            unsupportedLocale(result)
            return
        }
        if (!HomiOfflineSpeechModel.isInstalled(activity, spec)) {
            result.error(
                "ON_DEVICE_SPEECH_UNAVAILABLE",
                "Model ${spec.locale} offline của HOMI chưa được tải xong.",
                HomiOfflineSpeechModel.status(activity, spec),
            )
            return
        }
        val path = call.argument<String>("path") ?: call.argument<String>("filePath")
        val audioFile = path?.let(::File)
        if (audioFile == null || !audioFile.isFile) {
            result.error("RECORDED_AUDIO_INVALID", "Không tìm thấy bản ghi âm WAV.", null)
            return
        }

        val generation = recognitionGeneration.incrementAndGet()
        executor.execute {
            try {
                val recognition = transcribe(audioFile, generation, spec)
                activity.mainExecutor.execute {
                    if (!disposed.get()) result.success(recognition)
                }
            } catch (error: RecognitionCancelledException) {
                activity.mainExecutor.execute {
                    if (!disposed.get()) {
                        result.error("SPEECH_CANCELLED", "Nhận dạng đã được dừng.", null)
                    }
                }
            } catch (error: InvalidWavException) {
                activity.mainExecutor.execute {
                    if (!disposed.get()) {
                        result.error("RECORDED_AUDIO_INVALID", error.message, null)
                    }
                }
            } catch (error: Throwable) {
                Log.e(logTag, "Offline lesson recognition failed", error)
                activity.mainExecutor.execute {
                    if (!disposed.get()) {
                        result.error(
                            "ON_DEVICE_SPEECH_FAILED",
                            error.message ?: "Không thể nhận dạng bản ghi offline.",
                            null,
                        )
                    }
                }
            }
        }
    }

    private fun transcribe(
        audioFile: File,
        generation: Int,
        spec: HomiOfflineSpeechModelSpec,
    ): Map<String, Any> {
        Log.i(logTag, "Recognizing recorded audio with ${spec.modelId}")
        val wav = inspectWav(audioFile)
        Log.i(
            logTag,
            "Recorded WAV validated sampleRate=${wav.sampleRate} channels=${wav.channels} " +
                "bits=${wav.bitsPerSample} pcmBytes=${wav.dataLength}",
        )
        if (wav.sampleRate != targetSampleRate || wav.channels != 1 || wav.bitsPerSample != 16) {
            throw InvalidWavException("Bản ghi phải là WAV PCM 16-bit, mono, 16 kHz.")
        }
        if (wav.dataLength < minimumPcmBytes) {
            return mapOf(
                "text" to "",
                "alternatives" to emptyList<String>(),
                "engine" to engineName,
            )
        }

        Log.i(logTag, "Loading app-owned offline model")
        val model = model(spec)
        Log.i(logTag, "App-owned offline model ready")
        Recognizer(model, targetSampleRate.toFloat()).use { recognizer ->
            Log.i(logTag, "Offline recognizer ready")
            recognizer.setMaxAlternatives(maxAlternatives)
            RandomAccessFile(audioFile, "r").use { input ->
                input.seek(wav.dataOffset)
                var remaining = wav.dataLength
                val buffer = ByteArray(audioBufferBytes)
                while (remaining > 0) {
                    if (disposed.get() || generation != recognitionGeneration.get()) {
                        throw RecognitionCancelledException()
                    }
                    val count = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
                    if (count <= 0) break
                    recognizer.acceptWaveForm(buffer, count)
                    remaining -= count
                }
            }
            val parsed = parseResult(recognizer.finalResult)
            val candidateCount = (if (parsed.first.isEmpty()) 0 else 1) + parsed.second.size
            Log.i(logTag, "Offline lesson recognition completed candidates=$candidateCount")
            return mapOf(
                "text" to parsed.first,
                "alternatives" to parsed.second,
                "engine" to engineName,
                "modelId" to spec.modelId,
                "locale" to spec.locale,
            )
        }
    }

    private fun model(spec: HomiOfflineSpeechModelSpec): Model =
        synchronized(modelLock) {
            if (loadedModelId != spec.modelId) {
                loadedModel?.close()
                loadedModel = null
                loadedModelId = null
            }
            loadedModel
                ?: Model(HomiOfflineSpeechModel.modelDirectory(activity, spec).absolutePath).also {
                    loadedModel = it
                    loadedModelId = spec.modelId
                }
        }

    private fun requestedModel(call: MethodCall): HomiOfflineSpeechModelSpec? =
        HomiOfflineSpeechModels.forLocale(call.argument<String>("locale") ?: "en-US")

    private fun unsupportedLocale(result: MethodChannel.Result) {
        result.error(
            "OFFLINE_MODEL_LANGUAGE_UNSUPPORTED",
            "HOMI chỉ cung cấp model offline en-US và vi-VN.",
            null,
        )
    }

    private fun parseResult(rawJson: String): Pair<String, List<String>> {
        val json = JSONObject(rawJson)
        val alternativesJson = json.optJSONArray("alternatives")
        val candidates = mutableListOf<String>()
        if (alternativesJson != null) {
            for (index in 0 until alternativesJson.length()) {
                val text = alternativesJson.optJSONObject(index)?.optString("text")?.trim().orEmpty()
                if (text.isNotEmpty() && text !in candidates) candidates += text
            }
        }
        val directText = json.optString("text").trim()
        if (directText.isNotEmpty() && directText !in candidates) candidates.add(0, directText)
        val primary = candidates.firstOrNull().orEmpty()
        return primary to candidates.drop(1)
    }

    fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        recognitionGeneration.incrementAndGet()
        channel.setMethodCallHandler(null)
        executor.execute {
            synchronized(modelLock) {
                loadedModel?.close()
                loadedModel = null
                loadedModelId = null
            }
        }
        executor.shutdown()
    }

    private data class WavInfo(
        val sampleRate: Int,
        val channels: Int,
        val bitsPerSample: Int,
        val dataOffset: Long,
        val dataLength: Long,
    )

    private fun inspectWav(file: File): WavInfo {
        RandomAccessFile(file, "r").use { input ->
            if (input.length() < 44) throw InvalidWavException("File WAV quá ngắn.")
            if (input.readAscii(4) != "RIFF") throw InvalidWavException("Thiếu RIFF header.")
            input.skipBytes(4)
            if (input.readAscii(4) != "WAVE") throw InvalidWavException("Thiếu WAVE header.")

            var format = -1
            var channels = -1
            var sampleRate = -1
            var bits = -1
            var dataOffset = -1L
            var dataLength = -1L
            while (input.filePointer + 8 <= input.length()) {
                val chunkId = input.readAscii(4)
                val chunkSize = input.readLittleEndianUInt32()
                val chunkStart = input.filePointer
                val chunkEnd = chunkStart + chunkSize
                if (chunkEnd > input.length()) throw InvalidWavException("WAV chunk bị thiếu dữ liệu.")
                when (chunkId) {
                    "fmt " -> {
                        if (chunkSize < 16) throw InvalidWavException("WAV fmt không hợp lệ.")
                        format = input.readLittleEndianUInt16()
                        channels = input.readLittleEndianUInt16()
                        sampleRate = input.readLittleEndianInt32()
                        input.skipBytes(6)
                        bits = input.readLittleEndianUInt16()
                    }
                    "data" -> {
                        dataOffset = chunkStart
                        dataLength = chunkSize
                    }
                }
                input.seek(chunkEnd + (chunkSize and 1L))
                if (format >= 0 && dataOffset >= 0) break
            }
            if (format != 1) throw InvalidWavException("Bản ghi không phải PCM WAV.")
            if (dataOffset < 0 || dataLength <= 0) {
                throw InvalidWavException("WAV không có audio data.")
            }
            return WavInfo(sampleRate, channels, bits, dataOffset, dataLength)
        }
    }

    private fun RandomAccessFile.readAscii(length: Int): String {
        val bytes = ByteArray(length)
        readFully(bytes)
        return String(bytes, StandardCharsets.US_ASCII)
    }

    private fun RandomAccessFile.readLittleEndianUInt16(): Int {
        val low = read()
        val high = read()
        if (low < 0 || high < 0) throw IOException("Unexpected end of WAV")
        return low or (high shl 8)
    }

    private fun RandomAccessFile.readLittleEndianInt32(): Int {
        val b0 = read()
        val b1 = read()
        val b2 = read()
        val b3 = read()
        if (b0 < 0 || b1 < 0 || b2 < 0 || b3 < 0) throw IOException("Unexpected end of WAV")
        return b0 or (b1 shl 8) or (b2 shl 16) or (b3 shl 24)
    }

    private fun RandomAccessFile.readLittleEndianUInt32(): Long =
        readLittleEndianInt32().toLong() and 0xFFFF_FFFFL

    private class InvalidWavException(message: String) : IOException(message)
    private class RecognitionCancelledException : IOException()

    private companion object {
        const val channelName = "homi_offline_speech"
        const val logTag = "HomiOfflineSpeech"
        const val engineName = "vosk"
        const val targetSampleRate = 16_000
        const val minimumPcmBytes = 1_600L
        const val audioBufferBytes = 8_192
        const val maxAlternatives = 5
    }
}
