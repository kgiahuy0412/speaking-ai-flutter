import 'dart:async';

import 'hfp_audio_control.dart';
import 'streaming_speech_input.dart';

/// Opens the selected HFP/SCO route for every MAIN recognition window.
///
/// Normal conversation recording already owns this lifecycle. Voice
/// navigation uses [StreamingSpeechInput] directly, so without this adapter an
/// H20 can be selected successfully while MAIN still listens to the phone mic.
class HfpRoutedStreamingSpeechInput
    implements
        StreamingSpeechInput,
        CommandStreamingSpeechInput,
        AlternativeTranscriptStreamingSpeechInput {
  HfpRoutedStreamingSpeechInput({
    required StreamingSpeechInput speechInput,
    required HfpAudioControl hfpAudioControl,
  }) : _speechInput = speechInput,
       _hfpAudioControl = hfpAudioControl;

  final StreamingSpeechInput _speechInput;
  final HfpAudioControl _hfpAudioControl;

  Future<void> _operationQueue = Future<void>.value();
  bool _routeActive = false;
  bool _disposed = false;

  @override
  String get label => _speechInput.label;

  @override
  Stream<double> get amplitudeDbfs => _speechInput.amplitudeDbfs;

  @override
  Stream<void> get completed => _speechInput.completed;

  @override
  Stream<String> get partialText => _speechInput.partialText;

  @override
  Stream<List<String>> get transcriptAlternatives {
    final alternativeInput = _speechInput;
    return alternativeInput is AlternativeTranscriptStreamingSpeechInput
        ? (alternativeInput as AlternativeTranscriptStreamingSpeechInput)
              .transcriptAlternatives
        : const Stream<List<String>>.empty();
  }

  @override
  Future<bool> checkAvailability() => _speechInput.checkAvailability();

  @override
  Future<void> start() => _startWithRoute(_speechInput.start);

  @override
  Future<void> startCommandRecognition() {
    final commandInput = _speechInput;
    final useNormalHfpRecognition = _hfpAudioControl.status.isConnected;
    return _startWithRoute(
      // HFP/SCO needs the same recognizer profile as the proven "Nói câu
      // mới" path. Several Android recognition services apply the short
      // command silence thresholds before the Bluetooth route has delivered
      // stable speech, which produces NO_MATCH even though normal conversation
      // hears the same microphone correctly.
      !useNormalHfpRecognition && commandInput is CommandStreamingSpeechInput
          ? (commandInput as CommandStreamingSpeechInput)
                .startCommandRecognition
          : commandInput.start,
    );
  }

  Future<void> _startWithRoute(Future<void> Function() startInput) {
    return _enqueue<void>(() async {
      if (_disposed) {
        throw const StreamingSpeechInputException(
          'Bộ nhận lệnh MAIN đã đóng.',
          code: 'MAIN_INPUT_DISPOSED',
        );
      }
      await _startHfpRouteIfAvailable();
      try {
        await startInput();
      } catch (_) {
        await _stopHfpRoute();
        rethrow;
      }
    });
  }

  Future<void> _startHfpRouteIfAvailable() async {
    if (_routeActive || !_hfpAudioControl.status.isConnected) {
      return;
    }
    await _hfpAudioControl.startAudioRoute();
    _routeActive = true;
  }

  @override
  Future<StreamingSpeechCapture> stop() {
    return _enqueue<StreamingSpeechCapture>(() async {
      try {
        return await _speechInput.stop();
      } finally {
        // Release SCO before Bi cô replies so the recorder cannot capture the
        // assistant's own prompt and the next window starts from a clean route.
        await _stopHfpRoute();
      }
    });
  }

  @override
  Future<void> cancel() {
    return _enqueue<void>(() async {
      try {
        await _speechInput.cancel();
      } finally {
        await _stopHfpRoute();
      }
    });
  }

  Future<void> _stopHfpRoute() async {
    if (!_routeActive) return;
    try {
      await _hfpAudioControl.stopAudioRoute();
    } finally {
      _routeActive = false;
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.catchError((Object _) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<void> dispose() {
    return _enqueue<void>(() async {
      if (_disposed) return;
      _disposed = true;
      try {
        await _speechInput.dispose();
      } finally {
        await _stopHfpRoute();
      }
    });
  }
}
