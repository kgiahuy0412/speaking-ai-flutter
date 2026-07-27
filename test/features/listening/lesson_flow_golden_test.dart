import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_intro_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_practice_screen.dart';
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

  testWidgets('lesson intro matches the approved direction', (tester) async {
    await _usePhoneSurface(tester);
    await tester.pumpWidget(
      _GoldenApp(
        child: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
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
          topic: listeningCatalogs.first.topics.first,
          lesson: topicContent.lessons.first,
          progressStore: progressStore,
          mediaService: mediaService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(LessonPracticeScreen),
      matchesGoldenFile('goldens/lesson-practice-390x844.png'),
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
          topic: listeningCatalogs.first.topics.first,
          lesson: lesson,
          progressStore: progressStore,
          mediaService: mediaService,
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

class _GoldenMediaService extends LessonMediaService {
  bool showExistingRecording = false;

  @override
  Future<String?> existingRecording({
    required String lessonId,
    required int sentenceNumber,
  }) async {
    return showExistingRecording ? 'C:\\preview\\recording.m4a' : null;
  }

  @override
  Future<void> play(Uri uri) async {}

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> dispose() async {}
}

class _GoldenProgressStore extends ListeningProgressStore {
  const _GoldenProgressStore({this.currentSentence = 0});

  final int currentSentence;

  @override
  Future<Map<String, int>> readAll() async => const <String, int>{};

  @override
  Future<int> readLesson(String lessonId) async => 0;

  @override
  Future<int> readCurrentSentence(String lessonId) async => currentSentence;

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
