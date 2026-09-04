import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_challenge_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
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

      expect(mediaService.recordingStarts, 1);
      expect(find.text('Dừng và chấm'), findsOneWidget);

      await tester.tap(find.byKey(const Key('lesson-challenge-record-button')));
      await tester.pumpAndSettle();

      expect(find.text('Câu 2/2'), findsOneWidget);
      expect(mediaService.recordingStarts, 2);
      expect(find.text('Dừng và chấm'), findsOneWidget);
    },
  );
}

Widget _subject({
  required int startAge,
  _FakeLessonMediaService? mediaService,
  List<ListeningChallengeContent>? challenges,
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
      attemptEvaluator: const _AlwaysGoodAttemptEvaluator(),
      voicePromptService: const _FakeVoicePromptService(),
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

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> stopPlayback() async {}

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
  Future<LessonRecording> stopRecording() async => const LessonRecording(
    filePath: 'test-recording.m4a',
    duration: Duration(seconds: 1),
  );
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
