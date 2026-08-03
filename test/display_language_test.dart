import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'language setting changes display text only and hides backend URL',
    (tester) async {
      final controller = ConversationController(
        audioInput: _FakeAudioInput(),
        playbackService: const _FakePlaybackService(),
        repository: const DemoConversationRepository(),
        childAge: 6,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(
            controller: controller,
            config: AppConfig(
              backendBaseUri: Uri.parse('https://hidden.example.com'),
              useDemoBackend: true,
              childAge: 6,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Ngôn ngữ hiển thị'), findsOneWidget);
      expect(find.text('Tiếng Việt'), findsOneWidget);
      expect(find.text('https://hidden.example.com'), findsNothing);
      expect(find.text('Backend'), findsNothing);

      await tester.tap(find.text('简体中文'));
      await tester.pumpAndSettle();

      expect(find.text('显示语言'), findsOneWidget);
      expect(find.text('Tiếng Việt'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('请说越南语'), findsOneWidget);
      expect(find.text('开始说话'), findsOneWidget);
      expect(find.text('越南语句子'), findsOneWidget);
      expect(find.text('英语句子'), findsOneWidget);
    },
  );
}

class _FakeAudioInput implements ChunkedAudioInput {
  final Stream<Uint8List> _chunks = const Stream<Uint8List>.empty();

  @override
  String get label => 'Mic điện thoại';

  @override
  bool get isBluetooth => false;

  @override
  bool get isAvailable => true;

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<Uint8List> get audioChunks => _chunks;

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
