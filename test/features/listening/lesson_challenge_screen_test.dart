import 'package:ai_speaking_flutter_app/app/app_theme.dart';
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

    expect(find.byKey(const Key('lesson-challenge-screen')), findsOneWidget);
    expect(find.text('Đoạn hội thoại'), findsOneWidget);
    expect(find.text('Lượt của bạn'), findsOneWidget);
    expect(find.text('Can I come in?'), findsOneWidget);
    expect(
      find.byKey(const Key('lesson-challenge-record-button')),
      findsOneWidget,
    );
    expect(find.text('Nghe và trả lời'), findsNothing);
  });

  testWidgets(
    'skips role-play below age eight and keeps both authored choices',
    (tester) async {
      await _usePhoneSurface(tester);

      await tester.pumpWidget(_subject(startAge: 7));
      await tester.pump();

      expect(find.text('Đoạn hội thoại'), findsNothing);
      expect(find.text('Thử thách nghe'), findsOneWidget);
      expect(find.text('Nghe và trả lời'), findsOneWidget);
      expect(find.text('Where is the library?'), findsOneWidget);
      expect(find.text('Go straight.'), findsOneWidget);
      expect(find.text('It is five dollars.'), findsOneWidget);
      expect(
        find.text('Hãy nói cả câu tiếng Anh đúng, không nói A hoặc B.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('lesson-challenge-record-button')),
        findsOneWidget,
      );
      expect(find.text('Nói câu trả lời'), findsOneWidget);
    },
  );
}

Widget _subject({required int startAge}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: LessonChallengeScreen(
      language: DisplayLanguage.vietnamese,
      startAge: startAge,
      lesson: _lesson(),
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
      ],
      mediaService: _FakeLessonMediaService(),
      attemptEvaluator: const _AlwaysGoodAttemptEvaluator(),
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
  @override
  Future<void> cancelRecording() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> stopPlayback() async {}
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

Future<void> _usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
