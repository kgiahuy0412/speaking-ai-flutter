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
    _timeUpdateListener = ((web.Event _) => _onTimeUpdate()).toJS;
    _durationChangeListener = ((web.Event _) => _emitDuration()).toJS;
    _loadedDataListener = ((web.Event _) => _markPreloadLoaded()).toJS;
    _canPlayListener = ((web.Event _) => _markPreloadReady()).toJS;
    _errorListener = ((web.Event _) => _emitPlaying(false)).toJS;
    _element.addEventListener('ended', _endedListener);
    _element.addEventListener('timeupdate', _timeUpdateListener);
    _element.addEventListener('durationchange', _durationChangeListener);
    _element.addEventListener('loadedmetadata', _durationChangeListener);
    _element.addEventListener('loadeddata', _loadedDataListener);
    _element.addEventListener('canplay', _canPlayListener);
    _element.addEventListener('error', _errorListener);
    _setSource(Uri.parse(_silentWarmUpAudio));
  }

  static const _warmUpDurationMs = 300;
  static final String _silentWarmUpAudio = _buildSilentWarmUpAudio();

  final web.HTMLAudioElement _element =
      web.document.createElement('audio') as web.HTMLAudioElement;
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  late final JSFunction _endedListener;
  late final JSFunction _timeUpdateListener;
  late final JSFunction _durationChangeListener;
  late final JSFunction _loadedDataListener;
  late final JSFunction _canPlayListener;
  late final JSFunction _errorListener;
  Uri? _sourceUri;
  Uri? _preloadedSourceUri;
  DateTime? _preloadRequestedAt;
  DateTime? _preloadLoadedAt;
  DateTime? _preloadReadyAt;
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

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Duration get position => _secondsToDuration(_element.currentTime);

  @override
  Duration? get duration {
    final seconds = _element.duration;
    return seconds.isFinite && seconds > 0 ? _secondsToDuration(seconds) : null;
  }

  @override
  bool hasPreloadedSource(Uri uri) =>
      _sourceUri == uri && _preloadedSourceUri == uri;

  @override
  bool hasLoadedPreloadedSource(Uri uri) =>
      hasPreloadedSource(uri) && _preloadLoadedAt != null;

  @override
  bool hasReadyPreloadedSource(Uri uri) =>
      hasPreloadedSource(uri) && _preloadReadyAt != null;

  @override
  Duration? preloadedSourceLoadedAfter(Uri uri) =>
      hasLoadedPreloadedSource(uri) && _preloadRequestedAt != null
      ? _preloadLoadedAt!.difference(_preloadRequestedAt!)
      : null;

  @override
  Duration? preloadedSourceReadyAfter(Uri uri) =>
      hasReadyPreloadedSource(uri) && _preloadRequestedAt != null
      ? _preloadReadyAt!.difference(_preloadRequestedAt!)
      : null;

  void _markPreloadLoaded() {
    if (_disposed ||
        _preloadedSourceUri == null ||
        _preloadedSourceUri != _sourceUri) {
      return;
    }
    _preloadLoadedAt ??= DateTime.now();
  }

  void _markPreloadReady() {
    _markPreloadLoaded();
    if (_disposed ||
        _preloadedSourceUri == null ||
        _preloadedSourceUri != _sourceUri) {
      return;
    }
    _preloadReadyAt ??= DateTime.now();
  }

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

  void _onTimeUpdate() {
    if (!_positionController.isClosed) {
      _positionController.add(position);
    }
    _emitDuration();
    _finishAtMediaEnd();
  }

  void _emitDuration() {
    if (!_durationController.isClosed) {
      _durationController.add(duration);
    }
  }

  static Duration _secondsToDuration(double seconds) => Duration(
    microseconds:
        (seconds.isFinite ? seconds : 0) * Duration.microsecondsPerSecond ~/ 1,
  );

  void _setSource(Uri uri) {
    if (_sourceUri == uri) {
      return;
    }
    _element.src = uri.isScheme('asset') ? 'assets${uri.path}' : uri.toString();
    _element.load();
    _sourceUri = uri;
    if (!_positionController.isClosed) {
      _positionController.add(Duration.zero);
    }
    if (!_durationController.isClosed) {
      _durationController.add(null);
    }
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
    if (_preloadedSourceUri != uri) {
      _preloadRequestedAt = DateTime.now();
      _preloadLoadedAt = null;
      _preloadReadyAt = null;
    }
    _preloadedSourceUri = uri;
    _setSource(uri);
    // Safari may already have buffered a cached response before event handlers
    // observe the transition. readyState 2 is HAVE_CURRENT_DATA and 3 is
    // HAVE_FUTURE_DATA (the threshold used by the `canplay` event).
    if (_element.readyState >= 2) _markPreloadLoaded();
    if (_element.readyState >= 3) _markPreloadReady();
  }

  @override
  Future<void> play(Uri uri) async {
    if (_disposed) {
      throw StateError('Browser audio player is disposed.');
    }

    final reusingPreloadedSource = hasPreloadedSource(uri);
    if (!reusingPreloadedSource) {
      _preloadedSourceUri = null;
      _preloadRequestedAt = null;
      _preloadLoadedAt = null;
      _preloadReadyAt = null;
    }
    // _setSource deliberately does not call load() again for the URI retained
    // by preload. This keeps Safari attached to the same in-flight response.
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
    _element.removeEventListener('durationchange', _durationChangeListener);
    _element.removeEventListener('loadedmetadata', _durationChangeListener);
    _element.removeEventListener('loadeddata', _loadedDataListener);
    _element.removeEventListener('canplay', _canPlayListener);
    _element.removeEventListener('error', _errorListener);
    _element.removeAttribute('src');
    _element.load();
    _sourceUri = null;
    _preloadedSourceUri = null;
    _preloadRequestedAt = null;
    _preloadLoadedAt = null;
    _preloadReadyAt = null;
    await Future.wait<void>(<Future<void>>[
      _playingController.close(),
      _positionController.close(),
      _durationController.close(),
    ]);
  }
}
