package com.innotrik.aispeaking

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.ToneGenerator
import android.media.audiofx.LoudnessEnhancer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import kotlin.math.roundToInt

class VoicePromptBridge(
    context: Context,
    messenger: BinaryMessenger,
    private val hfpAudioBridge: HfpAudioBridge? = null,
) : MethodChannel.MethodCallHandler,
    TextToSpeech.OnInitListener {
    private companion object {
        private const val TAG = "HomiPromptAudio"
        private const val EXTERNAL_AUDIO_DRAIN_MS = 350L
        private const val COMMUNICATION_ROUTE_SETTLE_MS = 300L
        private const val PROMPT_TO_MIC_HANDOFF_GRACE_MS = 750L
    }

    private data class PendingPrompt(
        val text: String,
        val locale: String,
        val gainDb: Double,
        val forceSelectedOutput: Boolean,
        val completion: MethodChannel.Result?,
    )

    private val appContext = context.applicationContext
    private val methodChannel = MethodChannel(messenger, "ailingo_voice_prompt")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val audioManager =
        appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val promptAudioFocusListener =
        AudioManager.OnAudioFocusChangeListener { change ->
            mainHandler.post { handlePromptAudioFocusChange(change) }
        }
    private var textToSpeech: TextToSpeech? = null
    private var initialized = false
    private var pendingPrompt: PendingPrompt? = null
    private var awaitedUtteranceId: String? = null
    private var awaitedResult: MethodChannel.Result? = null
    private var readyCueGenerator: ToneGenerator? = null
    private var readyCueCompletion: Runnable? = null
    private var readyCueResult: MethodChannel.Result? = null
    private var readyCueSequence = 0L
    private var synthesizedPromptId: String? = null
    private var synthesizedPromptFile: File? = null
    private var synthesizedPromptGainMillibels = 0
    private var synthesizedPromptForceSelectedOutput = false
    private var promptPlaybackId: String? = null
    private var promptPlaybackFile: File? = null
    private var promptPlayer: MediaPlayer? = null
    private var promptLoudnessEnhancer: LoudnessEnhancer? = null
    private var promptAudioFocusRequest: AudioFocusRequest? = null
    private var promptAudioFocusRequested = false
    private var promptHasAudioFocus = false
    private var promptPrepared = false
    private var promptPausedForFocusLoss = false
    private var promptForceSelectedOutput = false
    private var promptFocusResumeCheck: Runnable? = null
    private var promptRouteActivation: Runnable? = null
    private var promptAudioSessionRelease: Runnable? = null
    private var promptRouteReady = false
    private var promptPlaybackStarted = false
    private var promptMutedUncooperativeMedia = false
    private var promptOwnsCommunicationRoute = false
    private var promptFocusHandedOff = false
    private var promptPreviousAudioMode = AudioManager.MODE_NORMAL
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
            speak(
                it.text,
                it.locale,
                it.gainDb,
                forceSelectedOutput = it.forceSelectedOutput,
                completion = it.completion,
            )
        }
        pendingPrompt = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "beginMainTurn" -> {
                result.success(hfpAudioBridge?.beginMainTurn())
            }
            "endMainTurn" -> {
                hfpAudioBridge?.endMainTurn(call.argument<String>("turnId"))
                result.success(null)
            }
            "speak" -> {
                val text = call.argument<String>("text")?.trim().orEmpty()
                val locale = call.argument<String>("locale")?.trim().orEmpty()
                val gainDb = requestedGainDb(call)
                val forceSelectedOutput = call.argument<Boolean>("forceMediaPlayback") == true
                if (text.isNotEmpty()) {
                    speak(
                        text,
                        locale.ifEmpty { "vi-VN" },
                        gainDb,
                        forceSelectedOutput = forceSelectedOutput,
                    )
                }
                result.success(null)
            }
            "speakAndWait" -> {
                val text = call.argument<String>("text")?.trim().orEmpty()
                val locale = call.argument<String>("locale")?.trim().orEmpty()
                val gainDb = requestedGainDb(call)
                val forceSelectedOutput = call.argument<Boolean>("forceMediaPlayback") == true
                if (text.isEmpty()) {
                    result.success(null)
                } else {
                    speak(
                        text,
                        locale.ifEmpty { "vi-VN" },
                        gainDb,
                        forceSelectedOutput = forceSelectedOutput,
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
        forceSelectedOutput: Boolean = false,
        completion: MethodChannel.Result? = null,
    ) {
        if (!initialized) {
            completePendingPrompt()
            pendingPrompt = PendingPrompt(
                text,
                localeTag,
                gainDb,
                forceSelectedOutput,
                completion,
            )
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
        synthesizedPromptForceSelectedOutput = forceSelectedOutput
        val status =
            engine.synthesizeToFile(text, speechParameters, outputFile, utteranceId)
        if (status == TextToSpeech.ERROR) {
            val useSelectedOutput = synthesizedPromptForceSelectedOutput
            clearSynthesizedPrompt()
            // Keep prompts functional on TTS engines that do not implement
            // file synthesis, although this fallback cannot receive the boost.
            preparePromptCommunicationRoute(useSelectedOutput)
            val fallbackStatus =
                engine.speak(text, TextToSpeech.QUEUE_FLUSH, speechParameters, utteranceId)
            if (fallbackStatus == TextToSpeech.ERROR) {
                releasePromptCommunicationRoute()
                completeAwaited(utteranceId, "TTS playback failed.")
            }
        }
    }

    private fun requestedGainDb(call: MethodCall): Double =
        (call.argument<Number>("gainDb")?.toDouble() ?: 8.0).coerceIn(0.0, 12.0)

    private fun handleTtsDone(utteranceId: String?) {
        mainHandler.post {
            if (utteranceId != null && utteranceId == synthesizedPromptId) {
                playSynthesizedPrompt(utteranceId)
            } else {
                releasePromptCommunicationRoute()
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
            releasePromptCommunicationRoute()
            completeAwaited(utteranceId, error)
        }
    }

    private fun handleTtsStopped(utteranceId: String?) {
        mainHandler.post {
            if (utteranceId != null && utteranceId == synthesizedPromptId) {
                clearSynthesizedPrompt()
            }
            releasePromptCommunicationRoute()
            completeAwaited(utteranceId)
        }
    }

    private fun playSynthesizedPrompt(utteranceId: String) {
        if (utteranceId != synthesizedPromptId) {
            return
        }
        val audioFile = synthesizedPromptFile
        val gainMillibels = synthesizedPromptGainMillibels
        val forceSelectedOutput = synthesizedPromptForceSelectedOutput
        synthesizedPromptId = null
        synthesizedPromptFile = null
        synthesizedPromptGainMillibels = 0
        synthesizedPromptForceSelectedOutput = false
        if (audioFile == null || !audioFile.exists() || audioFile.length() == 0L) {
            audioFile?.delete()
            completeAwaited(utteranceId, "TTS produced no playable audio.")
            return
        }

        val reuseRetainedAudioSession =
            forceSelectedOutput &&
                promptOwnsCommunicationRoute &&
                promptHasAudioFocus &&
                !promptFocusHandedOff
        if (reuseRetainedAudioSession) {
            cancelPromptAudioSessionRelease()
        }
        releasePromptPlayback(releaseAudioSession = !reuseRetainedAudioSession)
        val player = MediaPlayer()
        promptPlaybackId = utteranceId
        promptPlaybackFile = audioFile
        promptPlayer = player
        promptPrepared = false
        promptPausedForFocusLoss = false
        promptForceSelectedOutput = forceSelectedOutput
        promptRouteReady = false
        promptPlaybackStarted = false
        try {
            player.setAudioAttributes(promptAudioAttributes())
            player.setDataSource(audioFile.absolutePath)
            player.setVolume(1.0f, 1.0f)
            player.setOnPreparedListener { preparedPlayer ->
                if (promptPlayer !== preparedPlayer || promptPlaybackId != utteranceId) {
                    return@setOnPreparedListener
                }
                promptPrepared = true
                promptLoudnessEnhancer = try {
                    LoudnessEnhancer(preparedPlayer.audioSessionId).apply {
                        setTargetGain(gainMillibels)
                        enabled = true
                    }
                } catch (_: RuntimeException) {
                    null
                }
                startPromptWhenReady(preparedPlayer)
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
            if (!requestPromptAudioFocus()) {
                finishPromptPlayback(
                    utteranceId,
                    "Another application currently owns audio playback.",
                )
                return
            }
            // Decode the local WAV while the previous foreground app drains.
            // MediaPlayer does not emit audio until start(), so this work is safe
            // before SCO is selected and avoids adding needless prompt latency.
            player.prepareAsync()
            schedulePromptRouteActivation(utteranceId, player)
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
        val retainForMicrophone =
            error == null &&
                promptForceSelectedOutput &&
                promptOwnsCommunicationRoute &&
                promptHasAudioFocus &&
                !promptFocusHandedOff
        releasePromptPlayback(releaseAudioSession = !retainForMicrophone)
        if (retainForMicrophone) {
            schedulePromptAudioSessionRelease()
        }
        completeAwaited(utteranceId, error)
    }

    private fun clearSynthesizedPrompt() {
        synthesizedPromptId = null
        synthesizedPromptGainMillibels = 0
        synthesizedPromptForceSelectedOutput = false
        synthesizedPromptFile?.delete()
        synthesizedPromptFile = null
    }

    private fun releasePromptPlayback(releaseAudioSession: Boolean = true) {
        promptPlaybackId = null
        promptPrepared = false
        promptPausedForFocusLoss = false
        promptForceSelectedOutput = false
        promptRouteReady = false
        promptPlaybackStarted = false
        promptFocusResumeCheck?.let(mainHandler::removeCallbacks)
        promptFocusResumeCheck = null
        promptRouteActivation?.let(mainHandler::removeCallbacks)
        promptRouteActivation = null
        promptLoudnessEnhancer?.release()
        promptLoudnessEnhancer = null
        promptPlayer?.release()
        promptPlayer = null
        promptPlaybackFile?.delete()
        promptPlaybackFile = null
        if (releaseAudioSession && !promptFocusHandedOff) {
            cancelPromptAudioSessionRelease()
            // Restore the phone route before returning focus. Otherwise the previous
            // app can resume during the short interval in which H20 SCO is still the
            // system communication output.
            releasePromptCommunicationRoute()
            abandonPromptAudioFocus()
            restoreUncooperativeMediaAudio()
        }
    }

    private fun schedulePromptAudioSessionRelease() {
        cancelPromptAudioSessionRelease()
        lateinit var release: Runnable
        release = Runnable {
            if (promptAudioSessionRelease === release) {
                promptAudioSessionRelease = null
            }
            if (!promptFocusHandedOff) {
                releasePromptCommunicationRoute()
                abandonPromptAudioFocus()
                restoreUncooperativeMediaAudio()
                Log.d(TAG, "prompt HFP/SCO handoff grace expired")
            }
        }
        promptAudioSessionRelease = release
        mainHandler.postDelayed(release, PROMPT_TO_MIC_HANDOFF_GRACE_MS)
    }

    private fun cancelPromptAudioSessionRelease() {
        promptAudioSessionRelease?.let(mainHandler::removeCallbacks)
        promptAudioSessionRelease = null
    }

    private fun promptAudioAttributes(): AudioAttributes =
        AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .build()

    /**
     * Uses transient exclusive focus for assistant speech. If another
     * foreground app starts media afterwards, Android sends us a
     * transient loss: the prompt pauses and resumes only after focus returns.
     * This prevents phone media and the H20 prompt from being mixed together.
     */
    private fun requestPromptAudioFocus(): Boolean {
        if (promptAudioFocusRequested && promptHasAudioFocus && !promptFocusHandedOff) {
            return true
        }
        abandonPromptAudioFocus()
        val result =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val request =
                    AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                        .setAudioAttributes(promptAudioAttributes())
                        .setWillPauseWhenDucked(true)
                        .setOnAudioFocusChangeListener(promptAudioFocusListener, mainHandler)
                        .build()
                promptAudioFocusRequest = request
                audioManager.requestAudioFocus(request)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    promptAudioFocusListener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE,
                )
            }
        promptAudioFocusRequested = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        promptHasAudioFocus = promptAudioFocusRequested
        if (!promptAudioFocusRequested) {
            promptAudioFocusRequest = null
        }
        Log.d(
            TAG,
            "focus request result=$result granted=$promptAudioFocusRequested " +
                "musicActive=${audioManager.isMusicActive}",
        )
        return promptAudioFocusRequested
    }

    private fun handlePromptAudioFocusChange(change: Int) {
        val player = promptPlayer
        if (player == null) {
            if (
                change == AudioManager.AUDIOFOCUS_LOSS ||
                change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT ||
                change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK
            ) {
                promptHasAudioFocus = false
                if (promptOwnsCommunicationRoute && !promptFocusHandedOff) {
                    cancelPromptAudioSessionRelease()
                    releasePromptCommunicationRoute()
                    abandonPromptAudioFocus()
                    restoreUncooperativeMediaAudio()
                }
            }
            return
        }
        Log.d(TAG, "focus changed=$change prepared=$promptPrepared started=$promptPlaybackStarted")
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                promptHasAudioFocus = true
                schedulePromptRouteActivation(promptPlaybackId ?: return, player)
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK,
            -> {
                promptHasAudioFocus = false
                promptPausedForFocusLoss = true
                cancelPromptRouteActivation()
                if (promptPrepared) {
                    try {
                        if (player.isPlaying) player.pause()
                    } catch (_: IllegalStateException) {
                        // A simultaneous completion callback will clean up.
                    }
                }
                // SCO must not remain selected while another foreground app
                // owns media focus, otherwise that app can also be routed to
                // the H20 speaker instead of the phone.
                releasePromptCommunicationRoute()
                restoreUncooperativeMediaAudio()
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                promptHasAudioFocus = false
                promptAudioFocusRequested = false
                promptPausedForFocusLoss = true
                cancelPromptRouteActivation()
                if (promptPrepared) {
                    try {
                        if (player.isPlaying) player.pause()
                    } catch (_: IllegalStateException) {
                        // A simultaneous completion callback will clean up.
                    }
                }
                releasePromptCommunicationRoute()
                restoreUncooperativeMediaAudio()
                schedulePromptResumeAfterExternalMedia()
            }
        }
    }

    /**
     * Audio focus is acquired before this method runs. Give every well-behaved
     * media app a bounded window to pause and drain its output, then select SCO.
     * This is deliberately package-agnostic: Facebook, YouTube, Spotify, Zalo,
     * and future apps all follow the same Android AudioManager contract.
     */
    private fun schedulePromptRouteActivation(
        utteranceId: String,
        player: MediaPlayer,
    ) {
        cancelPromptRouteActivation()
        lateinit var activateRoute: Runnable
        activateRoute = Runnable {
            if (
                promptPlaybackId != utteranceId ||
                    promptPlayer !== player ||
                    !promptHasAudioFocus
            ) {
                return@Runnable
            }
            suppressUncooperativeMediaAudioIfNeeded()
            val routeChanged = preparePromptCommunicationRoute(promptForceSelectedOutput)
            lateinit var markReady: Runnable
            markReady = Runnable {
                if (promptRouteActivation === markReady) {
                    promptRouteActivation = null
                }
                if (
                    promptPlaybackId != utteranceId ||
                        promptPlayer !== player ||
                        !promptHasAudioFocus
                ) {
                    return@Runnable
                }
                promptRouteReady = true
                Log.d(
                    TAG,
                    "route ready changed=$routeChanged musicActive=${audioManager.isMusicActive}",
                )
                startPromptWhenReady(player)
            }
            promptRouteActivation = markReady
            if (routeChanged) {
                mainHandler.postDelayed(markReady, COMMUNICATION_ROUTE_SETTLE_MS)
            } else {
                markReady.run()
            }
        }
        promptRouteActivation = activateRoute
        val delay =
            if (promptOwnsCommunicationRoute && promptHasAudioFocus) 0L
            else EXTERNAL_AUDIO_DRAIN_MS
        mainHandler.postDelayed(activateRoute, delay)
    }

    private fun startPromptWhenReady(player: MediaPlayer) {
        if (
            promptPlayer !== player ||
                !promptPrepared ||
                !promptHasAudioFocus ||
                !promptRouteReady
        ) {
            return
        }
        if (promptPlaybackStarted && !promptPausedForFocusLoss) return
        val utteranceId = promptPlaybackId ?: return
        try {
            player.start()
            promptPlaybackStarted = true
            promptPausedForFocusLoss = false
            Log.d(TAG, "prompt started after focus and route handoff")
        } catch (_: IllegalStateException) {
            finishPromptPlayback(utteranceId, "Unable to start assistant audio.")
        }
    }

    private fun cancelPromptRouteActivation() {
        promptRouteActivation?.let(mainHandler::removeCallbacks)
        promptRouteActivation = null
        promptRouteReady = false
    }

    /**
     * Some media players keep rendering after Android grants exclusive focus.
     * Muting only STREAM_MUSIC is the final package-agnostic guard: calls,
     * alarms, and HOMI's communication stream remain unaffected. An existing
     * user mute is preserved because this bridge only restores its own mute.
     */
    private fun suppressUncooperativeMediaAudioIfNeeded() {
        if (
            promptMutedUncooperativeMedia ||
                !audioManager.isMusicActive ||
                audioManager.isStreamMute(AudioManager.STREAM_MUSIC)
        ) {
            return
        }
        try {
            audioManager.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                AudioManager.ADJUST_MUTE,
                0,
            )
            promptMutedUncooperativeMedia =
                audioManager.isStreamMute(AudioManager.STREAM_MUSIC)
            Log.d(TAG, "fallback media mute applied=$promptMutedUncooperativeMedia")
        } catch (error: SecurityException) {
            Log.w(TAG, "permission denied while muting uncooperative media", error)
        } catch (error: RuntimeException) {
            Log.w(TAG, "unable to mute uncooperative media", error)
        }
    }

    private fun restoreUncooperativeMediaAudio() {
        if (!promptMutedUncooperativeMedia) return
        promptMutedUncooperativeMedia = false
        try {
            audioManager.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                AudioManager.ADJUST_UNMUTE,
                0,
            )
            Log.d(TAG, "fallback media mute restored after prompt route release")
        } catch (error: SecurityException) {
            Log.w(TAG, "permission denied while restoring media mute", error)
        } catch (error: RuntimeException) {
            Log.w(TAG, "unable to restore media mute", error)
        }
    }

    /**
     * Some apps (including Facebook on this Xiaomi build) request permanent
     * GAIN even for a short video. Android then removes HOMI from the focus
     * stack and never sends a later GAIN callback. Poll the public global media
     * activity signal without stealing focus; only request focus and resume
     * after external media is no longer active.
     */
    private fun schedulePromptResumeAfterExternalMedia() {
        val utteranceId = promptPlaybackId ?: return
        promptFocusResumeCheck?.let(mainHandler::removeCallbacks)
        lateinit var check: Runnable
        check = Runnable {
            if (
                promptPlaybackId != utteranceId ||
                    !promptPausedForFocusLoss ||
                    promptPlayer == null
            ) {
                if (promptFocusResumeCheck === check) {
                    promptFocusResumeCheck = null
                }
                return@Runnable
            }
            if (audioManager.isMusicActive) {
                mainHandler.postDelayed(check, 500L)
                return@Runnable
            }
            if (requestPromptAudioFocus()) {
                promptPlayer?.let { player ->
                    schedulePromptRouteActivation(utteranceId, player)
                }
                if (promptFocusResumeCheck === check) {
                    promptFocusResumeCheck = null
                }
            } else {
                mainHandler.postDelayed(check, 500L)
            }
        }
        promptFocusResumeCheck = check
        mainHandler.postDelayed(check, 500L)
    }

    private fun abandonPromptAudioFocus() {
        if (!promptAudioFocusRequested && promptAudioFocusRequest == null) {
            promptHasAudioFocus = false
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            promptAudioFocusRequest?.let(audioManager::abandonAudioFocusRequest)
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(promptAudioFocusListener)
        }
        promptAudioFocusRequest = null
        promptAudioFocusRequested = false
        promptHasAudioFocus = false
        Log.d(TAG, "focus abandoned")
    }

    /**
     * Opens HFP/SCO only for a HOMI prompt that explicitly targets the selected
     * two-way output. Ordinary media remains on the phone because A2DP can stay
     * disabled for H20 in system settings.
     */
    private fun preparePromptCommunicationRoute(forceSelectedOutput: Boolean): Boolean {
        if (!forceSelectedOutput || promptOwnsCommunicationRoute) return false
        promptPreviousAudioMode = audioManager.mode
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alreadyRouted =
                audioManager.communicationDevice?.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            if (alreadyRouted) {
                false
            } else {
                val bluetoothSco =
                    audioManager.availableCommunicationDevices.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO &&
                            it.productName?.toString()?.contains("H20", ignoreCase = true) == true
                    } ?: audioManager.availableCommunicationDevices.firstOrNull {
                        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                    }
                if (bluetoothSco == null) {
                    false
                } else {
                    audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                    val routed = audioManager.setCommunicationDevice(bluetoothSco)
                    if (routed) {
                        promptOwnsCommunicationRoute = true
                        Log.d(TAG, "HFP/SCO route selected for assistant prompt")
                    } else {
                        audioManager.mode = promptPreviousAudioMode
                    }
                    routed
                }
            }
        } else {
            @Suppress("DEPRECATION")
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            @Suppress("DEPRECATION")
            audioManager.startBluetoothSco()
            @Suppress("DEPRECATION")
            run { audioManager.isBluetoothScoOn = true }
            promptOwnsCommunicationRoute = true
            true
        }
    }

    private fun releasePromptCommunicationRoute() {
        if (!promptOwnsCommunicationRoute) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION")
            audioManager.stopBluetoothSco()
            @Suppress("DEPRECATION")
            run { audioManager.isBluetoothScoOn = false }
        }
        audioManager.mode = promptPreviousAudioMode
        promptOwnsCommunicationRoute = false
        Log.d(TAG, "HFP/SCO route released before focus handback")
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
        val routeControl = hfpAudioBridge
        var adoptedPromptRoute = false
        if (
            routeControl != null &&
                promptOwnsCommunicationRoute &&
                promptAudioFocusRequested &&
                !promptFocusHandedOff
        ) {
            cancelPromptAudioSessionRelease()
            adoptedPromptRoute = routeControl.adoptPromptRouteForMicrophone(
                previousMode = promptPreviousAudioMode,
                releasePromptFocus = {
                    mainHandler.post {
                        promptFocusHandedOff = false
                        abandonPromptAudioFocus()
                        restoreUncooperativeMediaAudio()
                        Log.d(TAG, "prompt audio focus released after microphone turn")
                    }
                },
            )
            if (adoptedPromptRoute) {
                promptOwnsCommunicationRoute = false
                promptFocusHandedOff = true
                Log.d(TAG, "prompt HFP/SCO route handed directly to microphone")
            }
        }
        if (!adoptedPromptRoute && promptOwnsCommunicationRoute) {
            cancelPromptAudioSessionRelease()
            releasePromptCommunicationRoute()
            abandonPromptAudioFocus()
            restoreUncooperativeMediaAudio()
        }
        if (routeControl?.armReadyCue() == true) {
            // This is only a child-facing "your turn" notification. The HFP
            // bridge emits it once the actual microphone route is confirmed.
            result.success(null)
            return
        }
        val cueSequence = ++readyCueSequence
        readyCueResult = result
        startReadyCueTone(cueSequence, useHfpRoute = false)
    }

    private fun startReadyCueTone(
        cueSequence: Long,
        useHfpRoute: Boolean,
    ) {
        if (cueSequence != readyCueSequence || readyCueResult == null) return
        val stream = if (useHfpRoute) {
            AudioManager.STREAM_VOICE_CALL
        } else {
            AudioManager.STREAM_MUSIC
        }
        val generator = try {
            ToneGenerator(stream, if (useHfpRoute) 100 else 85).also {
                readyCueGenerator = it
            }
        } catch (error: RuntimeException) {
            val completion = readyCueResult
            readyCueResult = null
            hfpAudioBridge?.cancelArmedReadyCue()
            completion?.error("READY_CUE_UNAVAILABLE", error.message, null)
            return
        }
        if (!generator.startTone(ToneGenerator.TONE_PROP_BEEP, 170)) {
            generator.release()
            readyCueGenerator = null
            val completion = readyCueResult
            readyCueResult = null
            hfpAudioBridge?.cancelArmedReadyCue()
            completion?.error(
                "READY_CUE_UNAVAILABLE",
                "Unable to play the ready cue.",
                null,
            )
            return
        }
        Log.d(TAG, "ready cue started route=${if (useHfpRoute) "HFP/SCO" else "system"}")
        // Include a short gap so the microphone never records the tail of the tone.
        val completion = Runnable {
            completeReadyCue(
                expectedSequence = cueSequence,
                releasePreparedHfpRoute = !useHfpRoute,
            )
        }
        readyCueCompletion = completion
        mainHandler.postDelayed(completion, 230L)
    }

    private fun completeReadyCue(
        expectedSequence: Long? = null,
        releasePreparedHfpRoute: Boolean = true,
    ) {
        if (expectedSequence != null && expectedSequence != readyCueSequence) return
        readyCueCompletion?.let(mainHandler::removeCallbacks)
        readyCueCompletion = null
        readyCueGenerator?.stopTone()
        readyCueGenerator?.release()
        readyCueGenerator = null
        if (releasePreparedHfpRoute) {
            hfpAudioBridge?.cancelArmedReadyCue()
        }
        val completion = readyCueResult
        readyCueResult = null
        completion?.success(null)
        if (!releasePreparedHfpRoute) {
            Log.d(TAG, "ready cue finished; HFP/SCO reserved for microphone handoff")
        }
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
    }
}
