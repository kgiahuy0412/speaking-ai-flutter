package com.innotrik.aispeaking

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.ToneGenerator
import android.media.audiofx.LoudnessEnhancer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import kotlin.math.roundToInt

class VoicePromptBridge(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler,
    TextToSpeech.OnInitListener {
    private data class PendingPrompt(
        val text: String,
        val locale: String,
        val gainDb: Double,
        val completion: MethodChannel.Result?,
    )

    private val appContext = context.applicationContext
    private val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val methodChannel = MethodChannel(messenger, "ailingo_voice_prompt")
    private val mainHandler = Handler(Looper.getMainLooper())
    private var textToSpeech: TextToSpeech? = null
    private var initialized = false
    private var pendingPrompt: PendingPrompt? = null
    private var awaitedUtteranceId: String? = null
    private var awaitedResult: MethodChannel.Result? = null
    private var readyCueGenerator: ToneGenerator? = null
    private var readyCueCompletion: Runnable? = null
    private var readyCueResult: MethodChannel.Result? = null
    private var synthesizedPromptId: String? = null
    private var synthesizedPromptFile: File? = null
    private var synthesizedPromptGainMillibels = 0
    private var promptPlaybackId: String? = null
    private var promptPlaybackFile: File? = null
    private var promptPlayer: MediaPlayer? = null
    private var promptLoudnessEnhancer: LoudnessEnhancer? = null
    private var utteranceSequence = 0L

    init {
        methodChannel.setMethodCallHandler(this)
        textToSpeech = TextToSpeech(appContext, this)
    }

    override fun onInit(status: Int) {
        initialized = status == TextToSpeech.SUCCESS
        if (!initialized) {
            pendingPrompt?.completion?.error(
                "TTS_UNAVAILABLE",
                "Text to speech is unavailable.",
                null,
            )
            pendingPrompt = null
            return
        }
        textToSpeech?.apply {
            setSpeechRate(0.92f)
            setOnUtteranceProgressListener(
                object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) = Unit

                    override fun onDone(utteranceId: String?) {
                        handleTtsDone(utteranceId)
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        handleTtsFailure(utteranceId, "TTS synthesis failed.")
                    }

                    override fun onStop(
                        utteranceId: String?,
                        interrupted: Boolean,
                    ) {
                        handleTtsStopped(utteranceId)
                    }
                },
            )
        }
        pendingPrompt?.let {
            speak(it.text, it.locale, it.gainDb, completion = it.completion)
        }
        pendingPrompt = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "speak" -> {
                val text = call.argument<String>("text")?.trim().orEmpty()
                val locale = call.argument<String>("locale")?.trim().orEmpty()
                val gainDb = requestedGainDb(call)
                if (text.isNotEmpty()) {
                    speak(text, locale.ifEmpty { "vi-VN" }, gainDb,
                        assetPath = call.argument<String>("assetPath"),
                        filePath = call.argument<String>("filePath"))
                }
                result.success(null)
            }
            "speakAndWait" -> {
                val text = call.argument<String>("text")?.trim().orEmpty()
                val locale = call.argument<String>("locale")?.trim().orEmpty()
                val gainDb = requestedGainDb(call)
                if (text.isEmpty()) {
                    result.success(null)
                } else {
                    speak(
                        text,
                        locale.ifEmpty { "vi-VN" },
                        gainDb,
                        completion = result,
                        assetPath = call.argument<String>("assetPath"),
                        filePath = call.argument<String>("filePath"),
                    )
                }
            }
            "playSpeechReadyCue" -> playSpeechReadyCue(result)
            "stop" -> {
                completePendingPrompt()
                completeActiveAwaited()
                completeReadyCue()
                textToSpeech?.stop()
                clearSynthesizedPrompt()
                releasePromptPlayback()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun speak(
        text: String,
        localeTag: String,
        gainDb: Double,
        completion: MethodChannel.Result? = null,
        assetPath: String? = null,
        filePath: String? = null,
    ) {
        if (filePath != null) {
            playRecordedPrompt(null, text, localeTag, gainDb, completion, filePath)
            return
        }
        if (assetPath != null && assetPath.startsWith("assets/audio/") && !assetPath.contains("..")) {
            playRecordedPrompt(assetPath, text, localeTag, gainDb, completion)
            return
        }
        if (!initialized) {
            completePendingPrompt()
            pendingPrompt = PendingPrompt(text, localeTag, gainDb, completion)
            return
        }
        val engine = textToSpeech
        if (engine == null) {
            completion?.error("TTS_UNAVAILABLE", "Text to speech is unavailable.", null)
            return
        }
        completeReadyCue()
        completeActiveAwaited()
        engine.stop()
        clearSynthesizedPrompt()
        releasePromptPlayback()
        val requestedLocale = Locale.forLanguageTag(localeTag)
        val languageResult = engine.setLanguage(requestedLocale)
        if (
            languageResult == TextToSpeech.LANG_MISSING_DATA ||
                languageResult == TextToSpeech.LANG_NOT_SUPPORTED
        ) {
            engine.setLanguage(Locale("vi", "VN"))
        }
        utteranceSequence += 1
        val utteranceId = "voice-prompt-$utteranceSequence"
        if (completion != null) {
            awaitedUtteranceId = utteranceId
            awaitedResult = completion
        }
        val speechParameters = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
        }
        val outputFile = File(appContext.cacheDir, "$utteranceId.wav")
        outputFile.delete()
        synthesizedPromptId = utteranceId
        synthesizedPromptFile = outputFile
        synthesizedPromptGainMillibels = (gainDb * 100.0).roundToInt()
        val status =
            engine.synthesizeToFile(text, speechParameters, outputFile, utteranceId)
        if (status == TextToSpeech.ERROR) {
            clearSynthesizedPrompt()
            // Keep prompts functional on TTS engines that do not implement
            // file synthesis, although this fallback cannot receive the boost.
            engine.setAudioAttributes(promptAudioAttributes())
            val fallbackStatus =
                engine.speak(text, TextToSpeech.QUEUE_FLUSH, speechParameters, utteranceId)
            if (fallbackStatus == TextToSpeech.ERROR) {
                completeAwaited(utteranceId, "TTS playback failed.")
            }
        }
    }

    private fun requestedGainDb(call: MethodCall): Double =
        (call.argument<Number>("gainDb")?.toDouble() ?: 8.0).coerceIn(0.0, 12.0)

    private fun promptAudioAttributes(): AudioAttributes {
        // Match lesson playback's media volume on the phone, while retaining
        // the communication stream when an H20/HFP session already owns it.
        @Suppress("DEPRECATION")
        val communicationActive = audioManager.isBluetoothScoOn ||
            audioManager.mode == AudioManager.MODE_IN_COMMUNICATION ||
            audioManager.mode == AudioManager.MODE_IN_CALL
        return AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .setUsage(
                if (communicationActive) AudioAttributes.USAGE_VOICE_COMMUNICATION
                else AudioAttributes.USAGE_MEDIA,
            )
            .build()
    }

    private fun applyPromptGain(player: MediaPlayer, gainMillibels: Int) {
        promptLoudnessEnhancer?.release()
        promptLoudnessEnhancer = try {
            LoudnessEnhancer(player.audioSessionId).apply {
                setTargetGain(gainMillibels)
                enabled = true
            }
        } catch (_: RuntimeException) {
            // Some devices do not implement this optional audio effect.
            null
        }
    }

    // Recorded MP3s share the lesson/TTS gain and output stream, including
    // H20/HFP, and complete only when playback actually finishes.
    private fun playRecordedPrompt(
        assetPath: String?,
        text: String,
        localeTag: String,
        gainDb: Double,
        completion: MethodChannel.Result?,
        filePath: String? = null,
    ) {
        completePendingPrompt()
        completeReadyCue()
        completeActiveAwaited()
        textToSpeech?.stop()
        clearSynthesizedPrompt()
        releasePromptPlayback()
        val utteranceId = "recorded-prompt-${++utteranceSequence}"
        if (completion != null) {
            awaitedUtteranceId = utteranceId
            awaitedResult = completion
        }
        val player = MediaPlayer()
        promptPlaybackId = utteranceId
        promptPlayer = player
        fun fallbackToDeviceVoice() {
            if (promptPlaybackId != utteranceId) return
            val pending = if (awaitedUtteranceId == utteranceId) awaitedResult else null
            if (awaitedUtteranceId == utteranceId) {
                awaitedUtteranceId = null
                awaitedResult = null
            }
            releasePromptPlayback()
            speak(text, localeTag, gainDb, completion = pending)
        }
        try {
            player.setAudioAttributes(promptAudioAttributes())
            if (filePath != null) {
                val file = File(filePath).canonicalFile
                val audioDirectory = File(appContext.filesDir, "rule_audio_cache").canonicalFile
                require(file.path.startsWith(audioDirectory.path + File.separator) && file.isFile)
                player.setDataSource(file.path)
            } else {
                val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(requireNotNull(assetPath))
                appContext.assets.openFd(key).use { asset ->
                    player.setDataSource(asset.fileDescriptor, asset.startOffset, asset.length)
                }
            }
            player.setVolume(1.0f, 1.0f)
            player.setOnPreparedListener { ready ->
                if (promptPlayer !== ready || promptPlaybackId != utteranceId) return@setOnPreparedListener
                applyPromptGain(ready, (gainDb * 100.0).roundToInt())
                try { ready.start() } catch (_: RuntimeException) { fallbackToDeviceVoice() }
            }
            player.setOnCompletionListener {
                mainHandler.post { finishPromptPlayback(utteranceId) }
            }
            player.setOnErrorListener { _, _, _ ->
                mainHandler.post { fallbackToDeviceVoice() }
                true
            }
            player.prepareAsync()
        } catch (_: Exception) {
            fallbackToDeviceVoice()
        }
    }

    private fun handleTtsDone(utteranceId: String?) {
        mainHandler.post {
            if (utteranceId != null && utteranceId == synthesizedPromptId) {
                playSynthesizedPrompt(utteranceId)
            } else {
                completeAwaited(utteranceId)
            }
        }
    }

    private fun handleTtsFailure(
        utteranceId: String?,
        error: String,
    ) {
        mainHandler.post {
            if (utteranceId != null && utteranceId == synthesizedPromptId) {
                clearSynthesizedPrompt()
            }
            completeAwaited(utteranceId, error)
        }
    }

    private fun handleTtsStopped(utteranceId: String?) {
        mainHandler.post {
            if (utteranceId != null && utteranceId == synthesizedPromptId) {
                clearSynthesizedPrompt()
            }
            completeAwaited(utteranceId)
        }
    }

    private fun playSynthesizedPrompt(utteranceId: String) {
        if (utteranceId != synthesizedPromptId) {
            return
        }
        val audioFile = synthesizedPromptFile
        val gainMillibels = synthesizedPromptGainMillibels
        synthesizedPromptId = null
        synthesizedPromptFile = null
        synthesizedPromptGainMillibels = 0
        if (audioFile == null || !audioFile.exists() || audioFile.length() == 0L) {
            audioFile?.delete()
            completeAwaited(utteranceId, "TTS produced no playable audio.")
            return
        }

        releasePromptPlayback()
        val player = MediaPlayer()
        promptPlaybackId = utteranceId
        promptPlaybackFile = audioFile
        promptPlayer = player
        try {
            player.setAudioAttributes(promptAudioAttributes())
            player.setDataSource(audioFile.absolutePath)
            player.setVolume(1.0f, 1.0f)
            player.setOnPreparedListener { preparedPlayer ->
                if (promptPlayer !== preparedPlayer || promptPlaybackId != utteranceId) {
                    return@setOnPreparedListener
                }
                applyPromptGain(preparedPlayer, gainMillibels)
                preparedPlayer.start()
            }
            player.setOnCompletionListener {
                mainHandler.post { finishPromptPlayback(utteranceId) }
            }
            player.setOnErrorListener { _, _, _ ->
                mainHandler.post {
                    finishPromptPlayback(utteranceId, "TTS playback failed.")
                }
                true
            }
            player.prepareAsync()
        } catch (error: Exception) {
            finishPromptPlayback(
                utteranceId,
                error.message ?: "TTS playback failed.",
            )
        }
    }

    private fun finishPromptPlayback(
        utteranceId: String,
        error: String? = null,
    ) {
        if (utteranceId != promptPlaybackId) {
            return
        }
        releasePromptPlayback()
        completeAwaited(utteranceId, error)
    }

    private fun clearSynthesizedPrompt() {
        synthesizedPromptId = null
        synthesizedPromptGainMillibels = 0
        synthesizedPromptFile?.delete()
        synthesizedPromptFile = null
    }

    private fun releasePromptPlayback() {
        promptPlaybackId = null
        promptLoudnessEnhancer?.release()
        promptLoudnessEnhancer = null
        promptPlayer?.release()
        promptPlayer = null
        promptPlaybackFile?.delete()
        promptPlaybackFile = null
    }

    private fun completeAwaited(
        utteranceId: String?,
        error: String? = null,
    ) {
        mainHandler.post {
            if (utteranceId == null || utteranceId != awaitedUtteranceId) {
                return@post
            }
            val completion = awaitedResult
            awaitedUtteranceId = null
            awaitedResult = null
            if (error == null) {
                completion?.success(null)
            } else {
                completion?.error("TTS_PLAYBACK_FAILED", error, null)
            }
        }
    }

    private fun completePendingPrompt() {
        pendingPrompt?.completion?.success(null)
        pendingPrompt = null
    }

    private fun completeActiveAwaited() {
        val completion = awaitedResult
        awaitedUtteranceId = null
        awaitedResult = null
        completion?.success(null)
    }

    private fun playSpeechReadyCue(result: MethodChannel.Result) {
        completeReadyCue()
        val generator = try {
            readyCueGenerator ?: ToneGenerator(AudioManager.STREAM_MUSIC, 85).also {
                readyCueGenerator = it
            }
        } catch (error: RuntimeException) {
            result.error("READY_CUE_UNAVAILABLE", error.message, null)
            return
        }
        if (!generator.startTone(ToneGenerator.TONE_PROP_BEEP, 170)) {
            result.error("READY_CUE_UNAVAILABLE", "Unable to play the ready cue.", null)
            return
        }
        readyCueResult = result
        // Include a short gap so the microphone never records the tail of the tone.
        val completion = Runnable { completeReadyCue() }
        readyCueCompletion = completion
        mainHandler.postDelayed(completion, 260L)
    }

    private fun completeReadyCue() {
        readyCueCompletion?.let(mainHandler::removeCallbacks)
        readyCueCompletion = null
        readyCueGenerator?.stopTone()
        val completion = readyCueResult
        readyCueResult = null
        completion?.success(null)
    }

    fun stopForBackgroundSession() {
        mainHandler.post {
            completePendingPrompt()
            completeActiveAwaited()
            completeReadyCue()
            textToSpeech?.stop()
            clearSynthesizedPrompt()
            releasePromptPlayback()
        }
    }

    fun dispose() {
        completePendingPrompt()
        completeActiveAwaited()
        completeReadyCue()
        textToSpeech?.stop()
        clearSynthesizedPrompt()
        releasePromptPlayback()
        initialized = false
        methodChannel.setMethodCallHandler(null)
        textToSpeech?.shutdown()
        textToSpeech = null
        readyCueGenerator?.release()
        readyCueGenerator = null
    }
}
