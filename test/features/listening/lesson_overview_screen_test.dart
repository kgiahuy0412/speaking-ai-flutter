import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
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
    expect(find.byKey(const Key('virtual-lesson-controls')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '11-15 English-only overview speaks each sentence with a clear gap',
    (tester) async {
      final voicePrompt = _BlockingOverviewVoicePromptService('Third line.');
      addTearDown(voicePrompt.release);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: LessonOverviewScreen(
            language: DisplayLanguage.vietnamese,
            startAge: 11,
            endAge: 12,
            topic: listeningCatalogs[4].topics.first,
            lesson: _englishOnlyLesson,
            progressStore: const ListeningProgressStore(
              progressFilePath: 'build/overview-sequence-test-progress.json',
            ),
            mediaService: _OverviewMediaService(),
            voicePromptService: voicePrompt,
          ),
        ),
      );
      await tester.pump();

      expect(voicePrompt.spoken, <String>[
        'vi-VN|Bạn nghe qua nội dung trước nhé.',
        'en-US|First line.',
      ]);

      await tester.pump(const Duration(milliseconds: 699));
      expect(
        voicePrompt.spoken.where((value) => value.startsWith('en-US|')),
        hasLength(1),
      );

      await tester.pump(const Duration(milliseconds: 1));
      expect(
        voicePrompt.spoken.where((value) => value.startsWith('en-US|')),
        <String>['en-US|First line.', 'en-US|Second line.'],
      );

      await tester.pump(const Duration(milliseconds: 700));
      expect(
        voicePrompt.spoken.where((value) => value.startsWith('en-US|')),
        <String>[
          'en-US|First line.',
          'en-US|Second line.',
          'en-US|Third line.',
        ],
      );
      expect(
        voicePrompt.spoken.any((value) => value.contains('Dòng tiếng Việt')),
        isFalse,
      );
    },
  );
}

class _BlockingOverviewVoicePromptService implements VoicePromptService {
  _BlockingOverviewVoicePromptService(this.blockingText);

  final String blockingText;
  final List<String> spoken = <String>[];
  final Completer<void> _release = Completer<void>();

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      speakAndWait(text, locale: locale);

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {
    spoken.add('$locale|$text');
    if (text == blockingText) {
      await _release.future;
    }
  }

  @override
  Future<void> stop() async => release();

  @override
  Future<void> dispose() async => release();
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

const _englishOnlyLesson = ListeningLessonContent(
  id: 'overview-english-only',
  code: 'C1112-L1-T01-B01',
  number: 1,
  titleVi: 'English overview',
  titleEn: 'English overview',
  intro: '',
  outro: '',
  estimatedMinutes: 4,
  overviewMode: ListeningOverviewMode.englishOnly,
  sentences: <ListeningSentenceContent>[
    ListeningSentenceContent(
      id: 'overview-en-1',
      number: 1,
      english: 'First line.',
      vietnamese: 'Dòng tiếng Việt một.',
    ),
    ListeningSentenceContent(
      id: 'overview-en-2',
      number: 2,
      english: 'Second line.',
      vietnamese: 'Dòng tiếng Việt hai.',
    ),
    ListeningSentenceContent(
      id: 'overview-en-3',
      number: 3,
      english: 'Third line.',
      vietnamese: 'Dòng tiếng Việt ba.',
    ),
  ],
);
