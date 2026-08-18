import 'dart:async';
import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/core/device/main_button_coordinator.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'H20 loopback records and plays locally without repository calls',
    () async {
      final input = _FakeAudioInput();
      final hfp = _FakeHfpAudioControl();
      final playback = _FakePlaybackService();
      final repository = _NoNetworkRepository();
      final controller = ConversationController(
        audioInput: input,
        hfpAudioControl: hfp,
        playbackService: playback,
        repository: repository,
        childAge: 6,
      );

      await controller.setH20HardwareTestMode(true);
      await controller.startH20OfflineRecording();

      expect(controller.h20HardwareTestPhase, H20HardwareTestPhase.recording);
      expect(input.startCount, 1);
      expect(hfp.startRouteCount, 1);
      expect(playback.communicationRouteActive, isTrue);

      await controller.stopAndReplayH20OfflineRecording();

      expect(input.stopCount, 1);
      expect(playback.playedUris.single.scheme, 'file');
      expect(hfp.stopRouteCount, 1);
      expect(repository.networkCallCount, 0);
      expect(controller.h20HardwareTestPhase, H20HardwareTestPhase.completed);
      expect(controller.h20HardwareTestResult?.inputRouteVerified, isTrue);
      expect(controller.h20HardwareTestResult?.outputRouteVerified, isTrue);
      expect(
        controller.h20HardwareTestResult?.inputDeviceName,
        'H20 Microphone',
      );
      expect(controller.h20HardwareTestResult?.outputDeviceName, 'H20 Speaker');
      expect(playback.communicationRouteActive, isFalse);

      controller.confirmH20PlaybackAudible(true);
      expect(controller.h20HardwareTestResult?.playbackAudible, isTrue);
      controller.dispose();
    },
  );

  test('bundled speaker test uses an APK asset and no network', () async {
    final hfp = _FakeHfpAudioControl();
    final playback = _FakePlaybackService();
    final repository = _NoNetworkRepository();
    final controller = ConversationController(
      audioInput: _FakeAudioInput(),
      hfpAudioControl: hfp,
      playbackService: playback,
      repository: repository,
      childAge: 6,
    );

    await controller.setH20HardwareTestMode(true);
    await controller.playH20BundledSpeakerTest();

    expect(playback.playedUris.single.scheme, 'asset');
    expect(
      playback.playedUris.single.path,
      'assets/audio/A-3-5/GUIDE_RECORD/A035_GUIDE_RECORD_01.mp3',
    );
    expect(controller.h20HardwareTestResult?.outputRouteVerified, isTrue);
    expect(repository.networkCallCount, 0);
    controller.dispose();
  });

  test(
    'offline recording refuses to claim H20 when SCO route is not active',
    () async {
      final controller = ConversationController(
        audioInput: _FakeAudioInput(),
        hfpAudioControl: _FakeHfpAudioControl(activateRoute: false),
        playbackService: _FakePlaybackService(),
        repository: _NoNetworkRepository(),
        childAge: 6,
      );

      await controller.setH20HardwareTestMode(true);

      await expectLater(
        controller.startH20OfflineRecording(),
        throwsA(isA<StateError>()),
      );
      expect(controller.h20HardwareTestPhase, H20HardwareTestPhase.error);
      expect(controller.h20HardwareTestResult, isNull);
      controller.dispose();
    },
  );

  test(
    'confirmed MAIN toggles offline recording and duplicate is ignored',
    () async {
      final aiv0 = _FakeAiv0BleControl(protocolConfirmed: true);
      final input = _FakeAudioInput();
      final playback = _FakePlaybackService();
      final controller = ConversationController(
        audioInput: input,
        hfpAudioControl: _FakeHfpAudioControl(),
        aiv0BleControl: aiv0,
        playbackService: playback,
        repository: _NoNetworkRepository(),
        childAge: 6,
      );
      await controller.setH20HardwareTestMode(true);

      aiv0.emitMain(sequence: 1);
      await _flushAsyncEvents();
      expect(controller.h20HardwareTestPhase, H20HardwareTestPhase.recording);

      aiv0.emitMain(sequence: 1, duplicate: true);
      await _flushAsyncEvents();
      expect(controller.h20HardwareTestPhase, H20HardwareTestPhase.recording);
      expect(input.stopCount, 0);

      aiv0.emitMain(sequence: 2);
      await _flushAsyncEvents();
      expect(controller.h20HardwareTestPhase, H20HardwareTestPhase.completed);
      expect(input.stopCount, 1);
      expect(playback.playedUris.single.scheme, 'file');
      controller.dispose();
    },
  );

  test('observed raw MAIN toggles capture without APP State writes', () async {
    final aiv0 = _FakeAiv0BleControl(protocolConfirmed: false);
    final input = _FakeAudioInput();
    final controller = ConversationController(
      audioInput: input,
      hfpAudioControl: _FakeHfpAudioControl(),
      aiv0BleControl: aiv0,
      playbackService: _FakePlaybackService(),
      repository: _NoNetworkRepository(),
      childAge: 6,
    );
    await controller.setH20HardwareTestMode(true);

    aiv0.emitObservedRawMain();
    await _flushAsyncEvents();

    expect(input.startCount, 1);
    expect(controller.h20HardwareTestPhase, H20HardwareTestPhase.recording);
    expect(controller.aiv0ButtonEventLog, hasLength(1));
    expect(aiv0.appStateWrites, 0);
    controller.dispose();
  });

  test(
    'BLE long press stops once and release does not restart capture',
    () async {
      final aiv0 = _FakeAiv0BleControl(protocolConfirmed: true);
      final input = _FakeAudioInput();
      final controller = ConversationController(
        audioInput: input,
        hfpAudioControl: _FakeHfpAudioControl(),
        aiv0BleControl: aiv0,
        playbackService: _FakePlaybackService(),
        repository: _NoNetworkRepository(),
        childAge: 6,
      );
      final coordinator = MainButtonCoordinator(
        onScreenShortPress: (_) async => MainButtonActionResult.accepted,
        onBleShortPress: controller.handleBleMainShortPress,
        onLongPress: (_) => controller.stopCurrentMainAction(),
      );
      controller.setMainButtonDispatcher(coordinator.handle);
      await controller.setH20HardwareTestMode(true);

      aiv0.emitMain(sequence: 1);
      await _flushAsyncEvents();
      expect(controller.h20HardwareTestPhase, H20HardwareTestPhase.recording);

      aiv0.emitMain(sequence: 2, gesture: Aiv0ButtonGesture.longPress);
      await _flushAsyncEvents();
      expect(controller.h20HardwareTestPhase, H20HardwareTestPhase.completed);
      expect(input.stopCount, 1);

      aiv0.emitMain(sequence: 2, gesture: Aiv0ButtonGesture.release);
      await _flushAsyncEvents();
      expect(controller.h20HardwareTestPhase, H20HardwareTestPhase.completed);
      expect(input.startCount, 1);
      expect(input.stopCount, 1);
      controller.dispose();
    },
  );
}

Future<void> _flushAsyncEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeAudioInput implements AudioInput {
  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;

  @override
  String get label => 'Mic điện thoại';

  @override
  bool get isBluetooth => false;

  @override
  bool get isAvailable => true;

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<AudioCapture> stop() async {
    stopCount += 1;
    return const AudioCapture(
      filePath: r'C:\temp\h20-offline-test.m4a',
      mimeType: 'audio/mp4',
      duration: Duration(seconds: 3),
      inputLabel: 'Mic điện thoại',
      isBluetoothInput: false,
      initialNoiseRms: null,
    );
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
  }

  @override
  Future<void> dispose() async {}
}

class _FakeHfpAudioControl implements HfpAudioControl {
  _FakeHfpAudioControl({this.activateRoute = true});

  final bool activateRoute;
  final StreamController<BluetoothAudioStatus> _statuses =
      StreamController<BluetoothAudioStatus>.broadcast(sync: true);
  BluetoothAudioStatus _status = const BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.ready,
    deviceId: '00:11:22:33:44:55',
    deviceName: 'H20',
    sampleRate: 16000,
  );
  int startRouteCount = 0;
  int stopRouteCount = 0;

  @override
  bool get usesBrowserAudioInput => false;

  @override
  BluetoothAudioStatus get status => _status;

  @override
  Stream<BluetoothAudioStatus> get statusChanges => _statuses.stream;

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
    startRouteCount += 1;
    if (!activateRoute) return;
    _status = const BluetoothAudioStatus(
      phase: BluetoothAudioConnectionPhase.recording,
      deviceId: '00:11:22:33:44:55',
      deviceName: 'H20',
      sampleRate: 16000,
      routeActive: true,
      inputDeviceName: 'H20 Microphone',
      outputDeviceName: 'H20 Speaker',
      audioRoute: 'HFP/SCO two-way',
    );
    _statuses.add(_status);
  }

  @override
  Future<void> stopAudioRoute() async {
    stopRouteCount += 1;
    _status = const BluetoothAudioStatus(
      phase: BluetoothAudioConnectionPhase.ready,
      deviceId: '00:11:22:33:44:55',
      deviceName: 'H20',
      sampleRate: 16000,
    );
    _statuses.add(_status);
  }

  @override
  Future<void> dispose() => _statuses.close();
}

class _FakePlaybackService
    implements
        AudioPlaybackService,
        CompletionAwareAudioPlaybackService,
        CommunicationRouteAwareAudioPlaybackService {
  final StreamController<void> _completions = StreamController<void>.broadcast(
    sync: true,
  );
  final List<Uri> playedUris = <Uri>[];
  bool communicationRouteActive = false;

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Stream<void> get completionStream => _completions.stream;

  @override
  void setCommunicationRouteActive(bool active) {
    communicationRouteActive = active;
  }

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    playedUris.add(uri);
    scheduleMicrotask(() => _completions.add(null));
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: true,
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() => _completions.close();
}

class _FakeAiv0BleControl implements Aiv0BleControl {
  _FakeAiv0BleControl({required this.protocolConfirmed});

  final bool protocolConfirmed;
  final StreamController<Aiv0BleStatus> _statuses =
      StreamController<Aiv0BleStatus>.broadcast(sync: true);
  final StreamController<Aiv0ButtonEvent> _buttons =
      StreamController<Aiv0ButtonEvent>.broadcast(sync: true);
  int appStateWrites = 0;

  @override
  Aiv0BleStatus get status => Aiv0BleStatus(
    phase: Aiv0BlePhase.connected,
    protocolConfirmed: protocolConfirmed,
    deviceId: 'H20-BLE',
    deviceName: 'H20',
    writeMode: 'withResponse',
  );

  @override
  Stream<Aiv0BleStatus> get statusStream => _statuses.stream;

  @override
  Stream<Aiv0ButtonEvent> get buttonEvents => _buttons.stream;

  void emitMain({
    required int sequence,
    Aiv0ButtonGesture gesture = Aiv0ButtonGesture.shortPress,
    bool duplicate = false,
  }) {
    final gestureByte = switch (gesture) {
      Aiv0ButtonGesture.shortPress => 1,
      Aiv0ButtonGesture.longPress => 2,
      Aiv0ButtonGesture.release => 3,
      Aiv0ButtonGesture.unknown => 0,
    };
    _buttons.add(
      Aiv0ButtonEvent(
        rawBytes: Uint8List.fromList(<int>[
          1,
          1,
          gestureByte,
          0,
          sequence,
          0,
          100,
          0,
          0,
          0,
          0,
          0,
        ]),
        receivedAt: DateTime.now(),
        button: Aiv0Button.main,
        gesture: gesture,
        sequence: sequence,
        isDraftPacket: true,
        isDuplicate: duplicate,
      ),
    );
  }

  void emitObservedRawMain() {
    _buttons.add(
      Aiv0ButtonEvent(
        rawBytes: Uint8List.fromList(<int>[
          0x01,
          0x01,
          0x10,
          0x01,
          0x01,
          0x04,
          0x3E,
          0x00,
          0x3A,
          0xF2,
          0x0B,
          0x00,
        ]),
        receivedAt: DateTime.now(),
        button: Aiv0Button.main,
        gesture: Aiv0ButtonGesture.shortPress,
        sequence: 0x10,
        isObservedH20Packet: true,
      ),
    );
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<List<Aiv0BleDevice>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async => const <Aiv0BleDevice>[];

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendAppState({
    required Aiv0AppState state,
    required Aiv0AppResult result,
    int sequence = 0,
  }) async {
    if (protocolConfirmed) appStateWrites += 1;
  }

  @override
  Future<void> dispose() async {
    await _statuses.close();
    await _buttons.close();
  }
}

class _NoNetworkRepository implements ConversationRepository {
  int networkCallCount = 0;

  Never _networkCalled() {
    networkCallCount += 1;
    throw StateError('The offline H20 test must not call the repository.');
  }

  @override
  Future<void> warmAudioCache() async {}

  @override
  Future<ConversationResult> processAudio({
    required AudioCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
    String? fallbackReason,
  }) async => _networkCalled();

  @override
  Future<ConversationResult> processStreamingText({
    required StreamingSpeechCapture capture,
    required PracticeContext context,
    required int childAge,
    required int vadSilenceMs,
  }) async => _networkCalled();

  @override
  Future<ConversationPreview?> previewStreamingText({
    required String sourceText,
    required PracticeContext context,
    required int childAge,
  }) async => _networkCalled();

  @override
  Future<ConversationLearningOutcome> review({
    required String conversationId,
    required bool approved,
  }) async => _networkCalled();

  @override
  Future<void> patchPlaybackLatency({
    required String conversationId,
    required int timeToFirstAudioMs,
    required int audioLoadMs,
    required bool audioFromDeviceCache,
    int? responseToPlaybackMs,
    bool? audioPreloadLoadedData,
    bool? audioPreloadCanPlay,
    int? audioPreloadLoadedDataMs,
    int? audioPreloadCanPlayMs,
  }) async => _networkCalled();

  @override
  Future<List<ConversationHistoryItem>> fetchHistory() async =>
      _networkCalled();

  @override
  Future<void> deleteHistoryItem(String conversationId) async =>
      _networkCalled();

  @override
  Future<void> clearHistory() async => _networkCalled();

  @override
  Future<void> dispose() async {}
}
