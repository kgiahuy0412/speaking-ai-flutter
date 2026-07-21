import 'dart:async';
import 'dart:typed_data';

import 'audio_input.dart';

/// Selects the preferred chunked input when it is available and otherwise
/// keeps the phone microphone as a safe fallback.
class PreferredAudioInput implements ChunkedAudioInput {
  PreferredAudioInput({
    required ChunkedAudioInput fallback,
    ChunkedAudioInput? preferred,
  }) : _fallback = fallback,
       _preferred = preferred;

  final ChunkedAudioInput _fallback;
  final ChunkedAudioInput? _preferred;
  final StreamController<Uint8List> _chunkController =
      StreamController<Uint8List>.broadcast(sync: true);

  ChunkedAudioInput? _active;
  StreamSubscription<Uint8List>? _chunkSubscription;

  ChunkedAudioInput get _candidate {
    final preferred = _preferred;
    return preferred != null && preferred.isAvailable ? preferred : _fallback;
  }

  ChunkedAudioInput get _current => _active ?? _candidate;

  @override
  String get label => _current.label;

  @override
  bool get isBluetooth => _current.isBluetooth;

  @override
  bool get isAvailable => _candidate.isAvailable;

  @override
  Stream<double> get amplitudeDbfs => _current.amplitudeDbfs;

  @override
  Stream<Uint8List> get audioChunks => _chunkController.stream;

  @override
  Future<void> start() async {
    _active = _candidate;
    try {
      await _active!.start();
    } catch (_) {
      if (!identical(_active, _preferred) || !_fallback.isAvailable) {
        _active = null;
        rethrow;
      }
      _active = _fallback;
      await _fallback.start();
    }
  }

  @override
  Future<void> startChunked() async {
    _active = _candidate;
    await _listenToActiveChunks();
    try {
      await _active!.startChunked();
    } catch (_) {
      await _chunkSubscription?.cancel();
      _chunkSubscription = null;
      if (!identical(_active, _preferred) || !_fallback.isAvailable) {
        _active = null;
        rethrow;
      }
      await _active!.cancel().catchError((Object _) {});
      _active = _fallback;
      await _listenToActiveChunks();
      await _fallback.startChunked();
    }
  }

  Future<void> _listenToActiveChunks() async {
    await _chunkSubscription?.cancel();
    _chunkSubscription = _active!.audioChunks.listen(
      _chunkController.add,
      onError: _chunkController.addError,
    );
  }

  @override
  Future<AudioCapture> stop() async {
    final active = _active ?? _candidate;
    try {
      return await active.stop();
    } finally {
      await _chunkSubscription?.cancel();
      _chunkSubscription = null;
      _active = null;
    }
  }

  @override
  Future<void> cancel() async {
    final active = _active;
    await _chunkSubscription?.cancel();
    _chunkSubscription = null;
    _active = null;
    await active?.cancel();
  }

  @override
  Future<void> dispose() async {
    await _chunkSubscription?.cancel();
    await _chunkController.close();
    await _preferred?.dispose();
    await _fallback.dispose();
  }
}
