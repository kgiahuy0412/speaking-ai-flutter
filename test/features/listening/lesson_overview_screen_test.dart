import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_overview_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('V4 overview remains scroll-safe on a compact large-text phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: LessonOverviewScreen(
            language: DisplayLanguage.vietnamese,
            startAge: 8,
            endAge: 10,
            topic: listeningCatalogs[2].topics.first,
            lesson: _lesson,
            progressStore: const ListeningProgressStore(
              progressFilePath: 'build/overview-screen-test-progress.json',
            ),
            mediaService: LessonMediaService(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('lesson-overview-screen')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _lesson = ListeningLessonContent(
  id: 'overview-layout',
  code: 'C810-L1-T01-B01',
  number: 1,
  titleVi: 'My Daily Routine',
  titleEn: 'My Daily Routine',
  intro: '',
  outro: '',
  estimatedMinutes: 4,
  entry: ListeningLessonEntry(
    kind: ListeningLessonEntryKind.microObjective,
    text: 'Mình cùng nghe bài này nhé.',
  ),
  challengeBank: <ListeningChallengeContent>[
    ListeningChallengeContent(
      id: 'overview-q1',
      format: 'VI_TO_EN',
      prompt: 'Chào buổi sáng: Good morning hay Good night?',
      choices: <String>['Good morning.', 'Good night.'],
      correctAnswer: 'Good morning.',
      correctVietnamese: 'Chào buổi sáng.',
      targetId: 'overview-t1',
    ),
  ],
  sentences: <ListeningSentenceContent>[
    ListeningSentenceContent(
      id: 'overview-t1',
      number: 1,
      english: 'Good morning.',
      vietnamese: 'Chào buổi sáng.',
    ),
  ],
);
