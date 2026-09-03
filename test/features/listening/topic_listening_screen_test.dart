import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_lesson_list_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/topic_listening_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildSubject({
    int childAge = 6,
    DisplayLanguage language = DisplayLanguage.vietnamese,
    double textScale = 1,
    ThemeMode themeMode = ThemeMode.light,
    Future<void> Function()? onVoiceNavigationPause,
    VoidCallback? onVoiceNavigationResume,
    Future<ListeningContentCatalog>? contentFuture,
    ListeningProgressStore progressStore = const ListeningProgressStore(),
    TopicSelectionAfterCompletionPrompt? onTopicSelectionAfterCompletion,
    TopicLessonSelectionPrompt? onLessonSelectionRequested,
    ValueChanged<int>? onChildAgeChanged,
    Future<bool> Function()? onRequestParentAccess,
  }) {
    return MaterialApp(
      theme: buildAppTheme(),
      darkTheme: buildDarkAppTheme(),
      themeMode: themeMode,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
        ),
        child: TopicListeningScreen(
          language: language,
          childAge: childAge,
          onVoiceNavigationPause: onVoiceNavigationPause,
          onVoiceNavigationResume: onVoiceNavigationResume,
          contentFuture: contentFuture,
          progressStore: progressStore,
          onTopicSelectionAfterCompletion: onTopicSelectionAfterCompletion,
          onLessonSelectionRequested: onLessonSelectionRequested,
          onChildAgeChanged: onChildAgeChanged,
          onRequestParentAccess: onRequestParentAccess,
        ),
      ),
    );
  }

  testWidgets('dark theme keeps the listening journey text readable', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    final journeyTitle = tester.widget<Text>(find.text('Hành trình của con'));
    final groupLabel = tester.widget<Text>(find.text('Nhóm bài học hiện tại'));
    final theme = Theme.of(
      tester.element(find.byKey(const Key('topic-listening-screen'))),
    );

    expect(theme.brightness, Brightness.dark);
    expect(journeyTitle.style?.color, theme.colorScheme.onSurface);
    expect(groupLabel.style?.color, theme.colorScheme.primary);
  });

  test(
    'V4 journey cards match the source catalog and keep their images',
    () async {
      final content = await AssetListeningContentRepository().load();

      expect(listeningCatalogs, hasLength(5));
      expect(
        listeningCatalogs.expand((catalog) => catalog.topics),
        hasLength(50),
      );
      for (final group in content.groups) {
        final journey = listeningCatalogs.singleWhere(
          (catalog) =>
              catalog.startAge == group.startAge &&
              catalog.endAge == group.endAge,
        );
        expect(journey.topics, hasLength(group.topics.length));
        for (var index = 0; index < group.topics.length; index += 1) {
          final journeyTopic = journey.topics[index];
          final contentTopic = group.topics[index];
          expect(journeyTopic.titleVi, contentTopic.titleVi);
          expect(journeyTopic.total, contentTopic.lessons.length);
          expect(
            journeyTopic.imagePath,
            isNotNull,
            reason: journeyTopic.titleVi,
          );
          final bytes = await rootBundle.load(journeyTopic.imagePath!);
          expect(
            bytes.lengthInBytes,
            greaterThan(1000),
            reason: journeyTopic.titleVi,
          );
        }
      }
    },
  );

  testWidgets(
    'parent can change the global V4 age group from the topic screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var parentGateCalls = 0;
      int? selectedAge;
      await tester.pumpWidget(
        buildSubject(
          onRequestParentAccess: () async {
            parentGateCalls += 1;
            return true;
          },
          onChildAgeChanged: (age) => selectedAge = age,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nhóm bài học hiện tại'), findsOneWidget);
      expect(find.text('10 chủ đề'), findsOneWidget);
      expect(find.byKey(const Key('topic-age-selector')), findsOneWidget);

      await tester.tap(find.byKey(const Key('topic-age-selector')));
      await tester.pumpAndSettle();
      expect(parentGateCalls, 1);
      expect(find.text('Chọn nhóm bài học'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('age-8-10')));
      await tester.tap(find.byKey(const Key('apply-topic-age')));
      await tester.pumpAndSettle();

      expect(selectedAge, 8);
      expect(find.text('8–10 tuổi'), findsOneWidget);
      expect(find.text('Lịch sinh hoạt của mình'), findsOneWidget);
    },
  );

  testWidgets(
    'opens the V4 listen-first lesson journey from a selected topic',
    (tester) async {
      var voiceNavigationPauseCount = 0;
      var voiceNavigationResumeCount = 0;
      final lessonPrompts =
          <
            ({int childAge, int topicNumber, List<int> completedLessonNumbers})
          >[];
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        buildSubject(
          childAge: 3,
          onVoiceNavigationPause: () async {
            voiceNavigationPauseCount += 1;
          },
          onVoiceNavigationResume: () {
            voiceNavigationResumeCount += 1;
          },
          onLessonSelectionRequested:
              ({
                required childAge,
                required topicNumber,
                required topicContent,
                required completedLessonNumbers,
              }) async {
                lessonPrompts.add((
                  childAge: childAge,
                  topicNumber: topicNumber,
                  completedLessonNumbers: completedLessonNumbers,
                ));
              },
        ),
      );
      await tester.pumpAndSettle();

      final topic = find.byKey(const ValueKey('topic-3-5-0'));
      await tester.scrollUntilVisible(
        topic,
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('topic-listening-screen')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(topic);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('topic-lesson-list-screen')), findsOneWidget);
      expect(find.text('Bảng chữ cái'), findsWidgets);
      expect(find.text('3 bài nhỏ'), findsOneWidget);
      expect(find.text('26 câu'), findsOneWidget);
      expect(voiceNavigationPauseCount, 0);
      expect(lessonPrompts, hasLength(1));
      expect(lessonPrompts.single.childAge, 3);
      expect(lessonPrompts.single.topicNumber, 1);
      expect(lessonPrompts.single.completedLessonNumbers, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('start-lesson-c35-l1-t01-b01')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('lesson-intro-screen')), findsOneWidget);
      expect(find.byKey(const Key('skip-lesson-intro')), findsOneWidget);
      expect(voiceNavigationPauseCount, 1);
      expect(voiceNavigationResumeCount, 0);

      await tester.tap(find.byKey(const Key('skip-lesson-intro')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('lesson-overview-screen')), findsOneWidget);
      expect(find.text('Nghe tổng quan'), findsOneWidget);
      expect(find.text('A to I Letters'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reports completed V4 topics again after replaying one', (
    tester,
  ) async {
    final content = await AssetListeningContentRepository().load();
    final progressStore = _MemoryProgressStore();
    final requests = <({int childAge, List<int> completedTopicNumbers})>[];
    final topic = content.topic(startAge: 6, endAge: 7, topicNumber: 1);
    for (final lesson in topic.lessons) {
      await progressStore.saveLesson(lesson.id, lesson.sentences.length);
      await progressStore.markV4LessonActivityCompleted(lesson.id);
    }
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildSubject(
        childAge: 6,
        contentFuture: Future<ListeningContentCatalog>.value(content),
        progressStore: progressStore,
        onTopicSelectionAfterCompletion:
            ({required childAge, required completedTopicNumbers}) async {
              requests.add((
                childAge: childAge,
                completedTopicNumbers: completedTopicNumbers,
              ));
            },
      ),
    );
    await tester.pumpAndSettle();

    final firstTopic = find.byKey(const ValueKey('topic-6-7-0'));
    await tester.ensureVisible(firstTopic);
    await tester.tap(firstTopic);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('topic-lesson-list-screen')), findsOneWidget);

    tester
        .widget<TopicLessonListScreen>(find.byType(TopicLessonListScreen))
        .onTopicCompleted
        ?.call();
    Navigator.of(
      tester.element(find.byKey(const Key('topic-lesson-list-screen'))),
    ).pop();
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.single.childAge, 6);
    expect(requests.single.completedTopicNumbers, <int>[1]);
  });

  testWidgets(
    'does not report a V4 topic complete until its authored activities finish',
    (tester) async {
      final content = await AssetListeningContentRepository().load();
      final progressStore = _MemoryProgressStore();
      final requests = <({int childAge, List<int> completedTopicNumbers})>[];
      final topic = content.topic(startAge: 6, endAge: 7, topicNumber: 1);
      for (final lesson in topic.lessons) {
        await progressStore.saveLesson(lesson.id, lesson.sentences.length);
      }
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        buildSubject(
          childAge: 6,
          contentFuture: Future<ListeningContentCatalog>.value(content),
          progressStore: progressStore,
          onTopicSelectionAfterCompletion:
              ({required childAge, required completedTopicNumbers}) async {
                requests.add((
                  childAge: childAge,
                  completedTopicNumbers: completedTopicNumbers,
                ));
              },
        ),
      );
      await tester.pumpAndSettle();

      final firstTopic = find.byKey(const ValueKey('topic-6-7-0'));
      await tester.ensureVisible(firstTopic);
      await tester.tap(firstTopic);
      await tester.pumpAndSettle();

      expect(find.text('Hoàn thành thử thách'), findsWidgets);

      tester
          .widget<TopicLessonListScreen>(find.byType(TopicLessonListScreen))
          .onTopicCompleted
          ?.call();
      Navigator.of(
        tester.element(find.byKey(const Key('topic-lesson-list-screen'))),
      ).pop();
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(requests.single.childAge, 6);
      expect(requests.single.completedTopicNumbers, isEmpty);
    },
  );

  testWidgets(
    'renders a V4 song milestone as a normal lesson, not a legacy clip',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildSubject(childAge: 3));
      await tester.pumpAndSettle();

      final topicWithSongMilestone = find.byKey(const ValueKey('topic-3-5-1'));
      await tester.scrollUntilVisible(
        topicWithSongMilestone,
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('topic-listening-screen')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(topicWithSongMilestone);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('topic-lesson-list-screen')), findsOneWidget);
      expect(find.text('Bài hát & chant'), findsNothing);
      expect(find.byKey(const ValueKey('song-c35-l1-t02-b02')), findsNothing);
      final songMilestone = find.byKey(
        const ValueKey('start-lesson-c35-l1-t02-b02'),
      );
      await tester.scrollUntilVisible(songMilestone, 180);
      expect(songMilestone, findsOneWidget);
      expect(find.textContaining('Count With Me'), findsWidgets);
    },
  );

  test(
    'bundled lesson content matches the V4 source-of-truth catalog',
    () async {
      final content = await AssetListeningContentRepository().load();
      final topics = content.groups
          .expand((group) => group.topics)
          .toList(growable: false);
      final lessons = topics
          .expand((topic) => topic.lessons)
          .toList(growable: false);
      final targets = lessons
          .expand((lesson) => lesson.sentences)
          .toList(growable: false);
      final levels = content.groups
          .expand((group) => group.levels)
          .toList(growable: false);

      expect(content.groups, hasLength(5));
      expect(topics, hasLength(50));
      expect(levels, hasLength(15));
      expect(lessons, hasLength(109));
      expect(targets, hasLength(601));
      expect(
        lessons.map((lesson) => lesson.id).toSet(),
        hasLength(lessons.length),
      );
      expect(
        targets.map((target) => target.id).toSet(),
        hasLength(targets.length),
      );

      final alphabet = content.topic(startAge: 3, endAge: 5, topicNumber: 1);
      expect(alphabet.titleVi, 'Bảng chữ cái');
      expect(alphabet.levelNumber, 1);
      expect(alphabet.lessons, hasLength(3));
      expect(alphabet.sentenceCount, 26);
      expect(alphabet.lessons.first.id, 'c35-l1-t01-b01');
      expect(alphabet.lessons.first.sentences.first.english, 'A. Apple.');
      expect(
        alphabet.lessons.first.sentences.first.requiresAllExpectedTokens,
        isTrue,
      );

      final classroomTalk = lessons.singleWhere(
        (lesson) => lesson.id == 'c810-l1-t02-b02',
      );
      expect(classroomTalk.titleEn, 'Classroom Talk');
      expect(classroomTalk.rolePlay?.scenarioVi, 'Bạn đang ở trước cửa lớp.');
      expect(
        classroomTalk.rolePlay?.turns.map((turn) => turn.english),
        <String>['Can I come in?', 'Yes, come in.', 'Thank you.'],
      );

      final advanced = content.topic(startAge: 13, endAge: 15, topicNumber: 3);
      expect(advanced.titleVi, 'Nêu ý kiến');
      expect(advanced.levelNumber, 1);
      expect(
        advanced.lessons.first.overviewMode,
        ListeningOverviewMode.englishOnly,
      );
    },
  );

  testWidgets(
    'a compact phone can reach the V4 lesson intro without layout errors',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildSubject(childAge: 3, textScale: 1.3));
      await tester.pumpAndSettle();

      final compactTopic = find.byKey(const ValueKey('topic-3-5-0'));
      await tester.scrollUntilVisible(
        compactTopic,
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('topic-listening-screen')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await Scrollable.ensureVisible(
        tester.element(compactTopic),
        alignment: 0.4,
        duration: Duration.zero,
      );
      await tester.pump();
      await tester.tap(compactTopic);
      await tester.pumpAndSettle();

      final startLesson = find.byKey(
        const ValueKey('start-lesson-c35-l1-t01-b01'),
      );
      await tester.scrollUntilVisible(startLesson, 180);
      await Scrollable.ensureVisible(
        tester.element(startLesson),
        alignment: 0.45,
        duration: Duration.zero,
      );
      await tester.pump();
      await tester.tap(startLesson);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(const Key('lesson-intro-screen')), findsOneWidget);
      expect(find.byKey(const Key('skip-lesson-intro')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders the learning journey responsively on web width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-journey-path')), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-6-7-0')), findsOneWidget);
    expect(find.text('Hành trình của con'), findsOneWidget);
    expect(
      find.byKey(const Key('listening-bottom-navigation')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps core controls available at large text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildSubject(textScale: 2));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-age-selector')), findsOneWidget);
    expect(find.byKey(const Key('continue-listening-card')), findsNothing);
    expect(
      find.byKey(const Key('listening-bottom-navigation')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _MemoryProgressStore extends ListeningProgressStore {
  final Map<String, int> _progress = <String, int>{};
  final Set<String> _completedV4LessonActivities = <String>{};

  @override
  Future<Map<String, int>> readAll() async => Map<String, int>.of(_progress);

  @override
  Future<Set<String>> readCompletedV4LessonActivities() async =>
      Set<String>.of(_completedV4LessonActivities);

  @override
  Future<void> markV4LessonActivityCompleted(String lessonId) async {
    _completedV4LessonActivities.add(lessonId);
  }

  @override
  Future<void> saveLesson(String lessonId, int completedSentences) async {
    final previous = _progress[lessonId] ?? 0;
    if (completedSentences > previous) {
      _progress[lessonId] = completedSentences;
    }
  }
}
