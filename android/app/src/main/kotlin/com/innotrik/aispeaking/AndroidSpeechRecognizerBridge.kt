package com.innotrik.aispeaking

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class AndroidSpeechRecognizerBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    RecognitionListener {
    private val methodChannel =
        MethodChannel(messenger, "ailingo_speech")
    private val eventChannel =
        EventChannel(messenger, "ailingo_speech/events")

    private var recognizer: SpeechRecognizer? = null
    private var events: EventChannel.EventSink? = null
    private var listening = false
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionCommandMode = false
    private var pendingPermissionPreferOnDevice = false
    private var capturedPcm = ByteArrayOutputStream()
    private var capturedAudioFile: File? = null
    private var injectedAudioRead: ParcelFileDescriptor? = null
    private var injectedAudioWrite: ParcelFileDescriptor? = null
    private var injectedAudioThread: Thread? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "speech.isAvailable" ->
                result.success(SpeechRecognizer.isRecognitionAvailable(activity))
            "speech.supportsAudioSource" ->
                result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
            "speech.prepare" -> result.success(ensureRecognizer())
            "speech.start" -> startListening(call, result)
            "speech.recognizeFile" -> recognizeFile(call, result)
            "speech.stop" -> {
                closeInjectedAudio()
                recognizer?.stopListening()
                result.success(true)
            }
            "speech.cancel" -> {
                recognizer?.cancel()
                closeInjectedAudio()
                listening = false
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun startListening(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val commandMode = call.argument<Boolean>("commandMode") == true
        val preferOnDevice = call.argument<Boolean>("preferOnDevice") == true
        if (
            activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingPermissionResult != null) {
                result.error(
                    "MICROPHONE_PERMISSION_PENDING",
                    "Ứng dụng đang chờ cấp quyền micro.",
                    null,
                )
                return
            }

            pendingPermissionResult = result
            pendingPermissionCommandMode = commandMode
            pendingPermissionPreferOnDevice = preferOnDevice
            activity.requestPermissions(
                arrayOf(Manifest.permission.RECORD_AUDIO),
                microphonePermissionRequestCode,
            )
            return
        }

        startRecognizer(result, commandMode, preferOnDevice)
    }

    private fun startRecognizer(
        result: MethodChannel.Result,
        commandMode: Boolean = false,
        preferOnDevice: Boolean = false,
    ) {
        if (!ensureRecognizer()) {
            result.error(
                "SPEECH_UNAVAILABLE",
                "Android speech recognition is unavailable.",
                null,
            )
            return
        }

        if (listening) {
            recognizer?.cancel()
        }
        closeInjectedAudio()
        resetCapturedAudio()

        listening = true
        recognizer?.startListening(createRecognizerIntent(commandMode, preferOnDevice))
        result.success(true)
    }

    private fun createRecognizerIntent(
        commandMode: Boolean = false,
        preferOnDevice: Boolean = false,
    ): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "vi-VN")
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "vi-VN")
                // MAIN commands come from a fixed local corpus. Prefer the
                // installed Android recognition model so short navigation
                // phrases do not wait for a remote recognizer when offline
                // Vietnamese support is available on the device.
                if (preferOnDevice) {
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                }
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS,
                    if (commandMode) 450L else 800L,
                )
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                    if (commandMode) 500L else 700L,
                )
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                    if (commandMode) 650L else 900L,
                )
                putExtra(
                    RecognizerIntent.EXTRA_CALLING_PACKAGE,
                    activity.packageName,
                )
            }

    private fun recognizeFile(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.error(
                "RECORDED_AUDIO_RECOGNITION_UNAVAILABLE",
                "Thiết bị chưa hỗ trợ nhận diện từ bản ghi âm.",
                null,
            )
            return
        }
        val path = call.argument<String>("path")
        val sampleRate = call.argument<Int>("sampleRate") ?: capturedAudioSampleRate
        val audioFile = path?.let(::File)
        if (audioFile == null || !audioFile.isFile || audioFile.length() <= wavHeaderBytes) {
            result.error(
                "RECORDED_AUDIO_FILE_INVALID",
                "Không tìm thấy bản ghi âm Android hợp lệ.",
                null,
            )
            return
        }
        if (!ensureRecognizer()) {
            result.error(
                "SPEECH_UNAVAILABLE",
                "Android speech recognition is unavailable.",
                null,
            )
            return
        }

        if (listening) {
            recognizer?.cancel()
        }
        closeInjectedAudio()
        resetCapturedAudio()
        capturedAudioFile = audioFile

        val pipe = ParcelFileDescriptor.createPipe()
        val readSide = pipe[0]
        val writeSide = pipe[1]
        injectedAudioRead = readSide
        injectedAudioWrite = writeSide
        val intent =
            createRecognizerIntent().apply {
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readSide)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                putExtra(
                    RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING,
                    AudioFormat.ENCODING_PCM_16BIT,
                )
                putExtra(
                    RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE,
                    sampleRate,
                )
            }

        listening = true
        recognizer?.startListening(intent)
        val feeder =
            Thread(
                {
                    try {
                        FileInputStream(audioFile).use { input ->
                            var remainingHeaderBytes = wavHeaderBytes.toLong()
                            while (remainingHeaderBytes > 0) {
                                val skipped = input.skip(remainingHeaderBytes)
                                if (skipped <= 0) {
                                    break
                                }
                                remainingHeaderBytes -= skipped
                            }
                            ParcelFileDescriptor.AutoCloseOutputStream(writeSide).use { output ->
                                input.copyTo(output, injectedAudioBufferBytes)
                                output.flush()
                            }
                        }
                    } catch (_: Exception) {
                        // Closing/canceling the recognition also closes the
                        // pipe and is expected to interrupt this copy.
                    } finally {
                        if (injectedAudioWrite === writeSide) {
                            injectedAudioWrite = null
                        }
                    }
                },
                "ailingo-speech-audio-source",
            )
        injectedAudioThread = feeder
        feeder.start()
        result.success(true)
    }

    private fun ensureRecognizer(): Boolean {
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            return false
        }
        if (recognizer == null) {
            recognizer =
                SpeechRecognizer.createSpeechRecognizer(activity).also {
                    it.setRecognitionListener(this)
                }
        }
        return true
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != microphonePermissionRequestCode) {
            return false
        }

        val pendingResult = pendingPermissionResult
        pendingPermissionResult = null
        val commandMode = pendingPermissionCommandMode
        pendingPermissionCommandMode = false
        val preferOnDevice = pendingPermissionPreferOnDevice
        pendingPermissionPreferOnDevice = false

        if (pendingResult == null) {
            return true
        }

        if (
            grantResults.firstOrNull() ==
                PackageManager.PERMISSION_GRANTED
        ) {
            startRecognizer(pendingResult, commandMode, preferOnDevice)
        } else {
            pendingResult.error(
                "MICROPHONE_PERMISSION_DENIED",
                "Ứng dụng cần quyền micro để nghe con nói.",
                null,
            )
        }

        return true
    }

    override fun onListen(
        arguments: Any?,
        eventSink: EventChannel.EventSink?,
    ) {
        events = eventSink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    override fun onReadyForSpeech(params: Bundle?) {
        emit("speech.ready")
    }

    override fun onBeginningOfSpeech() {
        emit("speech.begin")
    }

    override fun onRmsChanged(rmsdB: Float) {
        events?.success(
            mapOf(
                "type" to "speech.rms",
                "rmsDb" to rmsdB.toDouble(),
            ),
        )
    }

    override fun onBufferReceived(buffer: ByteArray?) {
        if (capturedAudioFile != null || buffer == null || buffer.size < 2) {
            return
        }

        // RecognitionListener documents signed 16-bit mono PCM in big-endian
        // order. WAV stores the same samples little-endian, so normalize while
        // collecting instead of copying the complete utterance again later.
        var index = 0
        while (index + 1 < buffer.size) {
            capturedPcm.write(buffer[index + 1].toInt())
            capturedPcm.write(buffer[index].toInt())
            index += 2
        }
    }

    override fun onEndOfSpeech() {
        emit("speech.end")
    }

    override fun onError(error: Int) {
        listening = false
        closeInjectedAudio()
        val payload =
            mutableMapOf<String, Any>(
                "type" to "speech.error",
                "code" to error,
                "message" to errorMessage(error),
            )
        payload.putAll(finishCapturedAudio())
        events?.success(payload)
    }

    override fun onResults(results: Bundle?) {
        listening = false
        closeInjectedAudio()
        emitResult("speech.final", results)
    }

    override fun onPartialResults(partialResults: Bundle?) {
        emitResult("speech.partial", partialResults)
    }

    override fun onEvent(eventType: Int, params: Bundle?) = Unit

    private fun emitResult(type: String, bundle: Bundle?) {
        val candidates =
            bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val confidenceScores =
            bundle?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)

        val payload =
            mutableMapOf<String, Any>(
                "type" to type,
                "text" to (candidates?.firstOrNull() ?: ""),
                "alternatives" to (candidates ?: emptyList<String>()),
                "confidence" to
                    (confidenceScores?.firstOrNull()?.toDouble() ?: -1.0),
            )
        if (type == "speech.final") {
            payload.putAll(finishCapturedAudio())
        }
        events?.success(payload)
    }

    private fun finishCapturedAudio(): Map<String, Any> {
        val existing = capturedAudioFile
        if (existing != null && existing.exists() && existing.length() > wavHeaderBytes) {
            return audioMetadata(existing)
        }

        val pcm = capturedPcm.toByteArray()
        if (pcm.size < minimumCapturedPcmBytes) {
            return emptyMap()
        }
        val output =
            File(
                activity.cacheDir,
                "speech_${System.currentTimeMillis()}.wav",
            )
        FileOutputStream(output).use { stream ->
            stream.write(createWavHeader(pcm.size))
            stream.write(pcm)
            stream.flush()
        }
        capturedAudioFile = output
        return audioMetadata(output)
    }

    private fun audioMetadata(file: File): Map<String, Any> =
        mapOf(
            "audioPath" to file.absolutePath,
            "audioMimeType" to "audio/wav",
            "audioByteLength" to file.length(),
            "audioSampleRate" to capturedAudioSampleRate,
        )

    private fun resetCapturedAudio() {
        capturedPcm.reset()
        // Keep the previous cache file alive while Dart uploads it in the
        // background. Android manages cache eviction; deleting it at the next
        // recording start would race a slow Cloudinary request.
        capturedAudioFile = null
    }

    private fun closeInjectedAudio() {
        injectedAudioThread?.interrupt()
        injectedAudioThread = null
        try {
            injectedAudioWrite?.close()
        } catch (_: Exception) {
        }
        injectedAudioWrite = null
        try {
            injectedAudioRead?.close()
        } catch (_: Exception) {
        }
        injectedAudioRead = null
    }

    private fun createWavHeader(pcmByteLength: Int): ByteArray {
        val header = ByteArrayOutputStream(wavHeaderBytes)
        header.write("RIFF".toByteArray(Charsets.US_ASCII))
        writeIntLittleEndian(header, 36 + pcmByteLength)
        header.write("WAVE".toByteArray(Charsets.US_ASCII))
        header.write("fmt ".toByteArray(Charsets.US_ASCII))
        writeIntLittleEndian(header, 16)
        writeShortLittleEndian(header, 1)
        writeShortLittleEndian(header, 1)
        writeIntLittleEndian(header, capturedAudioSampleRate)
        writeIntLittleEndian(header, capturedAudioSampleRate * pcmBytesPerSample)
        writeShortLittleEndian(header, pcmBytesPerSample)
        writeShortLittleEndian(header, 16)
        header.write("data".toByteArray(Charsets.US_ASCII))
        writeIntLittleEndian(header, pcmByteLength)
        return header.toByteArray()
    }

    private fun writeIntLittleEndian(
        output: ByteArrayOutputStream,
        value: Int,
    ) {
        output.write(value and 0xff)
        output.write((value ushr 8) and 0xff)
        output.write((value ushr 16) and 0xff)
        output.write((value ushr 24) and 0xff)
    }

    private fun writeShortLittleEndian(
        output: ByteArrayOutputStream,
        value: Int,
    ) {
        output.write(value and 0xff)
        output.write((value ushr 8) and 0xff)
    }

    private fun emit(type: String) {
        events?.success(mapOf("type" to type))
    }

    private fun errorMessage(error: Int): String =
        when (error) {
            SpeechRecognizer.ERROR_AUDIO -> "Không thể đọc micro."
            SpeechRecognizer.ERROR_CLIENT -> "Dịch vụ nhận diện đã bị dừng."
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                "Ứng dụng chưa có quyền micro."
            SpeechRecognizer.ERROR_NETWORK,
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
            -> "Mạng nhận diện giọng nói không ổn định."
            SpeechRecognizer.ERROR_NO_MATCH ->
                "Không nghe rõ câu nói."
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
                "Dịch vụ nhận diện đang bận."
            SpeechRecognizer.ERROR_SERVER ->
                "Dịch vụ nhận diện tạm thời không phản hồi."
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                "Chưa nghe thấy giọng nói."
            else -> "Không thể nhận diện giọng nói (mã $error)."
        }

    fun dispose() {
        pendingPermissionResult?.error(
            "SPEECH_DISPOSED",
            "Ứng dụng đã dừng trước khi nhận quyền micro.",
            null,
        )
        pendingPermissionResult = null
        pendingPermissionCommandMode = false
        pendingPermissionPreferOnDevice = false
        recognizer?.cancel()
        closeInjectedAudio()
        recognizer?.destroy()
        recognizer = null
        listening = false
        resetCapturedAudio()
        events = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private companion object {
        const val microphonePermissionRequestCode = 4101
        const val capturedAudioSampleRate = 16000
        const val pcmBytesPerSample = 2
        const val wavHeaderBytes = 44
        const val minimumCapturedPcmBytes = 1600
        const val injectedAudioBufferBytes = 8192
    }
}
