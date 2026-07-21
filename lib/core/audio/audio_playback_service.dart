import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'device_audio_cache.dart';

class PlaybackStartMetrics {
  const PlaybackStartMetrics({
    required this.audioLoadDuration,
    required this.startedAfterRequest,
    required this.fromDeviceCache,
  });

  final Duration audioLoadDuration;
  final Duration startedAfterRequest;
  final bool fromDeviceCache;
}

abstract interface class AudioPlaybackService {
  Stream<bool> get playingStream;
  Future<void> prepare();
  Future<void> preload(Uri uri);
  Future<PlaybackStartMetrics> play(Uri uri);
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioPlaybackService implements AudioPlaybackService {
  static const _silentWarmUpAudio =
      'data:audio/wav;base64,'
      'UklGRiYAAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YQIAAAAAAA==';

  JustAudioPlaybackService({AudioPlayer? player, DeviceAudioCache? cache})
    : _cache = cache ?? DeviceAudioCache(),
      _ownsCache = cache == null,
      _player =
          player ??
          AudioPlayer(
            audioLoadConfiguration: const AudioLoadConfiguration(
              androidLoadControl: AndroidLoadControl(
                minBufferDuration: Duration(seconds: 1),
                maxBufferDuration: Duration(seconds: 8),
                bufferForPlaybackDuration: Duration(milliseconds: 300),
                bufferForPlaybackAfterRebufferDuration: Duration(
                  milliseconds: 750,
                ),
                prioritizeTimeOverSizeThresholds: true,
              ),
            ),
          ) {
    _audioSession = AudioSession.instance;
    _playerWarmUp = _warmUpPlayer();
  }

  final AudioPlayer _player;
  final DeviceAudioCache _cache;
  final bool _ownsCache;
  late final Future<AudioSession> _audioSession;
  late final Future<void> _playerWarmUp;
  Future<void>? _playbackSessionPreparation;
  Future<void> _sourceOperation = Future<void>.value();
  Uri? _loadedOriginalUri;
  Uri? _loadedResolvedUri;
  int _preloadRevision = 0;

  Future<void> _warmUpPlayer() async {
    try {
      await _player.setUrl(_silentWarmUpAudio);
    } catch (error) {
      assert(() {
        debugPrint('Audio player warm-up was skipped: $error');
        return true;
      }());
    }
  }

  Future<void> _configurePlaybackAudioSession() async {
    final session = await _audioSession;
    // Music mode intentionally routes generated speech through the Android
    // media path, which is the path used by Bluetooth Classic/A2DP speakers.
    // Recording reconfigures the shared session for speech, so playback must
    // restore this mode after every captured utterance.
    await session.configure(const AudioSessionConfiguration.music());
  }

  @override
  Future<void> prepare() {
    final preparation = _configurePlaybackAudioSession();
    _playbackSessionPreparation = preparation;
    return preparation;
  }

  Future<void> _consumePlaybackPreparation() async {
    final preparation = _playbackSessionPreparation ?? prepare();
    try {
      await preparation;
    } finally {
      if (identical(_playbackSessionPreparation, preparation)) {
        _playbackSessionPreparation = null;
      }
    }
  }

  Future<void> _startPlayback() async {
    unawaited(_player.play());
    await _player.positionStream
        .firstWhere((position) => position > Duration.zero)
        .timeout(const Duration(seconds: 2));
  }

  @override
  Stream<bool> get playingStream => _player.playingStream;

  Future<void> _setSource(Uri uri) async {
    if (uri.isScheme('file')) {
      await _player
          .setFilePath(uri.toFilePath())
          .timeout(const Duration(seconds: 8));
    } else {
      await _player.setUrl(uri.toString()).timeout(const Duration(seconds: 8));
    }
  }

  Future<void> _queueSource(Future<void> Function() operation) {
    final next = _sourceOperation.catchError((_) {}).then((_) => operation());
    _sourceOperation = next;
    return next;
  }

  @override
  Future<void> preload(Uri uri) async {
    final revision = ++_preloadRevision;
    await _playerWarmUp;
    final cachedUri = await _cache.cache(uri);
    if (cachedUri == null || revision != _preloadRevision) {
      return;
    }
    await _queueSource(() async {
      if (revision != _preloadRevision ||
          (_loadedOriginalUri == uri && _loadedResolvedUri == cachedUri)) {
        return;
      }
      await _setSource(cachedUri);
      _loadedOriginalUri = uri;
      _loadedResolvedUri = cachedUri;
    });
  }

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    ++_preloadRevision;
    final requestedAt = DateTime.now();
    await _playerWarmUp;
    await _consumePlaybackPreparation();
    final resolvedUri = await _cache.resolveAfterPreload(uri);
    final loadStartedAt = DateTime.now();
    await _queueSource(() async {
      if (_loadedOriginalUri == uri && _loadedResolvedUri == resolvedUri) {
        return;
      }
      await _setSource(resolvedUri);
      _loadedOriginalUri = uri;
      _loadedResolvedUri = resolvedUri;
    });
    final loadedAt = DateTime.now();
    assert(() {
      debugPrint(
        'Audio source ready after '
        '${loadedAt.difference(requestedAt).inMilliseconds} ms.',
      );
      return true;
    }());
    try {
      await _startPlayback();
    } on TimeoutException {
      // ExoPlayer can occasionally remain in a completed-but-playing state
      // when the same short clip is used again. Reset and retry once.
      await _player.pause();
      await _player.seek(Duration.zero);
      try {
        await _startPlayback();
      } on TimeoutException {
        throw const PlaybackException('Không thể bắt đầu phát câu tiếng Anh.');
      }
    }

    final startedAt = DateTime.now();
    if (!resolvedUri.isScheme('file')) {
      unawaited(_cache.cache(uri));
    }
    return PlaybackStartMetrics(
      audioLoadDuration: loadedAt.difference(loadStartedAt),
      startedAfterRequest: startedAt.difference(requestedAt),
      fromDeviceCache: resolvedUri.isScheme('file'),
    );
  }

  @override
  Future<void> stop() => _player.pause();

  @override
  Future<void> dispose() async {
    await _player.dispose();
    if (_ownsCache) {
      _cache.dispose();
    }
  }
}

class PlaybackException implements Exception {
  const PlaybackException(this.message);

  final String message;

  @override
  String toString() => message;
}
