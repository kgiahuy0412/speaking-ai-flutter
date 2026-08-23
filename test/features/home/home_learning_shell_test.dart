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
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_home_screen.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_session_controller.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/voice_navigation_controller.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/presentation/main_voice_assistant_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('reports settings modal visibility until the sheet closes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _controller();
    addTearDown(controller.dispose);
    final visibilityChanges = <bool>[];

    await tester.pumpWidget(
      _app(controller, onModalVisibilityChanged: visibilityChanges.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Cài đặt lượt nói'), findsOneWidget);
    expect(visibilityChanges, <bool>[true]);

    Navigator.of(tester.element(find.text('Cài đặt lượt nói'))).pop();
    await tester.pumpAndSettle();

    expect(visibilityChanges, <bool>[true, false]);
  });

  testWidgets('iOS exposes every primary navigation action and MAIN', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final speechInput = _FakeStreamingSpeechInput();
    final voiceNavigationController = VoiceNavigationController(
      speechInput: speechInput,
      ownsSpeechInput: true,
    );
    final speakingSessionController = MainSpeakingSessionController();
    final controller = _controller();
    addTearDown(controller.dispose);
    addTearDown(voiceNavigationController.dispose);
    addTearDown(speakingSessionController.dispose);

    await tester.pumpWidget(
      _app(
        controller,
        autoStartVoiceNavigation: true,
        voiceNavigationController: voiceNavigationController,
        speakingSessionController: speakingSessionController,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
    expect(speechInput.startCount, 0);

    await tester.tap(find.byTooltip('Lịch sử gần đây'));
    await tester.pumpAndSettle();
    expect(find.text('Lịch sử gần đây'), findsWidgets);
    Navigator.of(tester.element(find.text('Lịch sử gần đây').last)).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cài đặt'));
    await tester.pumpAndSettle();
    expect(find.text('Cài đặt lượt nói'), findsOneWidget);
    expect(find.byKey(const Key('ios-native-recognition')), findsOneWidget);
    expect(find.byKey(const Key('android-standard-recognition')), findsNothing);
    Navigator.of(tester.element(find.text('Cài đặt lượt nói'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyHomeScreen).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const Key('vocabulary-edge-tab')));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);

    await tester.tap(find.byKey(const Key('main-voice-assistant-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(speechInput.startCount, 1);
    expect(voiceNavigationController.isMainButtonSessionActive, isTrue);
    expect(voiceNavigationController.isListening, isTrue);
    expect(find.text('Đang nghe...'), findsOneWidget);

    // BLE/HFP status and diagnostics are surfaced through ConversationController
    // notifications. On iOS they must not cancel the explicit MAIN recognizer;
    // only Android owns the optional always-on navigation lifecycle here.
    controller.setChildAge(7);
    await tester.pump();
    await tester.pump();
    expect(voiceNavigationController.isMainButtonSessionActive, isTrue);
    expect(voiceNavigationController.isListening, isTrue);
    expect(speechInput.cancelCount, 0);
    expect(find.text('Đang nghe...'), findsOneWidget);

    await voiceNavigationController.pause();
    await tester.pump();
    await tester.tap(find.byKey(const Key('topic-listening-edge-tab')));
    await tester.pumpAndSettle();
    expect(find.byType(TopicListeningScreen), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
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
      _app(
        controller,
        voiceNavigationController: voiceNavigationController,
        listeningContentFuture: AssetListeningContentRepository(
          bundle: rootBundle,
        ).load(),
      ),
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

  testWidgets('opens a lesson inside a named topic from voice', (tester) async {
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
      _app(
        controller,
        voiceNavigationController: voiceNavigationController,
        listeningContentFuture: AssetListeningContentRepository(
          bundle: rootBundle,
        ).load(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      await voiceNavigationController.dispatchRecognizedText('Hey Pico'),
      isTrue,
    );
    expect(
      await voiceNavigationController.dispatchRecognizedText(
        'Con muốn học bài 1 trong chủ đề Gia đình và ngôi nhà',
      ),
      isTrue,
    );

    for (var index = 0; index < 14; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    for (var index = 0; index < 20; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final openedLessonScreenCount = <Key>[
      const Key('lesson-intro-screen'),
      const Key('lesson-review-screen'),
      const Key('lesson-practice-screen'),
    ].fold<int>(0, (count, key) => count + find.byKey(key).evaluate().length);
    expect(openedLessonScreenCount, 1);
  });

  testWidgets('Main flow uses spoken age to open topic 3 lesson 1', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final contentFuture = AssetListeningContentRepository(
      bundle: rootBundle,
    ).load();
    final speechInput = _FakeStreamingSpeechInput();
    final voiceNavigationController = VoiceNavigationController(
      speechInput: speechInput,
      ownsSpeechInput: true,
      mainAssistantFlow: MainVoiceAssistantFlow(
        contentLoader: () => contentFuture,
      ),
    );
    final controller = _controller();
    addTearDown(controller.dispose);
    addTearDown(voiceNavigationController.dispose);

    await tester.pumpWidget(
      _app(
        controller,
        childAge: 4,
        voiceNavigationController: voiceNavigationController,
        listeningContentFuture: contentFuture,
      ),
    );
    await tester.pumpAndSettle();

    expect(await voiceNavigationController.activateFromMainButton(), isTrue);
    expect(
      await voiceNavigationController.dispatchRecognizedText(
        'Con muốn học theo chủ đề',
      ),
      isTrue,
    );
    expect(
      await voiceNavigationController.dispatchRecognizedText('Con 6 tuổi'),
      isTrue,
    );
    expect(
      await voiceNavigationController.dispatchRecognizedText(
        'Con muốn học chủ đề số 3',
      ),
      isTrue,
    );
    for (var index = 0; index < 20; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Cặp sách và lớp học'), findsWidgets);
    expect(find.byKey(const Key('topic-lesson-list-screen')), findsOneWidget);

    final openLesson = voiceNavigationController.dispatchRecognizedText(
      'Con học bài số 1',
    );
    for (var index = 0; index < 40; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(await openLesson, isTrue);
    for (var index = 0; index < 40; index += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final openedLessonScreenCount = <Key>[
      const Key('lesson-intro-screen'),
      const Key('lesson-review-screen'),
      const Key('lesson-practice-screen'),
    ].fold<int>(0, (count, key) => count + find.byKey(key).evaluate().length);
    expect(openedLessonScreenCount, 1);
  });

  testWidgets(
    'Main speaking choice hands off to the automatic speaking session',
    (tester) async {
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
      var didStartMainSpeakingMode = false;

      await tester.pumpWidget(
        _app(
          controller,
          voiceNavigationController: voiceNavigationController,
          onMainSpeakingModeStarted: () => didStartMainSpeakingMode = true,
        ),
      );
      await tester.pumpAndSettle();

      expect(await voiceNavigationController.activateFromMainButton(), isTrue);
      expect(
        await voiceNavigationController.dispatchRecognizedText(
          'Con ghi muốn luyện nói',
        ),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
      expect(didStartMainSpeakingMode, isTrue);
      expect(controller.isRecording, isFalse);

      controller.dispose();
      voiceNavigationController.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('translation choice enters continuous translation directly', (
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
    var didStartContinuousMode = false;

    await tester.pumpWidget(
      _app(
        controller,
        voiceNavigationController: voiceNavigationController,
        onMainSpeakingModeStarted: () => didStartContinuousMode = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(await voiceNavigationController.activateFromMainButton(), isTrue);
    expect(
      await voiceNavigationController.dispatchRecognizedText(
        'Dịch sang tiếng Anh',
      ),
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(find.byType(ConversationScreen).hitTestable(), findsOneWidget);
    expect(didStartContinuousMode, isTrue);
    expect(controller.isRecording, isFalse);

    controller.dispose();
    voiceNavigationController.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _app(
  ConversationController controller, {
  bool autoStartVoiceNavigation = false,
  int childAge = 6,
  VoiceNavigationController? voiceNavigationController,
  Future<ListeningContentCatalog>? listeningContentFuture,
  MainSpeakingSessionController? speakingSessionController,
  VoidCallback? onMainSpeakingModeStarted,
  ValueChanged<bool>? onModalVisibilityChanged,
}) {
  final home = HomeLearningShell(
    controller: controller,
    voiceNavigationController: voiceNavigationController,
    listeningContentFuture: listeningContentFuture,
    onMainSpeakingModeStarted: onMainSpeakingModeStarted,
    onModalVisibilityChanged: onModalVisibilityChanged,
    config: AppConfig(
      backendBaseUri: Uri.parse('https://example.com'),
      useDemoBackend: true,
      childAge: childAge,
      autoStartVoiceNavigation: autoStartVoiceNavigation,
    ),
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: speakingSessionController == null
        ? home
        : Stack(
            fit: StackFit.expand,
            children: <Widget>[
              home,
              Positioned(
                right: 16,
                bottom: 88,
                child: MainVoiceAssistantButton(
                  voiceController: voiceNavigationController!,
                  conversationController: controller,
                  speakingSessionController: speakingSessionController,
                  isActivationPending: false,
                  onPressed: () async {
                    await voiceNavigationController.activateFromMainButton();
                  },
                  onLongPressed: () async {},
                  onLongPressReleased: () async {},
                ),
              ),
            ],
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
  Future<void> cancel() async {
    cancelCount += 1;
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
