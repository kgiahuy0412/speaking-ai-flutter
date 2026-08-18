import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_guide_audio_library.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_practice_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'next does not autoplay and previous plays praise without sentence audio',
    (tester) async {
      await _usePhoneSurface(tester);
      final store = _MemoryProgressStore();
      final lesson = _lessonWithSentences(3);
      final mediaService = _SilentMediaService();

      await tester.pumpWidget(
        _subject(
          lesson,
          store,
          const Key('manual-navigation-audio'),
          mediaService: mediaService,
          guideAudioLibrary: LessonGuideAudioLibrary(
            assetPaths: const <String>[
              'assets/audio/A-3-5/GUIDE_PRAISE/praise.mp3',
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(mediaService.playedUris, <Uri>[lesson.sentences.first.audioUri!]);

      await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
      await tester.pumpAndSettle();
      expect(find.text('Sentence 2'), findsOneWidget);
      expect(mediaService.playedUris, <Uri>[lesson.sentences.first.audioUri!]);

      await tester.tap(find.byKey(const Key('previous-lesson-sentence')));
      await tester.pumpAndSettle();
      expect(find.text('Sentence 1'), findsOneWidget);
      expect(mediaService.playedUris, <Uri>[
        lesson.sentences.first.audioUri!,
        Uri(
          scheme: 'asset',
          path: '/assets/audio/A-3-5/GUIDE_PRAISE/praise.mp3',
        ),
      ]);
    },
  );

  testWidgets('previous sentence is persisted and restored after re-entry', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final store = _MemoryProgressStore(currentSentence: 2);
    final lesson = _lessonWithSentences(3);

    await tester.pumpWidget(_subject(lesson, store, const Key('session-1')));
    await tester.pumpAndSettle();
    expect(find.text('Sentence 3'), findsOneWidget);
    var previousButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('previous-lesson-sentence')),
    );
    expect(
      previousButton.style?.backgroundColor?.resolve(const <WidgetState>{}),
      Colors.white,
    );

    await tester.tap(find.byKey(const Key('previous-lesson-sentence')));
    await tester.pumpAndSettle();
    expect(find.text('Sentence 2'), findsOneWidget);
    expect(store.currentSentence, 1);

    await tester.pumpWidget(_subject(lesson, store, const Key('session-2')));
    await tester.pumpAndSettle();
    expect(find.text('Sentence 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('previous-lesson-sentence')));
    await tester.pumpAndSettle();
    expect(find.text('Sentence 1'), findsOneWidget);
    expect(store.currentSentence, 0);

    previousButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('previous-lesson-sentence')),
    );
    expect(previousButton.onPressed, isNull);
    expect(
      previousButton.style?.backgroundColor?.resolve(const <WidgetState>{
        WidgetState.disabled,
      }),
      Colors.white.withValues(alpha: 0.72),
    );
  });

  testWidgets('MAIN previous command replays the previous sentence flow', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final store = _MemoryProgressStore(currentSentence: 1);
    final lesson = _lessonWithSentences(3);
    final mediaService = _SilentMediaService();

    await tester.pumpWidget(
      ActiveLearningModuleScope(
        registry: registry,
        child: _subject(
          lesson,
          store,
          const Key('main-previous-command'),
          mediaService: mediaService,
          voicePromptService: _SilentVoicePromptService(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sentence 2'), findsOneWidget);
    mediaService.playedUris.clear();

    await registry.execute(ActiveLearningCommand.stop);
    final operation = registry.execute(ActiveLearningCommand.previousItem);
    await tester.pump();
    final result = await operation;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result.wasHandled, isTrue);
    expect(find.text('Sentence 1'), findsOneWidget);
    expect(store.currentSentence, 0);
    expect(mediaService.playedUris, contains(lesson.sentences.first.audioUri));
  });

  testWidgets('review from beginning resets the resume sentence', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final store = _MemoryProgressStore();
    final lesson = _lessonWithSentences(1);

    await tester.pumpWidget(_subject(lesson, store, const Key('review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('lesson-review-screen')), findsOneWidget);
    final restartReview = find.byKey(const Key('restart-lesson-review'));
    await tester.ensureVisible(restartReview);
    await tester.tap(restartReview);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(store.completedSentences, 1);
    expect(find.byKey(const Key('lesson-review-screen')), findsNothing);
    expect(find.text('Sentence 1'), findsOneWidget);
    expect(store.currentSentence, 0);
    expect(store.completedSentences, 1);
  });

  testWidgets('completion remains usable on a compact phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final store = _MemoryProgressStore();
    final lesson = _lessonWithSentences(1);

    await tester.pumpWidget(_subject(lesson, store, const Key('compact')));
    await tester.pumpAndSettle();
    final continueButton = find.byKey(const Key('continue-lesson-sentence'));
    await tester.ensureVisible(continueButton);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(continueButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('lesson-review-screen')), findsOneWidget);
    expect(find.text('Đã học'), findsOneWidget);
    final restartReview = find.byKey(const Key('restart-lesson-review'));
    final primaryAction = find.byKey(const Key('post-lesson-primary-action'));
    await tester.ensureVisible(primaryAction);
    await tester.pump(const Duration(milliseconds: 200));
    expect(restartReview, findsOneWidget);
    expect(primaryAction, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MAIN commands pause, resume, and leave the lesson for home', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    final lesson = _lessonWithSentences(1);
    final mediaService = _SilentMediaService(
      existingRecordingPath: 'C:\\recordings\\previous-attempt.m4a',
    );

    await tester.pumpWidget(
      ActiveLearningModuleScope(
        registry: registry,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              key: const Key('test-home'),
              body: FilledButton(
                key: const Key('open-test-lesson'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => LessonPracticeScreen(
                      language: DisplayLanguage.vietnamese,
                      startAge: 3,
                      endAge: 5,
                      topic: listeningCatalogs.first.topics.first,
                      lesson: lesson,
                      progressStore: _MemoryProgressStore(),
                      mediaService: mediaService,
                      voicePromptService: _SilentVoicePromptService(),
                      guideAudioLibrary: LessonGuideAudioLibrary(
                        assetPaths: const <String>[],
                      ),
                    ),
                  ),
                ),
                child: const Text('Mở bài học'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-test-lesson')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isTrue);
    expect(registry.hasActiveModule, isTrue);
    expect(registry.isActiveModulePaused, isFalse);
    expect(mediaService.recording, isFalse);

    expect(
      (await registry.execute(ActiveLearningCommand.stop)).wasHandled,
      isTrue,
    );
    await tester.pump();
    expect(registry.isActiveModulePaused, isTrue);
    expect(mediaService.recording, isFalse);
    expect(find.text('Đã dừng. Nhấn MAIN để tiếp tục.'), findsOneWidget);

    expect(
      (await registry.execute(ActiveLearningCommand.resume)).wasHandled,
      isTrue,
    );
    await tester.pump();
    expect(registry.isActiveModulePaused, isFalse);
    expect(mediaService.recording, isTrue);
    expect(mediaService.startRecordingCount, 1);

    expect(
      (await registry.execute(ActiveLearningCommand.exitToHome)).wasHandled,
      isTrue,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(navigator.canPop(), isFalse);
    expect(find.byKey(const Key('test-home')), findsOneWidget);
    expect(find.byKey(const Key('lesson-practice-screen')), findsNothing);
    expect(registry.hasActiveModule, isFalse);
  });
}

Widget _subject(
  ListeningLessonContent lesson,
  ListeningProgressStore store,
  Key sessionKey, {
  LessonMediaService? mediaService,
  LessonGuideAudioLibrary? guideAudioLibrary,
  VoicePromptService? voicePromptService,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: LessonPracticeScreen(
      key: sessionKey,
      language: DisplayLanguage.vietnamese,
      startAge: 3,
      endAge: 5,
      topic: listeningCatalogs.first.topics.first,
      lesson: lesson,
      progressStore: store,
      mediaService: mediaService ?? _SilentMediaService(),
      voicePromptService: voicePromptService,
      guideAudioLibrary:
          guideAudioLibrary ??
          LessonGuideAudioLibrary(assetPaths: const <String>[]),
    ),
  );
}

ListeningLessonContent _lessonWithSentences(int count) {
  return ListeningLessonContent(
    id: 'navigation-test-lesson',
    number: 1,
    titleVi: 'Bài kiểm tra',
    titleEn: 'Test lesson',
    intro: 'Bắt đầu bài học.',
    outro: 'Con đã hoàn thành bài học rồi. Làm tốt lắm!',
    estimatedMinutes: 1,
    sentences: List<ListeningSentenceContent>.generate(
      count,
      (index) => ListeningSentenceContent(
        number: index + 1,
        english: 'Sentence ${index + 1}',
        audioUri: Uri.parse('https://example.com/sentence-${index + 1}.mp3'),
        vietnamese: 'Câu ${index + 1}',
      ),
      growable: false,
    ),
  );
}

class _MemoryProgressStore extends ListeningProgressStore {
  _MemoryProgressStore({this.currentSentence = 0});

  int currentSentence;
  int completedSentences = 0;

  @override
  Future<Map<String, int>> readAll() async => <String, int>{
    'navigation-test-lesson': completedSentences,
  };

  @override
  Future<int> readLesson(String lessonId) async => completedSentences;

  @override
  Future<int> readCurrentSentence(String lessonId) async => currentSentence;

  @override
  Future<Set<int>> readSkippedSentences(String lessonId) async => <int>{};

  @override
  Future<Set<int>> readNeedsPracticeSentences(String lessonId) async => <int>{};

  @override
  Future<void> saveSkippedSentence(String lessonId, int sentenceIndex) async {}

  @override
  Future<void> clearSkippedSentence(String lessonId, int sentenceIndex) async {}

  @override
  Future<void> clearSkippedSentences(String lessonId) async {}

  @override
  Future<void> clearNeedsPracticeSentence(
    String lessonId,
    int sentenceIndex,
  ) async {}

  @override
  Future<void> clearNeedsPracticeSentences(String lessonId) async {}

  @override
  Future<void> saveLesson(String lessonId, int completed) async {
    if (completed > completedSentences) {
      completedSentences = completed;
    }
  }

  @override
  Future<void> saveCurrentSentence(String lessonId, int sentenceIndex) async {
    currentSentence = sentenceIndex;
  }
}

class _SilentMediaService extends LessonMediaService {
  _SilentMediaService({this.existingRecordingPath});

  String? existingRecordingPath;
  final List<Uri> playedUris = <Uri>[];
  bool recording = false;
  int startRecordingCount = 0;

  @override
  Future<String?> existingRecording({
    required String lessonId,
    required int sentenceNumber,
    String? sentenceId,
  }) async => existingRecordingPath;

  @override
  Future<void> deleteRecordingsForLesson(String lessonId) async {
    existingRecordingPath = null;
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
    startRecordingCount += 1;
  }

  @override
  Future<void> cancelRecording() async {
    recording = false;
  }

  @override
  Future<void> play(Uri uri) async => playedUris.add(uri);

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
  }) async => playedUris.add(uri);

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {}
}

class _SilentVoicePromptService implements VoicePromptService {
  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

Future<void> _usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
