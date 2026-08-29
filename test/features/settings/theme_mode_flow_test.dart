import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/app/app_theme_mode.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/device/aiv0_ble_control.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/settings_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('theme mode is persisted and restored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const store = AppThemeModeStore();

    expect(await store.read(), ThemeMode.system);

    await store.write(ThemeMode.dark);

    expect(await store.read(), ThemeMode.dark);
  });

  testWidgets('settings switches between dark and light immediately', (
    tester,
  ) async {
    final controller = ConversationController(
      audioInput: _FakeAudioInput(),
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    final mode = ValueNotifier<ThemeMode>(ThemeMode.system);
    addTearDown(controller.dispose);
    addTearDown(mode.dispose);

    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (context, value, _) => MaterialApp(
          theme: buildAppTheme(),
          darkTheme: buildDarkAppTheme(),
          themeMode: value,
          home: Scaffold(
            body: SettingsSheet(
              controller: controller,
              themeMode: value,
              onThemeModeChanged: (nextMode) => mode.value = nextMode,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('theme-mode-dark')));
    await tester.pumpAndSettle();

    expect(mode.value, ThemeMode.dark);
    expect(
      Theme.of(
        tester.element(find.byKey(const Key('appearance-settings-card'))),
      ).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byKey(const ValueKey<String>('theme-mode-light')));
    await tester.pumpAndSettle();

    expect(mode.value, ThemeMode.light);
    expect(
      Theme.of(
        tester.element(find.byKey(const Key('appearance-settings-card'))),
      ).brightness,
      Brightness.light,
    );
  });

  testWidgets('settings changes the child age group', (tester) async {
    final controller = ConversationController(
      audioInput: _FakeAudioInput(),
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    addTearDown(controller.dispose);
    int? selectedAge;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SettingsSheet(
            controller: controller,
            onChildAgeChanged: (age) {
              selectedAge = age;
              controller.setChildAge(age);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('settings-age-8-10')));
    await tester.pump();

    expect(selectedAge, 8);
    expect(controller.childAge, 8);
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('settings-age-8-10')),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets(
    'Android settings separates standard recognition from audio source',
    (tester) async {
      final controller = ConversationController(
        audioInput: _FakeAudioInput(),
        streamingSpeechInput: _FakeStreamingSpeechInput(),
        playbackService: const _FakePlaybackService(),
        repository: const DemoConversationRepository(),
        childAge: 6,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SettingsSheet(
              controller: controller,
              themeMode: ThemeMode.system,
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('android-standard-recognition')),
        500,
      );

      expect(find.text('Nhận dạng'), findsOneWidget);
      expect(find.text('Chế độ tiêu chuẩn'), findsOneWidget);
      expect(find.text('Mic điện thoại'), findsOneWidget);
      expect(find.text('Cloudflare Batch Chunks'), findsNothing);
      expect(find.text('HFP streaming'), findsNothing);
    },
  );

  testWidgets('iOS settings keeps the GATT disconnect cause visible', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final ble = _DiagnosticAiv0BleControl();
    final controller = ConversationController(
      audioInput: _FakeAudioInput(),
      aiv0BleControl: ble,
      playbackService: const _FakePlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: SettingsSheet(controller: controller)),
      ),
    );

    expect(find.byKey(const Key('aiv0-native-diagnostics')), findsOneWidget);
    expect(find.byKey(const Key('aiv0-ble-hfp-timeline')), findsOneWidget);
    expect(find.textContaining('BLE_DISCONNECTED'), findsOneWidget);
    expect(find.textContaining('disconnected'), findsWidgets);
    expect(find.textContaining('CBErrorDomain:7'), findsOneWidget);
    expect(find.textContaining('reconnect'), findsWidgets);
    expect(find.text('MAIN → trợ lý'), findsOneWidget);
    expect(find.textContaining('0 gói'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _DiagnosticAiv0BleControl implements Aiv0BleControl {
  final StreamController<Aiv0BleStatus> _statuses =
      StreamController<Aiv0BleStatus>.broadcast();
  final StreamController<Aiv0ButtonEvent> _buttons =
      StreamController<Aiv0ButtonEvent>.broadcast();

  @override
  Aiv0BleStatus get status => Aiv0BleStatus.fromMap(<Object?, Object?>{
    'phase': 'connected',
    'deviceId': 'H20-BLE',
    'deviceName': 'H20',
    'peripheralState': 'disconnected',
    'mainNotificationState': 'unavailable',
    'lastDisconnectCode': 'CBErrorDomain:7',
    'lastDisconnectMessage': 'The specified device has disconnected.',
    'lastDisconnectEpochMs': 1_787_987_522_081,
    'lastNotificationRecovery':
        'reconnect • peripheral=disconnected • notify=unavailable',
    'deferredRecoveryRepeatCount': 12,
    'diagnosticTimeline': <Object?>[
      <Object?, Object?>{
        'stage': 'BLE_DISCONNECTED',
        'caller': 'Aiv0BleControlBridge',
        'eventEpochMs': 1_787_987_522_081,
        'systemIsReconnecting': false,
      },
    ],
  }, protocolConfirmed: false);

  @override
  Stream<Aiv0BleStatus> get statusStream => _statuses.stream;

  @override
  Stream<Aiv0ButtonEvent> get buttonEvents => _buttons.stream;

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> markParentDiagnosticsOpened() async {}

  @override
  Future<void> dispose() async {
    await _statuses.close();
    await _buttons.close();
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<List<Aiv0BleDevice>> scan({Duration timeout = Duration.zero}) async =>
      const <Aiv0BleDevice>[];

  @override
  Future<void> sendAppState({
    required Aiv0AppState state,
    required Aiv0AppResult result,
    int sequence = 0,
  }) async {}
}

class _FakeStreamingSpeechInput implements StreamingSpeechInput {
  @override
  String get label => 'Chế độ tiêu chuẩn';

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  Stream<String> get partialText => const Stream<String>.empty();

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {}

  @override
  Future<StreamingSpeechCapture> stop() async => const StreamingSpeechCapture(
    sourceText: 'Con muốn uống nước',
    duration: Duration(seconds: 1),
    inputLabel: 'Mic điện thoại',
    confidence: 0.9,
    firstResultMs: 100,
    finalAfterStopMs: 20,
  );

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeAudioInput implements ChunkedAudioInput {
  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<Uint8List> get audioChunks => const Stream<Uint8List>.empty();

  @override
  bool get isAvailable => true;

  @override
  bool get isBluetooth => false;

  @override
  String get label => 'Mic điện thoại';

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> startChunked() async {}

  @override
  Future<AudioCapture> stop() async => const AudioCapture(
    filePath: 'unused.wav',
    mimeType: 'audio/wav',
    duration: Duration(seconds: 1),
    inputLabel: 'Mic điện thoại',
    isBluetoothInput: false,
    initialNoiseRms: null,
  );
}

class _FakePlaybackService implements AudioPlaybackService {
  const _FakePlaybackService();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async =>
      const PlaybackStartMetrics(
        audioLoadDuration: Duration.zero,
        startedAfterRequest: Duration.zero,
        fromDeviceCache: false,
      );

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<void> stop() async {}
}
