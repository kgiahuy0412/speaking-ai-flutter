import 'dart:typed_data';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:ai_speaking_flutter_app/features/home/presentation/home_learning_shell.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_listening_screen.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opens vocabulary, returns to communication, and opens topics', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
    expect(
      find.byKey(const Key('vocabulary-edge-tab')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('topic-listening-edge-tab')).hitTestable(),
      findsOneWidget,
    );
    final vocabularyRailRect = tester.getRect(
      find.byKey(const Key('vocabulary-edge-tab')),
    );
    final topicRailRect = tester.getRect(
      find.byKey(const Key('topic-listening-edge-tab')),
    );
    expect(vocabularyRailRect.size, const Size(47, 224));
    expect(topicRailRect.size, const Size(47, 224));
    expect(vocabularyRailRect.top, lessThan(topicRailRect.top - 40));
    expect(find.byKey(const Key('topic-listening-shortcut')), findsNothing);
    expect(find.text('50 chủ đề'), findsNothing);

    await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyHomeScreen).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const Key('vocabulary-practice-button')));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Chủ đề'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(TopicListeningScreen), findsOneWidget);
  });
}

Widget _app(ConversationController controller) {
  return MaterialApp(
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
  );
}

ConversationController _controller() {
  return ConversationController(
    audioInput: _FakeAudioInput(),
    playbackService: const _FakePlaybackService(),
    repository: const DemoConversationRepository(),
    childAge: 6,
  );
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
