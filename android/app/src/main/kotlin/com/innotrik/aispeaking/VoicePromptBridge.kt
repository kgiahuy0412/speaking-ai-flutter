package com.innotrik.aispeaking

import android.content.Context
import android.speech.tts.TextToSpeech
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class VoicePromptBridge(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler,
    TextToSpeech.OnInitListener {
    private val methodChannel = MethodChannel(messenger, "ailingo_voice_prompt")
    private var textToSpeech: TextToSpeech? = null
    private var initialized = false
    private var pendingPrompt: Pair<String, String>? = null

    init {
        methodChannel.setMethodCallHandler(this)
        textToSpeech = TextToSpeech(context.applicationContext, this)
    }

    override fun onInit(status: Int) {
        initialized = status == TextToSpeech.SUCCESS
        if (!initialized) {
            pendingPrompt = null
            return
        }
        textToSpeech?.setSpeechRate(0.92f)
        pendingPrompt?.let { (text, locale) -> speak(text, locale) }
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
            "stop" -> {
                pendingPrompt = null
                textToSpeech?.stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun speak(
        text: String,
        localeTag: String,
    ) {
        if (!initialized) {
            pendingPrompt = text to localeTag
            return
        }
        val engine = textToSpeech ?: return
        val requestedLocale = Locale.forLanguageTag(localeTag)
        val languageResult = engine.setLanguage(requestedLocale)
        if (
            languageResult == TextToSpeech.LANG_MISSING_DATA ||
                languageResult == TextToSpeech.LANG_NOT_SUPPORTED
        ) {
            engine.setLanguage(Locale("vi", "VN"))
        }
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "asr-unclear-prompt")
    }

    fun dispose() {
        pendingPrompt = null
        initialized = false
        methodChannel.setMethodCallHandler(null)
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
    }
}
