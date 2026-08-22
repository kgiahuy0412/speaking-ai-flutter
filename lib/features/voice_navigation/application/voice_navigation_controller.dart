import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/device/active_learning_module.dart';
import 'main_voice_assistant_flow.dart';
import 'voice_navigation_intent_resolver.dart';

typedef VoiceNavigationIntentHandler =
    FutureOr<void> Function(VoiceNavigationIntent intent);
typedef ActiveLearningCommandHandler =
    FutureOr<ActiveLearningCommandResult> Function(
      ActiveLearningCommand command,
    );

/// Runs MAIN voice navigation independently from the conversation flow.
///
/// Android shares its platform recognizer with conversation recording. Web's
/// virtual MAIN supplies the same interface through Cloudflare Batch Chunks.
/// Neither path changes [ConversationController] state or forwards an
/// unmatched navigation command into the normal speaking result UI.
class VoiceNavigationController extends ChangeNotifier {
  VoiceNavigationController({
    required StreamingSpeechInput speechInput,
    VoiceNavigationIntentResolver resolver =
        const VoiceNavigationIntentResolver(),
    MainVoiceAssistantFlow? mainAssistantFlow,
    VoicePromptService? voicePromptService,
    bool ownsSpeechInput = false,
    bool ownsVoicePromptService = false,
    Duration restartDelay = const Duration(milliseconds: 300),
    Duration partialIntentDebounce = const Duration(milliseconds: 160),
    Duration commandWindowDuration = const Duration(seconds: 8),
    Duration speechReadyCueTimeout = const Duration(milliseconds: 900),
    Duration microphoneStartTimeout = const Duration(seconds: 15),
    Duration microphoneStartRetryDelay = const Duration(seconds: 2),
    ActiveLearningCommandHandler? activeLearningCommandHandler,
  }) : _speechInput = speechInput,
       _resolver = resolver,
       _mainAssistantFlow = mainAssistantFlow ?? MainVoiceAssistantFlow(),
       _voicePromptService = voicePromptService,
       _ownsSpeechInput = ownsSpeechInput,
       _ownsVoicePromptService = ownsVoicePromptService,
       _restartDelay = restartDelay,
       _partialIntentDebounce = partialIntentDebounce,
       _commandWindowDuration = commandWindowDuration,
       _speechReadyCueTimeout = speechReadyCueTimeout,
       _microphoneStartTimeout = microphoneStartTimeout,
       _microphoneStartRetryDelay = microphoneStartRetryDelay,
       _activeLearningCommandHandler = activeLearningCommandHandler {
    _completedSubscription = _speechInput.completed.listen((_) {
      if (_listening && !_finishing) {
        unawaited(_finishSession(_generation));
      }
    });
    _partialTextSubscription = _speechInput.partialText.listen(
      _handlePartialText,
    );
    _amplitudeSubscription = _speechInput.amplitudeDbfs.listen(
      _handleAmplitude,
    );
    final activityInput = _speechInput is SpeechActivityStreamingSpeechInput
        ? _speechInput as SpeechActivityStreamingSpeechInput
        : null;
    _speechActivitySubscription = activityInput?.speechStarted.listen((_) {
      _markSpeechActivity();
    });
    final alternativeInput =
        _speechInput is AlternativeTranscriptStreamingSpeechInput
        ? _speechInput as AlternativeTranscriptStreamingSpeechInput
        : null;
    _alternativeTextSubscription = alternativeInput?.transcriptAlternatives
        .listen(_handleAlternativeTranscripts);
  }

  static const Duration _noSpeechTimeout = Duration(seconds: 6);
  static const Duration _maximumSessionDuration = Duration(seconds: 12);
  static const Duration _voicePromptTimeout = Duration(seconds: 8);
  static const Duration _commandListenRestartDelay = Duration(
    milliseconds: 100,
  );
  static const Duration _mainCommandListenRestartDelay = Duration(
    milliseconds: 500,
  );
  static const int _maximumMicrophoneStartAttempts = 3;

  final StreamingSpeechInput _speechInput;
  final VoiceNavigationIntentResolver _resolver;
  final MainVoiceAssistantFlow _mainAssistantFlow;
  final VoicePromptService? _voicePromptService;
  final bool _ownsSpeechInput;
  final bool _ownsVoicePromptService;
  final Duration _restartDelay;
  final Duration _partialIntentDebounce;
  final Duration _commandWindowDuration;
  final Duration _speechReadyCueTimeout;
  final Duration _microphoneStartTimeout;
  final Duration _microphoneStartRetryDelay;
  final ActiveLearningCommandHandler? _activeLearningCommandHandler;

  StreamSubscription<void>? _completedSubscription;
  StreamSubscription<String>? _partialTextSubscription;
  StreamSubscription<double>? _amplitudeSubscription;
  StreamSubscription<void>? _speechActivitySubscription;
  StreamSubscription<List<String>>? _alternativeTextSubscription;
  Timer? _restartTimer;
  Timer? _noSpeechTimer;
  Timer? _maximumSessionTimer;
  Timer? _partialIntentTimer;
  Timer? _commandWindowTimer;
  VoiceNavigationIntentHandler? _intentHandler;
  Future<void>? _pauseInProgress;
  Future<void>? _startInProgress;
  Future<void>? _finishInProgress;
  bool _continuousRequested = false;
  bool _starting = false;
  bool _listening = false;
  bool _finishing = false;
  bool _speechDetected = false;
  int _speechActivitySamples = 0;
  bool _awaitingCommand = false;
  bool _acknowledgingWakeWord = false;
  bool _buttonCommandSession = false;
  bool _mainButtonActivationInProgress = false;
  bool _disposed = false;
  int _generation = 0;
  int _mainNoSpeechRetryCount = 0;
  int _microphoneStartAttemptCount = 0;
  Object? _lastError;
  String? _activeInputLabelOverride;

  bool get isListening => _listening;
  bool get isStarting => _starting;
  bool get isActive =>
      _starting ||
      _listening ||
      _finishing ||
      _acknowledgingWakeWord ||
      _startInProgress != null ||
      _pauseInProgress != null;
  bool get continuousRequested => _continuousRequested;
  bool get isAwaitingCommand => _awaitingCommand;
  bool get isAcknowledgingWakeWord => _acknowledgingWakeWord;
  bool get isMainButtonSessionActive =>
      _buttonCommandSession || _mainButtonActivationInProgress;
  MainVoiceAssistantStage get mainAssistantStage => _mainAssistantFlow.stage;
  Object? get lastError => _lastError;
  String get activeInputLabel =>
      _activeInputLabelOverride ?? _speechInput.label;
  String? get lastErrorMessage {
    final error = _lastError;
    if (error == null) return null;
    if (error is StreamingSpeechInputException) return error.message;
    final message = error.toString().trim();
    return message.isEmpty ? 'Không mở được micro. Con thử lại nhé.' : message;
  }

  void setIntentHandler(VoiceNavigationIntentHandler? handler) {
    _intentHandler = handler;
  }

  void setChildAge(int age) {
    _mainAssistantFlow.setChildAge(age);
  }

  void startContinuous({Duration delay = Duration.zero}) {
    if (_disposed) {
      return;
    }
    if (!_continuousRequested) {
      _lastError = null;
    }
    _continuousRequested = true;
    _scheduleSession(delay);
  }

  /// Opens one command window from the fixed Main button.
  ///
  /// This does not require a wake phrase. Any existing recognition session is
  /// released first, the assistant replies, then Android listens for one
  /// navigation command until the normal command window expires.
  Future<bool> activateFromMainButton({
    bool activeLearning = false,
    ActiveLearningModuleKind? activeLearningKind,
    String? inputLabelOverride,
  }) async {
    return _activateMainAssistantFlow(
      activeLearning
          ? _mainAssistantFlow.beginActiveLearning
          : _mainAssistantFlow.begin,
      inputLabelOverride: inputLabelOverride,
    );
  }

  /// Leaves automatic speaking practice and offers the remaining learning
  /// destinations without translating the child's command as practice text.
  Future<bool> activateOtherLearningFromSpeaking() async {
    return _activateMainAssistantFlow(_mainAssistantFlow.beginOtherLearning);
  }

  /// Continues the guided topic journey after the child completes a topic.
  Future<bool> activateTopicSelectionAfterCompletion({
    required int childAge,
    required List<int> completedTopicNumbers,
  }) async {
    return _activateMainAssistantFlow(
      () => _mainAssistantFlow.beginTopicSelectionAfterCompletion(
        childAge: childAge,
        completedTopicNumbers: completedTopicNumbers,
      ),
    );
  }

  Future<bool> _activateMainAssistantFlow(
    String Function() beginFlow, {
    String? inputLabelOverride,
  }) async {
    if (_disposed) {
      return false;
    }
    _mainButtonActivationInProgress = true;
    notifyListeners();
    try {
      await pause();
      if (_disposed) {
        return false;
      }
      _activeInputLabelOverride = inputLabelOverride;
      _lastError = null;
      _buttonCommandSession = true;
      _mainNoSpeechRetryCount = 0;
      _microphoneStartAttemptCount = 0;
      _continuousRequested = true;
      final generation = _generation;
      final acknowledged = await _acknowledgeWakeWord(
        generation,
        promptText: beginFlow(),
      );
      if (!acknowledged || _disposed || generation != _generation) {
        _buttonCommandSession = false;
        _continuousRequested = false;
        _mainAssistantFlow.reset();
        return false;
      }
      // Give Android audio focus and the speaker a short time to settle so the
      // recognizer does not capture the tail of Bi cô's own sentence.
      _scheduleSession(_mainCommandListenRestartDelay);
      return true;
    } finally {
      _mainButtonActivationInProgress = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  /// Releases the recognizer so the conversation microphone can use it.
  Future<void> pause() {
    if (_disposed) {
      return Future<void>.value();
    }
    _continuousRequested = false;
    _buttonCommandSession = false;
    _mainNoSpeechRetryCount = 0;
    _microphoneStartAttemptCount = 0;
    _mainAssistantFlow.reset();
    _generation += 1;
    _cancelTimers();
    final shouldStopPrompt = _acknowledgingWakeWord;
    _awaitingCommand = false;
    _acknowledgingWakeWord = false;
    final pendingPause = _pauseInProgress;
    if (pendingPause != null) {
      return pendingPause;
    }
    final shouldCancelInput = _starting || _listening;
    final starting = _startInProgress;
    final finishing = _finishInProgress;
    _starting = false;
    _listening = false;
    _speechDetected = false;
    final pendingOperations = <Future<void>>[
      if (shouldCancelInput) _speechInput.cancel().catchError((Object _) {}),
      if (starting != null) starting.catchError((Object _) {}),
      if (finishing != null) finishing.catchError((Object _) {}),
      if (shouldStopPrompt && _voicePromptService != null)
        _voicePromptService.stop().catchError((Object _) {}),
    ];
    final Future<void> operation = pendingOperations.isEmpty
        ? Future<void>.value()
        : Future.wait<void>(pendingOperations).then<void>((_) {});
    late final Future<void> pauseFuture;
    pauseFuture = operation.whenComplete(() {
      if (identical(_pauseInProgress, pauseFuture)) {
        _pauseInProgress = null;
      }
      if (!_disposed) {
        notifyListeners();
      }
      if (_continuousRequested) {
        _scheduleSession(_restartDelay);
      }
    });
    _pauseInProgress = pauseFuture;
    return pauseFuture;
  }

  /// Testable entry point for a transcript produced by the navigation ASR.
  Future<bool> dispatchRecognizedText(String recognizedText) =>
      _handleRecognizedText(recognizedText, _generation);

  Future<bool> _handleRecognizedText(
    String recognizedText,
    int generation,
  ) async {
    if (_disposed || generation != _generation) {
      return false;
    }

    if (!_awaitingCommand) {
      if (!_resolver.containsWakeWord(recognizedText)) {
        return false;
      }
      return _acknowledgeWakeWord(generation);
    }

    if (_buttonCommandSession) {
      return _handleMainAssistantText(recognizedText, generation);
    }

    final intent = _resolver.resolve(recognizedText);
    if (intent == null) {
      return false;
    }
    _commandWindowTimer?.cancel();
    _commandWindowTimer = null;
    _awaitingCommand = false;
    if (_buttonCommandSession) {
      _buttonCommandSession = false;
      _continuousRequested = false;
    }
    notifyListeners();
    return _dispatchIntent(intent);
  }

  Future<bool> _handleMainAssistantText(
    String recognizedText,
    int generation,
  ) async {
    _commandWindowTimer?.cancel();
    _commandWindowTimer = null;
    _awaitingCommand = false;
    notifyListeners();

    final turn = await _mainAssistantFlow.handle(recognizedText);
    if (_disposed || generation != _generation || !_buttonCommandSession) {
      return false;
    }

    final navigationBeforePrompt = turn.navigationBeforePrompt;
    if (navigationBeforePrompt != null) {
      await _dispatchIntent(navigationBeforePrompt);
      if (_disposed || generation != _generation || !_buttonCommandSession) {
        return false;
      }
    }

    final promptCompleted = await _acknowledgeWakeWord(
      generation,
      promptText: turn.promptText,
      promptSequence: turn.promptSequence,
      openCommandWindow: turn.continueListening,
    );
    if (!promptCompleted || _disposed || generation != _generation) {
      return false;
    }

    final onPromptCompleted = turn.onPromptCompleted;
    if (onPromptCompleted != null) {
      try {
        await onPromptCompleted();
      } catch (error) {
        if (!_disposed && generation == _generation) {
          _lastError = error;
        }
      }
      if (_disposed || generation != _generation) {
        return false;
      }
    }

    if (turn.continueListening) {
      _scheduleSession(_mainCommandListenRestartDelay);
      return true;
    }

    _buttonCommandSession = false;
    _continuousRequested = false;
    _mainNoSpeechRetryCount = 0;
    _mainAssistantFlow.reset();
    final activeLearningCommand = turn.activeLearningCommand;
    if (activeLearningCommand != null) {
      final handler = _activeLearningCommandHandler;
      if (handler != null) {
        await handler(activeLearningCommand);
      }
    }
    final navigationAfterPrompt = turn.navigationAfterPrompt;
    if (navigationAfterPrompt != null) {
      await _dispatchIntent(navigationAfterPrompt);
    }
    notifyListeners();
    return true;
  }

  Future<bool> _acknowledgeWakeWord(
    int generation, {
    String promptText = 'Pipo nghe đây',
    List<MainVoiceAssistantUtterance> promptSequence =
        const <MainVoiceAssistantUtterance>[],
    bool openCommandWindow = true,
  }) async {
    if (_acknowledgingWakeWord) {
      return true;
    }
    _commandWindowTimer?.cancel();
    _commandWindowTimer = null;
    _awaitingCommand = false;
    _acknowledgingWakeWord = true;
    notifyListeners();
    try {
      final promptService = _voicePromptService;
      if (promptService != null) {
        final utterances = promptSequence.isEmpty
            ? <MainVoiceAssistantUtterance>[
                MainVoiceAssistantUtterance(promptText),
              ]
            : promptSequence;
        for (final utterance in utterances) {
          if (_disposed || generation != _generation) {
            return false;
          }
          await promptService
              .speakAndWait(utterance.text, locale: utterance.locale)
              .timeout(
                _voicePromptTimeout,
                onTimeout: () => promptService.stop(),
              );
        }
      }
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _lastError = error;
      }
    }
    if (_disposed || generation != _generation) {
      return false;
    }
    if (!openCommandWindow) {
      _acknowledgingWakeWord = false;
      _awaitingCommand = false;
      notifyListeners();
      return true;
    }
    try {
      final readyCuePlayer = _voicePromptService;
      if (readyCuePlayer is SpeechReadyCuePlayer) {
        // AudioServices completion is not guaranteed to arrive promptly while
        // iOS is switching a Bluetooth HFP route after prompt playback. Never
        // let a missing ready-cue callback prevent Apple Speech from opening.
        await (readyCuePlayer as SpeechReadyCuePlayer)
            .playSpeechReadyCue()
            .timeout(_speechReadyCueTimeout);
      }
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _lastError = error;
      }
    }
    if (_disposed || generation != _generation) {
      return false;
    }
    // Keep the visible prompt state through the ready cue. The previous gap
    // showed an idle "Main" button between the beep and microphone startup,
    // even though the same activation was still in progress.
    _acknowledgingWakeWord = false;
    final diagnostics = _speechInput is NativeSpeechDiagnostics
        ? _speechInput as NativeSpeechDiagnostics
        : null;
    diagnostics?.reportNativeSpeechStage('prompt_done');
    _awaitingCommand = true;
    notifyListeners();
    return true;
  }

  void _armCommandWindowTimer(int generation) {
    _commandWindowTimer?.cancel();
    _commandWindowTimer = Timer(_commandWindowDuration, () {
      _commandWindowTimer = null;
      if (_disposed || generation != _generation || !_awaitingCommand) {
        return;
      }
      if (_buttonCommandSession) {
        unawaited(_handleMainCommandTimeout(generation));
        return;
      }
      _awaitingCommand = false;
      notifyListeners();
    });
  }

  Future<void> _handleMainCommandTimeout(int generation) async {
    if (_disposed ||
        generation != _generation ||
        !_buttonCommandSession ||
        !_awaitingCommand) {
      return;
    }
    _awaitingCommand = false;
    _cancelSessionTimers();
    final shouldCancelInput = _starting || _listening;
    _starting = false;
    _listening = false;
    _speechDetected = false;
    if (shouldCancelInput) {
      await _speechInput.cancel().catchError((Object _) {});
    }
    if (_disposed || generation != _generation || !_buttonCommandSession) {
      return;
    }
    if (_mainNoSpeechRetryCount == 0) {
      _mainNoSpeechRetryCount = 1;
      final prompted = await _acknowledgeWakeWord(
        generation,
        promptText: MainVoiceAssistantFlow.noSpeechRetryPrompt,
      );
      if (prompted && !_disposed && generation == _generation) {
        _scheduleSession(_mainCommandListenRestartDelay);
      }
      return;
    }
    await _acknowledgeWakeWord(
      generation,
      promptText: MainVoiceAssistantFlow.noSpeechExitPrompt,
      openCommandWindow: false,
    );
    if (_disposed || generation != _generation || !_buttonCommandSession) {
      return;
    }
    _buttonCommandSession = false;
    _continuousRequested = false;
    _mainNoSpeechRetryCount = 0;
    _mainAssistantFlow.reset();
    notifyListeners();
  }

  Future<bool> _dispatchIntent(VoiceNavigationIntent intent) async {
    final handler = _intentHandler;
    if (handler == null || _disposed) {
      return false;
    }
    await handler(intent);
    return true;
  }

  void _scheduleSession(Duration delay) {
    _restartTimer?.cancel();
    if (_disposed || !_continuousRequested || isActive) {
      return;
    }
    final generation = _generation;
    _restartTimer = Timer(delay, () {
      _restartTimer = null;
      final startFuture = _startSession(generation);
      _startInProgress = startFuture;
      unawaited(
        startFuture.whenComplete(() {
          if (identical(_startInProgress, startFuture)) {
            _startInProgress = null;
          }
        }),
      );
    });
  }

  Future<void> _startSession(int generation) async {
    if (_disposed ||
        !_continuousRequested ||
        generation != _generation ||
        isActive) {
      return;
    }
    _starting = true;
    notifyListeners();
    try {
      final commandInput = _speechInput is CommandStreamingSpeechInput
          ? _speechInput as CommandStreamingSpeechInput
          : null;
      final diagnostics = _speechInput is NativeSpeechDiagnostics
          ? _speechInput as NativeSpeechDiagnostics
          : null;
      diagnostics?.reportNativeSpeechStage('microphone_start_requested');
      final startOperation = commandInput != null
          ? commandInput.startCommandRecognition()
          : _speechInput.start();
      await startOperation.timeout(
        _microphoneStartTimeout,
        onTimeout: () async {
          await _speechInput.cancel().catchError((Object _) {});
          throw const StreamingSpeechInputException(
            'Micro mất quá nhiều thời gian để sẵn sàng. HOMI sẽ thử lại.',
            code: 'NAVIGATION_MICROPHONE_START_TIMEOUT',
          );
        },
      );
      if (_disposed || !_continuousRequested || generation != _generation) {
        await _speechInput.cancel().catchError((Object _) {});
        return;
      }
      _starting = false;
      _listening = true;
      _speechDetected = false;
      _speechActivitySamples = 0;
      _microphoneStartAttemptCount = 0;
      _lastError = null;
      diagnostics?.reportNativeSpeechStage('microphone_listening');
      // The prompt may have finished well before iOS finishes preparing the
      // HFP route or Apple Speech. Reset the command window here so the child
      // always receives the full listening period after the mic is truly open.
      if (_awaitingCommand) {
        _armCommandWindowTimer(generation);
      }
      // MAIN already owns a command-window timer which speaks a child-friendly
      // retry prompt. Running the generic no-speech timer at the same deadline
      // raced it, cancelled Apple Speech, and could make the button return to
      // Main immediately after the ready beep.
      if (!_buttonCommandSession || !_awaitingCommand) {
        _noSpeechTimer = Timer(_noSpeechTimeout, () {
          if (!_speechDetected) {
            unawaited(_cancelSessionAndRestart(generation));
          }
        });
      }
      _maximumSessionTimer = Timer(
        _maximumSessionDuration,
        () => unawaited(_finishSession(generation)),
      );
      notifyListeners();
    } catch (error) {
      final diagnostics = _speechInput is NativeSpeechDiagnostics
          ? _speechInput as NativeSpeechDiagnostics
          : null;
      diagnostics?.reportNativeSpeechStage(
        'microphone_start_failed',
        code: error is StreamingSpeechInputException ? error.code : null,
        message: error.toString(),
      );
      _lastError = error;
      _starting = false;
      _listening = false;
      _microphoneStartAttemptCount += 1;
      final exhaustedMainAttempts =
          _buttonCommandSession &&
          _microphoneStartAttemptCount >= _maximumMicrophoneStartAttempts;
      if (exhaustedMainAttempts) {
        _awaitingCommand = false;
        _buttonCommandSession = false;
        _continuousRequested = false;
        _mainNoSpeechRetryCount = 0;
        _mainAssistantFlow.reset();
      }
      if (!_disposed) {
        notifyListeners();
      }
      if (!exhaustedMainAttempts &&
          _continuousRequested &&
          generation == _generation) {
        _scheduleRetryAfterFailedStart(generation, _microphoneStartRetryDelay);
      }
    }
  }

  void _scheduleRetryAfterFailedStart(int generation, Duration delay) {
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () {
      _restartTimer = null;
      if (_disposed || generation != _generation || !_continuousRequested) {
        return;
      }
      // This timer runs after the failed start future has completed, so
      // _scheduleSession no longer rejects the retry as an active start.
      _scheduleSession(Duration.zero);
    });
  }

  void _handlePartialText(String text) {
    if (!_listening || text.trim().isEmpty) {
      return;
    }
    _markSpeechActivity();

    // A wake phrase can react from a partial result. Once awake, only explicit
    // action phrases use this fast path; short destination names still wait for
    // Android's final result to avoid redirecting a longer normal sentence.
    final shouldHandle = _awaitingCommand
        ? _buttonCommandSession
              ? _mainAssistantFlow.canHandle(text)
              : _resolver.resolve(text, allowShortDirectCommand: false) != null
        : _resolver.containsWakeWord(text);
    _partialIntentTimer?.cancel();
    _partialIntentTimer = null;
    if (!shouldHandle) {
      return;
    }
    final generation = _generation;
    _partialIntentTimer = Timer(_partialIntentDebounce, () {
      _partialIntentTimer = null;
      unawaited(_finishFromPartialRecognition(generation, text));
    });
  }

  void _handleAmplitude(double dbfs) {
    if (!_listening) return;
    if (dbfs <= -42) {
      _speechActivitySamples = 0;
      return;
    }
    _speechActivitySamples += 1;
    // Require two adjacent loud buffers so a route click or the tail of the
    // ready cue does not count as the child's answer. speech.begin remains the
    // immediate native fast path when Swift has already confirmed activity.
    if (_speechActivitySamples >= 2) {
      _markSpeechActivity();
    }
  }

  void _markSpeechActivity() {
    if (!_listening) return;
    final firstActivity = !_speechDetected;
    _speechDetected = true;
    _noSpeechTimer?.cancel();
    _noSpeechTimer = null;
    if (firstActivity && _buttonCommandSession && _awaitingCommand) {
      // Give Apple Speech a complete command window after the child actually
      // starts talking; HFP audio can precede its first partial transcript.
      _armCommandWindowTimer(_generation);
    }
  }

  void _handleAlternativeTranscripts(List<String> candidates) {
    if (!_listening || candidates.length < 2) {
      return;
    }
    // The primary transcript already arrives through partialText. Inspect only
    // the remaining Android alternatives and forward the first actionable one.
    for (final candidate in candidates.skip(1)) {
      final shouldHandle = _awaitingCommand
          ? _buttonCommandSession
                ? _mainAssistantFlow.canHandle(candidate)
                : _resolver.resolve(
                        candidate,
                        allowShortDirectCommand: false,
                      ) !=
                      null
          : _resolver.containsWakeWord(candidate);
      if (shouldHandle) {
        _handlePartialText(candidate);
        return;
      }
    }
  }

  Future<void> _finishFromPartialRecognition(
    int generation,
    String recognizedText,
  ) {
    if (_disposed || generation != _generation || !_listening || _finishing) {
      return Future<void>.value();
    }
    _cancelSessionTimers();
    _listening = false;
    _finishing = true;
    notifyListeners();
    late final Future<void> finishFuture;
    finishFuture = _runPartialRecognition(generation, recognizedText)
        .whenComplete(() {
          if (identical(_finishInProgress, finishFuture)) {
            _finishInProgress = null;
          }
        });
    _finishInProgress = finishFuture;
    return finishFuture;
  }

  Future<void> _runPartialRecognition(
    int generation,
    String recognizedText,
  ) async {
    try {
      await _speechInput.cancel();
      if (_disposed || generation != _generation) {
        return;
      }
      await _handleRecognizedText(recognizedText, generation);
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _lastError = error;
      }
    } finally {
      _finishing = false;
      _speechDetected = false;
      if (!_disposed) {
        notifyListeners();
      }
      if (_continuousRequested && generation == _generation) {
        _scheduleSession(
          _awaitingCommand
              ? _buttonCommandSession
                    ? _mainCommandListenRestartDelay
                    : _commandListenRestartDelay
              : _restartDelay,
        );
      }
    }
  }

  Future<void> _cancelSessionAndRestart(int generation) async {
    if (_disposed || generation != _generation || !_listening) {
      return;
    }
    _cancelSessionTimers();
    _listening = false;
    notifyListeners();
    await _speechInput.cancel().catchError((Object _) {});
    if (_continuousRequested && generation == _generation) {
      _scheduleSession(_restartDelay);
    }
  }

  Future<void> _finishSession(int generation) {
    if (_disposed || generation != _generation || !_listening || _finishing) {
      return Future<void>.value();
    }
    _cancelSessionTimers();
    if (_buttonCommandSession && _awaitingCommand) {
      // A native runtime completion can arrive before a usable transcript
      // (for example while HFP is settling). Pause the command deadline while
      // stop/fallback is being resolved; the next confirmed microphone start
      // rearms the full window in _startSession.
      _commandWindowTimer?.cancel();
      _commandWindowTimer = null;
    }
    _listening = false;
    _finishing = true;
    notifyListeners();
    late final Future<void> finishFuture;
    finishFuture = _runFinishSession(generation).whenComplete(() {
      if (identical(_finishInProgress, finishFuture)) {
        _finishInProgress = null;
      }
    });
    _finishInProgress = finishFuture;
    return finishFuture;
  }

  Future<void> _runFinishSession(int generation) async {
    try {
      final capture = await _speechInput.stop();
      if (_disposed || generation != _generation) {
        return;
      }
      final candidates = <String>[capture.sourceText, ...capture.alternatives];
      final orderedCandidates = _buttonCommandSession
          ? <String>[
              ...candidates.where(_mainAssistantFlow.canHandle),
              ...candidates.where(
                (candidate) => !_mainAssistantFlow.canHandle(candidate),
              ),
            ]
          : candidates;
      final handledCandidates = <String>{};
      for (final candidate in orderedCandidates) {
        final recognizedText = candidate.trim();
        if (recognizedText.isEmpty || !handledCandidates.add(recognizedText)) {
          continue;
        }
        if (await _handleRecognizedText(recognizedText, generation)) {
          break;
        }
      }
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _lastError = error;
      }
    } finally {
      _finishing = false;
      _speechDetected = false;
      if (!_disposed) {
        notifyListeners();
      }
      if (_continuousRequested && generation == _generation) {
        _scheduleSession(
          _awaitingCommand
              ? _buttonCommandSession
                    ? _mainCommandListenRestartDelay
                    : _commandListenRestartDelay
              : _restartDelay,
        );
      }
    }
  }

  void _cancelSessionTimers() {
    _partialIntentTimer?.cancel();
    _partialIntentTimer = null;
    _noSpeechTimer?.cancel();
    _noSpeechTimer = null;
    _maximumSessionTimer?.cancel();
    _maximumSessionTimer = null;
  }

  void _cancelTimers() {
    _restartTimer?.cancel();
    _restartTimer = null;
    _commandWindowTimer?.cancel();
    _commandWindowTimer = null;
    _cancelSessionTimers();
  }

  @override
  void dispose() {
    _disposed = true;
    _continuousRequested = false;
    _generation += 1;
    _cancelTimers();
    unawaited(_completedSubscription?.cancel());
    unawaited(_partialTextSubscription?.cancel());
    unawaited(_amplitudeSubscription?.cancel());
    unawaited(_speechActivitySubscription?.cancel());
    unawaited(_alternativeTextSubscription?.cancel());
    if (_ownsSpeechInput) {
      unawaited(_speechInput.dispose());
    }
    if (_ownsVoicePromptService) {
      unawaited(_voicePromptService?.dispose());
    }
    super.dispose();
  }
}
