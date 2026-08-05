import 'dart:typed_data';

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

void main() {
  testWidgets('capture current settings top and bottom', (tester) async {
    await _loadAuditFonts();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = ConversationController(
      audioInput: _AuditAudioInput(),
      playbackService: const _AuditPlaybackService(),
      repository: const DemoConversationRepository(),
      childAge: 6,
    );
    addTearDown(controller.dispose);

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
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/01-settings-top-390x844.png'),
    );

    final scroll = find.byType(SingleChildScrollView).last;
    await tester.drag(scroll, const Offset(0, -1100));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/02-settings-bottom-390x844.png'),
    );
  });
}

Future<void> _loadAuditFonts() async {
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
  await Future.wait<void>(<Future<void>>[roboto.load(), materialIcons.load()]);
}

class _AuditAudioInput implements ChunkedAudioInput {
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

class _AuditPlaybackService implements AudioPlaybackService {
  const _AuditPlaybackService();

  @override
  Stream<bool> get playingStream => const Stream<bool>.empty();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> preload(Uri uri) async {}

  @override
  Future<PlaybackStartMetrics> play(Uri uri) async =>
      const PlaybackStartMetrics(
        audioLoadDuration: Duration.zero,
        startedAfterRequest: Duration.zero,
        fromDeviceCache: false,
      );

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
