import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/app/app_theme_mode.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/settings/presentation/settings_sheet.dart';
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
