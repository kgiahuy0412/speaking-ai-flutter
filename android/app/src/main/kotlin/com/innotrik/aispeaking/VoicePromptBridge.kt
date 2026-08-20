package com.innotrik.aispeaking

import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class VoicePromptBridge(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler,
    TextToSpeech.OnInitListener {
    private data class PendingPrompt(
        val text: String,
        val locale: String,
        val completion: MethodChannel.Result?,
    )

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
    private var utteranceSequence = 0L

    init {
        methodChannel.setMethodCallHandler(this)
        textToSpeech = TextToSpeech(context.applicationContext, this)
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
                        completeAwaited(utteranceId)
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        completeAwaited(utteranceId, "TTS playback failed.")
                    }

                    override fun onStop(
                        utteranceId: String?,
                        interrupted: Boolean,
                    ) {
                        completeAwaited(utteranceId)
                    }
                },
            )
        }
        pendingPrompt?.let {
            speak(it.text, it.locale, completion = it.completion)
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
                if (text.isNotEmpty()) {
                    speak(text, locale.ifEmpty { "vi-VN" })
                }
                result.success(null)
            }
            "speakAndWait" -> {
                val text = call.argument<String>("text")?.trim().orEmpty()
                val locale = call.argument<String>("locale")?.trim().orEmpty()
                if (text.isEmpty()) {
                    result.success(null)
                } else {
                    speak(
                        text,
                        locale.ifEmpty { "vi-VN" },
                        completion = result,
                    )
                }
            }
            "playSpeechReadyCue" -> playSpeechReadyCue(result)
            "stop" -> {
                completePendingPrompt()
                completeActiveAwaited()
                completeReadyCue()
                textToSpeech?.stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun speak(
        text: String,
        localeTag: String,
        completion: MethodChannel.Result? = null,
    ) {
        if (!initialized) {
            completePendingPrompt()
            pendingPrompt = PendingPrompt(text, localeTag, completion)
            return
        }
        val engine = textToSpeech
        if (engine == null) {
            completion?.error("TTS_UNAVAILABLE", "Text to speech is unavailable.", null)
            return
        }
        completeReadyCue()
        completeActiveAwaited()
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
        val status =
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
        if (status == TextToSpeech.ERROR) {
            completeAwaited(utteranceId, "TTS playback failed.")
        }
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

    fun dispose() {
        completePendingPrompt()
        completeActiveAwaited()
        completeReadyCue()
        initialized = false
        methodChannel.setMethodCallHandler(null)
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        readyCueGenerator?.release()
        readyCueGenerator = null
    }
}
