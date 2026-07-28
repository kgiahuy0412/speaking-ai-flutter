import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_guide_audio_library.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_intro_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_practice_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_review_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_lesson_list_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ListeningTopicContent topicContent;
  late _GoldenMediaService mediaService;
  late _GoldenProgressStore progressStore;

  setUpAll(() async {
    await _loadGoldenFonts();
    final catalog = await AssetListeningContentRepository().load();
    topicContent = catalog.topic(startAge: 3, endAge: 5, topicNumber: 1);
  });

  setUp(() {
    mediaService = _GoldenMediaService();
    progressStore = const _GoldenProgressStore();
  });

  testWidgets('topic lesson journey matches the approved direction', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    await tester.pumpWidget(
      _GoldenApp(
        child: TopicLessonListScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 3,
          endAge: 5,
          topic: listeningCatalogs.first.topics.first,
          content: topicContent,
          progressStore: progressStore,
          mediaService: mediaService,
        ),
      ),
    );
    await _precache(
      tester,
      find.byType(TopicLessonListScreen),
      const <AssetImage>[AssetImage('assets/images/topics/hello-goodbye.jpg')],
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(TopicLessonListScreen),
      matchesGoldenFile('goldens/topic-lesson-journey-390x844.png'),
    );
  });

  testWidgets('completed lessons offer review instead of continue', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final lesson = topicContent.lessons.first;
    progressStore = _GoldenProgressStore(
      progress: <String, int>{lesson.id: lesson.sentences.length},
    );
    await tester.pumpWidget(
      _GoldenApp(
        child: TopicLessonListScreen(
          language: DisplayLanguage.vietnamese,
          topic: listeningCatalogs.first.topics.first,
          content: topicContent,
          progressStore: progressStore,
          mediaService: mediaService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ôn lại'), findsOneWidget);
    expect(find.text('Học tiếp'), findsNothing);
  });

  testWidgets('lesson intro matches the approved direction', (tester) async {
    await _usePhoneSurface(tester);
    await tester.pumpWidget(
      _GoldenApp(
        child: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 3,
          endAge: 5,
          topic: listeningCatalogs.first.topics.first,
          lesson: topicContent.lessons.first,
          progressStore: progressStore,
          mediaService: mediaService,
          autoAdvance: false,
        ),
      ),
    );
    await _precache(tester, find.byType(LessonIntroScreen), const <AssetImage>[
      AssetImage('assets/images/lesson-intro-stage.webp'),
      AssetImage('assets/images/mascot-robot.png'),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    await expectLater(
      find.byType(LessonIntroScreen),
      matchesGoldenFile('goldens/lesson-intro-390x844.png'),
    );
  });

  testWidgets('sentence practice matches the approved direction', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    mediaService.showExistingRecording = true;
    await tester.pumpWidget(
      _GoldenApp(
        child: LessonPracticeScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 3,
          endAge: 5,
          topic: listeningCatalogs.first.topics.first,
          lesson: topicContent.lessons.first,
          progressStore: progressStore,
          mediaService: mediaService,
          guideAudioLibrary: _silentGuideAudioLibrary(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(LessonPracticeScreen),
      matchesGoldenFile('goldens/lesson-practice-390x844.png'),
    );
  });

  testWidgets('friendly reminder popup matches the approved direction', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    await tester.pumpWidget(
      _GoldenApp(
        child: LessonPracticeScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 3,
          endAge: 5,
          topic: listeningCatalogs.first.topics.first,
          lesson: topicContent.lessons.first,
          progressStore: progressStore,
          mediaService: mediaService,
          guideAudioLibrary: _silentGuideAudioLibrary(),
        ),
      ),
    );
    await _precache(
      tester,
      find.byType(LessonPracticeScreen),
      const <AssetImage>[AssetImage('assets/images/mascot-robot.png')],
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(LessonPracticeScreen),
      matchesGoldenFile('goldens/lesson-reminder-popup-390x844.png'),
    );
  });

  testWidgets('recording praise popup matches the approved direction', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    await tester.pumpWidget(
      _GoldenApp(
        child: LessonPracticeScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 3,
          endAge: 5,
          topic: listeningCatalogs.first.topics.first,
          lesson: topicContent.lessons.first,
          progressStore: progressStore,
          mediaService: mediaService,
          guideAudioLibrary: _silentGuideAudioLibrary(),
        ),
      ),
    );
    await _precache(
      tester,
      find.byType(LessonPracticeScreen),
      const <AssetImage>[AssetImage('assets/images/mascot-robot.png')],
    );
    await tester.pump();
    final recordButton = find.byKey(const Key('record-lesson-sentence'));
    await tester.tap(recordButton);
    await tester.pump();
    await tester.tap(recordButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(LessonPracticeScreen),
      matchesGoldenFile('goldens/lesson-praise-popup-390x844.png'),
    );
  });

  testWidgets('English-only lesson review matches the approved direction', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    await tester.pumpWidget(
      _GoldenApp(
        child: LessonReviewScreen(
          language: DisplayLanguage.vietnamese,
          lesson: topicContent.lessons.first,
          mediaService: mediaService,
          unrecordedSentenceIndexes: const <int>{2},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(LessonReviewScreen),
      matchesGoldenFile('goldens/lesson-review-390x844.png'),
    );
  });

  testWidgets('lesson completion celebrates the child', (tester) async {
    await _usePhoneSurface(tester);
    final lesson = topicContent.lessons.first;
    progressStore = _GoldenProgressStore(
      currentSentence: lesson.sentences.length - 1,
    );
    await tester.pumpWidget(
      _GoldenApp(
        child: LessonPracticeScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 3,
          endAge: 5,
          topic: listeningCatalogs.first.topics.first,
          lesson: lesson,
          progressStore: progressStore,
          mediaService: mediaService,
          guideAudioLibrary: _silentGuideAudioLibrary(),
        ),
      ),
    );
    await _precache(
      tester,
      find.byType(LessonPracticeScreen),
      const <AssetImage>[AssetImage('assets/images/mascot-robot.png')],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('continue-lesson-sentence')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final completeReview = find.byKey(const Key('complete-lesson-review'));
    await tester.ensureVisible(completeReview);
    await tester.pump(const Duration(seconds: 6));
    await tester.tap(completeReview);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/lesson-completion-390x844.png'),
    );
  });
}

class _GoldenApp extends StatelessWidget {
  const _GoldenApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: child,
    );
  }
}

LessonGuideAudioLibrary _silentGuideAudioLibrary() {
  return LessonGuideAudioLibrary(assetPaths: const <String>[]);
}

class _GoldenMediaService extends LessonMediaService {
  bool showExistingRecording = false;
  bool recording = false;

  @override
  Future<String?> existingRecording({
    required String lessonId,
    required int sentenceNumber,
    String? sentenceId,
  }) async {
    return showExistingRecording ? 'C:\\preview\\recording.m4a' : null;
  }

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
      filePath: 'C:\\preview\\recording.m4a',
      duration: Duration(seconds: 2),
    );
  }

  @override
  Future<void> play(Uri uri) async {}

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
  }) async {}

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {}
}

class _GoldenProgressStore extends ListeningProgressStore {
  const _GoldenProgressStore({
    this.currentSentence = 0,
    this.progress = const <String, int>{},
  });

  final int currentSentence;
  final Map<String, int> progress;

  @override
  Future<Map<String, int>> readAll() async => progress;

  @override
  Future<int> readLesson(String lessonId) async => progress[lessonId] ?? 0;

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
  Future<void> saveLesson(String lessonId, int completedSentences) async {}

  @override
  Future<void> saveCurrentSentence(String lessonId, int sentenceIndex) async {}
}

Future<void> _usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _precache(
  WidgetTester tester,
  Finder screen,
  List<AssetImage> images,
) async {
  await tester.pump();
  final context = tester.element(screen);
  await tester.runAsync(() async {
    await Future.wait<void>(
      images.map((provider) => precacheImage(provider, context)),
    );
  });
}

Future<void> _loadGoldenFonts() async {
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
  await Future.wait<void>(<Future<void>>[roboto.load(), materialIcons.load()]);
}
