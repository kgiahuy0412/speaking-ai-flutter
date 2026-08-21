import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_gain.dart';
import 'browser_audio_playback.dart';
import 'browser_audio_playback_factory.dart';
import 'device_audio_cache.dart';

class PlaybackStartMetrics {
  const PlaybackStartMetrics({
    required this.audioLoadDuration,
    required this.startedAfterRequest,
    required this.fromDeviceCache,
    this.preloadedSourceLoaded = false,
    this.preloadedSourceReady = false,
    this.preloadLoadedDuration,
    this.preloadReadyDuration,
  });

  final Duration audioLoadDuration;
  final Duration startedAfterRequest;
  final bool fromDeviceCache;
  final bool preloadedSourceLoaded;
  final bool preloadedSourceReady;
  final Duration? preloadLoadedDuration;
  final Duration? preloadReadyDuration;
}

abstract interface class AudioPlaybackService {
  Stream<bool> get playingStream;
  Future<void> prepare();
  Future<void> preload(Uri uri);
  Future<PlaybackStartMetrics> play(Uri uri);
  Future<void> stop();
  Future<void> dispose();
}

/// Optional capability for callers that must distinguish a temporary pause
/// from the source actually reaching its end.
abstract interface class CompletionAwareAudioPlaybackService {
  Stream<void> get completionStream;
}

/// Optional playback telemetry used by long-form media such as songs.
///
/// Short lesson prompts do not need to implement this capability, which keeps
/// existing test doubles and lightweight playback implementations compatible.
abstract interface class ProgressAwareAudioPlaybackService {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Duration get position;
  Duration? get duration;
}

/// Optional capability used by browsers that require audio playback to be
/// started directly from a user gesture before later automatic playback.
abstract interface class UserGestureAudioPlaybackService {
  Future<void> unlockForUserGesture();
}

/// Optional web capability that resumes an already loaded source directly
/// inside the browser's tap callback.
abstract interface class DirectUserGestureAudioPlaybackService {
  Future<PlaybackStartMetrics?> playLoadedForUserGesture(Uri uri);
}

/// Optional capability for two-way HFP/SCO devices. Media playback attributes
/// can leave Android on A2DP or the phone speaker; communication attributes
/// keep English audio on the same HFP route as the external microphone.
abstract interface class CommunicationRouteAwareAudioPlaybackService {
  void setCommunicationRouteActive(bool active);
}

/// Optional capability for speech that should be played more slowly without
/// changing ASR, translation, TTS generation, or network processing time.
abstract interface class PlaybackRateAwareAudioPlaybackService {
  void setPlaybackRate(double rate);
}

class JustAudioPlaybackService
    implements
        AudioPlaybackService,
        CompletionAwareAudioPlaybackService,
        ProgressAwareAudioPlaybackService,
        UserGestureAudioPlaybackService,
        DirectUserGestureAudioPlaybackService,
        CommunicationRouteAwareAudioPlaybackService,
        PlaybackRateAwareAudioPlaybackService {
  static Future<void>? _assetCacheRefresh;
  // A modest boost makes speech clearer on small speakers and HFP headsets
  // without pushing typical voice recordings into heavy clipping.
  static const double androidPlaybackGainDb = androidSpeechBoostDb;

  JustAudioPlaybackService({AudioPlayer? player, DeviceAudioCache? cache})
    : _cache = cache ?? DeviceAudioCache(),
      _ownsCache = cache == null,
      _browserPlayback = createBrowserAudioPlayback(),
      _player = player ?? _createDefaultPlayer() {
    _audioSession = AudioSession.instance;
  }

  static AudioPlayer _createDefaultPlayer() {
    final androidEffects = <AndroidAudioEffect>[];
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final loudnessEnhancer = AndroidLoudnessEnhancer();
      // These setters update the effect's initial configuration synchronously
      // while the player is inactive, so playback starts with the boost ready.
      unawaited(loudnessEnhancer.setTargetGain(androidPlaybackGainDb));
      unawaited(loudnessEnhancer.setEnabled(true));
      androidEffects.add(loudnessEnhancer);
    }
    return AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: androidEffects),
      audioLoadConfiguration: const AudioLoadConfiguration(
        androidLoadControl: AndroidLoadControl(
          minBufferDuration: Duration(milliseconds: 600),
          maxBufferDuration: Duration(seconds: 8),
          bufferForPlaybackDuration: Duration(milliseconds: 180),
          bufferForPlaybackAfterRebufferDuration: Duration(milliseconds: 500),
          prioritizeTimeOverSizeThresholds: true,
        ),
      ),
    );
  }

  final AudioPlayer _player;
  final BrowserAudioPlayback? _browserPlayback;
  final DeviceAudioCache _cache;
  final bool _ownsCache;
  late final Future<AudioSession> _audioSession;
  Future<void>? _playbackSessionPreparation;
  Future<void> _sourceOperation = Future<void>.value();
  Uri? _loadedOriginalUri;
  Uri? _loadedResolvedUri;
  int _preloadRevision = 0;
  bool _communicationRouteActive = false;
  double _playbackRate = 1.0;

  @override
  void setPlaybackRate(double rate) {
    final safeRate = rate.clamp(0.4, 2.0).toDouble();
    if (_playbackRate == safeRate) return;
    _playbackRate = safeRate;
    _browserPlayback?.setPlaybackRate(safeRate);
  }

  @override
  void setCommunicationRouteActive(bool active) {
    if (_communicationRouteActive == active) return;
    _communicationRouteActive = active;
    _playbackSessionPreparation = null;
  }

  @override
  Future<void> unlockForUserGesture() async {
    final browserPlayback = _browserPlayback;
    if (browserPlayback == null) {
      return;
    }

    try {
      await browserPlayback.unlockForUserGesture();
    } catch (error) {
      debugPrint('Web audio unlock was skipped: $error');
    }
  }

  Future<void> _configurePlaybackAudioSession() async {
    final session = await _audioSession;
    // Recording changes the shared audio session, so restore the desired
    // route before every playback request.
    if (_communicationRouteActive) {
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        ),
      );
      return;
    }
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ),
    );
  }

  @override
  Future<void> prepare() {
    if (_browserPlayback != null) {
      return Future<void>.value();
    }
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
    final started = Completer<void>();
    late final StreamSubscription<Duration> positionSubscription;
    late final StreamSubscription<PlayerState> playerStateSubscription;
    positionSubscription = _player.positionStream.listen(
      (position) {
        if (position > Duration.zero && !started.isCompleted) {
          started.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!started.isCompleted) {
          started.completeError(error, stackTrace);
        }
      },
    );
    playerStateSubscription = _player.playerStateStream.listen(
      (state) {
        if (state.playing &&
            state.processingState == ProcessingState.ready &&
            !started.isCompleted) {
          started.complete();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!started.isCompleted) {
          started.completeError(error, stackTrace);
        }
      },
    );

    await _player.setSpeed(_playbackRate);
    final playback = _player.play();
    unawaited(
      playback.catchError((Object error, StackTrace stackTrace) {
        if (!started.isCompleted) {
          started.completeError(error, stackTrace);
        }
      }),
    );
    try {
      await started.future.timeout(const Duration(seconds: 2));
    } finally {
      await Future.wait<void>(<Future<void>>[
        positionSubscription.cancel(),
        playerStateSubscription.cancel(),
      ]);
    }
  }

  Future<void> _rewindCompletedPlayback() async {
    final duration = _player.duration;
    final reachedEnd =
        duration != null &&
        duration > Duration.zero &&
        _player.position >= duration - const Duration(milliseconds: 20);
    if (_player.processingState == ProcessingState.completed || reachedEnd) {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<PlaybackStartMetrics?> playLoadedForUserGesture(Uri uri) async {
    final browserPlayback = _browserPlayback;
    if (browserPlayback == null) {
      return null;
    }

    final requestedAt = DateTime.now();
    final reusedPreloadedSource = browserPlayback.hasPreloadedSource(uri);
    final preloadedSourceLoaded = browserPlayback.hasLoadedPreloadedSource(uri);
    final preloadedSourceReady = browserPlayback.hasReadyPreloadedSource(uri);
    final preloadLoadedDuration = browserPlayback.preloadedSourceLoadedAfter(
      uri,
    );
    final preloadReadyDuration = browserPlayback.preloadedSourceReadyAfter(uri);
    try {
      // The browser implementation invokes HTMLMediaElement.play() before its
      // first await, preserving Safari's transient activation for this tap.
      final playback = browserPlayback.play(uri);
      await playback;
      _loadedOriginalUri = uri;
      _loadedResolvedUri = uri;
      return PlaybackStartMetrics(
        audioLoadDuration: Duration.zero,
        startedAfterRequest: DateTime.now().difference(requestedAt),
        fromDeviceCache: reusedPreloadedSource,
        preloadedSourceLoaded: preloadedSourceLoaded,
        preloadedSourceReady: preloadedSourceReady,
        preloadLoadedDuration: preloadLoadedDuration,
        preloadReadyDuration: preloadReadyDuration,
      );
    } catch (error) {
      debugPrint('Direct web playback failed: $error');
      throw const PlaybackException(
        'Safari chưa thể phát âm thanh. Hãy chạm nút phát lại một lần nữa.',
      );
    }
  }

  @override
  Stream<bool> get playingStream =>
      _browserPlayback?.playingStream ??
      _player.playerStateStream
          .map(
            (state) =>
                state.playing &&
                state.processingState != ProcessingState.completed,
          )
          .distinct();

  @override
  Stream<Duration> get positionStream =>
      _browserPlayback?.positionStream ?? _player.positionStream;

  @override
  Stream<Duration?> get durationStream =>
      _browserPlayback?.durationStream ?? _player.durationStream;

  @override
  Duration get position => _browserPlayback?.position ?? _player.position;

  @override
  Duration? get duration => _browserPlayback?.duration ?? _player.duration;

  Future<void> _refreshAssetCacheOnce() {
    if (kIsWeb) {
      return Future<void>.value();
    }

    // just_audio extracts bundled assets into a persistent cache keyed by the
    // asset path. When an asset is replaced without changing its path, older
    // installations can otherwise keep playing the previously extracted file.
    // Share this future across service instances so the cache is cleared only
    // once per app process and always before the first asset is loaded.
    return _assetCacheRefresh ??= AudioPlayer.clearAssetCache();
  }

  @override
  Stream<void> get completionStream {
    final browserPlayback = _browserPlayback;
    if (browserPlayback != null) {
      return browserPlayback.playingStream
          .where((playing) => !playing)
          .map((_) {});
    }
    final expectedDuration = _player.duration;
    var currentPlaybackStarted =
        _player.processingState != ProcessingState.completed &&
        (_player.playing || _player.position > Duration.zero);
    return _player.playerStateStream
        .where((state) {
          if (state.playing &&
              state.processingState != ProcessingState.completed) {
            currentPlaybackStarted = true;
          }
          return isPlaybackAtSourceEnd(
            processingState: state.processingState,
            position: _player.position,
            duration: expectedDuration ?? _player.duration,
            currentPlaybackStarted: currentPlaybackStarted,
          );
        })
        .map((_) {});
  }

  Future<void> _setSource(Uri uri) async {
    if (uri.isScheme('asset')) {
      await _refreshAssetCacheOnce();
      final assetPath = uri.path.startsWith('/')
          ? uri.path.substring(1)
          : uri.path;
      await _player.setAsset(assetPath).timeout(const Duration(seconds: 8));
    } else if (uri.isScheme('file')) {
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
    final browserPlayback = _browserPlayback;
    if (browserPlayback != null) {
      await browserPlayback.preload(uri);
      _loadedOriginalUri = uri;
      _loadedResolvedUri = uri;
      return;
    }

    final revision = ++_preloadRevision;
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
    final requestedAt = DateTime.now();
    final browserPlayback = _browserPlayback;
    if (browserPlayback != null) {
      final reusedPreloadedSource = browserPlayback.hasPreloadedSource(uri);
      final preloadedSourceLoadedBeforePlayback = browserPlayback
          .hasLoadedPreloadedSource(uri);
      final preloadedSourceReadyBeforePlayback = browserPlayback
          .hasReadyPreloadedSource(uri);
      final loadStartedAt = DateTime.now();
      try {
        await browserPlayback.play(uri);
      } catch (error) {
        debugPrint('Browser audio playback failed: $error');
        throw const PlaybackException(
          'Safari chưa cho phép tự phát. Hãy chạm nút phát câu tiếng Anh.',
        );
      }
      final startedAt = DateTime.now();
      // Safari can dispatch loadeddata/canplay while the play() promise is
      // pending. Sample readiness again after playback starts so telemetry does
      // not report a false miss for the exact element that was successfully
      // buffered and reused.
      final preloadedSourceLoaded =
          preloadedSourceLoadedBeforePlayback ||
          browserPlayback.hasLoadedPreloadedSource(uri);
      final preloadedSourceReady =
          preloadedSourceReadyBeforePlayback ||
          browserPlayback.hasReadyPreloadedSource(uri);
      final preloadLoadedDuration = browserPlayback.preloadedSourceLoadedAfter(
        uri,
      );
      final preloadReadyDuration = browserPlayback.preloadedSourceReadyAfter(
        uri,
      );
      _loadedOriginalUri = uri;
      _loadedResolvedUri = uri;
      return PlaybackStartMetrics(
        audioLoadDuration: startedAt.difference(loadStartedAt),
        startedAfterRequest: startedAt.difference(requestedAt),
        // On Web this flag means no second network source was assigned after
        // finalize: the exact HTMLAudioElement preload continued into play().
        fromDeviceCache: reusedPreloadedSource,
        preloadedSourceLoaded: preloadedSourceLoaded,
        preloadedSourceReady: preloadedSourceReady,
        preloadLoadedDuration: preloadLoadedDuration,
        preloadReadyDuration: preloadReadyDuration,
      );
    }

    ++_preloadRevision;
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
        'Audio source ready for $uri after '
        '${loadedAt.difference(requestedAt).inMilliseconds} ms '
        '(duration: ${_player.duration}, position: ${_player.position}).',
      );
      return true;
    }());
    try {
      await _rewindCompletedPlayback();
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
    } catch (error) {
      debugPrint('Audio playback failed: $error');
      throw PlaybackException(
        kIsWeb
            ? 'Trình duyệt chưa cho phép phát âm thanh. Hãy chạm nút phát lại.'
            : 'Không thể bắt đầu phát câu tiếng Anh.',
      );
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
  Future<void> stop() => _browserPlayback?.pause() ?? _player.pause();

  @override
  Future<void> dispose() async {
    await _browserPlayback?.dispose();
    await _player.dispose();
    if (_ownsCache) {
      _cache.dispose();
    }
  }
}

@visibleForTesting
bool isPlaybackAtSourceEnd({
  required ProcessingState processingState,
  required Duration position,
  required Duration? duration,
  required bool currentPlaybackStarted,
}) {
  if (processingState != ProcessingState.completed ||
      !currentPlaybackStarted ||
      duration == null ||
      duration <= Duration.zero) {
    return false;
  }
  const tolerance = Duration(milliseconds: 200);
  return position >= duration - tolerance;
}

class PlaybackException implements Exception {
  const PlaybackException(this.message);

  final String message;

  @override
  String toString() => message;
}
