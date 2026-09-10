import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_guide_audio_library.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_intro_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_overview_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_practice_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('V4 resumes from its first interrupted core sentence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 8,
          endAge: 10,
          topic: listeningCatalogs[2].topics.first,
          lesson: _lesson,
          progressStore: _OverviewProgressStore(coreStarted: true),
          mediaService: _OverviewMediaService(),
          guideAudioLibrary: LessonGuideAudioLibrary(
            assetPaths: const <String>[],
          ),
          voicePromptService: const _ImmediateVoicePromptService(),
          autoAdvance: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Mình học tiếp bài My Daily Routine nhé.'),
      findsOneWidget,
    );
  });

  testWidgets('V4 announces an interrupted role-play separately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 8,
          endAge: 10,
          topic: listeningCatalogs[2].topics.first,
          lesson: _lesson,
          progressStore: _OverviewProgressStore(
            coreStarted: true,
            resumeStage: ListeningResumeStage.rolePlay,
          ),
          mediaService: _OverviewMediaService(),
          guideAudioLibrary: LessonGuideAudioLibrary(
            assetPaths: const <String>[],
          ),
          voicePromptService: const _ImmediateVoicePromptService(),
          autoAdvance: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Mình tiếp tục đoạn hội thoại nhé.'), findsOneWidget);
  });

  testWidgets('V4 does not announce replay for an interrupted song', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 8,
          endAge: 10,
          topic: listeningCatalogs[2].topics.first,
          lesson: _lesson,
          progressStore: _OverviewProgressStore(
            coreStarted: true,
            resumeStage: ListeningResumeStage.song,
          ),
          mediaService: _OverviewMediaService(),
          guideAudioLibrary: LessonGuideAudioLibrary(
            assetPaths: const <String>[],
          ),
          voicePromptService: const _ImmediateVoicePromptService(),
          autoAdvance: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Mình tiếp tục phần tiếp theo nhé.'), findsOneWidget);
    expect(find.text('Mình nghe lại bài hát từ đầu nhé.'), findsNothing);
  });

  testWidgets('intro opens V4 practice directly without overview prompts', (
    tester,
  ) async {
    final voicePrompt = _TransitionVoicePromptService();
    addTearDown(voicePrompt.release);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 8,
          endAge: 10,
          topic: listeningCatalogs[2].topics.first,
          lesson: _lesson,
          progressStore: _OverviewProgressStore(),
          mediaService: _OverviewMediaService(),
          voicePromptService: voicePrompt,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-lesson-intro')));
    for (
      var attempt = 0;
      attempt < 12 && find.byType(LessonPracticeScreen).evaluate().isEmpty;
      attempt += 1
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.byType(LessonPracticeScreen),
      findsOneWidget,
      reason: 'Spoken prompts: ${voicePrompt.spoken}',
    );
    expect(
      voicePrompt.spoken,
      isNot(contains('vi-VN|Bạn nghe qua nội dung trước nhé.')),
    );
    expect(find.byType(LessonOverviewScreen), findsNothing);
    expect(voicePrompt.stopCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('legacy overview route forwards directly into practice', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final voicePrompt = _TransitionVoicePromptService();
    addTearDown(voicePrompt.release);

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
            voicePromptService: voicePrompt,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(LessonPracticeScreen), findsOneWidget);
    expect(find.byKey(const Key('lesson-overview-screen')), findsNothing);
    expect(
      voicePrompt.spoken,
      isNot(contains('vi-VN|Bạn nghe qua nội dung trước nhé.')),
    );
    expect(tester.takeException(), isNull);
  });
}

class _ImmediateVoicePromptService implements VoicePromptService {
  const _ImmediateVoicePromptService();

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _TransitionVoicePromptService implements VoicePromptService {
  final List<String> spoken = <String>[];
  final Completer<void> _overviewRelease = Completer<void>();
  int stopCount = 0;

  void release() {
    if (!_overviewRelease.isCompleted) _overviewRelease.complete();
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      speakAndWait(text, locale: locale);

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    spoken.add('$locale|$text');
    if (text == 'Bạn nghe qua nội dung trước nhé.') {
      await _overviewRelease.future;
    }
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    release();
  }

  @override
  Future<void> dispose() => stop();
}

class _OverviewProgressStore extends ListeningProgressStore {
  _OverviewProgressStore({
    this.coreStarted = false,
    this.resumeStage = ListeningResumeStage.core,
  });

  final bool coreStarted;
  final ListeningResumeStage resumeStage;

  @override
  Future<int> readLesson(String lessonId) async => 0;

  @override
  Future<int> readCurrentSentence(String lessonId) async => 0;

  @override
  Future<ListeningResumeStage> readResumeStage(String lessonId) async =>
      resumeStage;

  @override
  Future<bool> hasStartedLessonCore(String lessonId) async => coreStarted;

  @override
  Future<bool> hasCompletedV4LessonActivity(String lessonId) async => false;

  @override
  Future<bool> hasOpenedLearningGuide() async => false;

  @override
  Future<void> markLearningGuideOpened() async {}
}

class _OverviewMediaService extends LessonMediaService {
  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {}
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
