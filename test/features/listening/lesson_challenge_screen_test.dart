import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_challenge_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the authored role-play before challenges from age eight', (
    tester,
  ) async {
    await _usePhoneSurface(tester);

    await tester.pumpWidget(_subject(startAge: 8));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('lesson-challenge-screen')), findsOneWidget);
    expect(find.text('Đoạn hội thoại'), findsOneWidget);
    expect(find.text('Lượt của bạn'), findsOneWidget);
    expect(find.text('Can I come in?'), findsOneWidget);
    expect(
      find.byKey(const Key('lesson-challenge-record-button')),
      findsOneWidget,
    );
    expect(find.text('Dừng và chấm'), findsOneWidget);
    expect(find.text('Nghe và trả lời'), findsNothing);
  });

  testWidgets(
    'skips role-play below age eight and keeps both authored choices',
    (tester) async {
      await _usePhoneSurface(tester);

      await tester.pumpWidget(_subject(startAge: 7));
      await tester.pump();
      await tester.pump();

      expect(find.text('Đoạn hội thoại'), findsNothing);
      expect(find.text('Thử thách nghe'), findsOneWidget);
      expect(find.text('Nghe và trả lời'), findsOneWidget);
      expect(find.text('Where is the library?'), findsOneWidget);
      expect(find.text('Go straight.'), findsOneWidget);
      expect(find.text('It is five dollars.'), findsOneWidget);
      expect(
        find.text('Hãy nói đáp án bằng tiếng Anh, không nói A hoặc B.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('lesson-challenge-record-button')),
        findsOneWidget,
      );
      expect(find.text('Dừng và chấm'), findsOneWidget);
    },
  );

  testWidgets(
    'automatically opens the H20 microphone again for challenge two',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _FakeLessonMediaService();
      await tester.pumpWidget(
        _subject(
          startAge: 7,
          mediaService: mediaService,
          challenges: const <ListeningChallengeContent>[
            ListeningChallengeContent(
              id: 'challenge-1',
              format: 'VI_TO_EN',
              prompt: 'Where is the library?',
              choices: <String>['Go straight.', 'It is five dollars.'],
              correctAnswer: 'Go straight.',
              correctVietnamese: 'Đi thẳng.',
              targetId: 'target-1',
            ),
            ListeningChallengeContent(
              id: 'challenge-2',
              format: 'VI_TO_EN',
              prompt: 'How are you?',
              choices: <String>['I am fine.', 'I am eight.'],
              correctAnswer: 'I am fine.',
              correctVietnamese: 'Con khỏe.',
              targetId: 'target-2',
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(mediaService.selectedOutputPreparations, 1);
      expect(mediaService.recordingStarts, 1);
      expect(find.text('Dừng và chấm'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lesson-challenge-record-button')));
      await tester.pumpAndSettle();

      expect(find.text('Câu 2/2'), findsOneWidget);
      expect(mediaService.selectedOutputPreparations, 2);
      expect(mediaService.recordingStarts, 2);
      expect(find.text('Dừng và chấm'), findsOneWidget);
    },
  );

  testWidgets(
    'opens the H20 microphone when iOS TTS omits its finish callback',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _FakeLessonMediaService();
      final voicePromptService = _MissingSecondFinishVoicePromptService();
      await tester.pumpWidget(
        _subject(
          startAge: 7,
          mediaService: mediaService,
          voicePromptService: voicePromptService,
        ),
      );
      await tester.pump();

      expect(mediaService.recordingStarts, 0);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(voicePromptService.stopCalls, greaterThanOrEqualTo(1));
      expect(mediaService.recordingStarts, 1);
      expect(find.text('Dừng và chấm'), findsOneWidget);
    },
  );

  testWidgets(
    'auto-stops, waits for a correct score, then opens challenge two',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _FakeLessonMediaService();
      final evaluator = _ControlledAttemptEvaluator();
      await tester.pumpWidget(
        _subject(
          startAge: 7,
          mediaService: mediaService,
          attemptEvaluator: evaluator,
          challenges: const <ListeningChallengeContent>[
            ListeningChallengeContent(
              id: 'challenge-1',
              format: 'VI_TO_EN',
              prompt: 'Where is the library?',
              choices: <String>['Go straight.', 'It is five dollars.'],
              correctAnswer: 'Go straight.',
              correctVietnamese: 'Đi thẳng.',
              targetId: 'target-1',
            ),
            ListeningChallengeContent(
              id: 'challenge-2',
              format: 'VI_TO_EN',
              prompt: 'How are you?',
              choices: <String>['I am fine.', 'I am eight.'],
              correctAnswer: 'I am fine.',
              correctVietnamese: 'Con khỏe.',
              targetId: 'target-2',
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(mediaService.recordingStarts, 1);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();

      expect(mediaService.recordingStops, 1);
      expect(evaluator.evaluationCalls, 1);
      expect(find.text('Câu 1/2'), findsOneWidget);
      expect(mediaService.recordingStarts, 1);

      evaluator.complete(LessonAttemptOutcome.good);
      await tester.pumpAndSettle();

      expect(find.text('Câu 2/2'), findsOneWidget);
      expect(mediaService.recordingStarts, 2);
      expect(find.text('Dừng và chấm'), findsOneWidget);
    },
  );

  testWidgets('iOS scores a challenge on device without calling the backend', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await _usePhoneSurface(tester);
    final mediaService = _FakeLessonMediaService();
    final speechInput = _FakeLessonEnglishSpeechInput('Go straight.');
    final backendEvaluator = _FailIfCalledAttemptEvaluator();
    await tester.pumpWidget(
      _subject(
        startAge: 7,
        mediaService: mediaService,
        iosSpeechInput: speechInput,
        attemptEvaluator: backendEvaluator,
        challenges: const <ListeningChallengeContent>[
          ListeningChallengeContent(
            id: 'challenge-1',
            format: 'VI_TO_EN',
            prompt: 'Where is the library?',
            choices: <String>['Go straight.', 'It is five dollars.'],
            correctAnswer: 'Go straight.',
            correctVietnamese: 'Đi thẳng.',
            targetId: 'target-1',
          ),
          ListeningChallengeContent(
            id: 'challenge-2',
            format: 'VI_TO_EN',
            prompt: 'How are you?',
            choices: <String>['I am fine.', 'I am eight.'],
            correctAnswer: 'I am fine.',
            correctVietnamese: 'Con khỏe.',
            targetId: 'target-2',
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(speechInput.startCalls, 1);
    expect(mediaService.recordingStarts, 0);
    expect(mediaService.nativeCaptureHandoffs, 1);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(speechInput.stopCalls, 1);
    expect(backendEvaluator.evaluationCalls, 0);
    expect(find.text('Câu 2/2'), findsOneWidget);
    expect(speechInput.startCalls, 2);
    expect(find.text('Dừng và chấm'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}

Widget _subject({
  required int startAge,
  _FakeLessonMediaService? mediaService,
  List<ListeningChallengeContent>? challenges,
  VoicePromptService? voicePromptService,
  LessonAttemptEvaluator? attemptEvaluator,
  LessonEnglishSpeechInput? iosSpeechInput,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: LessonChallengeScreen(
      language: DisplayLanguage.vietnamese,
      startAge: startAge,
      lesson: _lesson(),
      challenges:
          challenges ??
          const <ListeningChallengeContent>[
            ListeningChallengeContent(
              id: 'challenge-1',
              format: 'VI_TO_EN',
              prompt: 'Where is the library?',
              choices: <String>['Go straight.', 'It is five dollars.'],
              correctAnswer: 'Go straight.',
              correctVietnamese: 'Đi thẳng.',
              targetId: 'target-1',
            ),
          ],
      mediaService: mediaService ?? _FakeLessonMediaService(),
      attemptEvaluator: attemptEvaluator ?? const _AlwaysGoodAttemptEvaluator(),
      voicePromptService: voicePromptService ?? const _FakeVoicePromptService(),
      iosSpeechInput: iosSpeechInput,
    ),
  );
}

ListeningLessonContent _lesson() {
  return const ListeningLessonContent(
    id: 'challenge-test-lesson',
    number: 1,
    titleVi: 'Bài kiểm tra',
    titleEn: 'Challenge test',
    intro: '',
    outro: '',
    estimatedMinutes: 1,
    sentences: <ListeningSentenceContent>[],
    rolePlay: ListeningRolePlayContent(
      scenarioVi: 'Trong lớp học',
      openingHint: 'Can I...',
      turns: <ListeningRolePlayTurn>[
        ListeningRolePlayTurn(
          speaker: ListeningRolePlaySpeaker.child,
          english: 'Can I come in?',
          vietnamese: 'Con vào được không?',
        ),
      ],
    ),
  );
}

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
      filePath: 'test-recording.m4a',
      duration: Duration(seconds: 1),
    );
  }
}

class _AlwaysGoodAttemptEvaluator implements LessonAttemptEvaluator {
  const _AlwaysGoodAttemptEvaluator();

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
  }) async => LessonAttemptOutcome.good;
}

class _ControlledAttemptEvaluator implements LessonAttemptEvaluator {
  final Completer<LessonAttemptOutcome> _completion =
      Completer<LessonAttemptOutcome>();
  int evaluationCalls = 0;

  void complete(LessonAttemptOutcome outcome) => _completion.complete(outcome);

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
  }) {
    evaluationCalls += 1;
    return _completion.future;
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
    throw StateError('Backend must not be called for iOS on-device scoring.');
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
      inputLabel: 'H20 Apple Speech',
      confidence: 1,
      firstResultMs: 120,
      finalAfterStopMs: 80,
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

class _MissingSecondFinishVoicePromptService implements VoicePromptService {
  int speakCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) {
    speakCalls += 1;
    if (speakCalls == 1) {
      return Future<void>.value();
    }
    return Completer<void>().future;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }
}

Future<void> _usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
