import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/audio/adaptive_voice_activity_detector.dart';
import '../../../core/audio/audio_input.dart';
import '../../../core/audio/hfp_audio_control.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../conversation/domain/conversation_models.dart';
import '../../conversation/domain/conversation_repository.dart';
import '../../conversation/domain/speech_gated_batch_upload_session.dart';

/// Adapts a chunked microphone + Cloudflare Batch Chunks pipeline to the
/// short-command interface used by the fixed MAIN assistant on Web and iOS.
///
/// This is intentionally separate from [ConversationController]: a MAIN turn
/// only needs the Vietnamese transcript and must never play the translated
/// response produced by `/api/conversation`. Audio chunks are uploaded while
/// the child is speaking, then the authoritative result is finalized after a
/// short VAD silence.
class WebBatchStreamingSpeechInput
    implements
        StreamingSpeechInput,
        CommandStreamingSpeechInput,
        RecordedAudioFallbackSpeechInput {
  WebBatchStreamingSpeechInput({
    required ChunkedAudioInput audioInput,
    required ConversationRepository repository,
    required int childAge,
    HfpAudioControl? audioRouteControl,
    this.vadSilenceDuration = const Duration(milliseconds: 700),
    AdaptiveVoiceActivityDetector? voiceActivityDetector,
  }) : _audioInput = audioInput,
       _repository = repository,
       _childAge = childAge,
       _audioRouteControl = audioRouteControl,
       _voiceActivityDetector =
           voiceActivityDetector ?? AdaptiveVoiceActivityDetector();

  final ChunkedAudioInput _audioInput;
  final ConversationRepository _repository;
  final HfpAudioControl? _audioRouteControl;
  int _childAge;
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
  int? _audioStartMs;
  int? _uploadSessionReadyMs;
  int? _firstChunkMs;
  int? _speechDetectedMs;
  bool _active = false;
  bool _stopping = false;
  bool _speechDetected = false;
  bool _audioRouteStarted = false;

  void setChildAge(int age) {
    _childAge = age;
  }

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
    _audioStartMs = null;
    _uploadSessionReadyMs = null;
    _firstChunkMs = null;
    _speechDetectedMs = null;

    final uploadGate = SpeechGatedBatchUploadSession();
    _uploadGate = uploadGate;
    _chunkSubscription = _audioInput.audioChunks.listen((bytes) {
      _firstChunkMs ??= _recordingStopwatch?.elapsedMilliseconds;
      uploadGate.addAudioChunk(bytes);
    }, onError: (_) {});
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
                _uploadSessionReadyMs ??=
                    _recordingStopwatch?.elapsedMilliseconds;
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

    Future<void>? startFuture;
    try {
      final routeControl = _audioRouteControl;
      if (routeControl != null && routeControl.status.isConnected) {
        try {
          await routeControl.startAudioRoute();
          _audioRouteStarted = true;
        } catch (error) {
          // Batch must remain usable when iOS cannot activate H20 HFP. Clear
          // the stale preferred route and let the recorder use the phone mic.
          debugPrint(
            'HOMI Batch HFP route failed; falling back to phone mic: $error',
          );
          await routeControl.stopAudioRoute().catchError((Object _) {});
          await routeControl.disconnect().catchError((Object _) {});
        }
      }
      startFuture = _audioInput.startChunked();
      _audioStartFuture = startFuture;
      await startFuture;
      _audioStartMs = _recordingStopwatch?.elapsedMilliseconds;
    } catch (error) {
      if (generation == _generation) {
        _active = false;
        await _stopAudioRoute();
        await _discardUpload('web_main_micro_start_failed');
        await _cancelSubscriptions();
      }
      rethrow;
    } finally {
      if (startFuture != null && identical(_audioStartFuture, startFuture)) {
        _audioStartFuture = null;
      }
    }

    if (_disposed || generation != _generation || !_active) {
      await _audioInput.cancel().catchError((Object _) {});
      await _stopAudioRoute();
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
      _speechDetectedMs = _recordingStopwatch?.elapsedMilliseconds;
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
      // Keep the chunk subscription alive until stop() drains the PCM stream,
      // otherwise the final consonant can be lost.
      final captureStopwatch = Stopwatch()..start();
      final capture = await _audioInput.stop();
      final captureStopMs = captureStopwatch.elapsedMilliseconds;
      await _cancelSubscriptions();
      final finalizeStopwatch = Stopwatch()..start();
      final result = await _finalizeOrFallback(capture);
      final finalizeMs = finalizeStopwatch.elapsedMilliseconds;
      final transcript = result.vietnameseText.trim();
      if (transcript.isEmpty) {
        throw const StreamingSpeechInputException(
          'Mình chưa nghe rõ. Con thử nói lại nhé.',
          code: 'WEB_BATCH_NO_SPEECH',
        );
      }
      final totalMs = DateTime.now().difference(startedAt).inMilliseconds;
      final latency = <String, dynamic>{
        'event': 'main_cloud_batch_latency',
        'audioStartMs': _audioStartMs,
        'uploadSessionReadyMs': _uploadSessionReadyMs,
        'firstChunkMs': _firstChunkMs,
        'speechDetectedMs': _speechDetectedMs,
        'captureStopMs': captureStopMs,
        'batchFinalizeMs': finalizeMs,
        'totalMs': totalMs,
        'usedBluetoothInput': capture.isBluetoothInput,
      };
      // This is intentionally metadata-only: never log transcript or audio.
      // It makes physical-device and Codemagic logs useful for finding slow
      // audio startup, upload-session creation, drain, or backend finalization.
      // ignore: avoid_print
      print(jsonEncode(latency));
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
          'cloudBatchMain': true,
          'speechDetected': _speechDetected,
          'recordingElapsedMs': totalMs,
          'audioStartMs': _audioStartMs,
          'uploadSessionReadyMs': _uploadSessionReadyMs,
          'firstChunkMs': _firstChunkMs,
          'speechDetectedMs': _speechDetectedMs,
          'captureStopMs': captureStopMs,
          'batchFinalizeMs': finalizeMs,
        },
      );
    } finally {
      _active = false;
      _stopping = false;
      await _stopAudioRoute();
      _recordingStopwatch?.stop();
      _recordingStopwatch = null;
      _startedAt = null;
      _uploadGate = null;
      _sessionFuture = null;
      _audioStartMs = null;
      _uploadSessionReadyMs = null;
      _firstChunkMs = null;
      _speechDetectedMs = null;
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
  Future<StreamingSpeechCapture> recognizeRecordedAudio(
    AudioCapture capture, {
    String? fallbackReason,
  }) async {
    if (_disposed) {
      throw const StreamingSpeechInputException(
        'Bộ nhận lệnh Batch đã đóng.',
        code: 'WEB_BATCH_DISPOSED',
      );
    }
    final stopwatch = Stopwatch()..start();
    final result = await _repository.processAudio(
      capture: capture,
      context: PracticeContext.home,
      childAge: _childAge,
      vadSilenceMs: vadSilenceDuration.inMilliseconds,
      fallbackReason: fallbackReason ?? 'ios_native_main_runtime_failure',
    );
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
      finalAfterStopMs: stopwatch.elapsedMilliseconds,
      asrMode: AsrMode.batchChunks.apiValue,
      isBluetoothInput: capture.isBluetoothInput,
      initialNoiseRms: capture.initialNoiseRms,
      recordedAudio: capture,
      extraBenchmark: <String, dynamic>{
        'navigationCommand': true,
        'cloudBatchMain': true,
        'nativeRuntimeFallback': true,
        'batchFinalizeMs': stopwatch.elapsedMilliseconds,
      },
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
    await _stopAudioRoute();
    await _cancelSubscriptions();
    await _discardUpload('web_main_cancelled');
    _recordingStopwatch?.stop();
    _recordingStopwatch = null;
    _startedAt = null;
    _uploadGate = null;
    _sessionFuture = null;
    _audioStartMs = null;
    _uploadSessionReadyMs = null;
    _firstChunkMs = null;
    _speechDetectedMs = null;
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

  Future<void> _stopAudioRoute() async {
    if (!_audioRouteStarted) return;
    _audioRouteStarted = false;
    await _audioRouteControl?.stopAudioRoute().catchError((Object _) {});
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
