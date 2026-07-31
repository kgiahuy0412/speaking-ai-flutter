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

  test('all five karaoke songs have loadable intro and full audio', () async {
    final content = await AssetListeningContentRepository().load();
    final songs = <String, ListeningLessonContent>{
      for (final song
          in content.groups
              .expand((group) => group.topics)
              .expand((topic) => topic.songs))
        song.id: song,
    };
    const expectedAssets = <String, String>{
      'a067_t05_song01': 'assets/audio/A-6-7/SONGS/A067_T05_SONG01_FULL_EN.mp3',
      'a067_t07_song01': 'assets/audio/A-6-7/SONGS/A067_T07_SONG01_FULL_EN.mp3',
      'a067_t08_song01': 'assets/audio/A-6-7/SONGS/A067_T08_SONG01_FULL_EN.mp3',
      'a0810_t03_song01':
          'assets/audio/A-8-10/SONGS/A0810_T03_SONG01_FULL_EN.mp3',
      'a0810_t04_song01':
          'assets/audio/A-8-10/SONGS/A0810_T04_SONG01_FULL_EN.mp3',
    };
    const expectedTimelineLengths = <String, int>{
      'a067_t05_song01': 12,
      'a067_t07_song01': 56,
      'a067_t08_song01': 44,
      'a0810_t03_song01': 62,
      'a0810_t04_song01': 22,
    };
    const expectedIntros = <String, (String, String, String)>{
      'a067_t05_song01': (
        'Count the Days',
        'Chào con! Bây giờ mình cùng nghe bài hát “Count the Days”. Con hãy lắng nghe và hát theo nhé!',
        'assets/audio/A-6-7/SONG_INTRO/SONG_INTRO_06_07_01.mp3',
      ),
      'a067_t07_song01': (
        'My Day',
        'Chào con! Bây giờ mình cùng nghe bài hát “My Day”. Con hãy lắng nghe và hát theo nhé!',
        'assets/audio/A-6-7/SONG_INTRO/SONG_INTRO_06_07_02.mp3',
      ),
      'a067_t08_song01': (
        'What Should I Wear?',
        'Chào con! Bây giờ mình cùng nghe bài hát “What Should I Wear?”. Con hãy lắng nghe và hát theo nhé!',
        'assets/audio/A-6-7/SONG_INTRO/SONG_INTRO_06_07_03.mp3',
      ),
      'a0810_t03_song01': (
        'My Busy Day',
        'Chào con! Bây giờ mình cùng nghe bài hát “My Busy Day”. Con hãy lắng nghe và hát theo nhé!',
        'assets/audio/A-8-10/SONG_INTRO/SONG_INTRO_08_10_01.mp3',
      ),
      'a0810_t04_song01': (
        'Let’s Play Together',
        'Chào con! Bây giờ mình cùng nghe bài hát “Let’s Play Together”. Con hãy lắng nghe và hát theo nhé!',
        'assets/audio/A-8-10/SONG_INTRO/SONG_INTRO_08_10_02.mp3',
      ),
    };

    for (final entry in expectedAssets.entries) {
      final song = songs[entry.key];
      final uri = song?.fullAudioUri;
      expect(uri?.scheme, 'asset', reason: entry.key);
      expect(uri?.path, '/${entry.value}', reason: entry.key);
      final bytes = await rootBundle.load(entry.value);
      expect(bytes.lengthInBytes, greaterThan(1000), reason: entry.key);
      final expectedIntro = expectedIntros[entry.key]!;
      expect(song?.titleEn, expectedIntro.$1, reason: entry.key);
      expect(song?.intro, expectedIntro.$2, reason: entry.key);
      expect(song?.introAudioUri?.scheme, 'asset', reason: entry.key);
      expect(
        song?.introAudioUri?.path,
        '/${expectedIntro.$3}',
        reason: entry.key,
      );
      final introBytes = await rootBundle.load(expectedIntro.$3);
      expect(introBytes.lengthInBytes, greaterThan(1000), reason: entry.key);
      expect(
        song?.karaokeLines,
        hasLength(expectedTimelineLengths[entry.key]),
        reason: entry.key,
      );
      expect(
        song?.karaokeLines.every(
          (line) =>
              line.karaokeStart != null &&
              line.karaokeEnd != null &&
              line.karaokeEnd! > line.karaokeStart!,
        ),
        isTrue,
        reason: entry.key,
      );
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

    expect(find.byKey(const Key('lesson-review-screen')), findsOneWidget);
    expect(find.text('Nghe tổng quan'), findsOneWidget);
    expect(find.byKey(const Key('unrecorded-sentences-banner')), findsNothing);
    expect(find.text('Sẵn sàng nghe lại'), findsNothing);

    await tester.pump(const Duration(seconds: 6));
    final learnNowButton = find.byKey(const Key('complete-lesson-review'));
    await tester.ensureVisible(learnNowButton);
    await tester.pump();
    await tester.tap(learnNowButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lesson-practice-screen')), findsOneWidget);
    expect(find.text('Hello!'), findsOneWidget);
    expect(find.text('Xin chào!'), findsOneWidget);
    expect(find.byKey(const Key('record-lesson-sentence')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides song and chant content for ages three to five', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildSubject(childAge: 3));
    await tester.pumpAndSettle();

    final topicWithSongs = find.byKey(const ValueKey('topic-3-5-1'));
    await tester.scrollUntilVisible(
      topicWithSongs,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('topic-listening-screen')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(topicWithSongs);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-lesson-list-screen')), findsOneWidget);
    expect(find.text('♫ 3 bài hát/chant'), findsNothing);
    expect(find.text('Bài hát & chant'), findsNothing);
    expect(find.byKey(const ValueKey('song-a035_t02_song01')), findsNothing);
    expect(find.byKey(const ValueKey('lesson-a035_t02_l01')), findsOneWidget);

    final lessonJourneyScrollView = find
        .descendant(
          of: find.byKey(const Key('topic-lesson-list-screen')),
          matching: find.byType(Scrollable),
        )
        .first;
    final startLesson = find.byKey(const ValueKey('start-lesson-a035_t02_l01'));
    await tester.scrollUntilVisible(
      startLesson,
      -220,
      scrollable: lessonJourneyScrollView,
    );

    await tester.tap(startLesson);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('lesson-intro-screen')), findsOneWidget);
    expect(find.byKey(const Key('skip-lesson-intro')), findsOneWidget);

    await tester.tap(find.byKey(const Key('skip-lesson-intro')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lesson-review-screen')), findsOneWidget);
    expect(find.byKey(const Key('auto-play-lesson-review')), findsOneWidget);
    expect(find.byKey(const Key('complete-lesson-review')), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    final learnNowButton = find.byKey(const Key('complete-lesson-review'));
    await tester.ensureVisible(learnNowButton);
    await tester.tap(learnNowButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('lesson-practice-screen')), findsOneWidget);
    expect(find.byKey(const Key('play-lesson-sample')), findsOneWidget);
    expect(find.byKey(const Key('play-vietnamese-meaning')), findsOneWidget);
    expect(find.byKey(const Key('record-lesson-sentence')), findsOneWidget);
    expect(find.byKey(const Key('continue-lesson-sentence')), findsOneWidget);
  });

  testWidgets('keeps song and chant content for ages six and older', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildSubject(childAge: 6));
    await tester.pumpAndSettle();

    final topicWithSongs = find.byKey(const ValueKey('topic-6-7-4'));
    final topicsScrollable = find
        .descendant(
          of: find.byKey(const Key('topic-listening-screen')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      topicWithSongs,
      180,
      scrollable: topicsScrollable,
    );
    await tester.drag(topicsScrollable, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(topicWithSongs);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-lesson-list-screen')), findsOneWidget);
    expect(find.text('♫ 1 bài hát/chant'), findsOneWidget);

    final firstSong = find.byKey(const ValueKey('song-a067_t05_song01'));
    await tester.scrollUntilVisible(
      firstSong,
      220,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('topic-lesson-list-screen')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Bài hát & chant'), findsOneWidget);
    expect(firstSong, findsOneWidget);
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
    expect(songLines, hasLength(79));
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

    final referenceLessons = content
        .topic(startAge: 6, endAge: 7, topicNumber: 1)
        .lessons;
    final updatedLessons = <ListeningLessonContent>[
      ...content.topic(startAge: 3, endAge: 5, topicNumber: 2).lessons,
      ...content.topic(startAge: 3, endAge: 5, topicNumber: 3).lessons,
      ...content.topic(startAge: 3, endAge: 5, topicNumber: 6).lessons,
      ...content.topic(startAge: 3, endAge: 5, topicNumber: 10).lessons,
    ];

    expect(referenceLessons, hasLength(2));
    expect(updatedLessons, hasLength(9));
    bool supportsStandardLessonFlow(ListeningLessonContent lesson) {
      return lesson.type == ListeningLessonType.standard &&
          lesson.intro.isNotEmpty &&
          lesson.introAudioUri != null &&
          lesson.sentences.isNotEmpty &&
          lesson.sentences.every(
            (sentence) =>
                sentence.audioUri != null &&
                sentence.vietnameseAudioUri != null,
          );
    }

    expect(referenceLessons.every(supportsStandardLessonFlow), isTrue);
    expect(updatedLessons.every(supportsStandardLessonFlow), isTrue);
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
    expect(find.byKey(const Key('lesson-review-screen')), findsOneWidget);
    expect(find.text('Nghe tổng quan'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    final learnNowButton = find.byKey(const Key('complete-lesson-review'));
    await tester.ensureVisible(learnNowButton);
    await tester.pump();
    await tester.tap(learnNowButton);
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
