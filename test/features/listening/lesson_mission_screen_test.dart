import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_mission_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('automatically records, scores, and opens the next mission', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _FakeLessonMediaService();
    final evaluator = _QueuedAttemptEvaluator(<LessonAttemptOutcome>[
      LessonAttemptOutcome.good,
    ]);

    await tester.pumpWidget(
      _subject(mediaService: mediaService, attemptEvaluator: evaluator),
    );
    await tester.pump();
    await tester.pump();

    expect(mediaService.selectedOutputPreparations, 1);
    expect(mediaService.recordingStarts, 1);
    expect(find.text('Dừng và chấm'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    await tester.pump();

    expect(mediaService.recordingStops, 1);
    expect(evaluator.evaluationCalls, 1);
    expect(find.textContaining('Câu 2/4'), findsOneWidget);
    expect(mediaService.recordingStarts, 2);
    expect(find.text('Dừng và chấm'), findsOneWidget);
  });

  testWidgets('automatically reopens recording after the first retry', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _FakeLessonMediaService();
    final evaluator = _QueuedAttemptEvaluator(<LessonAttemptOutcome>[
      LessonAttemptOutcome.retry,
      LessonAttemptOutcome.good,
    ]);

    await tester.pumpWidget(
      _subject(mediaService: mediaService, attemptEvaluator: evaluator),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Câu 1/4'), findsOneWidget);
    expect(mediaService.recordingStarts, 2);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    await tester.pump();

    expect(evaluator.evaluationCalls, 2);
    expect(find.textContaining('Câu 2/4'), findsOneWidget);
    expect(mediaService.recordingStarts, 3);
  });

  testWidgets('iOS automatically scores a mission on device', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _usePhoneSurface(tester);
    final mediaService = _FakeLessonMediaService();
    final speechInput = _FakeLessonEnglishSpeechInput('Wake up at seven.');
    final evaluator = _FailIfCalledAttemptEvaluator();

    await tester.pumpWidget(
      _subject(
        mediaService: mediaService,
        attemptEvaluator: evaluator,
        iosSpeechInput: speechInput,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(speechInput.startCalls, 1);
    expect(mediaService.recordingStarts, 0);
    expect(mediaService.nativeCaptureHandoffs, 1);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    await tester.pump();

    expect(speechInput.stopCalls, 1);
    expect(evaluator.evaluationCalls, 0);
    expect(find.textContaining('Câu 2/4'), findsOneWidget);
    expect(speechInput.startCalls, 2);
    debugDefaultTargetPlatformOverride = null;
  });
}

Widget _subject({
  required _FakeLessonMediaService mediaService,
  required LessonAttemptEvaluator attemptEvaluator,
  LessonEnglishSpeechInput? iosSpeechInput,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: LessonMissionScreen(
      language: DisplayLanguage.vietnamese,
      startAge: 7,
      lesson: _lesson,
      missions: _missions,
      mediaService: mediaService,
      attemptEvaluator: attemptEvaluator,
      voicePromptService: const _FakeVoicePromptService(),
      iosSpeechInput: iosSpeechInput,
      levelTitle: 'Level 1: Xây nền',
    ),
  );
}

const _lesson = ListeningLessonContent(
  id: 'mission-test-lesson',
  number: 1,
  code: 'MISSION_TEST',
  titleVi: 'Bài kiểm tra',
  titleEn: 'Mission test',
  intro: '',
  outro: '',
  estimatedMinutes: 1,
  sentences: <ListeningSentenceContent>[],
);

const _missions = <ListeningMissionContent>[
  ListeningMissionContent(
    id: 'mission-1',
    topicNumber: 1,
    format: 'VI_TO_EN',
    prompt: 'Bạn cần nói “Thức dậy lúc bảy giờ”.',
    choices: <String>['Wake up at seven.', 'School starts at eight.'],
    correctAnswer: 'Wake up at seven.',
    correctVietnamese: 'Thức dậy lúc bảy giờ.',
    coverageTargetId: 'target-1',
  ),
  ListeningMissionContent(
    id: 'mission-2',
    topicNumber: 1,
    format: 'VI_TO_EN',
    prompt: 'Bạn cần nói “Trường bắt đầu lúc tám giờ”.',
    choices: <String>['Wake up at seven.', 'School starts at eight.'],
    correctAnswer: 'School starts at eight.',
    correctVietnamese: 'Trường bắt đầu lúc tám giờ.',
    coverageTargetId: 'target-2',
  ),
  ListeningMissionContent(
    id: 'mission-3',
    topicNumber: 1,
    format: 'VI_TO_EN',
    prompt: 'Bạn cần nói “Con khỏe”.',
    choices: <String>['I am fine.', 'I am eight.'],
    correctAnswer: 'I am fine.',
    correctVietnamese: 'Con khỏe.',
    coverageTargetId: 'target-3',
  ),
  ListeningMissionContent(
    id: 'mission-4',
    topicNumber: 1,
    format: 'VI_TO_EN',
    prompt: 'Bạn cần nói “Đi thẳng”.',
    choices: <String>['Go straight.', 'Turn left.'],
    correctAnswer: 'Go straight.',
    correctVietnamese: 'Đi thẳng.',
    coverageTargetId: 'target-4',
  ),
];

class _FakeLessonMediaService extends LessonMediaService {
  int recordingStarts = 0;
  int recordingStops = 0;
  int selectedOutputPreparations = 0;
  int nativeCaptureHandoffs = 0;

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> prepareSelectedLessonOutput() async {
    selectedOutputPreparations += 1;
  }

  @override
  void handoffSelectedLessonOutputToNativeCapture() {
    nativeCaptureHandoffs += 1;
  }

  @override
  Future<void> startRecording({
    required String lessonId,
    required int sentenceNumber,
    String? lessonTitle,
    String? sentenceId,
    String? english,
    String? vietnamese,
    bool saveToHistory = true,
  }) async {
    recordingStarts += 1;
  }

  @override
  Future<LessonRecording> stopRecording() async {
    recordingStops += 1;
    return const LessonRecording(
      filePath: 'mission-test.wav',
      duration: Duration(seconds: 1),
    );
  }
}

class _QueuedAttemptEvaluator implements LessonAttemptEvaluator {
  _QueuedAttemptEvaluator(this.outcomes);

  final List<LessonAttemptOutcome> outcomes;
  int evaluationCalls = 0;

  @override
  Future<LessonAttemptOutcome> evaluate({
    required String lessonCode,
    required String sentenceId,
    required String expectedEnglish,
    required String recordingPath,
    required Duration recordingDuration,
    required int attemptNumber,
    required int childAge,
    Iterable<String> acceptedVariants = const <String>[],
    bool requireAllExpectedTokens = false,
  }) async {
    final outcome = outcomes[evaluationCalls];
    evaluationCalls += 1;
    return outcome;
  }
}

class _FailIfCalledAttemptEvaluator implements LessonAttemptEvaluator {
  int evaluationCalls = 0;

  @override
  Future<LessonAttemptOutcome> evaluate({
    required String lessonCode,
    required String sentenceId,
    required String expectedEnglish,
    required String recordingPath,
    required Duration recordingDuration,
    required int attemptNumber,
    required int childAge,
    Iterable<String> acceptedVariants = const <String>[],
    bool requireAllExpectedTokens = false,
  }) async {
    evaluationCalls += 1;
    throw StateError('Backend must not be called for iOS mission scoring.');
  }
}

class _FakeLessonEnglishSpeechInput implements LessonEnglishSpeechInput {
  _FakeLessonEnglishSpeechInput(this.transcript);

  final String transcript;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> startLessonEnglishRecognition() async {
    startCalls += 1;
  }

  @override
  Future<StreamingSpeechCapture> stop() async {
    stopCalls += 1;
    return StreamingSpeechCapture(
      sourceText: transcript,
      duration: const Duration(seconds: 1),
      inputLabel: 'Apple Speech',
      confidence: 1,
      firstResultMs: 100,
      finalAfterStopMs: 50,
      alternatives: const <String>[],
    );
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }
}

class _FakeVoicePromptService implements VoicePromptService {
  const _FakeVoicePromptService();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> stop() async {}
}

Future<void> _usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
