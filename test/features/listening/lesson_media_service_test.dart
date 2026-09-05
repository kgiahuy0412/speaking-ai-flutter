import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  test(
    'playToCompletion does not finish until playback reports ended',
    () async {
      final playback = _ControlledPlaybackService();
      final mediaService = LessonMediaService(playbackService: playback);
      var completed = false;

      final future = mediaService
          .playToCompletion(Uri.parse('https://example.test/intro.mp3'))
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);

      expect(playback.playCalls, 1);
      expect(completed, isFalse);

      playback.finish();
      await future;
      expect(completed, isTrue);

      await mediaService.dispose();
    },
  );

  test(
    'completion-aware playback ignores a temporary playing false state',
    () async {
      final playback = _CompletionAwareControlledPlaybackService();
      final mediaService = LessonMediaService(playbackService: playback);
      var completed = false;

      final future = mediaService
          .playToCompletion(Uri.parse('https://example.test/next-intro.mp3'))
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);

      playback.pauseTemporarily();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      playback.resume();
      playback.finish();
      await future;
      expect(completed, isTrue);

      await mediaService.dispose();
    },
  );

  test(
    'completion-aware playback ignores a completed state from the old source',
    () async {
      final playback = _StaleCompletionPlaybackService();
      final mediaService = LessonMediaService(playbackService: playback);
      var completed = false;

      final future = mediaService
          .playToCompletion(Uri.parse('https://example.test/new-intro.mp3'))
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(playback.playCalls, 1);
      expect(completed, isFalse);

      playback.finish();
      await future;
      expect(completed, isTrue);

      await mediaService.dispose();
    },
  );

  test(
    'Android selected H20 route is prepared before lesson playback starts',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final events = <String>[];
      final playback = _RouteAwareControlledPlaybackService(events);
      final hfp = _FakeHfpAudioControl(
        events,
        status: const BluetoothAudioStatus(
          phase: BluetoothAudioConnectionPhase.ready,
          deviceId: 'h20-uid',
          deviceName: 'H20',
          sampleRate: 16000,
        ),
      );
      final mediaService = LessonMediaService(
        playbackService: playback,
        hfpAudioControl: hfp,
      );

      final future = mediaService.playToCompletion(
        Uri.parse('https://example.test/guide.mp3'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, <String>[
        'communication:true',
        'prepare',
        'hfp:start',
        'play',
      ]);

      playback.finish();
      await future;
      await mediaService.stopPlayback();
      expect(hfp.stopCalls, 1);
      await mediaService.dispose();
    },
  );

  test('iOS selected H20 lesson playback holds HFP for output', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final events = <String>[];
    final playback = _RouteAwareControlledPlaybackService(events);
    final hfp = _FakeHfpAudioControl(
      events,
      status: const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.ready,
        deviceId: 'h20-uid',
        deviceName: 'H20',
        sampleRate: 16000,
      ),
    );
    final mediaService = LessonMediaService(
      playbackService: playback,
      hfpAudioControl: hfp,
    );

    final playing = mediaService.playToCompletion(
      Uri.parse('https://example.test/guide.mp3'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, <String>[
      'communication:true',
      'prepare',
      'hfp:start',
      'play',
    ]);
    expect(hfp.startCalls, 1);

    playback.finish();
    await playing;
    await mediaService.dispose();
  });

  test('phone playback does not activate an unselected HFP route', () async {
    final events = <String>[];
    final playback = _RouteAwareControlledPlaybackService(events);
    final hfp = _FakeHfpAudioControl(
      events,
      status: const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.idle,
        sampleRate: 16000,
      ),
    );
    final mediaService = LessonMediaService(
      playbackService: playback,
      hfpAudioControl: hfp,
    );

    final future = mediaService.playToCompletion(
      Uri.parse('https://example.test/guide.mp3'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, <String>['communication:false', 'prepare', 'play']);
    expect(hfp.startCalls, 0);

    playback.finish();
    await future;
    await mediaService.dispose();
  });

  test('coach prompt leaves H20 and plays on the phone speaker', () async {
    final events = <String>[];
    final playback = _RouteAwareControlledPlaybackService(events);
    final hfp = _FakeHfpAudioControl(
      events,
      status: const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.ready,
        deviceId: 'h20-uid',
        deviceName: 'H20',
        sampleRate: 16000,
      ),
    );
    final mediaService = LessonMediaService(
      playbackService: playback,
      hfpAudioControl: hfp,
    );

    final sample = mediaService.playToCompletion(
      Uri.parse('https://example.test/sample.mp3'),
    );
    await Future<void>.delayed(Duration.zero);
    playback.finish();
    await sample;

    final prompt = mediaService.playToCompletion(
      Uri.parse('https://example.test/coach.mp3'),
      route: LessonPlaybackRoute.phoneSpeaker,
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, <String>[
      'communication:true',
      'prepare',
      'hfp:start',
      'play',
      'communication:false',
      'hfp:stop',
      'prepare',
      'play',
    ]);

    playback.finish();
    await prompt;
    await mediaService.dispose();
  });

  test('consecutive H20 clips keep one owned SCO route', () async {
    final events = <String>[];
    final playback = _RouteAwareControlledPlaybackService(events);
    final hfp = _FakeHfpAudioControl(
      events,
      status: const BluetoothAudioStatus(
        phase: BluetoothAudioConnectionPhase.ready,
        deviceId: 'h20-uid',
        deviceName: 'H20',
        sampleRate: 16000,
      ),
    );
    final mediaService = LessonMediaService(
      playbackService: playback,
      hfpAudioControl: hfp,
    );

    for (final uri in <Uri>[
      Uri.parse('https://example.test/english.mp3'),
      Uri.parse('https://example.test/vietnamese.mp3'),
    ]) {
      final playing = mediaService.playToCompletion(uri);
      await Future<void>.delayed(Duration.zero);
      playback.finish();
      await playing;
    }

    expect(hfp.startCalls, 1);
    await mediaService.stopPlayback();
    expect(hfp.stopCalls, 1);
    await mediaService.dispose();
  });

  test('iOS lesson recording configuration is input-capable', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final hfpSession = lessonRecordingAudioSessionConfiguration(
      useSelectedHfp: true,
    );
    final phoneSession = lessonRecordingAudioSessionConfiguration(
      useSelectedHfp: false,
    );
    final hfpRecord = LessonMediaService.lessonRecordConfig(
      useSelectedHfp: true,
    );
    final phoneRecord = LessonMediaService.lessonRecordConfig(
      useSelectedHfp: false,
    );

    expect(
      hfpSession.avAudioSessionCategory,
      AVAudioSessionCategory.playAndRecord,
    );
    expect(hfpSession.avAudioSessionMode, AVAudioSessionMode.voiceChat);
    expect(
      hfpSession.avAudioSessionCategoryOptions,
      AVAudioSessionCategoryOptions.allowBluetooth,
    );
    expect(
      phoneSession.avAudioSessionCategoryOptions,
      AVAudioSessionCategoryOptions.defaultToSpeaker,
    );
    expect(hfpRecord.iosConfig.categoryOptions, <IosAudioCategoryOption>[
      IosAudioCategoryOption.allowBluetooth,
    ]);
    expect(phoneRecord.iosConfig.categoryOptions, <IosAudioCategoryOption>[
      IosAudioCategoryOption.defaultToSpeaker,
    ]);
    expect(hfpRecord.androidConfig.manageBluetooth, isFalse);
    expect(
      hfpRecord.androidConfig.audioSource,
      AndroidAudioSource.voiceCommunication,
    );
    expect(
      hfpRecord.androidConfig.audioManagerMode,
      AudioManagerMode.modeInCommunication,
    );
    expect(phoneRecord.androidConfig.manageBluetooth, isFalse);
    expect(phoneRecord.androidConfig.audioSource, AndroidAudioSource.mic);
    expect(
      phoneRecord.androidConfig.audioManagerMode,
      AudioManagerMode.modeNormal,
    );
    expect(hfpRecord.encoder, AudioEncoder.aacLc);
  });

  test('Android lesson recording is 16 kHz mono PCM WAV', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final recordConfig = LessonMediaService.lessonRecordConfig(
      useSelectedHfp: false,
    );

    expect(recordConfig.encoder, AudioEncoder.wav);
    expect(recordConfig.sampleRate, 16000);
    expect(recordConfig.numChannels, 1);
  });

  test('iOS recording input selects exact H20 UID and built-in phone mic', () {
    const builtIn = InputDevice(
      id: 'iphone-mic',
      label: 'iPhone Microphone',
      type: InputDeviceType.builtIn,
    );
    const otherHeadset = InputDevice(
      id: 'other-hfp',
      label: 'Other Headset',
      type: InputDeviceType.bluetoothSco,
    );
    const h20 = InputDevice(
      id: 'h20-uid',
      label: 'H20',
      type: InputDeviceType.bluetoothSco,
    );
    const devices = <InputDevice>[builtIn, otherHeadset, h20];

    expect(
      selectLessonRecordingInput(
        devices,
        useSelectedHfp: true,
        selectedHfpDeviceId: 'h20-uid',
      ),
      h20,
    );
    expect(selectLessonRecordingInput(devices, useSelectedHfp: false), builtIn);
  });
}

class _ControlledPlaybackService implements AudioPlaybackService {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  int playCalls = 0;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    playCalls += 1;
    _playing.add(true);
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  void finish() => _playing.add(false);

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> stop() async => finish();

  @override
  Future<void> dispose() => _playing.close();
}

class _CompletionAwareControlledPlaybackService
    implements AudioPlaybackService, CompletionAwareAudioPlaybackService {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<void> _completed = StreamController<void>.broadcast();

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<void> get completionStream => _completed.stream;

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    _playing.add(true);
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  void pauseTemporarily() => _playing.add(false);

  void resume() => _playing.add(true);

  void finish() {
    _completed.add(null);
    _playing.add(false);
  }

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> stop() async => _playing.add(false);

  @override
  Future<void> dispose() async {
    await Future.wait<void>(<Future<void>>[
      _playing.close(),
      _completed.close(),
    ]);
  }
}

class _StaleCompletionPlaybackService
    implements AudioPlaybackService, CompletionAwareAudioPlaybackService {
  _StaleCompletionPlaybackService() {
    _completed = StreamController<void>.broadcast(
      sync: true,
      onListen: () {
        final subscribedBeforeNewSourceStarted = playCalls == 0;
        if (subscribedBeforeNewSourceStarted) {
          scheduleMicrotask(() => _completed.add(null));
        }
      },
    );
  }

  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  late final StreamController<void> _completed;
  int playCalls = 0;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<void> get completionStream => _completed.stream;

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    playCalls += 1;
    _playing.add(true);
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  void finish() {
    _completed.add(null);
    _playing.add(false);
  }

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> stop() async => _playing.add(false);

  @override
  Future<void> dispose() async {
    await Future.wait<void>(<Future<void>>[
      _playing.close(),
      _completed.close(),
    ]);
  }
}

class _RouteAwareControlledPlaybackService extends _ControlledPlaybackService
    implements CommunicationRouteAwareAudioPlaybackService {
  _RouteAwareControlledPlaybackService(this.events);

  final List<String> events;

  @override
  void setCommunicationRouteActive(bool active) {
    events.add('communication:$active');
  }

  @override
  Future<void> prepare() async {
    events.add('prepare');
  }

  @override
  Future<PlaybackStartMetrics> play(Uri uri) {
    events.add('play');
    return super.play(uri);
  }
}

class _FakeHfpAudioControl implements HfpAudioControl {
  _FakeHfpAudioControl(this.events, {required this.status});

  final List<String> events;

  @override
  BluetoothAudioStatus status;

  int startCalls = 0;
  int stopCalls = 0;

  @override
  bool get usesBrowserAudioInput => false;

  @override
  Stream<BluetoothAudioStatus> get statusChanges =>
      const Stream<BluetoothAudioStatus>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<List<HfpAudioDevice>> findDevices() async => const <HfpAudioDevice>[];

  @override
  Future<void> connect(HfpAudioDevice device) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> startAudioRoute() async {
    startCalls += 1;
    events.add('hfp:start');
  }

  @override
  Future<void> stopAudioRoute() async {
    stopCalls += 1;
    events.add('hfp:stop');
  }

  @override
  Future<void> dispose() async {}
}
