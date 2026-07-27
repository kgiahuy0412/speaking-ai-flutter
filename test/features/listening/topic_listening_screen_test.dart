import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
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
  }) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(textScale),
        ),
        child: TopicListeningScreen(language: language, childAge: childAge),
      ),
    );
  }

  test('all 50 listening topics have a loadable image asset', () async {
    final topics = listeningCatalogs
        .expand((catalog) => catalog.topics)
        .toList();

    expect(topics, hasLength(50));
    for (final topic in topics) {
      expect(topic.imagePath, isNotNull, reason: topic.titleVi);
      final bytes = await rootBundle.load(topic.imagePath!);
      expect(bytes.lengthInBytes, greaterThan(1000), reason: topic.titleVi);
    }
  });

  testWidgets('selects the matching age group and changes its topic catalog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    expect(find.text('Tên và tuổi của con'), findsOneWidget);
    expect(find.text('10 chủ đề'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('topic-age-selector')),
      const Offset(-220, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('age-8-10')));
    await tester.pumpAndSettle();

    expect(find.text('Con và những người bạn'), findsOneWidget);
    expect(find.text('Tên và tuổi của con'), findsNothing);
  });

  testWidgets('opens the selected topic lesson journey', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildSubject(childAge: 3));
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
    expect(find.textContaining('Chào hỏi'), findsOneWidget);
    expect(find.text('2 bài nhỏ'), findsOneWidget);
    expect(find.text('10 câu'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('start-lesson-a035_t01_l01')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('lesson-intro-screen')), findsOneWidget);
    expect(find.textContaining('Chào con!'), findsOneWidget);

    await tester.tap(find.byKey(const Key('skip-lesson-intro')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lesson-practice-screen')), findsOneWidget);
    expect(find.text('Hello!'), findsOneWidget);
    expect(find.text('Xin chào!'), findsOneWidget);
    expect(find.byKey(const Key('record-lesson-sentence')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bundled lesson content matches the approved Word catalog', (
    tester,
  ) async {
    final content = await AssetListeningContentRepository().load();
    final topics = content.groups.expand((group) => group.topics).toList();
    final lessons = topics.expand((topic) => topic.lessons).toList();
    final sentences = lessons.expand((lesson) => lesson.sentences).toList();

    expect(content.groups, hasLength(5));
    expect(topics, hasLength(50));
    final songs = topics.expand((topic) => topic.songs).toList();
    final songLines = songs.expand((song) => song.sentences).toList();
    final allLearningItems = <ListeningLessonContent>[...lessons, ...songs];
    final allSentences = allLearningItems
        .expand((lesson) => lesson.sentences)
        .toList();

    expect(lessons, hasLength(101));
    expect(sentences, hasLength(634));
    expect(songs, hasLength(11));
    expect(songLines, hasLength(69));
    expect(
      allLearningItems.map((lesson) => lesson.id).toSet(),
      hasLength(allLearningItems.length),
    );
    expect(
      allSentences.map((sentence) => sentence.id).toSet(),
      hasLength(allSentences.length),
    );
    expect(
      allSentences.every(
        (sentence) =>
            sentence.englishAudioId != null &&
            sentence.vietnameseAudioId != null &&
            sentence.englishAudioId != sentence.vietnameseAudioId,
      ),
      isTrue,
    );
    expect(
      songs.every((lesson) => lesson.type == ListeningLessonType.song),
      isTrue,
    );
    expect(
      content.groups[0].topics
          .expand((topic) => topic.lessons)
          .every((lesson) => lesson.autoAdvanceDelay.inMilliseconds == 2750),
      isTrue,
    );
    expect(
      content.groups[4].topics
          .expand((topic) => topic.lessons)
          .every((lesson) => lesson.autoAdvanceDelay.inMilliseconds == 1250),
      isTrue,
    );

    final greetings = content.topic(startAge: 3, endAge: 5, topicNumber: 1);
    expect(greetings.lessons, hasLength(2));
    expect(greetings.lessons.first.sentences, hasLength(5));
    expect(greetings.lessons.first.sentences.first.english, 'Hello!');
    expect(greetings.lessons.first.sentences.first.vietnamese, 'Xin chào!');
  });

  testWidgets('lesson flow remains usable on a compact phone', (tester) async {
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
    await tester.tap(compactTopic);
    await tester.pumpAndSettle();
    final startLesson = find.byKey(const ValueKey('start-lesson-a035_t01_l01'));
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
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('skip-lesson-intro')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lesson-practice-screen')), findsOneWidget);
    expect(find.byKey(const Key('record-lesson-sentence')), findsOneWidget);
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
    expect(find.byKey(const Key('continue-listening-card')), findsOneWidget);
    expect(
      find.byKey(const Key('listening-bottom-navigation')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
