import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/features/conversation/data/demo_conversation_repository.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_controller.dart';
import 'package:ai_speaking_flutter_app/features/conversation/presentation/conversation_screen.dart';
import 'package:ai_speaking_flutter_app/features/home/presentation/home_learning_shell.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_listening_screen.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_home_screen.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_controller.dart';
import 'package:flutter/foundation.dart';
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

  testWidgets('opens vocabulary from a recognized voice command', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final speechInput = _FakeStreamingSpeechInput();
    final voiceNavigationController = VoiceNavigationController(
      speechInput: speechInput,
      ownsSpeechInput: true,
    );
    final controller = _controller();
    addTearDown(controller.dispose);
    addTearDown(voiceNavigationController.dispose);

    await tester.pumpWidget(
      _app(controller, voiceNavigationController: voiceNavigationController),
    );
    await tester.pumpAndSettle();
    expect(
      await voiceNavigationController.dispatchRecognizedText('Hey Pico'),
      isTrue,
    );
    final handled = await voiceNavigationController.dispatchRecognizedText(
      'Con muốn học từ vựng',
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.byType(VocabularyHomeScreen).hitTestable(), findsOneWidget);
    expect(find.textContaining('Đã nhận lệnh giọng nói'), findsOneWidget);

    await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
    await tester.pumpAndSettle();
    expect(find.byType(TopicListeningScreen), findsOneWidget);

    expect(
      await voiceNavigationController.dispatchRecognizedText('Hey Pico'),
      isTrue,
    );
    final returnToVocabulary = voiceNavigationController.dispatchRecognizedText(
      'Con muốn học từ vựng',
    );
    await tester.pumpAndSettle();

    expect(await returnToVocabulary, isTrue);
    expect(find.byType(TopicListeningScreen), findsNothing);
    expect(find.byType(VocabularyHomeScreen).hitTestable(), findsOneWidget);
  });

  testWidgets('starts continuous voice navigation on Android', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final speechInput = _FakeStreamingSpeechInput();
    final voiceNavigationController = VoiceNavigationController(
      speechInput: speechInput,
    );
    final controller = _controller();

    await tester.pumpWidget(
      _app(
        controller,
        autoStartVoiceNavigation: true,
        voiceNavigationController: voiceNavigationController,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 901));

    expect(speechInput.startCount, 1);
    expect(voiceNavigationController.isListening, isTrue);
    expect(controller.isRecording, isFalse);
    expect(find.text('Bắt đầu nói'), findsOneWidget);
    expect(find.textContaining('Hey Pico'), findsOneWidget);

    await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
    await tester.pumpAndSettle();

    expect(find.byType(TopicListeningScreen), findsOneWidget);
    expect(voiceNavigationController.isListening, isTrue);
    expect(controller.isRecording, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    voiceNavigationController.dispose();
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}

Widget _app(
  ConversationController controller, {
  bool autoStartVoiceNavigation = false,
  VoiceNavigationController? voiceNavigationController,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: HomeLearningShell(
      controller: controller,
      voiceNavigationController: voiceNavigationController,
      config: AppConfig(
        backendBaseUri: Uri.parse('https://example.com'),
        useDemoBackend: true,
        childAge: 6,
        autoStartVoiceNavigation: autoStartVoiceNavigation,
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

class _FakeStreamingSpeechInput implements StreamingSpeechInput {
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<String> _partialTextController =
      StreamController<String>.broadcast();
  int startCount = 0;
  int cancelCount = 0;

  @override
  String get label => 'ASR Android trực tiếp';

  @override
  Stream<double> get amplitudeDbfs => _amplitudeController.stream;

  @override
  Stream<void> get completed => _completedController.stream;

  @override
  Stream<String> get partialText => _partialTextController.stream;

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<StreamingSpeechCapture> stop() async => const StreamingSpeechCapture(
    sourceText: 'Con muốn học từ vựng',
    duration: Duration(seconds: 1),
    inputLabel: 'ASR Android trực tiếp',
    confidence: 0.9,
    firstResultMs: 100,
    finalAfterStopMs: 20,
  );

  @override
  Future<void> cancel() {
    cancelCount += 1;
    return SynchronousFuture<void>(null);
  }

  @override
  Future<void> dispose() async {
    await _amplitudeController.close();
    await _completedController.close();
    await _partialTextController.close();
  }
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
