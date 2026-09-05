package com.innotrik.aispeaking

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

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
    private var recognizerMode: RecognizerMode? = null
    private var events: EventChannel.EventSink? = null
    private var listening = false
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionCommandMode = false
    private var pendingPermissionPreferOnDevice = false
    private var pendingPermissionRequireOnDevice = false
    private var pendingPermissionLocale = defaultLocale
    private var pendingFileResult: MethodChannel.Result? = null
    private var activeRequireOnDevice = false
    private var recognitionGeneration = 0
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
                result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        (
                            call.argument<Boolean>("requireOnDevice") != true ||
                                isOnDeviceRecognitionAvailable()
                        ),
                )
            "speech.prepare" -> result.success(ensureRecognizer(RecognizerMode.STANDARD))
            "speech.getOnDeviceModelStatus" -> getOnDeviceModelStatus(call, result)
            "speech.requestOnDeviceModelDownload" ->
                requestOnDeviceModelDownload(call, result)
            "speech.start" -> startListening(call, result)
            "speech.recognizeFile" -> recognizeFile(call, result, waitForFinalResult = false)
            "speech.recognizeFileOnce" -> recognizeFile(call, result, waitForFinalResult = true)
            "speech.stop" -> {
                closeInjectedAudio()
                recognizer?.stopListening()
                result.success(true)
            }
            "speech.cancel" -> {
                recognitionGeneration += 1
                recognizer?.cancel()
                closeInjectedAudio()
                listening = false
                completePendingFileError(
                    "SPEECH_CANCELLED",
                    "Nhận diện bản ghi âm đã bị dừng.",
                )
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
        val requireOnDevice = call.argument<Boolean>("requireOnDevice") == true
        val locale = call.argument<String>("locale")?.ifBlank { defaultLocale } ?: defaultLocale
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
            pendingPermissionRequireOnDevice = requireOnDevice
            pendingPermissionLocale = locale
            activity.requestPermissions(
                arrayOf(Manifest.permission.RECORD_AUDIO),
                microphonePermissionRequestCode,
            )
            return
        }

        startRecognizer(result, commandMode, preferOnDevice, requireOnDevice, locale)
    }

    private fun getOnDeviceModelStatus(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(
                modelStatusPayload(
                    state = "unsupported",
                    strictOnDeviceAvailable = false,
                ),
            )
            return
        }
        if (listening) {
            result.error(
                "SPEECH_RECOGNIZER_BUSY",
                "Dịch vụ nhận diện đang bận.",
                null,
            )
            return
        }

        val locale = call.argument<String>("locale")?.ifBlank { "en-US" } ?: "en-US"
        val strictOnDeviceAvailable = supportsStrictOnDeviceFileRecognition()
        val requestedMode =
            if (strictOnDeviceAvailable) RecognizerMode.ON_DEVICE else RecognizerMode.STANDARD
        if (!ensureRecognizer(requestedMode)) {
            result.success(
                modelStatusPayload(
                    state = "unavailable",
                    strictOnDeviceAvailable = strictOnDeviceAvailable,
                ),
            )
            return
        }

        val activeRecognizer = recognizer
        if (activeRecognizer == null) {
            result.success(
                modelStatusPayload(
                    state = "unavailable",
                    strictOnDeviceAvailable = strictOnDeviceAvailable,
                ),
            )
            return
        }
        val intent = createRecognizerIntent(locale = locale, preferOnDevice = true)
        // Some OEM recognition services incorrectly deliver onError and a
        // later onSupportResult for one request. A MethodChannel reply is
        // single-use, so accept only the first terminal callback.
        val callbackCompleted = AtomicBoolean(false)
        try {
            activeRecognizer.checkRecognitionSupport(
                intent,
                activity.mainExecutor,
                object : RecognitionSupportCallback {
                    override fun onSupportResult(recognitionSupport: RecognitionSupport) {
                        if (!callbackCompleted.compareAndSet(false, true)) return
                        val installed = recognitionSupport.installedOnDeviceLanguages
                        val pending = recognitionSupport.pendingOnDeviceLanguages
                        val downloadable = recognitionSupport.supportedOnDeviceLanguages
                        val online = recognitionSupport.onlineLanguages
                        val state =
                            when {
                                installed.any { languageTagsMatch(it, locale) } -> "installed"
                                pending.any { languageTagsMatch(it, locale) } -> "pending"
                                downloadable.any { languageTagsMatch(it, locale) } -> "downloadable"
                                online.any { languageTagsMatch(it, locale) } -> "missing"
                                else -> "missing"
                            }
                        Log.i(
                            logTag,
                            "English offline model status=$state locale=$locale " +
                                "strict=$strictOnDeviceAvailable installed=${installed.joinToString()} " +
                                "downloadable=${downloadable.joinToString()} " +
                                "pending=${pending.joinToString()}",
                        )
                        result.success(
                            modelStatusPayload(
                                state = state,
                                strictOnDeviceAvailable = strictOnDeviceAvailable,
                            ),
                        )
                    }

                    override fun onError(error: Int) {
                        if (!callbackCompleted.compareAndSet(false, true)) return
                        Log.w(logTag, "English model support check failed: $error")
                        // API 33 devices with a valid recognition service can still
                        // request the locale model when support enumeration fails.
                        result.success(
                            modelStatusPayload(
                                state = "missing",
                                strictOnDeviceAvailable = strictOnDeviceAvailable,
                                supportError = error,
                            ),
                        )
                    }
                },
            )
        } catch (error: RuntimeException) {
            if (!callbackCompleted.compareAndSet(false, true)) return
            Log.w(logTag, "English model support check threw", error)
            result.success(
                modelStatusPayload(
                    state = "missing",
                    strictOnDeviceAvailable = strictOnDeviceAvailable,
                ),
            )
        }
    }

    private fun requestOnDeviceModelDownload(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.error(
                "ON_DEVICE_MODEL_UNSUPPORTED",
                "Android này chưa hỗ trợ tải model nhận diện từ ứng dụng.",
                null,
            )
            return
        }
        if (listening) {
            result.error(
                "SPEECH_RECOGNIZER_BUSY",
                "Dịch vụ nhận diện đang bận.",
                null,
            )
            return
        }
        if (!hasValidatedUnmeteredWifi()) {
            result.error(
                "ON_DEVICE_MODEL_WIFI_REQUIRED",
                "HOMI chỉ tải model nhận diện tiếng Anh qua Wi-Fi.",
                null,
            )
            return
        }

        val locale = call.argument<String>("locale")?.ifBlank { "en-US" } ?: "en-US"
        val strictOnDeviceAvailable = supportsStrictOnDeviceFileRecognition()
        val requestedMode =
            if (strictOnDeviceAvailable) RecognizerMode.ON_DEVICE else RecognizerMode.STANDARD
        if (!ensureRecognizer(requestedMode)) {
            result.error(
                "ON_DEVICE_MODEL_UNSUPPORTED",
                "Thiết bị không có dịch vụ nhận diện hỗ trợ tải model.",
                null,
            )
            return
        }

        try {
            recognizer?.triggerModelDownload(
                createRecognizerIntent(locale = locale, preferOnDevice = true),
            )
            Log.i(
                logTag,
                "Requested English offline model download locale=$locale " +
                    "mode=$requestedMode wifi=validated_unmetered",
            )
            result.success(
                mapOf(
                    "state" to "requested",
                    "locale" to locale,
                    "apiLevel" to Build.VERSION.SDK_INT,
                    "strictOnDeviceAvailable" to strictOnDeviceAvailable,
                ),
            )
        } catch (error: RuntimeException) {
            Log.w(logTag, "English model download request failed", error)
            result.error(
                "ON_DEVICE_MODEL_DOWNLOAD_FAILED",
                error.message ?: "Không thể yêu cầu Android tải model tiếng Anh.",
                null,
            )
        }
    }

    private fun modelStatusPayload(
        state: String,
        strictOnDeviceAvailable: Boolean,
        supportError: Int? = null,
    ): Map<String, Any> =
        mutableMapOf<String, Any>(
            "state" to state,
            "locale" to "en-US",
            "apiLevel" to Build.VERSION.SDK_INT,
            "strictOnDeviceAvailable" to strictOnDeviceAvailable,
        ).apply {
            if (supportError != null) put("supportError", supportError)
        }

    private fun startRecognizer(
        result: MethodChannel.Result,
        commandMode: Boolean = false,
        preferOnDevice: Boolean = false,
        requireOnDevice: Boolean = false,
        locale: String = defaultLocale,
    ) {
        completePendingFileError(
            "SPEECH_REPLACED",
            "Một lượt nhận diện mới đã thay thế lượt trước.",
        )
        val requestedMode = resolveRecognizerMode(requireOnDevice)
        if (requestedMode == null) {
            result.error(
                "ON_DEVICE_SPEECH_UNAVAILABLE",
                "Thiết bị chưa có bộ nhận diện giọng nói offline.",
                null,
            )
            return
        }
        if (!ensureRecognizer(requestedMode)) {
            result.error(
                if (requireOnDevice) "ON_DEVICE_SPEECH_UNAVAILABLE" else "SPEECH_UNAVAILABLE",
                if (requireOnDevice) {
                    "Thiết bị chưa có bộ nhận diện giọng nói offline."
                } else {
                    "Android speech recognition is unavailable."
                },
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
        activeRequireOnDevice = requireOnDevice
        recognitionGeneration += 1
        recognizer?.startListening(
            createRecognizerIntent(
                commandMode = commandMode,
                locale = locale,
                preferOnDevice = preferOnDevice || requireOnDevice,
            ),
        )
        result.success(true)
    }

    private fun createRecognizerIntent(
        commandMode: Boolean = false,
        locale: String = defaultLocale,
        preferOnDevice: Boolean = false,
    ): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
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
        waitForFinalResult: Boolean,
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
        val locale = call.argument<String>("locale")?.ifBlank { defaultLocale } ?: defaultLocale
        val preferOnDevice = call.argument<Boolean>("preferOnDevice") == true
        val requireOnDevice = call.argument<Boolean>("requireOnDevice") == true
        val allowDisconnectedOfflineCompatibility =
            call.argument<Boolean>("allowDisconnectedOfflineCompatibility") == true
        val audioFile = path?.let(::File)
        val wavAudio = audioFile?.let(::inspectPcm16MonoWav)
        if (audioFile == null || wavAudio == null) {
            result.error(
                "RECORDED_AUDIO_FILE_INVALID",
                "Bản ghi Android phải là WAV PCM 16-bit, mono, 16 kHz hợp lệ.",
                null,
            )
            return
        }
        val requestedSampleRate = call.argument<Int>("sampleRate") ?: wavAudio.sampleRate
        if (requestedSampleRate != capturedAudioSampleRate) {
            result.error(
                "RECORDED_AUDIO_FILE_INVALID",
                "Bản ghi Android phải có sample rate 16 kHz.",
                null,
            )
            return
        }
        val strictOnDeviceAvailable = supportsStrictOnDeviceFileRecognition()
        val useDisconnectedOfflineCompatibility =
            requireOnDevice &&
                !strictOnDeviceAvailable &&
                allowDisconnectedOfflineCompatibility &&
                supportsDisconnectedOfflineCompatibility()
        if (requireOnDevice && !strictOnDeviceAvailable && !useDisconnectedOfflineCompatibility) {
            result.error(
                "ON_DEVICE_SPEECH_UNAVAILABLE",
                "Thiết bị chưa hỗ trợ nhận diện file bằng model offline.",
                null,
            )
            return
        }
        val requestedMode =
            if (requireOnDevice && strictOnDeviceAvailable) {
                RecognizerMode.ON_DEVICE
            } else {
                RecognizerMode.STANDARD
            }
        if (!ensureRecognizer(requestedMode)) {
            result.error(
                if (requireOnDevice) "ON_DEVICE_SPEECH_UNAVAILABLE" else "SPEECH_UNAVAILABLE",
                if (requireOnDevice) {
                    "Thiết bị chưa có bộ nhận diện giọng nói offline."
                } else {
                    "Android speech recognition is unavailable."
                },
                null,
            )
            return
        }

        completePendingFileError(
            "SPEECH_REPLACED",
            "Một lượt nhận diện mới đã thay thế lượt trước.",
        )
        if (listening) {
            recognizer?.cancel()
        }
        closeInjectedAudio()
        resetCapturedAudio()
        capturedAudioFile = audioFile
        val intent =
            createRecognizerIntent(
                locale = locale,
                preferOnDevice = preferOnDevice || requireOnDevice,
            )
        val generation = ++recognitionGeneration
        if (waitForFinalResult) {
            pendingFileResult = result
        }

        val beginRecognition = {
            if (generation == recognitionGeneration) {
                Log.i(
                    logTag,
                    "Starting recorded English recognition mode=$requestedMode " +
                        "disconnectedCompatibility=$useDisconnectedOfflineCompatibility",
                )
                beginFileRecognition(
                    audioFile = audioFile,
                    wavAudio = wavAudio,
                    intent = intent,
                    methodResult = result,
                    waitForFinalResult = waitForFinalResult,
                    requireOnDevice = requireOnDevice,
                )
            }
        }

        if (requireOnDevice && !useDisconnectedOfflineCompatibility) {
            checkInstalledOnDeviceModel(
                intent = intent,
                locale = locale,
                generation = generation,
                onInstalled = beginRecognition,
                onUnavailable = {
                    failFileRequest(
                        result,
                        waitForFinalResult,
                        "ON_DEVICE_SPEECH_UNAVAILABLE",
                        "Model nhận diện tiếng Anh offline chưa được cài trên thiết bị.",
                    )
                },
            )
        } else {
            beginRecognition()
        }
    }

    private fun beginFileRecognition(
        audioFile: File,
        wavAudio: WavAudio,
        intent: Intent,
        methodResult: MethodChannel.Result,
        waitForFinalResult: Boolean,
        requireOnDevice: Boolean,
    ) {
        try {
            val pipe = ParcelFileDescriptor.createPipe()
            val readSide = pipe[0]
            val writeSide = pipe[1]
            injectedAudioRead = readSide
            injectedAudioWrite = writeSide
            intent.apply {
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, readSide)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                putExtra(
                    RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING,
                    AudioFormat.ENCODING_PCM_16BIT,
                )
                putExtra(
                    RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE,
                    wavAudio.sampleRate,
                )
            }

            listening = true
            activeRequireOnDevice = requireOnDevice
            recognizer?.startListening(intent)
            val feeder =
                Thread(
                    {
                        try {
                            FileInputStream(audioFile).use { input ->
                                var remainingHeaderBytes = wavAudio.dataOffset
                                while (remainingHeaderBytes > 0) {
                                    val skipped = input.skip(remainingHeaderBytes)
                                    if (skipped <= 0) break
                                    remainingHeaderBytes -= skipped
                                }
                                ParcelFileDescriptor.AutoCloseOutputStream(writeSide).use { output ->
                                    val buffer = ByteArray(injectedAudioBufferBytes)
                                    var remainingAudioBytes = wavAudio.dataLength
                                    while (remainingAudioBytes > 0) {
                                        val count = input.read(
                                            buffer,
                                            0,
                                            minOf(buffer.size.toLong(), remainingAudioBytes).toInt(),
                                        )
                                        if (count <= 0) break
                                        output.write(buffer, 0, count)
                                        remainingAudioBytes -= count
                                    }
                                    output.flush()
                                }
                            }
                        } catch (_: Exception) {
                            // Closing recognition is expected to interrupt the pipe.
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
            if (!waitForFinalResult) methodResult.success(true)
        } catch (_: Exception) {
            listening = false
            closeInjectedAudio()
            failFileRequest(
                methodResult,
                waitForFinalResult,
                "RECORDED_AUDIO_FILE_INVALID",
                "Không thể đọc bản ghi WAV Android.",
            )
        }
    }

    private fun resolveRecognizerMode(requireOnDevice: Boolean): RecognizerMode? {
        if (requireOnDevice && !isOnDeviceRecognitionAvailable()) return null
        return if (requireOnDevice) {
            RecognizerMode.ON_DEVICE
        } else {
            // `preferOnDevice` remains the existing EXTRA_PREFER_OFFLINE hint
            // on the standard recognizer. Voice navigation already uses that
            // hint and must not silently switch to a different recognizer.
            RecognizerMode.STANDARD
        }
    }

    private fun ensureRecognizer(requestedMode: RecognizerMode): Boolean {
        val available = when (requestedMode) {
            RecognizerMode.STANDARD -> SpeechRecognizer.isRecognitionAvailable(activity)
            RecognizerMode.ON_DEVICE -> isOnDeviceRecognitionAvailable()
        }
        if (!available) {
            return false
        }
        if (recognizer != null && recognizerMode != requestedMode) {
            recognizer?.cancel()
            closeInjectedAudio()
            recognizer?.destroy()
            recognizer = null
            recognizerMode = null
            listening = false
            activeRequireOnDevice = false
        }
        if (recognizer == null) {
            recognizer = try {
                val created = when (requestedMode) {
                    RecognizerMode.STANDARD -> SpeechRecognizer.createSpeechRecognizer(activity)
                    RecognizerMode.ON_DEVICE ->
                        SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
                }
                created.also {
                    it.setRecognitionListener(this)
                }
            } catch (_: UnsupportedOperationException) {
                null
            }
            recognizerMode = if (recognizer == null) null else requestedMode
        }
        return recognizer != null
    }

    private fun isOnDeviceRecognitionAvailable(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)

    private fun supportsStrictOnDeviceFileRecognition(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            isOnDeviceRecognitionAvailable()

    /**
     * Some Android 13 Xiaomi builds expose Google Speech Services while leaving
     * the framework on-device recognizer component empty. The strict factory is
     * then unavailable even with an installed offline language pack. Keep this
     * compatibility path constrained to a device with no validated network;
     * normal online lesson scoring never reaches this recognizer.
     */
    private fun supportsDisconnectedOfflineCompatibility(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            SpeechRecognizer.isRecognitionAvailable(activity) &&
            !hasValidatedInternetConnection()

    private fun hasValidatedInternetConnection(): Boolean =
        try {
            val connectivityManager =
                activity.getSystemService(ConnectivityManager::class.java)
                    ?: return true
            val activeNetwork = connectivityManager.activeNetwork ?: return false
            val capabilities =
                connectivityManager.getNetworkCapabilities(activeNetwork) ?: return false
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } catch (_: SecurityException) {
            // Fail closed if an OEM blocks network-state inspection.
            true
        }

    private fun hasValidatedUnmeteredWifi(): Boolean =
        try {
            val connectivityManager =
                activity.getSystemService(ConnectivityManager::class.java)
                    ?: return false
            val activeNetwork = connectivityManager.activeNetwork ?: return false
            val capabilities =
                connectivityManager.getNetworkCapabilities(activeNetwork) ?: return false
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        } catch (_: SecurityException) {
            false
        }

    private fun checkInstalledOnDeviceModel(
        intent: Intent,
        locale: String,
        generation: Int,
        onInstalled: () -> Unit,
        onUnavailable: () -> Unit,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            onUnavailable()
            return
        }
        val activeRecognizer = recognizer
        if (activeRecognizer == null || recognizerMode != RecognizerMode.ON_DEVICE) {
            onUnavailable()
            return
        }
        val callbackCompleted = AtomicBoolean(false)
        try {
            activeRecognizer.checkRecognitionSupport(
                intent,
                activity.mainExecutor,
                object : RecognitionSupportCallback {
                    override fun onSupportResult(recognitionSupport: RecognitionSupport) {
                        if (!callbackCompleted.compareAndSet(false, true)) return
                        if (generation != recognitionGeneration) return
                        Log.i(
                            logTag,
                            "Installed on-device speech languages=" +
                                recognitionSupport.installedOnDeviceLanguages.joinToString(),
                        )
                        if (
                            recognitionSupport.installedOnDeviceLanguages.any {
                                languageTagsMatch(it, locale)
                            }
                        ) {
                            onInstalled()
                        } else {
                            onUnavailable()
                        }
                    }

                    override fun onError(error: Int) {
                        if (!callbackCompleted.compareAndSet(false, true)) return
                        Log.w(logTag, "Recognition support check failed: $error")
                        if (generation == recognitionGeneration) onUnavailable()
                    }
                },
            )
        } catch (_: RuntimeException) {
            if (!callbackCompleted.compareAndSet(false, true)) return
            if (generation == recognitionGeneration) onUnavailable()
        }
    }

    private fun languageTagsMatch(left: String, right: String): Boolean {
        val leftLocale = Locale.forLanguageTag(left.replace('_', '-'))
        val rightLocale = Locale.forLanguageTag(right.replace('_', '-'))
        if (!leftLocale.language.equals(rightLocale.language, ignoreCase = true)) return false
        return leftLocale.country.isEmpty() ||
            rightLocale.country.isEmpty() ||
            leftLocale.country.equals(rightLocale.country, ignoreCase = true)
    }

    private fun failFileRequest(
        methodResult: MethodChannel.Result,
        waitForFinalResult: Boolean,
        code: String,
        message: String,
    ) {
        if (waitForFinalResult && pendingFileResult === methodResult) {
            pendingFileResult = null
        }
        methodResult.error(code, message, null)
    }

    private fun completePendingFileError(code: String, message: String) {
        val pending = pendingFileResult ?: return
        pendingFileResult = null
        pending.error(code, message, null)
    }

    private fun inspectPcm16MonoWav(file: File): WavAudio? {
        if (!file.isFile || file.length() < wavHeaderBytes) return null
        return try {
            RandomAccessFile(file, "r").use { input ->
                val header = ByteArray(12)
                input.readFully(header)
                if (
                    String(header, 0, 4, Charsets.US_ASCII) != "RIFF" ||
                    String(header, 8, 4, Charsets.US_ASCII) != "WAVE"
                ) {
                    return null
                }

                var validFormat = false
                var sampleRate = -1
                var dataOffset = -1L
                var dataLength = 0L
                while (input.filePointer + 8 <= input.length()) {
                    val chunkIdBytes = ByteArray(4)
                    input.readFully(chunkIdBytes)
                    val chunkId = String(chunkIdBytes, Charsets.US_ASCII)
                    val chunkSize = input.readLittleEndianUnsignedInt()
                    val chunkStart = input.filePointer
                    val chunkEnd = chunkStart + chunkSize
                    if (chunkSize < 0 || chunkEnd > input.length()) return null

                    if (chunkId == "fmt ") {
                        if (chunkSize < 16) return null
                        val audioFormat = input.readLittleEndianUnsignedShort()
                        val channels = input.readLittleEndianUnsignedShort()
                        sampleRate = input.readLittleEndianUnsignedInt().toInt()
                        input.skipBytes(4)
                        val blockAlign = input.readLittleEndianUnsignedShort()
                        val bitsPerSample = input.readLittleEndianUnsignedShort()
                        validFormat =
                            audioFormat == pcmWavAudioFormat &&
                                channels == 1 &&
                                bitsPerSample == 16 &&
                                blockAlign == pcmBytesPerSample
                    } else if (chunkId == "data") {
                        dataOffset = chunkStart
                        dataLength = chunkSize
                    }

                    val nextChunk = chunkEnd + (chunkSize and 1L)
                    if (nextChunk > input.length()) return null
                    input.seek(nextChunk)
                }

                if (
                    validFormat &&
                    sampleRate == capturedAudioSampleRate &&
                    dataOffset > 0 &&
                    dataLength > 0
                ) {
                    WavAudio(
                        dataOffset = dataOffset,
                        dataLength = dataLength,
                        sampleRate = sampleRate,
                    )
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun RandomAccessFile.readLittleEndianUnsignedShort(): Int {
        val first = readUnsignedByte()
        val second = readUnsignedByte()
        return first or (second shl 8)
    }

    private fun RandomAccessFile.readLittleEndianUnsignedInt(): Long {
        val first = readUnsignedByte().toLong()
        val second = readUnsignedByte().toLong()
        val third = readUnsignedByte().toLong()
        val fourth = readUnsignedByte().toLong()
        return first or (second shl 8) or (third shl 16) or (fourth shl 24)
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
        val requireOnDevice = pendingPermissionRequireOnDevice
        pendingPermissionRequireOnDevice = false
        val locale = pendingPermissionLocale
        pendingPermissionLocale = defaultLocale

        if (pendingResult == null) {
            return true
        }

        if (
            grantResults.firstOrNull() ==
                PackageManager.PERMISSION_GRANTED
        ) {
            startRecognizer(
                pendingResult,
                commandMode,
                preferOnDevice,
                requireOnDevice,
                locale,
            )
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
        if (pendingFileResult == null) emit("speech.ready")
    }

    override fun onBeginningOfSpeech() {
        if (pendingFileResult == null) emit("speech.begin")
    }

    override fun onRmsChanged(rmsdB: Float) {
        if (pendingFileResult != null) return
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
        if (pendingFileResult == null) emit("speech.end")
    }

    override fun onError(error: Int) {
        val wasRequiredOnDevice = activeRequireOnDevice
        Log.w(
            logTag,
            "Speech recognition failed: error=$error mode=$recognizerMode " +
                "requiredOnDevice=$wasRequiredOnDevice",
        )
        listening = false
        closeInjectedAudio()
        activeRequireOnDevice = false
        val pendingResult = pendingFileResult
        if (pendingResult != null) {
            pendingFileResult = null
            pendingResult.error(
                directRecognitionErrorCode(error, wasRequiredOnDevice),
                errorMessage(error),
                null,
            )
            return
        }
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
        activeRequireOnDevice = false
        val pendingResult = pendingFileResult
        if (pendingResult != null) {
            pendingFileResult = null
            pendingResult.success(resultPayload("speech.final", results))
            return
        }
        emitResult("speech.final", results)
    }

    override fun onPartialResults(partialResults: Bundle?) {
        if (pendingFileResult == null) emitResult("speech.partial", partialResults)
    }

    override fun onEvent(eventType: Int, params: Bundle?) = Unit

    private fun emitResult(type: String, bundle: Bundle?) {
        events?.success(resultPayload(type, bundle))
    }

    private fun resultPayload(type: String, bundle: Bundle?): MutableMap<String, Any> {
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
        return payload
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

    private fun directRecognitionErrorCode(
        error: Int,
        requiredOnDevice: Boolean,
    ): String =
        when (error) {
            SpeechRecognizer.ERROR_NO_MATCH -> "SPEECH_NO_MATCH"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "SPEECH_TIMEOUT"
            SpeechRecognizer.ERROR_AUDIO -> "RECORDED_AUDIO_FILE_INVALID"
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE,
            -> "ON_DEVICE_SPEECH_UNAVAILABLE"
            SpeechRecognizer.ERROR_NETWORK,
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
            SpeechRecognizer.ERROR_SERVER,
            SpeechRecognizer.ERROR_SERVER_DISCONNECTED,
            ->
                if (requiredOnDevice) {
                    "ON_DEVICE_SPEECH_UNAVAILABLE"
                } else {
                    "RECORDED_AUDIO_RECOGNITION_FAILED"
                }
            else -> "RECORDED_AUDIO_RECOGNITION_FAILED"
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
        pendingPermissionRequireOnDevice = false
        pendingPermissionLocale = defaultLocale
        recognitionGeneration += 1
        completePendingFileError(
            "SPEECH_DISPOSED",
            "Ứng dụng đã dừng trước khi nhận diện xong bản ghi âm.",
        )
        recognizer?.cancel()
        closeInjectedAudio()
        recognizer?.destroy()
        recognizer = null
        recognizerMode = null
        listening = false
        activeRequireOnDevice = false
        resetCapturedAudio()
        events = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private enum class RecognizerMode {
        STANDARD,
        ON_DEVICE,
    }

    private data class WavAudio(
        val dataOffset: Long,
        val dataLength: Long,
        val sampleRate: Int,
    )

    private companion object {
        const val microphonePermissionRequestCode = 4101
        const val defaultLocale = "vi-VN"
        const val capturedAudioSampleRate = 16000
        const val pcmWavAudioFormat = 1
        const val pcmBytesPerSample = 2
        const val wavHeaderBytes = 44
        const val minimumCapturedPcmBytes = 1600
        const val injectedAudioBufferBytes = 8192
        const val logTag = "HomiSpeech"
    }
}
