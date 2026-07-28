import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_intro_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_practice_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_review_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'prompts twice, then offers skip without automatically skipping',
    (tester) async {
      await _usePhoneSurface(tester);
      final lesson = _lesson(sentenceCount: 2);
      await tester.pumpWidget(_subject(lesson, _GuidedMediaService()));
      await _finishInitialLoad(tester);

      expect(find.byKey(const Key('skip-lesson-sentence')), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(
        find.byKey(const Key('lesson-coach-popup-firstReminder')),
        findsOneWidget,
      );
      expect(find.text('Đến lượt con rồi!'), findsOneWidget);
      expect(find.byKey(const Key('skip-lesson-sentence')), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('lesson-coach-popup-firstReminder')),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 1700));
      expect(find.byKey(const Key('skip-lesson-sentence')), findsOneWidget);
      expect(
        find.byKey(const Key('lesson-coach-popup-secondReminder')),
        findsOneWidget,
      );
      expect(find.text('Sentence 1'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('lesson-coach-popup-secondReminder')),
        findsNothing,
      );
      expect(find.text('Sentence 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('skip-lesson-sentence')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Sentence 2'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'successful recording shows praise, latest recording and four actions',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _GuidedMediaService();
      await tester.pumpWidget(
        _subject(_lesson(sentenceCount: 2), mediaService),
      );
      await _finishInitialLoad(tester);

      final recordButton = find.byKey(const Key('record-lesson-sentence'));
      await tester.tap(recordButton);
      await tester.pump();
      await tester.pump();
      expect(mediaService.recording, isTrue);

      await tester.tap(recordButton);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('lesson-coach-popup-praise')),
        findsOneWidget,
      );
      expect(find.text('Con làm tuyệt lắm!'), findsOneWidget);
      expect(find.text('Bản ghi của con'), findsOneWidget);
      expect(find.text('Nghe câu mẫu'), findsOneWidget);
      expect(find.text('Nghe bản ghi'), findsOneWidget);
      expect(find.text('Ghi âm lại'), findsOneWidget);
      expect(find.text('Câu tiếp theo'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('lesson-coach-popup-praise')), findsNothing);
      expect(find.text('Sentence 1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Sentence 1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'dialogue and song lessons expose age-appropriate practice cues',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _GuidedMediaService();
      await tester.pumpWidget(
        _subject(
          _lesson(type: ListeningLessonType.dialogue, voice: 'Bạn A'),
          mediaService,
        ),
      );
      await _finishInitialLoad(tester);
      expect(find.textContaining('Bạn A · 1/1'), findsOneWidget);
      expect(find.byIcon(Icons.forum_rounded), findsOneWidget);

      await tester.pumpWidget(
        _subject(_lesson(type: ListeningLessonType.song), mediaService),
      );
      await _finishInitialLoad(tester);
      expect(find.text('Dòng 1/1'), findsOneWidget);
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('review lists English only and marks skipped sentences gently', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LessonReviewScreen(
          language: DisplayLanguage.vietnamese,
          lesson: _lesson(sentenceCount: 2),
          mediaService: _GuidedMediaService(),
          unrecordedSentenceIndexes: const <int>{1},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Sentence 1'), findsOneWidget);
    expect(find.text('Sentence 2'), findsOneWidget);
    expect(find.text('Câu 1'), findsNothing);
    expect(find.text('Câu 2'), findsNothing);
    expect(find.text('Chưa ghi âm'), findsOneWidget);
    expect(find.byKey(const Key('complete-lesson-review')), findsOneWidget);
    var completeButton = tester.widget<FilledButton>(
      find.byKey(const Key('complete-lesson-review')),
    );
    expect(completeButton.onPressed, isNull);
    expect(find.text('Hoàn thành sau 6 giây'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    completeButton = tester.widget<FilledButton>(
      find.byKey(const Key('complete-lesson-review')),
    );
    expect(completeButton.onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    completeButton = tester.widget<FilledButton>(
      find.byKey(const Key('complete-lesson-review')),
    );
    expect(completeButton.onPressed, isNotNull);
    expect(find.text('Hoàn thành bài'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'review derives every unrecorded sentence from saved recordings',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _GuidedMediaService(
        recordedSentenceNumbers: const <int>{2},
      );
      await tester.pumpWidget(
        _subject(_lesson(sentenceCount: 3), mediaService),
      );
      await _finishInitialLoad(tester);

      for (var index = 0; index < 3; index++) {
        await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
        await tester.pump();
        await tester.pump();
      }

      expect(find.byType(LessonReviewScreen), findsOneWidget);
      expect(find.text('2 câu chưa ghi âm'), findsOneWidget);
      expect(find.textContaining('không sao đâu'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('review-sentence-1')))
            .style
            ?.fontWeight,
        FontWeight.w800,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('review-sentence-2')))
            .style
            ?.fontWeight,
        FontWeight.w600,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('review-sentence-3')))
            .style
            ?.fontWeight,
        FontWeight.w800,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('lesson intro waits until its audio really finishes', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _ControlledIntroMediaService();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
          topic: listeningCatalogs.first.topics.first,
          lesson: _lesson(
            introAudioUri: Uri.parse('https://example.test/intro.mp3'),
          ),
          progressStore: _MemoryProgressStore(),
          mediaService: mediaService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(find.byType(LessonIntroScreen), findsOneWidget);
    expect(find.byType(LessonPracticeScreen), findsNothing);

    mediaService.finishIntro();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.byType(LessonPracticeScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('coach popup stays inside a compact phone viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(_subject(_lesson(), _GuidedMediaService()));
    await _finishInitialLoad(tester);
    await tester.pump(const Duration(seconds: 5));

    final popup = find.byKey(const Key('lesson-coach-popup-firstReminder'));
    expect(popup, findsOneWidget);
    final rect = tester.getRect(popup);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(568));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Widget _subject(
  ListeningLessonContent lesson,
  LessonMediaService mediaService,
) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: LessonPracticeScreen(
      language: DisplayLanguage.vietnamese,
      topic: listeningCatalogs.first.topics.first,
      lesson: lesson,
      progressStore: _MemoryProgressStore(),
      mediaService: mediaService,
    ),
  );
}

ListeningLessonContent _lesson({
  int sentenceCount = 1,
  ListeningLessonType type = ListeningLessonType.standard,
  String voice = '',
  Uri? introAudioUri,
}) {
  return ListeningLessonContent(
    id: 'guided-flow',
    code: 'GUIDED_FLOW',
    number: 1,
    titleVi: 'Bài hướng dẫn',
    titleEn: 'Guided lesson',
    intro: 'Bắt đầu.',
    introAudioUri: introAudioUri,
    outro: 'Hoàn thành.',
    estimatedMinutes: 1,
    type: type,
    autoAdvanceDelay: const Duration(seconds: 3),
    sentences: List<ListeningSentenceContent>.generate(
      sentenceCount,
      (index) => ListeningSentenceContent(
        id: 'GUIDED_FLOW_S${index + 1}',
        number: index + 1,
        voice: voice,
        english: 'Sentence ${index + 1}',
        vietnamese: 'Câu ${index + 1}',
      ),
    ),
  );
}

class _GuidedMediaService extends LessonMediaService {
  _GuidedMediaService({this.recordedSentenceNumbers = const <int>{}});

  final Set<int> recordedSentenceNumbers;
  bool recording = false;

  @override
  Future<String?> existingRecording({
    required String lessonId,
    required int sentenceNumber,
    String? sentenceId,
  }) async => recordedSentenceNumbers.contains(sentenceNumber)
      ? 'C:\\recordings\\sentence-$sentenceNumber.m4a'
      : null;

  @override
  Future<void> startRecording({
    required String lessonId,
    required int sentenceNumber,
    String? lessonTitle,
    String? sentenceId,
    String? english,
    String? vietnamese,
  }) async {
    recording = true;
  }

  @override
  Future<LessonRecording> stopRecording() async {
    recording = false;
    return const LessonRecording(
      filePath: 'C:\\recordings\\latest.m4a',
      duration: Duration(seconds: 2),
    );
  }

  @override
  Future<void> play(Uri uri) async {}

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {}
}

class _ControlledIntroMediaService extends LessonMediaService {
  final Completer<void> _completion = Completer<void>();

  void finishIntro() => _completion.complete();

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
  }) => _completion.future;

  @override
  Future<void> stopPlayback() async {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }

  @override
  Future<void> dispose() async {}
}

class _MemoryProgressStore extends ListeningProgressStore {
  int currentSentence = 0;
  int completed = 0;

  @override
  Future<Map<String, int>> readAll() async => <String, int>{};

  @override
  Future<int> readLesson(String lessonId) async => completed;

  @override
  Future<int> readCurrentSentence(String lessonId) async => currentSentence;

  @override
  Future<Set<int>> readSkippedSentences(String lessonId) async => <int>{};

  @override
  Future<void> saveSkippedSentence(String lessonId, int sentenceIndex) async {}

  @override
  Future<void> clearSkippedSentence(String lessonId, int sentenceIndex) async {}

  @override
  Future<void> clearSkippedSentences(String lessonId) async {}

  @override
  Future<void> saveLesson(String lessonId, int completedSentences) async {
    completed = completedSentences;
  }

  @override
  Future<void> saveCurrentSentence(String lessonId, int sentenceIndex) async {
    currentSentence = sentenceIndex;
  }
}

Future<void> _finishInitialLoad(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
