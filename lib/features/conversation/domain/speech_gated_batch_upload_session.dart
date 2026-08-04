import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../../../core/audio/audio_input.dart';
import '../../../core/audio/wav_audio.dart';
import 'conversation_models.dart';
import 'conversation_repository.dart';

/// Keeps a short rolling pre-roll while the client VAD is listening, then
/// forwards only confirmed speech to the resumable Batch Chunks upload.
///
/// The wrapped session receives adjusted PCM metadata at finalize time so the
/// backend can assemble a valid WAV from the gated bytes.
class SpeechGatedBatchUploadSession implements BatchChunkUploadSession {
  SpeechGatedBatchUploadSession({
    BatchChunkUploadSession? delegate,
    this.preRollChunkCount = 2,
    this.postRollChunkCount = 1,
  }) : _delegate = delegate {
    if (preRollChunkCount < 1) {
      throw ArgumentError.value(
        preRollChunkCount,
        'preRollChunkCount',
        'must be at least one',
      );
    }
    if (postRollChunkCount < 0) {
      throw ArgumentError.value(
        postRollChunkCount,
        'postRollChunkCount',
        'must not be negative',
      );
    }
  }

  BatchChunkUploadSession? _delegate;
  final int preRollChunkCount;
  final int postRollChunkCount;
  final ListQueue<Uint8List> _preRoll = ListQueue<Uint8List>();
  final ListQueue<Uint8List> _trailingSilence = ListQueue<Uint8List>();
  final List<Uint8List> _pendingForwarded = <Uint8List>[];

  bool _speechDetected = false;
  bool _voiceActive = false;
  bool _closed = false;
  int _forwardedAudioBytes = 0;

  int get forwardedAudioBytes => _forwardedAudioBytes;

  void attachDelegate(BatchChunkUploadSession delegate) {
    if (_closed) {
      unawaited(delegate.discard(reason: 'speech_gate_closed'));
      return;
    }
    if (_delegate != null) {
      throw StateError('Batch upload delegate is already attached.');
    }
    _delegate = delegate;
    for (final bytes in _pendingForwarded) {
      delegate.addAudioChunk(bytes);
    }
    _pendingForwarded.clear();
  }

  void markSpeechDetected() {
    if (_closed || _speechDetected) {
      return;
    }
    _speechDetected = true;
    _voiceActive = true;
    while (_preRoll.isNotEmpty) {
      _forward(_preRoll.removeFirst());
    }
  }

  void markVoiceActive() {
    if (_closed || !_speechDetected) {
      return;
    }
    _voiceActive = true;
    // A resumed voice means the buffered pause was inside the utterance, not
    // trailing silence, so keep it before forwarding new speech.
    while (_trailingSilence.isNotEmpty) {
      _forward(_trailingSilence.removeFirst());
    }
  }

  void markVoiceInactive() {
    if (_closed || !_speechDetected) {
      return;
    }
    _voiceActive = false;
  }

  @override
  void addAudioChunk(Uint8List bytes) {
    if (_closed || bytes.isEmpty) {
      return;
    }
    final immutable = Uint8List.fromList(bytes);
    if (_speechDetected) {
      if (_voiceActive) {
        _forward(immutable);
      } else {
        _trailingSilence.addLast(immutable);
      }
      return;
    }

    _preRoll.addLast(immutable);
    while (_preRoll.length > preRollChunkCount) {
      _preRoll.removeFirst();
    }
  }

  void _forward(Uint8List bytes) {
    _forwardedAudioBytes += bytes.length;
    final delegate = _delegate;
    if (delegate == null) {
      _pendingForwarded.add(bytes);
      return;
    }
    delegate.addAudioChunk(bytes);
  }

  @override
  Future<ConversationResult> finalize({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) {
    _closed = true;
    _preRoll.clear();
    final delegate = _delegate;
    if (delegate == null) {
      return Future<ConversationResult>.error(
        StateError('Batch upload delegate is not attached.'),
      );
    }
    // Keep one short tail by default. Fully dropping the first inactive frame
    // can remove a quiet final consonant from child speech; the remaining
    // trailing ambient frames are discarded.
    for (
      var kept = 0;
      kept < postRollChunkCount && _trailingSilence.isNotEmpty;
      kept += 1
    ) {
      _forward(_trailingSilence.removeFirst());
    }
    _trailingSilence.clear();
    return delegate.finalize(
      capture: _gatedCapture(capture),
      context: context,
      childAge: childAge,
      vadSilenceMs: vadSilenceMs,
    );
  }

  AudioCapture _gatedCapture(AudioCapture capture) {
    final sampleRate = capture.recordingSampleRate;
    if (_forwardedAudioBytes <= 0 || sampleRate == null || sampleRate <= 0) {
      return capture;
    }

    const bytesPerSample = pcm16BitsPerSample ~/ 8;
    const bytesPerFrame = pcm16ChannelCount * bytesPerSample;
    final bytesPerSecond = sampleRate * bytesPerFrame;
    final duration = Duration(
      microseconds:
          (_forwardedAudioBytes * Duration.microsecondsPerSecond) ~/
          bytesPerSecond,
    );
    final header = buildPcm16WavHeader(
      pcmByteLength: _forwardedAudioBytes,
      sampleRate: sampleRate,
      channelCount: pcm16ChannelCount,
    );

    return AudioCapture(
      filePath: capture.filePath,
      mimeType: capture.mimeType,
      duration: duration,
      inputLabel: capture.inputLabel,
      isBluetoothInput: capture.isBluetoothInput,
      initialNoiseRms: capture.initialNoiseRms,
      streamHeaderBytes: header,
      streamedAudioBytes: _forwardedAudioBytes,
      recordingSampleRate: sampleRate,
      audioProcessing: capture.audioProcessing,
    );
  }

  @override
  Future<void> discard({String reason = 'unspecified'}) {
    _closed = true;
    _preRoll.clear();
    _trailingSilence.clear();
    _pendingForwarded.clear();
    return _delegate?.discard(reason: reason) ?? Future<void>.value();
  }
}
