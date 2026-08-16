import 'dart:async';
import 'dart:typed_data';

import '../../../core/audio/adaptive_voice_activity_detector.dart';
import '../../../core/audio/audio_input.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../conversation/domain/conversation_models.dart';
import '../../conversation/domain/conversation_repository.dart';
import '../../conversation/domain/speech_gated_batch_upload_session.dart';

/// Adapts the browser microphone + Cloudflare Batch Chunks pipeline to the
/// short-command interface used by the fixed MAIN assistant.
///
/// This is intentionally separate from [ConversationController]: a MAIN turn
/// only needs the Vietnamese transcript and must never play the translated
/// response produced by `/api/conversation`. Audio chunks are uploaded while
/// the child is speaking, then the authoritative result is finalized after a
/// short VAD silence.
class WebBatchStreamingSpeechInput
    implements StreamingSpeechInput, CommandStreamingSpeechInput {
  WebBatchStreamingSpeechInput({
    required ChunkedAudioInput audioInput,
    required ConversationRepository repository,
    required int childAge,
    this.vadSilenceDuration = const Duration(milliseconds: 700),
    AdaptiveVoiceActivityDetector? voiceActivityDetector,
  }) : _audioInput = audioInput,
       _repository = repository,
       _childAge = childAge,
       _voiceActivityDetector =
           voiceActivityDetector ?? AdaptiveVoiceActivityDetector();

  final ChunkedAudioInput _audioInput;
  final ConversationRepository _repository;
  final int _childAge;
  final Duration vadSilenceDuration;
  final AdaptiveVoiceActivityDetector _voiceActivityDetector;

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<String> _partialTextController =
      StreamController<String>.broadcast();

  StreamSubscription<double>? _amplitudeSubscription;
  StreamSubscription<Uint8List>? _chunkSubscription;
  SpeechGatedBatchUploadSession? _uploadGate;
  Future<BatchChunkUploadSession?>? _sessionFuture;
  Future<void>? _audioStartFuture;
  Timer? _silenceTimer;
  Stopwatch? _recordingStopwatch;
  DateTime? _startedAt;
  bool _active = false;
  bool _stopping = false;
  bool _speechDetected = false;
  bool _completionEmitted = false;
  bool _disposed = false;
  int _generation = 0;

  @override
  String get label => 'Cloudflare Batch • ${_audioInput.label}';

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<void> get completed => _completedController.stream;

  @override
  Stream<String> get partialText => _partialTextController.stream;

  @override
  Future<bool> checkAvailability() async =>
      !_disposed && _audioInput.isAvailable;

  @override
  Future<void> startCommandRecognition() => start();

  @override
  Future<void> start() async {
    if (_disposed) {
      throw const StreamingSpeechInputException(
        'Bộ nhận lệnh Web đã đóng.',
        code: 'WEB_BATCH_DISPOSED',
      );
    }
    if (_active || _stopping) {
      throw const StreamingSpeechInputException(
        'Micro đang được sử dụng.',
        code: 'WEB_BATCH_ALREADY_ACTIVE',
      );
    }

    final generation = ++_generation;
    _active = true;
    _speechDetected = false;
    _completionEmitted = false;
    _voiceActivityDetector.reset();
    _silenceTimer?.cancel();
    _recordingStopwatch = Stopwatch()..start();
    _startedAt = DateTime.now();

    final uploadGate = SpeechGatedBatchUploadSession();
    _uploadGate = uploadGate;
    _chunkSubscription = _audioInput.audioChunks.listen(
      (bytes) => uploadGate.addAudioChunk(bytes),
      onError: (_) {},
    );
    _amplitudeSubscription = _audioInput.amplitudeDbfs.listen(
      (dbfs) => _handleAmplitude(dbfs, generation),
      onError: (_) {},
    );

    final chunkedRepository = _repository is ChunkedConversationRepository
        ? _repository as ChunkedConversationRepository
        : null;
    _sessionFuture = chunkedRepository == null
        ? Future<BatchChunkUploadSession?>.value()
        : chunkedRepository
              .startBatchChunkUpload()
              .then<BatchChunkUploadSession?>((session) {
                if (_disposed || generation != _generation || !_active) {
                  unawaited(
                    session.discard(reason: 'web_main_session_superseded'),
                  );
                  return null;
                }
                uploadGate.attachDelegate(session);
                return session;
              })
              .catchError((Object _) => null);

    final startFuture = _audioInput.startChunked();
    _audioStartFuture = startFuture;
    try {
      await startFuture;
    } catch (error) {
      if (generation == _generation) {
        _active = false;
        await _discardUpload('web_main_micro_start_failed');
        await _cancelSubscriptions();
      }
      rethrow;
    } finally {
      if (identical(_audioStartFuture, startFuture)) {
        _audioStartFuture = null;
      }
    }

    if (_disposed || generation != _generation || !_active) {
      await _audioInput.cancel().catchError((Object _) {});
      throw const StreamingSpeechInputException(
        'Phiên nhận lệnh đã dừng.',
        code: 'WEB_BATCH_CANCELLED',
      );
    }
  }

  void _handleAmplitude(double dbfs, int generation) {
    if (_disposed || generation != _generation || !_active || _stopping) {
      return;
    }
    _amplitudeController.add(dbfs);
    final elapsed = _recordingStopwatch?.elapsed ?? Duration.zero;
    final update = _voiceActivityDetector.addSample(dbfs, elapsed: elapsed);
    final uploadGate = _uploadGate;

    if (update.speechStarted && !_speechDetected) {
      _speechDetected = true;
      uploadGate?.markSpeechDetected();
      // VoiceNavigationController uses a non-empty partial only as a speech
      // presence signal. The ellipsis normalizes to no command, so it cannot
      // accidentally navigate before the authoritative Batch result.
      _partialTextController.add('…');
    }
    if (!_speechDetected) {
      return;
    }
    if (update.voiceActive) {
      uploadGate?.markVoiceActive();
      _silenceTimer?.cancel();
      _silenceTimer = null;
      return;
    }

    uploadGate?.markVoiceInactive();
    _silenceTimer ??= Timer(vadSilenceDuration, () {
      if (_disposed ||
          generation != _generation ||
          !_active ||
          _stopping ||
          _completionEmitted) {
        return;
      }
      _completionEmitted = true;
      _completedController.add(null);
    });
  }

  @override
  Future<StreamingSpeechCapture> stop() async {
    if (_disposed || !_active || _stopping) {
      throw const StreamingSpeechInputException(
        'Chưa có phiên nhận lệnh Web đang chạy.',
        code: 'WEB_BATCH_NOT_ACTIVE',
      );
    }
    _stopping = true;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    final stopRequestedAt = DateTime.now();
    final startedAt = _startedAt ?? stopRequestedAt;

    try {
      // Keep the chunk subscription alive until stop() drains the browser PCM
      // stream, otherwise the final consonant can be lost.
      final capture = await _audioInput.stop();
      await _cancelSubscriptions();
      final result = await _finalizeOrFallback(capture);
      final transcript = result.vietnameseText.trim();
      if (transcript.isEmpty) {
        throw const StreamingSpeechInputException(
          'Mình chưa nghe rõ. Con thử nói lại nhé.',
          code: 'WEB_BATCH_NO_SPEECH',
        );
      }
      return StreamingSpeechCapture(
        sourceText: transcript,
        duration: capture.duration,
        inputLabel: label,
        confidence: null,
        firstResultMs: null,
        finalAfterStopMs: DateTime.now()
            .difference(stopRequestedAt)
            .inMilliseconds,
        asrMode: AsrMode.batchChunks.apiValue,
        isBluetoothInput: capture.isBluetoothInput,
        initialNoiseRms: capture.initialNoiseRms,
        recordedAudio: capture,
        extraBenchmark: <String, dynamic>{
          'navigationCommand': true,
          'webVirtualMain': true,
          'speechDetected': _speechDetected,
          'recordingElapsedMs': DateTime.now()
              .difference(startedAt)
              .inMilliseconds,
        },
      );
    } finally {
      _active = false;
      _stopping = false;
      _recordingStopwatch?.stop();
      _recordingStopwatch = null;
      _startedAt = null;
      _uploadGate = null;
      _sessionFuture = null;
    }
  }

  Future<ConversationResult> _finalizeOrFallback(AudioCapture capture) async {
    final uploadGate = _uploadGate;
    final session = await _sessionFuture?.catchError((Object _) => null);
    if (uploadGate != null && session != null && _speechDetected) {
      try {
        return await uploadGate.finalize(
          capture: capture,
          context: PracticeContext.home,
          childAge: _childAge,
          vadSilenceMs: vadSilenceDuration.inMilliseconds,
        );
      } catch (_) {
        // The in-memory Web capture is still complete, so a single multipart
        // retry is safer than making the child repeat a command.
      }
    } else {
      await uploadGate?.discard(reason: 'web_main_direct_fallback');
    }
    return _repository.processAudio(
      capture: capture,
      context: PracticeContext.home,
      childAge: _childAge,
      vadSilenceMs: vadSilenceDuration.inMilliseconds,
      fallbackReason: 'web_virtual_main_batch_unavailable',
    );
  }

  @override
  Future<void> cancel() async {
    if (_disposed && !_active && !_stopping) {
      return;
    }
    _generation += 1;
    final wasActive = _active || _stopping;
    _active = false;
    _stopping = false;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    final startFuture = _audioStartFuture;
    if (startFuture != null) {
      await startFuture.catchError((Object _) {});
    }
    if (wasActive) {
      await _audioInput.cancel().catchError((Object _) {});
    }
    await _cancelSubscriptions();
    await _discardUpload('web_main_cancelled');
    _recordingStopwatch?.stop();
    _recordingStopwatch = null;
    _startedAt = null;
    _uploadGate = null;
    _sessionFuture = null;
  }

  Future<void> _discardUpload(String reason) async {
    final gate = _uploadGate;
    await _sessionFuture?.catchError((Object _) => null);
    await gate?.discard(reason: reason).catchError((Object _) {});
  }

  Future<void> _cancelSubscriptions() async {
    await _amplitudeSubscription?.cancel();
    await _chunkSubscription?.cancel();
    _amplitudeSubscription = null;
    _chunkSubscription = null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await cancel();
    _disposed = true;
    await _amplitudeController.close();
    await _completedController.close();
    await _partialTextController.close();
  }
}
