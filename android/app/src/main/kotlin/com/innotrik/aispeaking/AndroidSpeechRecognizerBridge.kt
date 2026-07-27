package com.innotrik.aispeaking

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

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
            "speech.start" -> startListening(result)
            "speech.stop" -> {
                recognizer?.stopListening()
                result.success(true)
            }
            "speech.cancel" -> {
                recognizer?.cancel()
                listening = false
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun startListening(result: MethodChannel.Result) {
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
            activity.requestPermissions(
                arrayOf(Manifest.permission.RECORD_AUDIO),
                microphonePermissionRequestCode,
            )
            return
        }

        startRecognizer(result)
    }

    private fun startRecognizer(result: MethodChannel.Result) {
        if (!SpeechRecognizer.isRecognitionAvailable(activity)) {
            result.error(
                "SPEECH_UNAVAILABLE",
                "Android speech recognition is unavailable.",
                null,
            )
            return
        }

        if (recognizer == null) {
            recognizer =
                SpeechRecognizer.createSpeechRecognizer(activity).also {
                    it.setRecognitionListener(this)
                }
        }

        if (listening) {
            recognizer?.cancel()
        }

        val intent =
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "vi-VN")
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "vi-VN")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS,
                    800L,
                )
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                    700L,
                )
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                    900L,
                )
                putExtra(
                    RecognizerIntent.EXTRA_CALLING_PACKAGE,
                    activity.packageName,
                )
            }

        listening = true
        recognizer?.startListening(intent)
        result.success(true)
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

        if (pendingResult == null) {
            return true
        }

        if (
            grantResults.firstOrNull() ==
                PackageManager.PERMISSION_GRANTED
        ) {
            startRecognizer(pendingResult)
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

    override fun onBufferReceived(buffer: ByteArray?) = Unit

    override fun onEndOfSpeech() {
        emit("speech.end")
    }

    override fun onError(error: Int) {
        listening = false
        events?.success(
            mapOf(
                "type" to "speech.error",
                "code" to error,
                "message" to errorMessage(error),
            ),
        )
    }

    override fun onResults(results: Bundle?) {
        listening = false
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

        events?.success(
            mapOf(
                "type" to type,
                "text" to (candidates?.firstOrNull() ?: ""),
                "alternatives" to (candidates ?: emptyList<String>()),
                "confidence" to
                    (confidenceScores?.firstOrNull()?.toDouble() ?: -1.0),
            ),
        )
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
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
        listening = false
        events = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private companion object {
        const val microphonePermissionRequestCode = 4101
    }
}
