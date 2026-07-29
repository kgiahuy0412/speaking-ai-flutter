import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser_audio_playback.dart';
import 'wav_audio.dart';

BrowserAudioPlayback? createBrowserAudioPlayback() =>
    _HtmlAudioElementPlayback();

class _HtmlAudioElementPlayback implements BrowserAudioPlayback {
  _HtmlAudioElementPlayback() {
    _element.crossOrigin = 'anonymous';
    _element.preload = 'auto';
    _endedListener = ((web.Event _) => _emitPlaying(false)).toJS;
    _timeUpdateListener = ((web.Event _) => _finishAtMediaEnd()).toJS;
    _errorListener = ((web.Event _) => _emitPlaying(false)).toJS;
    _element.addEventListener('ended', _endedListener);
    _element.addEventListener('timeupdate', _timeUpdateListener);
    _element.addEventListener('error', _errorListener);
    _setSource(Uri.parse(_silentWarmUpAudio));
  }

  static const _warmUpDurationMs = 300;
  static final String _silentWarmUpAudio = _buildSilentWarmUpAudio();

  final web.HTMLAudioElement _element =
      web.document.createElement('audio') as web.HTMLAudioElement;
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  late final JSFunction _endedListener;
  late final JSFunction _timeUpdateListener;
  late final JSFunction _errorListener;
  Uri? _sourceUri;
  bool _unlocked = false;
  bool _playing = false;
  bool _disposed = false;

  static String _buildSilentWarmUpAudio() {
    const sampleRate = 8000;
    final pcmLength = pcm16ChunkByteLength(
      sampleRate: sampleRate,
      durationMs: _warmUpDurationMs,
    );
    final pcmBytes = Uint8List(pcmLength);
    final wavBytes = Uint8List.fromList(<int>[
      ...buildPcm16WavHeader(pcmByteLength: pcmLength, sampleRate: sampleRate),
      ...pcmBytes,
    ]);
    return 'data:audio/wav;base64,${base64Encode(wavBytes)}';
  }

  @override
  Stream<bool> get playingStream => _playingController.stream;

  void _emitPlaying(bool value) {
    if (_playing == value) {
      return;
    }
    _playing = value;
    if (!_playingController.isClosed) {
      _playingController.add(value);
    }
  }

  void _finishAtMediaEnd() {
    final duration = _element.duration;
    final reachedEnd =
        duration.isFinite &&
        duration > 0 &&
        _element.currentTime >= duration - 0.05;
    if (_element.ended || reachedEnd) {
      _emitPlaying(false);
    }
  }

  void _setSource(Uri uri) {
    if (_sourceUri == uri) {
      return;
    }
    _element.src = uri.isScheme('asset') ? 'assets${uri.path}' : uri.toString();
    _element.load();
    _sourceUri = uri;
  }

  void _rewindIfCompleted() {
    final duration = _element.duration;
    final reachedEnd =
        duration.isFinite &&
        duration > 0 &&
        _element.currentTime >= duration - 0.02;
    if (_element.ended || reachedEnd) {
      _element.currentTime = 0;
    }
  }

  void _resetAfterFailure() {
    _element.pause();
    _emitPlaying(false);
    try {
      _element.currentTime = 0;
    } catch (_) {
      // Metadata may not be available yet. The next source load starts at 0.
    }
  }

  @override
  Future<void> unlockForUserGesture() async {
    if (_disposed || _unlocked) {
      return;
    }

    try {
      // HTMLMediaElement.play() is invoked before the first await so Safari
      // sees the original tap. Its promise resolves when playback has begun,
      // not when the 300 ms silent clip ends.
      await _element.play().toDart.timeout(const Duration(milliseconds: 350));
      _element.pause();
      _element.currentTime = 0;
      _emitPlaying(false);
      _unlocked = true;
    } catch (error) {
      _resetAfterFailure();
      throw StateError('Safari audio unlock failed: $error');
    }
  }

  @override
  Future<void> preload(Uri uri) async {
    if (_disposed) {
      return;
    }
    _setSource(uri);
  }

  @override
  Future<void> play(Uri uri) async {
    if (_disposed) {
      throw StateError('Browser audio player is disposed.');
    }

    _setSource(uri);
    _rewindIfCompleted();
    // Mark the attempt before calling play(). Very short guide clips can reach
    // `ended` on iOS Safari before the play promise resumes in Dart. Emitting
    // here makes that end event observable instead of leaving callers waiting
    // for their safety timeout.
    _emitPlaying(true);
    try {
      // Keep this as the first asynchronous browser media operation. For the
      // Play button it runs in the same tap callback; for autoplay it reuses
      // the exact element unlocked when recording began.
      await _element.play().toDart.timeout(const Duration(seconds: 4));
    } catch (error) {
      _resetAfterFailure();
      throw StateError('Browser audio playback failed: $error');
    }
  }

  @override
  Future<void> pause() async {
    if (_disposed) {
      return;
    }
    _element.pause();
    _emitPlaying(false);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _element.pause();
    _element.removeEventListener('ended', _endedListener);
    _element.removeEventListener('timeupdate', _timeUpdateListener);
    _element.removeEventListener('error', _errorListener);
    _element.removeAttribute('src');
    _element.load();
    await _playingController.close();
  }
}
