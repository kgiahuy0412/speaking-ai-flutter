import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_guide_audio_library.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_completion_choice_recognizer.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_intro_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_practice_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_review_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/listening_route_names.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'V2 automatically guides, records, praises, and starts the next sentence',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _GuidedMediaService();
      final voicePrompts = _ReadyCueVoicePromptService();
      final vocabularyStore = _MemoryVocabularyStore();
      await tester.pumpWidget(
        _subject(
          _lesson(code: 'A035_T01_L01', sentenceCount: 2),
          mediaService,
          guideAudioLibrary: _silentGuideAudioLibrary(),
          attemptEvaluator: const RecordedAttemptEvaluator(),
          voicePromptService: voicePrompts,
          vocabularyStore: vocabularyStore,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        voicePrompts.spoken,
        containsAllInOrder(<String>[
          'vi-VN|Nói theo cô nhé.',
          'en-US|Sentence 1',
          'vi-VN|Câu 1',
          'vi-VN|Bây giờ đến lượt con. Con nói lại nhé.',
        ]),
      );
      expect(mediaService.recording, isTrue);
      expect(voicePrompts.readyCueCount, 1);
      expect(mediaService.selectedOutputPreparationCount, 4);
      expect(mediaService.phoneOutputPreparationCount, 0);

      await tester.tap(find.byKey(const Key('record-lesson-sentence')));
      await tester.pumpAndSettle();

      expect(find.text('Sentence 2'), findsOneWidget);
      expect(mediaService.recording, isTrue);
      expect(voicePrompts.readyCueCount, 2);
      // Four selected-route preparations per guided sentence, plus the praise
      // prompt between sentence one and sentence two.
      expect(mediaService.selectedOutputPreparationCount, 9);
      expect(mediaService.phoneOutputPreparationCount, 0);
      expect(vocabularyStore.entries, hasLength(1));
      expect(vocabularyStore.entries.single.word, 'Sentence 1');
      expect(
        vocabularyStore.entries.single.collection,
        VocabularyCollection.star,
      );
      expect(
        voicePrompts.spoken,
        containsAllInOrder(<String>[
          'vi-VN|Con làm tốt lắm',
          'vi-VN|Nói theo cô nhé.',
          'en-US|Sentence 2',
          'vi-VN|Câu 2',
          'vi-VN|Bây giờ đến lượt con. Con nói lại nhé.',
        ]),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('V2 automatically stops a child recording after six seconds', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _GuidedMediaService();
    await tester.pumpWidget(
      _subject(
        _lesson(code: 'A035_T01_L01', sentenceCount: 2),
        mediaService,
        guideAudioLibrary: _silentGuideAudioLibrary(),
        voicePromptService: _FakeVoicePromptService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(mediaService.recording, isTrue);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(LessonGuideFlowV2.guideToSamplePause);
    await tester.pump(LessonGuideFlowV2.englishToVietnamesePause);
    await tester.pump();

    expect(find.text('Sentence 2'), findsOneWidget);
    expect(mediaService.startedSentenceIds, contains('GUIDED-FLOW_S2'));
    expect(mediaService.recording, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('MAIN pause then resume accepts a correct fresh lesson attempt', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final mediaService = _GuidedMediaService();
    final voicePrompts = _FakeVoicePromptService();
    final vocabularyStore = _MemoryVocabularyStore();

    await tester.pumpWidget(
      ActiveLearningModuleScope(
        registry: registry,
        child: _subject(
          _lesson(code: 'A035_T01_L01', sentenceCount: 2),
          mediaService,
          guideAudioLibrary: _silentGuideAudioLibrary(),
          attemptEvaluator: _ScriptedAttemptEvaluator(<LessonAttemptOutcome>[
            LessonAttemptOutcome.good,
          ]),
          voicePromptService: voicePrompts,
          vocabularyStore: vocabularyStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(mediaService.recording, isTrue);
    expect(mediaService.startedSentenceIds, hasLength(1));

    expect(
      (await registry.execute(ActiveLearningCommand.stop)).wasHandled,
      isTrue,
    );
    await tester.pump();
    expect(registry.isActiveModulePaused, isTrue);
    expect(mediaService.recording, isFalse);

    expect(
      (await registry.execute(ActiveLearningCommand.resume)).wasHandled,
      isTrue,
    );
    await tester.pump();
    expect(registry.isActiveModulePaused, isFalse);
    expect(mediaService.recording, isTrue);
    expect(mediaService.startedSentenceIds, hasLength(2));

    await tester.tap(find.byKey(const Key('record-lesson-sentence')));
    await tester.pumpAndSettle();

    expect(find.text('Sentence 2'), findsOneWidget);
    expect(voicePrompts.spoken, contains('vi-VN|Con làm tốt lắm'));
    expect(voicePrompts.spoken, isNot(contains('vi-VN|Con tập trung học đi')));
    expect(vocabularyStore.entries, hasLength(1));
    expect(
      vocabularyStore.entries.single.collection,
      VocabularyCollection.star,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('MAIN invalidates an evaluation that finishes after pause', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final mediaService = _GuidedMediaService();
    final evaluator = _DeferredAttemptEvaluator();
    final voicePrompts = _FakeVoicePromptService();
    final vocabularyStore = _MemoryVocabularyStore();

    await tester.pumpWidget(
      ActiveLearningModuleScope(
        registry: registry,
        child: _subject(
          _lesson(code: 'A035_T01_L01', sentenceCount: 2),
          mediaService,
          guideAudioLibrary: _silentGuideAudioLibrary(),
          attemptEvaluator: evaluator,
          voicePromptService: voicePrompts,
          vocabularyStore: vocabularyStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('record-lesson-sentence')));
    await tester.pump();
    await evaluator.started.future;
    expect(await registry.pauseForMainAssistant(), isTrue);
    evaluator.complete(LessonAttemptOutcome.good);
    await tester.pumpAndSettle();

    expect(find.text('Sentence 1'), findsOneWidget);
    expect(mediaService.recording, isFalse);
    expect(vocabularyStore.entries, isEmpty);
    expect(voicePrompts.spoken, isNot(contains('vi-VN|Con làm tốt lắm')));
  });

  testWidgets(
    'MAIN detaches a pending lesson microphone start before takeover',
    (tester) async {
      await _usePhoneSurface(tester);
      final registry = ActiveLearningModuleRegistry();
      addTearDown(registry.dispose);
      final mediaService = _BlockingRecordingStartMediaService();

      await tester.pumpWidget(
        ActiveLearningModuleScope(
          registry: registry,
          child: _subject(
            _lesson(code: 'A035_T01_L01', sentenceCount: 2),
            mediaService,
            guideAudioLibrary: _silentGuideAudioLibrary(),
            voicePromptService: _FakeVoicePromptService(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(LessonGuideFlowV2.guideToSamplePause);
      await tester.pump();
      await tester.pump(LessonGuideFlowV2.englishToVietnamesePause);
      await tester.pump();
      await mediaService.startRequested.future;

      var pauseCompleted = false;
      final pauseFuture = registry.pauseForMainAssistant().then((value) {
        pauseCompleted = true;
        return value;
      });
      await tester.pump();
      expect(pauseCompleted, isTrue);
      expect(await pauseFuture, isTrue);

      // A late Android recording callback is still cleaned up, but it no longer
      // owns or delays the MAIN handoff.
      mediaService.releaseStart();
      await tester.pump();
      await tester.pump();

      expect(registry.isActiveModulePaused, isTrue);
      expect(mediaService.recording, isFalse);
      expect(mediaService.cancelCalls, greaterThanOrEqualTo(2));
      expect(find.text('Bài học đang tạm dừng.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'V2 rejects wrong content and automatically records the same sentence again',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _GuidedMediaService();
      final progressStore = _MemoryProgressStore();
      final vocabularyStore = _MemoryVocabularyStore();
      final voicePrompts = _FakeVoicePromptService();
      final evaluator = _ScriptedAttemptEvaluator(<LessonAttemptOutcome>[
        LessonAttemptOutcome.retry,
        LessonAttemptOutcome.retry,
      ]);
      await tester.pumpWidget(
        _subject(
          _lesson(code: 'A035_T01_L01', sentenceCount: 2),
          mediaService,
          guideAudioLibrary: _silentGuideAudioLibrary(),
          progressStore: progressStore,
          attemptEvaluator: evaluator,
          voicePromptService: voicePrompts,
          vocabularyStore: vocabularyStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('record-lesson-sentence')));
      await tester.pumpAndSettle();
      expect(mediaService.recording, isTrue);
      expect(find.text('Sentence 1'), findsOneWidget);
      expect(
        voicePrompts.spoken,
        contains('vi-VN|Gần được rồi! Con nghe lại câu này nhé.'),
      );
      expect(progressStore.needsPractice, contains(0));
      expect(vocabularyStore.entries, hasLength(1));
      expect(
        vocabularyStore.entries.single.collection,
        VocabularyCollection.review,
      );

      await tester.tap(find.byKey(const Key('record-lesson-sentence')));
      await tester.pumpAndSettle();

      expect(mediaService.recording, isTrue);
      expect(find.text('Sentence 1'), findsOneWidget);
      expect(progressStore.needsPractice, contains(0));
      expect(
        voicePrompts.spoken.where(
          (message) =>
              message == 'vi-VN|Gần được rồi! Con nghe lại câu này nhé.',
        ),
        hasLength(1),
      );
      expect(
        voicePrompts.spoken,
        contains('vi-VN|Bây giờ con thử nói lại lần nữa nhé.'),
      );
      expect(
        voicePrompts.spoken,
        isNot(contains('vi-VN|Mình cùng học câu khác nhé!')),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'V2 asks neutrally and retries when ASR could not hear the sentence',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _GuidedMediaService();
      final progressStore = _MemoryProgressStore();
      final vocabularyStore = _MemoryVocabularyStore();
      final voicePrompts = _FakeVoicePromptService();
      final evaluator = _ScriptedAttemptEvaluator(<LessonAttemptOutcome>[
        LessonAttemptOutcome.unclear,
      ]);
      await tester.pumpWidget(
        _subject(
          _lesson(code: 'A035_T01_L01', sentenceCount: 2),
          mediaService,
          guideAudioLibrary: _silentGuideAudioLibrary(),
          progressStore: progressStore,
          attemptEvaluator: evaluator,
          voicePromptService: voicePrompts,
          vocabularyStore: vocabularyStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('record-lesson-sentence')));
      await tester.pumpAndSettle();

      expect(mediaService.recording, isTrue);
      expect(find.text('Sentence 1'), findsOneWidget);
      expect(
        voicePrompts.spoken,
        contains('vi-VN|Cô chưa nghe rõ. Con nói lại nhé.'),
      );
      expect(
        voicePrompts.spoken,
        isNot(contains('vi-VN|Con tập trung học đi')),
      );
      expect(progressStore.needsPractice, isEmpty);
      expect(vocabularyStore.entries, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('V2 keeps the same sentence after two unclear recordings', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _GuidedMediaService();
    final progressStore = _MemoryProgressStore();
    final vocabularyStore = _MemoryVocabularyStore();
    final voicePrompts = _FakeVoicePromptService();
    final evaluator = _ScriptedAttemptEvaluator(<LessonAttemptOutcome>[
      LessonAttemptOutcome.unclear,
      LessonAttemptOutcome.unclear,
    ]);
    await tester.pumpWidget(
      _subject(
        _lesson(code: 'A035_T01_L01', sentenceCount: 2),
        mediaService,
        guideAudioLibrary: _silentGuideAudioLibrary(),
        progressStore: progressStore,
        attemptEvaluator: evaluator,
        voicePromptService: voicePrompts,
        vocabularyStore: vocabularyStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('record-lesson-sentence')));
    await tester.pumpAndSettle();
    expect(mediaService.recording, isTrue);
    expect(find.text('Sentence 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('record-lesson-sentence')));
    await tester.pumpAndSettle();

    expect(find.text('Sentence 1'), findsOneWidget);
    expect(mediaService.recording, isTrue);
    expect(progressStore.needsPractice, contains(0));
    expect(
      voicePrompts.spoken.where(
        (message) => message == 'vi-VN|Cô chưa nghe rõ. Con nói lại nhé.',
      ),
      hasLength(1),
    );
    expect(
      voicePrompts.spoken,
      contains('vi-VN|Bây giờ con thử nói lại lần nữa nhé.'),
    );
    expect(
      voicePrompts.spoken,
      isNot(contains('vi-VN|Mình cùng học câu khác nhé!')),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'V2 promotes a retry sentence from Review to Stars when correct',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _GuidedMediaService();
      final progressStore = _MemoryProgressStore();
      final vocabularyStore = _MemoryVocabularyStore();
      final evaluator = _ScriptedAttemptEvaluator(<LessonAttemptOutcome>[
        LessonAttemptOutcome.retry,
        LessonAttemptOutcome.good,
      ]);
      await tester.pumpWidget(
        _subject(
          _lesson(code: 'A035_T01_L01', sentenceCount: 2),
          mediaService,
          guideAudioLibrary: _silentGuideAudioLibrary(),
          progressStore: progressStore,
          attemptEvaluator: evaluator,
          voicePromptService: _FakeVoicePromptService(),
          vocabularyStore: vocabularyStore,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('record-lesson-sentence')));
      await tester.pumpAndSettle();
      expect(
        vocabularyStore.entries.single.collection,
        VocabularyCollection.review,
      );
      expect(progressStore.needsPractice, contains(0));

      await tester.tap(find.byKey(const Key('record-lesson-sentence')));
      await tester.pumpAndSettle();

      expect(vocabularyStore.entries, hasLength(1));
      expect(
        vocabularyStore.entries.single.collection,
        VocabularyCollection.star,
      );
      expect(vocabularyStore.entries.single.word, 'Sentence 1');
      expect(progressStore.needsPractice, isNot(contains(0)));
      expect(find.text('Sentence 2'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('V2 hears restart choice and starts sentence one again', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _GuidedMediaService();
    final voicePrompts = _FakeVoicePromptService();
    await tester.pumpWidget(
      _subject(
        _lesson(code: 'A035_T01_L01'),
        mediaService,
        guideAudioLibrary: _silentGuideAudioLibrary(),
        voicePromptService: voicePrompts,
        completionChoiceRecognizer: _FakeCompletionChoiceRecognizer(
          'Con muốn luyện lại từ đầu',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('record-lesson-sentence')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(mediaService.startedSentenceIds.last, contains('completion-choice'));

    await tester.tap(find.byKey(const Key('record-lesson-sentence')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(LessonGuideFlowV2.guideToSamplePause);
    await tester.pump(LessonGuideFlowV2.englishToVietnamesePause);
    await tester.pump();

    expect(mediaService.startedSentenceIds.last, 'GUIDED-FLOW_S1');
    expect(mediaService.recording, isTrue);
    expect(mediaService.deletedLessonIds, <String>['guided-flow']);
    expect(find.text('Sentence 1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('V2 hears next lesson choice and opens lesson two', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final nextIntroUri = Uri.parse('https://example.test/v2-next-intro.mp3');
    final firstLesson = _lesson(
      id: 'v2-first',
      code: 'A035_T01_L01',
      number: 1,
    );
    final nextLesson = _lesson(
      id: 'v2-next',
      code: 'A035_T01_L02',
      number: 2,
      intro: 'Mở đầu bài hai.',
      introAudioUri: nextIntroUri,
    );
    const levelContent = ListeningLevelContent(
      id: 'v4-level-1',
      number: 1,
      titleVi: 'Level 1',
      topicNumbers: <int>[1, 2, 3],
    );
    final mediaService = _ControlledNextIntroMediaService(nextIntroUri);
    await tester.pumpWidget(
      _subject(
        firstLesson,
        mediaService,
        topicContent: _topicContent(<ListeningLessonContent>[
          firstLesson,
          nextLesson,
        ]),
        levelContent: levelContent,
        guideAudioLibrary: _silentGuideAudioLibrary(),
        voicePromptService: _FakeVoicePromptService(),
        completionChoiceRecognizer: _FakeCompletionChoiceRecognizer(
          'Bài tiếp theo',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('record-lesson-sentence')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(mediaService.startedSentenceIds.last, contains('completion-choice'));

    await tester.tap(find.byKey(const Key('record-lesson-sentence')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LessonIntroScreen), findsOneWidget);
    expect(
      tester
          .widget<LessonIntroScreen>(find.byType(LessonIntroScreen))
          .lesson
          .id,
      nextLesson.id,
    );
    expect(
      tester
          .widget<LessonIntroScreen>(find.byType(LessonIntroScreen))
          .levelContent,
      same(levelContent),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('V2 asks the child to repeat an unclear completion choice', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _GuidedMediaService();
    final voicePrompts = _FakeVoicePromptService();
    await tester.pumpWidget(
      _subject(
        _lesson(code: 'A035_T01_L01'),
        mediaService,
        guideAudioLibrary: _silentGuideAudioLibrary(),
        voicePromptService: voicePrompts,
        completionChoiceRecognizer: _FakeCompletionChoiceRecognizer(
          'Con chưa biết',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('record-lesson-sentence')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(mediaService.startedSentenceIds.last, contains('completion-choice'));

    await tester.tap(find.byKey(const Key('record-lesson-sentence')));
    await tester.pumpAndSettle();

    expect(voicePrompts.spoken, contains('vi-VN|Nói lại lựa chọn của con nhé'));
    expect(find.byKey(const Key('retry-voice-choice')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('V2 announces topic completion after its last lesson', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final lesson = _lesson(code: 'A035_T01_L02', number: 2);
    final mediaService = _GuidedMediaService();
    final voicePrompts = _FakeVoicePromptService();
    var topicCompletedCount = 0;
    await tester.pumpWidget(
      _subject(
        lesson,
        mediaService,
        topicContent: _topicContent(<ListeningLessonContent>[lesson]),
        guideAudioLibrary: _silentGuideAudioLibrary(),
        voicePromptService: voicePrompts,
        completionChoiceRecognizer: _FakeCompletionChoiceRecognizer(
          'Bài tiếp theo',
        ),
        onTopicCompleted: () => topicCompletedCount += 1,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('record-lesson-sentence')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('record-lesson-sentence')));
    await tester.pump();
    await tester.pump();

    expect(
      voicePrompts.spoken,
      contains(
        'vi-VN|Con đã học xong chủ đề này rồi. Con chọn tiếp chủ đề mới nhé.',
      ),
    );
    expect(topicCompletedCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

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
    expect(find.byType(LessonReviewScreen), findsNothing);
    expect(find.text('Nghe tổng quan'), findsNothing);
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

  testWidgets('learned review announces the next H20 action', (tester) async {
    await _usePhoneSurface(tester);
    final mediaService = _GuidedMediaService();
    final voicePrompt = _FakeVoicePromptService();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LessonReviewScreen(
          language: DisplayLanguage.vietnamese,
          lesson: _lesson(sentenceCount: 2),
          mediaService: mediaService,
          mode: LessonReviewMode.learned,
          hasNextLesson: true,
          voicePromptService: voicePrompt,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      voicePrompt.spoken,
      contains(
        'vi-VN|Giỏi lắm! Con đã hoàn thành bài học. Bấm nút Main rồi nói “Bài tiếp theo” để học tiếp, hoặc nói “Luyện lại” để học lại từ đầu nhé.',
      ),
    );
    expect(find.textContaining('Bấm nút Main rồi nói'), findsOneWidget);
    expect(mediaService.selectedOutputPreparationCount, 1);

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

  testWidgets('V2 lesson intro uses introAudioUrl before opening practice', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _ControlledIntroMediaService();
    final introUri = Uri.parse('https://example.test/intro.mp3');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 3,
          endAge: 5,
          topic: listeningCatalogs.first.topics.first,
          lesson: _lesson(code: 'A067_T01_L01', introAudioUri: introUri),
          progressStore: _MemoryProgressStore(),
          mediaService: mediaService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(find.byType(LessonIntroScreen), findsOneWidget);
    expect(find.byType(LessonPracticeScreen), findsNothing);
    expect(mediaService.playedUri, introUri);
    expect(
      mediaService.playbackRoute,
      LessonPlaybackRoute.selectedLessonDevice,
    );

    mediaService.finishIntro();
    await tester.pump();
    await tester.pump();
    expect(find.byType(LessonReviewScreen), findsNothing);
    expect(find.text('Nghe tổng quan'), findsNothing);
    expect(find.byType(LessonPracticeScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'V2 lesson intro keeps selected output when its clip is missing',
    (tester) async {
      await _usePhoneSurface(tester);
      final mediaService = _GuidedMediaService();
      final voicePrompt = _FakeVoicePromptService();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: LessonIntroScreen(
            language: DisplayLanguage.vietnamese,
            startAge: 6,
            endAge: 7,
            topic: listeningCatalogs[1].topics.first,
            lesson: _lesson(code: 'A067_T05_L02'),
            progressStore: _MemoryProgressStore(),
            mediaService: mediaService,
            voicePromptService: voicePrompt,
            autoAdvance: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(voicePrompt.spoken, hasLength(1));
      expect(voicePrompt.spoken.single, contains('Hôm nay mình'));
      expect(mediaService.selectedOutputPreparationCount, 1);
      expect(find.textContaining('Không thể phát lời mở đầu'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('MAIN pauses review audio and its completion countdown', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final audioUri = Uri.parse('https://example.test/main-review.mp3');
    final mediaService = _ControlledLessonAudioMediaService();

    await tester.pumpWidget(
      ActiveLearningModuleScope(
        registry: registry,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: LessonReviewScreen(
            language: DisplayLanguage.vietnamese,
            lesson: _lesson(sentenceCount: 2, sentenceAudioUri: audioUri),
            mediaService: mediaService,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('auto-play-lesson-review')));
    await tester.pump();
    await tester.pump();

    expect(mediaService.playedUris, <Uri>[audioUri]);
    final stopsBeforeMain = mediaService.stopCalls;
    expect(await registry.pauseForMainAssistant(), isTrue);
    await tester.pump();

    expect(registry.isActiveModulePaused, isTrue);
    expect(mediaService.stopCalls, stopsBeforeMain + 1);
    expect(find.text('Bài học đang tạm dừng.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Học ngay sau 6 giây'), findsOneWidget);
    expect(mediaService.playedUris, <Uri>[audioUri]);

    expect(
      (await registry.execute(ActiveLearningCommand.resume)).wasHandled,
      isTrue,
    );
    await tester.pump();
    expect(mediaService.playedUris, <Uri>[audioUri, audioUri]);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Học ngay sau 5 giây'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('MAIN stops intro audio and prevents automatic navigation', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final mediaService = _ControlledIntroMediaService();
    final introUri = Uri.parse('https://example.test/main-paused-intro.mp3');

    await tester.pumpWidget(
      ActiveLearningModuleScope(
        registry: registry,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: LessonIntroScreen(
            language: DisplayLanguage.vietnamese,
            startAge: 3,
            endAge: 5,
            topic: listeningCatalogs.first.topics.first,
            lesson: _lesson(code: 'A067_T01_L01', introAudioUri: introUri),
            progressStore: _MemoryProgressStore(),
            mediaService: mediaService,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(registry.hasActiveModule, isTrue);
    expect(mediaService.playedUri, introUri);
    expect(await registry.pauseForMainAssistant(), isTrue);
    await tester.pump();

    expect(registry.isActiveModulePaused, isTrue);
    expect(mediaService.stopCalls, 1);
    expect(find.text('Bài học đang tạm dừng.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 20));
    expect(find.byType(LessonIntroScreen), findsOneWidget);
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
    expect(find.byType(LessonReviewScreen), findsNothing);
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
  LessonMediaService mediaService, {
  LessonGuideAudioLibrary? guideAudioLibrary,
  ListeningTopicContent? topicContent,
  ListeningLevelContent? levelContent,
  ListeningProgressStore? progressStore,
  LessonAttemptEvaluator? attemptEvaluator,
  VoicePromptService? voicePromptService,
  LessonCompletionChoiceRecognizer? completionChoiceRecognizer,
  VocabularyStore? vocabularyStore,
  VoidCallback? onTopicCompleted,
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
      levelContent: levelContent,
      progressStore: progressStore ?? _MemoryProgressStore(),
      mediaService: mediaService,
      vocabularyStore: vocabularyStore ?? _MemoryVocabularyStore(),
      guideAudioLibrary: guideAudioLibrary,
      attemptEvaluator: attemptEvaluator ?? const RecordedAttemptEvaluator(),
      // Keep widget tests independent from the platform-channel speech-ready
      // cue used by the preserved single-sentence flow.
      voicePromptService: voicePromptService ?? _FakeVoicePromptService(),
      completionChoiceRecognizer: completionChoiceRecognizer,
      onTopicCompleted: onTopicCompleted,
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

LessonGuideAudioLibrary _silentGuideAudioLibrary() {
  return LessonGuideAudioLibrary(assetPaths: const <String>[]);
}

ListeningLessonContent _lesson({
  String id = 'guided-flow',
  String code = 'GUIDED_FLOW',
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
    code: code,
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

class _ScriptedAttemptEvaluator implements LessonAttemptEvaluator {
  _ScriptedAttemptEvaluator(this._outcomes);

  final List<LessonAttemptOutcome> _outcomes;
  int _index = 0;

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
    final outcome = _outcomes[_index.clamp(0, _outcomes.length - 1)];
    _index += 1;
    return outcome;
  }
}

class _DeferredAttemptEvaluator implements LessonAttemptEvaluator {
  final Completer<void> started = Completer<void>();
  final Completer<LessonAttemptOutcome> _result =
      Completer<LessonAttemptOutcome>();

  void complete(LessonAttemptOutcome outcome) => _result.complete(outcome);

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
    if (!started.isCompleted) {
      started.complete();
    }
    return _result.future;
  }
}

class _FakeVoicePromptService implements VoicePromptService {
  final List<String> spoken = <String>[];

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spoken.add('$locale|$text');
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _ReadyCueVoicePromptService extends _FakeVoicePromptService
    implements SpeechReadyCuePlayer {
  int readyCueCount = 0;

  @override
  Future<void> playSpeechReadyCue() async {
    readyCueCount += 1;
  }
}

class _FakeCompletionChoiceRecognizer
    implements LessonCompletionChoiceRecognizer {
  _FakeCompletionChoiceRecognizer(this.transcript);

  final String transcript;

  @override
  Future<String> transcribe(LessonRecording recording) async => transcript;

  @override
  void dispose() {}
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
  _GuidedMediaService({Set<int> recordedSentenceNumbers = const <int>{}})
    : recordedSentenceNumbers = <int>{...recordedSentenceNumbers};

  final Set<int> recordedSentenceNumbers;
  bool recording = false;
  final List<Uri> playedUris = <Uri>[];
  final List<String> startedSentenceIds = <String>[];
  final List<String> deletedLessonIds = <String>[];
  int selectedOutputPreparationCount = 0;
  int phoneOutputPreparationCount = 0;

  @override
  Future<void> preparePhoneSpeakerOutput() async {
    phoneOutputPreparationCount += 1;
  }

  @override
  Future<void> prepareSelectedLessonOutput() async {
    selectedOutputPreparationCount += 1;
  }

  @override
  Future<String?> existingRecording({
    required String lessonId,
    required int sentenceNumber,
    String? sentenceId,
  }) async => recordedSentenceNumbers.contains(sentenceNumber)
      ? 'C:\\recordings\\sentence-$sentenceNumber.m4a'
      : null;

  @override
  Future<void> deleteRecordingsForLesson(String lessonId) async {
    deletedLessonIds.add(lessonId);
    recordedSentenceNumbers.clear();
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
    recording = true;
    startedSentenceIds.add(sentenceId ?? '');
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
  Future<void> cancelRecording() async {
    recording = false;
  }

  @override
  Future<void> play(
    Uri uri, {
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
  }) async {
    playedUris.add(uri);
  }

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
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
  int stopCalls = 0;

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
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
    stopCalls += 1;
    final pending = List<Completer<void>>.of(_pendingLessonAudio);
    _pendingLessonAudio.clear();
    for (final completion in pending) {
      if (!completion.isCompleted) {
        completion.complete();
      }
    }
  }
}

class _BlockingRecordingStartMediaService extends _GuidedMediaService {
  final Completer<void> startRequested = Completer<void>();
  final Completer<void> _startRelease = Completer<void>();
  int cancelCalls = 0;

  void releaseStart() {
    if (!_startRelease.isCompleted) {
      _startRelease.complete();
    }
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
    if (!startRequested.isCompleted) {
      startRequested.complete();
    }
    await _startRelease.future;
    recording = true;
    startedSentenceIds.add(sentenceId ?? '');
  }

  @override
  Future<void> cancelRecording() async {
    cancelCalls += 1;
    recording = false;
  }
}

class _ControlledIntroMediaService extends LessonMediaService {
  final Completer<void> _completion = Completer<void>();
  Uri? playedUri;
  LessonPlaybackRoute? playbackRoute;
  int stopCalls = 0;

  void finishIntro() => _completion.complete();

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
  }) {
    playedUri = uri;
    playbackRoute = route;
    return _completion.future;
  }

  @override
  Future<void> stopPlayback() async {
    stopCalls += 1;
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
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
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
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
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

class _MemoryVocabularyStore extends VocabularyStore {
  List<VocabularyEntry> entries = <VocabularyEntry>[];

  @override
  Future<List<VocabularyEntry>> read() async => List.of(entries);

  @override
  Future<void> write(List<VocabularyEntry> value) async {
    entries = List.of(value);
  }
}

class _MemoryProgressStore extends ListeningProgressStore {
  int currentSentence = 0;
  int completed = 0;
  bool learningGuideOpened = false;
  final Set<int> needsPractice = <int>{};

  @override
  Future<Map<String, int>> readAll() async => <String, int>{};

  @override
  Future<int> readLesson(String lessonId) async => completed;

  @override
  Future<int> readCurrentSentence(String lessonId) async => currentSentence;

  @override
  Future<bool> hasOpenedLearningGuide() async => learningGuideOpened;

  @override
  Future<void> markLearningGuideOpened() async {
    learningGuideOpened = true;
  }

  @override
  Future<Set<int>> readSkippedSentences(String lessonId) async => <int>{};

  @override
  Future<void> saveSkippedSentence(String lessonId, int sentenceIndex) async {}

  @override
  Future<void> clearSkippedSentence(String lessonId, int sentenceIndex) async {}

  @override
  Future<void> clearSkippedSentences(String lessonId) async {}

  @override
  Future<Set<int>> readNeedsPracticeSentences(String lessonId) async =>
      Set<int>.of(needsPractice);

  @override
  Future<void> saveNeedsPracticeSentence(
    String lessonId,
    int sentenceIndex,
  ) async {
    needsPractice.add(sentenceIndex);
  }

  @override
  Future<void> clearNeedsPracticeSentence(
    String lessonId,
    int sentenceIndex,
  ) async {
    needsPractice.remove(sentenceIndex);
  }

  @override
  Future<void> clearNeedsPracticeSentences(String lessonId) async {
    needsPractice.clear();
  }

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
