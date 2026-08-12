import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/audio/voice_prompt_service.dart';
import 'voice_navigation_intent_resolver.dart';

typedef VoiceNavigationIntentHandler =
    FutureOr<void> Function(VoiceNavigationIntent intent);

/// Runs Android voice navigation independently from the conversation flow.
///
/// It shares the platform speech recognizer with conversation recording, but
/// never changes [ConversationController] state and never forwards unmatched
/// speech to the conversation backend.
class VoiceNavigationController extends ChangeNotifier {
  VoiceNavigationController({
    required StreamingSpeechInput speechInput,
    VoiceNavigationIntentResolver resolver =
        const VoiceNavigationIntentResolver(),
    VoicePromptService? voicePromptService,
    bool ownsSpeechInput = false,
    bool ownsVoicePromptService = false,
    Duration restartDelay = const Duration(milliseconds: 300),
    Duration partialIntentDebounce = const Duration(milliseconds: 160),
    Duration commandWindowDuration = const Duration(seconds: 8),
  }) : _speechInput = speechInput,
       _resolver = resolver,
       _voicePromptService = voicePromptService,
       _ownsSpeechInput = ownsSpeechInput,
       _ownsVoicePromptService = ownsVoicePromptService,
       _restartDelay = restartDelay,
       _partialIntentDebounce = partialIntentDebounce,
       _commandWindowDuration = commandWindowDuration {
    _completedSubscription = _speechInput.completed.listen((_) {
      if (_listening && !_finishing) {
        unawaited(_finishSession(_generation));
      }
    });
    _partialTextSubscription = _speechInput.partialText.listen(
      _handlePartialText,
    );
  }

  static const Duration _noSpeechTimeout = Duration(seconds: 8);
  static const Duration _maximumSessionDuration = Duration(seconds: 12);
  static const Duration _wakePromptTimeout = Duration(seconds: 3);
  static const Duration _commandListenRestartDelay = Duration(
    milliseconds: 100,
  );

  final StreamingSpeechInput _speechInput;
  final VoiceNavigationIntentResolver _resolver;
  final VoicePromptService? _voicePromptService;
  final bool _ownsSpeechInput;
  final bool _ownsVoicePromptService;
  final Duration _restartDelay;
  final Duration _partialIntentDebounce;
  final Duration _commandWindowDuration;

  StreamSubscription<void>? _completedSubscription;
  StreamSubscription<String>? _partialTextSubscription;
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
  bool _awaitingCommand = false;
  bool _acknowledgingWakeWord = false;
  bool _disposed = false;
  int _generation = 0;
  Object? _lastError;

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
  Object? get lastError => _lastError;

  void setIntentHandler(VoiceNavigationIntentHandler? handler) {
    _intentHandler = handler;
  }

  void startContinuous({Duration delay = Duration.zero}) {
    if (_disposed) {
      return;
    }
    _continuousRequested = true;
    _scheduleSession(delay);
  }

  /// Releases the recognizer so the conversation microphone can use it.
  Future<void> pause() {
    if (_disposed) {
      return Future<void>.value();
    }
    _continuousRequested = false;
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

    final intent = _resolver.resolve(recognizedText);
    if (intent == null) {
      return false;
    }
    _commandWindowTimer?.cancel();
    _commandWindowTimer = null;
    _awaitingCommand = false;
    notifyListeners();
    return _dispatchIntent(intent);
  }

  Future<bool> _acknowledgeWakeWord(int generation) async {
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
        await promptService
            .speakAndWait('Pipo nghe đây')
            .timeout(_wakePromptTimeout, onTimeout: () => promptService.stop());
      }
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _lastError = error;
      }
    }
    if (_disposed || generation != _generation) {
      return false;
    }
    _acknowledgingWakeWord = false;
    _awaitingCommand = true;
    _commandWindowTimer = Timer(_commandWindowDuration, () {
      _commandWindowTimer = null;
      if (_disposed || generation != _generation || !_awaitingCommand) {
        return;
      }
      _awaitingCommand = false;
      notifyListeners();
    });
    notifyListeners();
    return true;
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
    _lastError = null;
    notifyListeners();
    try {
      final commandInput = _speechInput is CommandStreamingSpeechInput
          ? _speechInput as CommandStreamingSpeechInput
          : null;
      if (commandInput != null) {
        await commandInput.startCommandRecognition();
      } else {
        await _speechInput.start();
      }
      if (_disposed || !_continuousRequested || generation != _generation) {
        await _speechInput.cancel().catchError((Object _) {});
        return;
      }
      _starting = false;
      _listening = true;
      _speechDetected = false;
      _noSpeechTimer = Timer(_noSpeechTimeout, () {
        if (!_speechDetected) {
          unawaited(_cancelSessionAndRestart(generation));
        }
      });
      _maximumSessionTimer = Timer(
        _maximumSessionDuration,
        () => unawaited(_finishSession(generation)),
      );
      notifyListeners();
    } catch (error) {
      _lastError = error;
      _starting = false;
      _listening = false;
      if (!_disposed) {
        notifyListeners();
      }
      if (_continuousRequested && generation == _generation) {
        _scheduleSession(const Duration(seconds: 2));
      }
    }
  }

  void _handlePartialText(String text) {
    if (!_listening || text.trim().isEmpty) {
      return;
    }
    _speechDetected = true;
    _noSpeechTimer?.cancel();
    _noSpeechTimer = null;

    // A wake phrase can react from a partial result. Once awake, only explicit
    // action phrases use this fast path; short destination names still wait for
    // Android's final result to avoid redirecting a longer normal sentence.
    final shouldHandle = _awaitingCommand
        ? _resolver.resolve(text, allowShortDirectCommand: false) != null
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
          _awaitingCommand ? _commandListenRestartDelay : _restartDelay,
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
      await _handleRecognizedText(capture.sourceText, generation);
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
          _awaitingCommand ? _commandListenRestartDelay : _restartDelay,
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
    if (_ownsSpeechInput) {
      unawaited(_speechInput.dispose());
    }
    if (_ownsVoicePromptService) {
      unawaited(_voicePromptService?.dispose());
    }
    super.dispose();
  }
}
