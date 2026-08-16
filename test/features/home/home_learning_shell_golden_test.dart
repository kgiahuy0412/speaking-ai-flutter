import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/home/presentation/home_learning_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home communication matches image one', (tester) async {
    final controller = await _pumpGoldenApp(tester);
    addTearDown(controller.dispose);

    await expectLater(
      find.byType(HomeLearningShell),
      matchesGoldenFile('goldens/home-communication-390x844.png'),
    );
  });

  testWidgets('vocabulary page matches image two', (tester) async {
    final controller = await _pumpGoldenApp(tester);
    addTearDown(controller.dispose);

    await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(HomeLearningShell),
      matchesGoldenFile('goldens/home-vocabulary-390x844.png'),
    );
  });

  testWidgets('topic rail opens the catalog directly', (tester) async {
    final controller = await _pumpGoldenApp(tester);
    addTearDown(controller.dispose);

    await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-listening-screen')), findsOneWidget);
    expect(find.byKey(const Key('expanded-home-mode-rail')), findsNothing);
  });

  testWidgets('add vocabulary dialog matches image three', (tester) async {
    final controller = await _pumpGoldenApp(tester);
    addTearDown(controller.dispose);

    await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-vocabulary-button')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home-add-vocabulary-390x844.png'),
    );
  });
}

Future<ConversationController> _pumpGoldenApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await _loadGoldenFonts();
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final controller = ConversationController(
    audioInput: _FakeAudioInput(),
    playbackService: const _FakePlaybackService(),
    repository: const DemoConversationRepository(),
    childAge: 6,
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeLearningShell(
        controller: controller,
        config: AppConfig(
          backendBaseUri: Uri.parse('https://example.com'),
          useDemoBackend: true,
          childAge: 6,
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    final context = tester.element(find.byType(HomeLearningShell));
    await Future.wait<void>(
      const <AssetImage>[
        AssetImage('assets/images/learning-minimal-sky-background.png'),
        AssetImage('assets/images/mascot/penguin-avatar.png'),
        AssetImage('assets/images/mascot/penguin-listen.png'),
      ].map((provider) => precacheImage(provider, context)),
    );
  });
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _loadGoldenFonts() async {
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
  await Future.wait<void>(<Future<void>>[roboto.load(), materialIcons.load()]);
}

class _FakeAudioInput implements ChunkedAudioInput {
  @override
  String get label => 'Mic điện thoại';

  @override
  bool get isBluetooth => false;

  @override
  bool get isAvailable => true;

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<Uint8List> get audioChunks => const Stream<Uint8List>.empty();

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

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _FakePlaybackService implements AudioPlaybackService {
  const _FakePlaybackService();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async {
    return const PlaybackStartMetrics(
      audioLoadDuration: Duration.zero,
      startedAfterRequest: Duration.zero,
      fromDeviceCache: false,
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
