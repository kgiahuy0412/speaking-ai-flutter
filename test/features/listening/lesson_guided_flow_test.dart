import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_guide_audio_library.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_intro_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_practice_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_review_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/listening_route_names.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'prompts twice, then offers skip without automatically skipping',
    (tester) async {
      await _usePhoneSurface(tester);
      final lesson = _lesson(sentenceCount: 2);
      final mediaService = _GuidedMediaService();
      await tester.pumpWidget(
        _subject(lesson, mediaService, guideAudioLibrary: _guideAudioLibrary()),
      );
      await _finishInitialLoad(tester);

      expect(find.byKey(const Key('skip-lesson-sentence')), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      expect(
        find.byKey(const Key('lesson-coach-popup-firstReminder')),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(
        find.byKey(const Key('lesson-coach-popup-firstReminder')),
        findsOneWidget,
      );
      expect(
        mediaService.playedUris.last.path,
        '/assets/audio/A-3-5/GUIDE_IDLE1/idle-first.mp3',
      );
      expect(find.text('Đến lượt con rồi!'), findsOneWidget);
      expect(find.byKey(const Key('skip-lesson-sentence')), findsNothing);

      final firstReminder = find.byKey(
        const Key('lesson-coach-popup-firstReminder'),
      );
      final firstReminderBlocker = find.byKey(
        const Key('lesson-coach-popup-interaction-blocker'),
      );
      expect(firstReminderBlocker, findsOneWidget);
      expect(
        tester.widget<AbsorbPointer>(firstReminderBlocker).absorbing,
        isTrue,
      );

      await tester.pump(const Duration(milliseconds: 2499));
      expect(firstReminder, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(firstReminder, findsNothing);
      await tester.pump(const Duration(milliseconds: 4999));
      expect(find.byKey(const Key('skip-lesson-sentence')), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(find.byKey(const Key('skip-lesson-sentence')), findsOneWidget);
      expect(
        find.byKey(const Key('lesson-coach-popup-secondReminder')),
        findsOneWidget,
      );
      expect(
        mediaService.playedUris.last.path,
        '/assets/audio/A-3-5/GUIDE_IDLE2/idle-second.mp3',
      );
      expect(find.text('Sentence 1'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('skip-lesson-sentence')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.text('Sentence 1'), findsOneWidget);
      expect(
        find.byKey(const Key('lesson-coach-popup-secondReminder')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 2499));
      expect(
        find.byKey(const Key('lesson-coach-popup-secondReminder')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(
        find.byKey(const Key('lesson-coach-popup-secondReminder')),
        findsNothing,
      );
      expect(find.text('Sentence 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('skip-lesson-sentence')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Sentence 2'), findsOneWidget);
      expect(
        mediaService.playedUris.last.path,
        '/assets/audio/A-3-5/GUIDE_SKIP/skip.mp3',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'successful recording shows non-blocking fireworks and four actions',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _GuidedMediaService();
      await tester.pumpWidget(
        _subject(
          _lesson(sentenceCount: 2),
          mediaService,
          guideAudioLibrary: _guideAudioLibrary(),
        ),
      );
      await _finishInitialLoad(tester);

      final recordButton = find.byKey(const Key('record-lesson-sentence'));
      final playedBeforeRecording = List<Uri>.of(mediaService.playedUris);
      await tester.tap(recordButton);
      await tester.pump();
      await tester.pump();
      expect(mediaService.recording, isTrue);
      expect(mediaService.playedUris, playedBeforeRecording);

      await tester.tap(recordButton);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('lesson-praise-fireworks')), findsOneWidget);
      expect(
        find.byKey(const Key('lesson-praise-fireworks-left')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('lesson-praise-fireworks-right')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IgnorePointer>(
              find.byKey(const Key('lesson-praise-fireworks-interaction')),
            )
            .ignoring,
        isTrue,
      );
      expect(
        mediaService.playedUris.last.path,
        '/assets/audio/A-3-5/GUIDE_PRAISE/praise.mp3',
      );
      expect(find.byKey(const Key('lesson-coach-popup-praise')), findsNothing);
      expect(find.text('Con làm tuyệt lắm!'), findsNothing);
      expect(find.textContaining('Bản ghi đã được lưu'), findsNothing);
      expect(find.text('Bản ghi của con'), findsOneWidget);
      expect(find.text('Nghe câu mẫu'), findsOneWidget);
      expect(find.text('Nghe bản ghi'), findsOneWidget);
      expect(find.text('Ghi âm lại'), findsOneWidget);
      expect(find.text('Câu tiếp theo'), findsOneWidget);

      final playedBeforeContinue = List<Uri>.of(mediaService.playedUris);
      await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('Sentence 2'), findsOneWidget);
      expect(find.byKey(const Key('lesson-praise-fireworks')), findsNothing);
      expect(mediaService.playedUris, playedBeforeContinue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'sample and Vietnamese audio finish before the record guide plays',
    (tester) async {
      await _usePhoneSurface(tester);
      final sampleUri = Uri.parse('https://example.test/english.mp3');
      final vietnameseUri = Uri.parse('https://example.test/vietnamese.mp3');
      final recordGuideUri = Uri(
        scheme: 'asset',
        path: '/assets/audio/A-3-5/GUIDE_RECORD/record.mp3',
      );
      final mediaService = _ControlledLessonAudioMediaService();
      await tester.pumpWidget(
        _subject(
          _lesson(
            sentenceAudioUri: sampleUri,
            vietnameseAudioUri: vietnameseUri,
          ),
          mediaService,
          guideAudioLibrary: _guideAudioLibrary(),
        ),
      );
      await _finishInitialLoad(tester);
      mediaService.playedUris.clear();

      await tester.tap(find.byKey(const Key('play-lesson-sample')));
      await tester.pump();
      expect(mediaService.playedUris, <Uri>[sampleUri]);

      mediaService.finishNextLessonAudio();
      await tester.pump();
      await tester.pump();
      expect(mediaService.playedUris, <Uri>[sampleUri, recordGuideUri]);

      await tester.tap(find.byKey(const Key('play-vietnamese-meaning')));
      await tester.pump();
      expect(mediaService.playedUris, <Uri>[
        sampleUri,
        recordGuideUri,
        vietnameseUri,
      ]);

      mediaService.finishNextLessonAudio();
      await tester.pump();
      await tester.pump();
      expect(mediaService.playedUris, <Uri>[
        sampleUri,
        recordGuideUri,
        vietnameseUri,
        recordGuideUri,
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'completion opens the learned review without playing the ending guide',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _GuidedMediaService();
      await tester.pumpWidget(
        _subject(
          _lesson(),
          mediaService,
          guideAudioLibrary: _guideAudioLibrary(),
        ),
      );
      await _finishInitialLoad(tester);

      final recordButton = find.byKey(const Key('record-lesson-sentence'));
      await tester.tap(recordButton);
      await tester.pump();
      await tester.pump();
      await tester.tap(recordButton);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('lesson-review-screen')), findsOneWidget);
      expect(find.text('Đã học'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('post-lesson-primary-action')),
          matching: find.text('Luyện nghe'),
        ),
        findsOneWidget,
      );
      expect(find.text('Luyện lại từ đầu'), findsOneWidget);
      expect(find.text('Nghe tổng quan'), findsNothing);
      expect(find.byKey(const Key('auto-play-lesson-review')), findsNothing);
      expect(find.byKey(const Key('complete-lesson-review')), findsNothing);

      expect(
        mediaService.playedUris.where(
          (uri) => uri.path.contains('/GUIDE_ENDING/'),
        ),
        isEmpty,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('learned review opens the next lesson in the same topic', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final nextIntroUri = Uri.parse('https://example.test/next-intro.mp3');
    final firstLesson = _lesson(id: 'first-lesson', intro: 'Mở đầu bài một.');
    final nextLesson = _lesson(
      id: 'next-lesson',
      number: 2,
      intro: 'Mở đầu bài tiếp theo.',
      introAudioUri: nextIntroUri,
    );
    final topicContent = _topicContent(<ListeningLessonContent>[
      firstLesson,
      nextLesson,
    ]);

    final mediaService = _ControlledNextIntroMediaService(nextIntroUri);
    await tester.pumpWidget(
      _subject(
        firstLesson,
        mediaService,
        guideAudioLibrary: LessonGuideAudioLibrary(
          assetPaths: const <String>[],
        ),
        topicContent: topicContent,
      ),
    );
    await _finishInitialLoad(tester);
    await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Đã học'), findsOneWidget);
    expect(find.text('Bài tiếp theo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('post-lesson-primary-action')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LessonIntroScreen), findsOneWidget);
    expect(find.text('Mở đầu bài tiếp theo.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 20));
    expect(find.byType(LessonIntroScreen), findsOneWidget);
    expect(find.byType(LessonPracticeScreen), findsNothing);

    mediaService.finishNextIntro();
    await tester.pump();
    await tester.pump();
    expect(find.byType(LessonReviewScreen), findsOneWidget);
    expect(find.text('Nghe tổng quan'), findsOneWidget);
    expect(find.byType(LessonPracticeScreen), findsNothing);

    await tester.pump(const Duration(seconds: 6));
    final learnNowButton = find.byKey(const Key('complete-lesson-review'));
    await tester.ensureVisible(learnNowButton);
    await tester.tap(learnNowButton);
    await tester.pumpAndSettle();
    expect(find.byType(LessonPracticeScreen), findsOneWidget);
    expect(find.text('Sentence 1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('learned review restarts the current lesson from sentence one', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final progressStore = _MemoryProgressStore();
    await tester.pumpWidget(
      _subject(
        _lesson(sentenceCount: 2),
        _GuidedMediaService(),
        progressStore: progressStore,
      ),
    );
    await _finishInitialLoad(tester);
    for (var index = 0; index < 2; index++) {
      await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
      await tester.pump();
      await tester.pump();
    }

    expect(find.text('Đã học'), findsOneWidget);
    expect(progressStore.currentSentence, 1);
    await tester.tap(find.byKey(const Key('restart-lesson-review')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LessonPracticeScreen), findsOneWidget);
    expect(find.text('Sentence 1'), findsOneWidget);
    expect(progressStore.currentSentence, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('last learned lesson returns to the selected listening topic', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final lesson = _lesson(id: 'last-lesson');
    final topicContent = _topicContent(<ListeningLessonContent>[lesson]);
    final mediaService = _GuidedMediaService();
    final progressStore = _MemoryProgressStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            key: const Key('selected-listening-topic'),
            body: FilledButton(
              key: const Key('open-last-lesson'),
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => LessonPracticeScreen(
                      language: DisplayLanguage.vietnamese,
                      startAge: 3,
                      endAge: 5,
                      topic: listeningCatalogs.first.topics.first,
                      lesson: lesson,
                      topicContent: topicContent,
                      progressStore: progressStore,
                      mediaService: mediaService,
                    ),
                  ),
                );
              },
              child: const Text('Mở bài cuối'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-last-lesson')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('post-lesson-primary-action')),
        matching: find.text('Luyện nghe'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('post-lesson-primary-action')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('selected-listening-topic')), findsOneWidget);
    expect(find.byType(LessonPracticeScreen), findsNothing);
    expect(find.byType(LessonReviewScreen), findsNothing);
  });

  testWidgets('listening action pops the topic detail to the age catalog', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final lesson = _lesson(id: 'catalog-return-lesson');
    final topicContent = _topicContent(<ListeningLessonContent>[lesson]);
    final mediaService = _GuidedMediaService();
    final progressStore = _MemoryProgressStore();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        initialRoute: ListeningRouteNames.topicCatalog,
        routes: <String, WidgetBuilder>{
          ListeningRouteNames.topicCatalog: (context) => Scaffold(
            key: const Key('selected-age-topic-catalog'),
            body: FilledButton(
              key: const Key('open-topic-detail'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    key: const Key('topic-detail'),
                    body: FilledButton(
                      key: const Key('open-catalog-return-lesson'),
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => LessonPracticeScreen(
                            language: DisplayLanguage.vietnamese,
                            startAge: 6,
                            endAge: 7,
                            topic: listeningCatalogs[1].topics.first,
                            lesson: lesson,
                            topicContent: topicContent,
                            progressStore: progressStore,
                            mediaService: mediaService,
                          ),
                        ),
                      ),
                      child: const Text('Open lesson'),
                    ),
                  ),
                ),
              ),
              child: const Text('Open topic detail'),
            ),
          ),
        },
      ),
    );

    await tester.tap(find.byKey(const Key('open-topic-detail')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('open-catalog-return-lesson')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('post-lesson-primary-action')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('selected-age-topic-catalog')), findsOneWidget);
    expect(find.byKey(const Key('topic-detail')), findsNothing);
    expect(find.byType(LessonPracticeScreen), findsNothing);
    expect(find.byType(LessonReviewScreen), findsNothing);
  });

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

  testWidgets('review uses overview copy and neutral English sentence cards', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _GuidedMediaService();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LessonReviewScreen(
          language: DisplayLanguage.vietnamese,
          lesson: _lesson(sentenceCount: 2),
          mediaService: mediaService,
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
    expect(find.text('Nghe tổng quan'), findsOneWidget);
    expect(find.textContaining('câu tiếng Anh đã học'), findsNothing);
    expect(find.text('Chưa ghi âm'), findsNothing);
    expect(find.text('Sẵn sàng nghe lại'), findsNothing);
    expect(find.text('Đang tự động phát'), findsNothing);
    expect(find.byKey(const Key('unrecorded-sentences-banner')), findsNothing);
    expect(find.byKey(const Key('auto-play-lesson-review')), findsOneWidget);
    expect(find.text('Tự động phát'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
    expect(find.text('Bẩm để học'), findsOneWidget);
    final learningHint = find.byKey(
      const Key('review-first-sentence-learning-hint'),
    );
    expect(learningHint, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(learningHint).opacity, 1);
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.widget<AnimatedOpacity>(learningHint).opacity, 0.28);
    expect(mediaService.playedUris, isEmpty);
    expect(find.byKey(const Key('complete-lesson-review')), findsOneWidget);
    var completeButton = tester.widget<FilledButton>(
      find.byKey(const Key('complete-lesson-review')),
    );
    expect(completeButton.onPressed, isNull);
    expect(find.text('Học ngay sau 6 giây'), findsOneWidget);

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
    expect(find.text('Học ngay'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('review only auto-plays after the toggle is activated', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final audioUri = Uri.parse('https://example.test/overview.mp3');
    final mediaService = _ControlledLessonAudioMediaService();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LessonReviewScreen(
          language: DisplayLanguage.vietnamese,
          lesson: _lesson(sentenceCount: 2, sentenceAudioUri: audioUri),
          mediaService: mediaService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(_reviewTileBorder(tester, 1).top.color, AppColors.lavenderBorder);
    expect(_reviewTileBorder(tester, 2).top.color, AppColors.lavenderBorder);
    expect(mediaService.playedUris, isEmpty);
    expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('auto-play-lesson-review')));
    await tester.pump();
    await tester.pump();

    expect(_reviewTileBorder(tester, 1).top.color, AppColors.indigo);
    expect(_reviewTileBorder(tester, 1).top.width, 1.5);
    expect(_reviewTileBorder(tester, 2).top.color, AppColors.lavenderBorder);
    expect(mediaService.playedUris, <Uri>[audioUri]);
    expect(
      find.descendant(
        of: find.byKey(const Key('auto-play-lesson-review')),
        matching: find.byIcon(Icons.graphic_eq_rounded),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 10));
    expect(_reviewTileBorder(tester, 1).top.color, AppColors.indigo);

    mediaService.finishNextLessonAudio();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 999));

    expect(_reviewTileBorder(tester, 1).top.color, AppColors.indigo);
    expect(_reviewTileBorder(tester, 2).top.color, AppColors.lavenderBorder);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(_reviewTileBorder(tester, 1).top.color, AppColors.lavenderBorder);
    expect(_reviewTileBorder(tester, 2).top.color, AppColors.indigo);
    expect(_reviewTileBorder(tester, 2).top.width, 1.5);

    await tester.tap(find.byKey(const Key('auto-play-lesson-review')));
    await tester.pump();
    await tester.pump();

    expect(_reviewTileBorder(tester, 2).top.color, AppColors.lavenderBorder);
    expect(
      find.descendant(
        of: find.byKey(const Key('auto-play-lesson-review')),
        matching: find.byIcon(Icons.play_circle_outline_rounded),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('learned review highlights recorded and unrecorded sentences', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _GuidedMediaService(
      recordedSentenceNumbers: const <int>{2},
    );
    await tester.pumpWidget(_subject(_lesson(sentenceCount: 3), mediaService));
    await _finishInitialLoad(tester);

    for (var index = 0; index < 3; index++) {
      await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
      await tester.pump();
      await tester.pump();
    }

    expect(find.byType(LessonReviewScreen), findsOneWidget);
    expect(find.text('2 câu chưa ghi âm'), findsNothing);
    expect(find.textContaining('không sao đâu'), findsNothing);
    expect(find.text('Đã ghi âm'), findsOneWidget);
    expect(find.text('Chưa ghi âm'), findsNWidgets(2));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_off_rounded), findsNWidgets(2));
    expect(
      (tester
                  .widget<AnimatedContainer>(
                    find.byKey(const ValueKey('review-sentence-tile-1')),
                  )
                  .decoration
              as BoxDecoration)
          .color,
      AppColors.coralSoft,
    );
    expect(
      (tester
                  .widget<AnimatedContainer>(
                    find.byKey(const ValueKey('review-sentence-tile-2')),
                  )
                  .decoration
              as BoxDecoration)
          .color,
      AppColors.successSoft,
    );
    expect(
      (tester
                  .widget<AnimatedContainer>(
                    find.byKey(const ValueKey('review-sentence-tile-3')),
                  )
                  .decoration
              as BoxDecoration)
          .color,
      AppColors.coralSoft,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('lesson intro opens the overview only after audio finishes', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _ControlledIntroMediaService();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 3,
          endAge: 5,
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
    await tester.pump();
    expect(find.byType(LessonReviewScreen), findsOneWidget);
    expect(find.text('Nghe tổng quan'), findsOneWidget);
    expect(find.byType(LessonPracticeScreen), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('lesson intro does not auto advance when playback fails', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 3,
          endAge: 5,
          topic: listeningCatalogs.first.topics.first,
          lesson: _lesson(
            introAudioUri: Uri.parse('https://example.test/broken-intro.mp3'),
          ),
          progressStore: _MemoryProgressStore(),
          mediaService: _FailingIntroMediaService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));

    expect(find.byType(LessonIntroScreen), findsOneWidget);
    expect(find.byType(LessonReviewScreen), findsNothing);
    expect(find.textContaining('Không thể phát lời mở đầu'), findsOneWidget);

    await tester.tap(find.byKey(const Key('skip-lesson-intro')));
    await tester.pumpAndSettle();
    expect(find.byType(LessonReviewScreen), findsOneWidget);

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
  LessonMediaService mediaService, {
  LessonGuideAudioLibrary? guideAudioLibrary,
  ListeningTopicContent? topicContent,
  ListeningProgressStore? progressStore,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: LessonPracticeScreen(
      language: DisplayLanguage.vietnamese,
      startAge: 3,
      endAge: 5,
      topic: listeningCatalogs.first.topics.first,
      lesson: lesson,
      topicContent: topicContent,
      progressStore: progressStore ?? _MemoryProgressStore(),
      mediaService: mediaService,
      guideAudioLibrary: guideAudioLibrary,
    ),
  );
}

Border _reviewTileBorder(WidgetTester tester, int sentenceNumber) {
  final tile = tester.widget<AnimatedContainer>(
    find.byKey(ValueKey('review-sentence-tile-$sentenceNumber')),
  );
  return (tile.decoration! as BoxDecoration).border! as Border;
}

LessonGuideAudioLibrary _guideAudioLibrary() {
  return LessonGuideAudioLibrary(
    assetPaths: const <String>[
      'assets/audio/A-3-5/GUIDE_RECORD/record.mp3',
      'assets/audio/A-3-5/GUIDE_PRAISE/praise.mp3',
      'assets/audio/A-3-5/GUIDE_NEXT/next.mp3',
      'assets/audio/A-3-5/GUIDE_IDLE1/idle-first.mp3',
      'assets/audio/A-3-5/GUIDE_IDLE2/idle-second.mp3',
      'assets/audio/A-3-5/GUIDE_SKIP/skip.mp3',
      'assets/audio/A-3-5/GUIDE_ENDING/ending.mp3',
      'assets/audio/A-6-7/GUIDE_RECORD/wrong-age.mp3',
    ],
  );
}

ListeningLessonContent _lesson({
  String id = 'guided-flow',
  int number = 1,
  String intro = 'Bắt đầu.',
  int sentenceCount = 1,
  ListeningLessonType type = ListeningLessonType.standard,
  String voice = '',
  Uri? introAudioUri,
  Uri? sentenceAudioUri,
  Uri? vietnameseAudioUri,
}) {
  return ListeningLessonContent(
    id: id,
    code: 'GUIDED_FLOW',
    number: number,
    titleVi: 'Bài hướng dẫn',
    titleEn: 'Guided lesson',
    intro: intro,
    introAudioUri: introAudioUri,
    outro: 'Hoàn thành.',
    estimatedMinutes: 1,
    type: type,
    autoAdvanceDelay: const Duration(seconds: 3),
    sentences: List<ListeningSentenceContent>.generate(
      sentenceCount,
      (index) => ListeningSentenceContent(
        id: '${id.toUpperCase()}_S${index + 1}',
        number: index + 1,
        voice: voice,
        english: 'Sentence ${index + 1}',
        audioUri: sentenceAudioUri,
        vietnameseAudioUri: vietnameseAudioUri,
        vietnamese: 'Câu ${index + 1}',
      ),
    ),
  );
}

ListeningTopicContent _topicContent(List<ListeningLessonContent> lessons) {
  return ListeningTopicContent(
    id: 'guided-topic',
    number: 1,
    titleVi: 'Chủ đề hướng dẫn',
    titleEn: 'Guided topic',
    lessons: lessons,
  );
}

class _GuidedMediaService extends LessonMediaService {
  _GuidedMediaService({this.recordedSentenceNumbers = const <int>{}});

  final Set<int> recordedSentenceNumbers;
  bool recording = false;
  final List<Uri> playedUris = <Uri>[];

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
  Future<void> play(Uri uri) async {
    playedUris.add(uri);
  }

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    playedUris.add(uri);
  }

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {}
}

class _ControlledLessonAudioMediaService extends _GuidedMediaService {
  final List<Completer<void>> _pendingLessonAudio = <Completer<void>>[];

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    playedUris.add(uri);
    if (uri.scheme == 'asset') {
      return;
    }
    final completion = Completer<void>();
    _pendingLessonAudio.add(completion);
    await completion.future;
  }

  void finishNextLessonAudio() {
    _pendingLessonAudio.removeAt(0).complete();
  }

  @override
  Future<void> stopPlayback() async {
    final pending = List<Completer<void>>.of(_pendingLessonAudio);
    _pendingLessonAudio.clear();
    for (final completion in pending) {
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
  }
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

class _FailingIntroMediaService extends LessonMediaService {
  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    throw StateError('Playback failed.');
  }

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {}
}

class _ControlledNextIntroMediaService extends _GuidedMediaService {
  _ControlledNextIntroMediaService(this.nextIntroUri);

  final Uri nextIntroUri;
  final Completer<void> _nextIntroCompletion = Completer<void>();
  bool _nextIntroStarted = false;

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    playedUris.add(uri);
    if (uri != nextIntroUri) {
      return;
    }
    _nextIntroStarted = true;
    await _nextIntroCompletion.future;
  }

  void finishNextIntro() {
    if (!_nextIntroCompletion.isCompleted) {
      _nextIntroCompletion.complete();
    }
  }

  @override
  Future<void> stopPlayback() async {
    if (_nextIntroStarted && !_nextIntroCompletion.isCompleted) {
      _nextIntroCompletion.complete();
    }
  }
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
