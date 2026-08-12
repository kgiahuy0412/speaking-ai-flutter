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
    ThemeMode themeMode = ThemeMode.light,
    Future<void> Function()? onVoiceNavigationPause,
    VoidCallback? onVoiceNavigationResume,
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
    final continueLabel = tester.widget<Text>(find.text('Tiếp tục học'));
    final theme = Theme.of(
      tester.element(find.byKey(const Key('topic-listening-screen'))),
    );

    expect(theme.brightness, Brightness.dark);
    expect(journeyTitle.style?.color, theme.colorScheme.onSurface);
    expect(continueLabel.style?.color, theme.colorScheme.primary);
  });

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

  test('song topics use the approved Vietnamese names', () async {
    final content = await AssetListeningContentRepository().load();
    const expectedNames =
        <({int startAge, int endAge, int topicNumber, String titleVi})>[
          (startAge: 6, endAge: 7, topicNumber: 5, titleVi: 'Số đếm'),
          (startAge: 6, endAge: 7, topicNumber: 7, titleVi: 'Một ngày của con'),
          (startAge: 6, endAge: 7, topicNumber: 8, titleVi: 'Thời tiết'),
          (
            startAge: 8,
            endAge: 10,
            topicNumber: 3,
            titleVi: 'Một ngày ở trường',
          ),
          (startAge: 8, endAge: 10, topicNumber: 4, titleVi: 'Môn thể thao'),
        ];

    for (final expected in expectedNames) {
      final catalog = listeningCatalogs.singleWhere(
        (catalog) =>
            catalog.startAge == expected.startAge &&
            catalog.endAge == expected.endAge,
      );
      expect(
        catalog.topics[expected.topicNumber - 1].titleVi,
        expected.titleVi,
      );
      expect(
        content
            .topic(
              startAge: expected.startAge,
              endAge: expected.endAge,
              topicNumber: expected.topicNumber,
            )
            .titleVi,
        expected.titleVi,
      );
    }
  });

  test(
    'five updated topics expose their retained lesson as lesson 1',
    () async {
      final content = await AssetListeningContentRepository().load();
      const expectedLessons =
          <({int startAge, int endAge, int topicNumber, String lessonId})>[
            (startAge: 6, endAge: 7, topicNumber: 5, lessonId: 'a067_t05_l02'),
            (startAge: 6, endAge: 7, topicNumber: 7, lessonId: 'a067_t07_l02'),
            (startAge: 6, endAge: 7, topicNumber: 8, lessonId: 'a067_t08_l02'),
            (
              startAge: 8,
              endAge: 10,
              topicNumber: 3,
              lessonId: 'a0810_t03_l02',
            ),
            (
              startAge: 8,
              endAge: 10,
              topicNumber: 4,
              lessonId: 'a0810_t04_l02',
            ),
          ];

      for (final expected in expectedLessons) {
        final topic = content.topic(
          startAge: expected.startAge,
          endAge: expected.endAge,
          topicNumber: expected.topicNumber,
        );
        expect(topic.lessons, hasLength(1));
        expect(topic.lessons.single.id, expected.lessonId);
        expect(topic.lessons.single.number, 1);
      }
    },
  );

  test('five new lessons have loadable opening audio', () async {
    final content = await AssetListeningContentRepository().load();
    final lessons = content.groups
        .expand((group) => group.topics)
        .expand((topic) => topic.lessons)
        .toList();
    const expectedOpenings = <String, ({String intro, String assetPath})>{
      'a067_t05_l02': (
        intro:
            'Chào con! Hôm nay mình sẽ học bài “Count and Move”. Trước tiên, con nghe nội dung tổng, rồi học từng câu và ghi âm nhé!',
        assetPath: 'assets/audio/A-6-7/LESSON_INTRO/A067_T05_L02_OPEN.mp3',
      ),
      'a067_t07_l02': (
        intro:
            'Chào con! Hôm nay mình sẽ học bài “Things I Do”. Trước tiên, con nghe nội dung tổng, rồi học từng câu và ghi âm nhé!',
        assetPath: 'assets/audio/A-6-7/LESSON_INTRO/A067_T07_L02_OPEN.mp3',
      ),
      'a067_t08_l02': (
        intro:
            'Chào con! Hôm nay mình sẽ học bài “Dress for Today”. Trước tiên, con nghe nội dung tổng, rồi học từng câu và ghi âm nhé!',
        assetPath: 'assets/audio/A-6-7/LESSON_INTRO/A067_T08_L02_OPEN.mp3',
      ),
      'a0810_t03_l02': (
        intro:
            'Chào con! Hôm nay mình sẽ học bài “My School Day”. Trước tiên, con nghe nội dung tổng, rồi học từng câu và ghi âm nhé!',
        assetPath: 'assets/audio/A-8-10/LESSON_INTRO/A0810_T03_L02_OPEN.mp3',
      ),
      'a0810_t04_l02': (
        intro:
            'Chào con! Hôm nay mình sẽ học bài “Sports I Like”. Trước tiên, con nghe nội dung tổng, rồi học từng câu và ghi âm nhé!',
        assetPath: 'assets/audio/A-8-10/LESSON_INTRO/A0810_T04_L02_OPEN.mp3',
      ),
    };

    for (final entry in expectedOpenings.entries) {
      final lesson = lessons.singleWhere((lesson) => lesson.id == entry.key);
      expect(lesson.intro, entry.value.intro);
      expect(
        lesson.introAudioUri,
        Uri.parse('asset:///${entry.value.assetPath}'),
      );
      final bytes = await rootBundle.load(entry.value.assetPath);
      expect(bytes.lengthInBytes, greaterThan(100000));
    }
  });

  test('all five official songs have loadable intro and full audio', () async {
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
      'a067_t07_song01': 16,
      'a067_t08_song01': 8,
      'a0810_t03_song01': 16,
      'a0810_t04_song01': 19,
    };
    const expectedPracticeLengths = <String, int>{
      'a067_t05_song01': 12,
      'a067_t07_song01': 16,
      'a067_t08_song01': 8,
      'a0810_t03_song01': 16,
      'a0810_t04_song01': 19,
    };
    const expectedTimelineEnds = <String, int>{
      'a067_t05_song01': 19220,
      'a067_t07_song01': 45900,
      'a067_t08_song01': 21960,
      'a0810_t03_song01': 27980,
      'a0810_t04_song01': 46260,
    };
    const expectedAudioBytes = <String, int>{
      'a067_t05_song01': 449304,
      'a067_t07_song01': 1071672,
      'a067_t08_song01': 536280,
      'a0810_t03_song01': 690600,
      'a0810_t04_song01': 1075272,
    };
    const expectedIntros = <String, (String, String, String)>{
      'a067_t05_song01': (
        'Count with Me',
        'Chào con! Bây giờ mình cùng nghe bài hát “Count with Me”. Con hãy lắng nghe và hát theo nhé!',
        'assets/audio/A-6-7/SONG_INTRO/SONG_INTRO_06_07_01.mp3',
      ),
      'a067_t07_song01': (
        'My Happy Day',
        'Chào con! Bây giờ mình cùng nghe bài hát “My Happy Day”. Con hãy lắng nghe và hát theo nhé!',
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
      expect(
        bytes.lengthInBytes,
        expectedAudioBytes[entry.key],
        reason: entry.key,
      );
      final expectedIntro = expectedIntros[entry.key]!;
      expect(song?.titleEn, expectedIntro.$1, reason: entry.key);
      expect(song?.titleVi, expectedIntro.$1, reason: entry.key);
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
        song?.sentences,
        hasLength(expectedPracticeLengths[entry.key]),
        reason: entry.key,
      );
      expect(
        song?.sentences.every((line) => line.vietnamese.trim().isNotEmpty),
        isTrue,
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
      expect(
        song?.karaokeLines.last.karaokeEnd,
        Duration(milliseconds: expectedTimelineEnds[entry.key]!),
        reason: entry.key,
      );
      for (var index = 1; index < song!.karaokeLines.length; index += 1) {
        expect(
          song.karaokeLines[index].karaokeStart,
          greaterThanOrEqualTo(song.karaokeLines[index - 1].karaokeEnd!),
          reason: '${entry.key} line ${index + 1}',
        );
      }
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
    var voiceNavigationPauseCount = 0;
    var voiceNavigationResumeCount = 0;
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
    expect(find.textContaining('Chào hỏi'), findsOneWidget);
    expect(find.text('2 bài nhỏ'), findsOneWidget);
    expect(find.text('10 câu'), findsWidgets);
    expect(voiceNavigationPauseCount, 0);

    await tester.tap(find.byKey(const ValueKey('start-lesson-a035_t01_l01')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('lesson-intro-screen')), findsOneWidget);
    expect(find.textContaining('Chào con!'), findsOneWidget);
    expect(voiceNavigationPauseCount, 1);
    expect(voiceNavigationResumeCount, 0);

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
    await tester.ensureVisible(topicWithSongs);
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

    expect(lessons, hasLength(96));
    expect(sentences, hasLength(608));
    expect(songs, hasLength(11));
    expect(songLines, hasLength(110));

    final approvedSongLeadLessons =
        <
          String,
          ({
            String titleEn,
            String titleVi,
            List<String> english,
            List<String> vietnamese,
          })
        >{
          'a067_t05_l02': (
            titleEn: 'Count and Move',
            titleVi: 'Đếm và chuyển động',
            english: <String>[
              'One, two.',
              'Three, four.',
              'Five, six.',
              'Seven, eight.',
              'Nine, ten.',
              'Clap your hands.',
              'Turn around.',
              'Touch the ground.',
            ],
            vietnamese: <String>[
              'Một, hai.',
              'Ba, bốn.',
              'Năm, sáu.',
              'Bảy, tám.',
              'Chín, mười.',
              'Vỗ tay nào.',
              'Xoay một vòng.',
              'Chạm xuống đất.',
            ],
          ),
          'a067_t07_l02': (
            titleEn: 'Things I Do',
            titleVi: 'Những điều con làm',
            english: <String>[
              'Wake up.',
              'Wash my face.',
              'Eat breakfast.',
              'Go to school.',
              'Learn and play.',
              'Time for bed.',
            ],
            vietnamese: <String>[
              'Thức dậy.',
              'Rửa mặt.',
              'Ăn sáng.',
              'Đi học.',
              'Học và chơi.',
              'Đến giờ đi ngủ.',
            ],
          ),
          'a067_t08_l02': (
            titleEn: 'Dress for Today',
            titleVi: 'Đồ mặc hôm nay',
            english: <String>[
              'It’s sunny.',
              'Put your hat on.',
              'It’s rainy.',
              'Put your coat on.',
              'It’s cold.',
              'Zip it up.',
              'It’s hot.',
              'Wear a T-shirt.',
            ],
            vietnamese: <String>[
              'Trời nắng.',
              'Đội mũ lên.',
              'Trời mưa.',
              'Mặc áo khoác vào.',
              'Trời lạnh.',
              'Kéo khóa lên.',
              'Trời nóng.',
              'Mặc áo thun.',
            ],
          ),
          'a0810_t03_l02': (
            titleEn: 'My School Day',
            titleVi: 'Một ngày ở trường của mình',
            english: <String>[
              'I get dressed.',
              'I pack my bag.',
              'I’m on my way.',
              'It’s a busy day.',
              'I learn at school.',
              'I play with friends.',
            ],
            vietnamese: <String>[
              'Mình mặc quần áo.',
              'Mình chuẩn bị cặp.',
              'Mình lên đường rồi.',
              'Hôm nay là một ngày bận rộn.',
              'Mình học ở trường.',
              'Mình chơi với bạn.',
            ],
          ),
          'a0810_t04_l02': (
            titleEn: 'Sports I Like',
            titleVi: 'Môn thể thao mình thích',
            english: <String>[
              'Do you like soccer?',
              'Yes, I do.',
              'Do you like swimming?',
              'I do too.',
              'Let’s play together.',
              'Run and jump with me.',
            ],
            vietnamese: <String>[
              'Bạn có thích bóng đá không?',
              'Có, mình thích.',
              'Bạn có thích bơi không?',
              'Mình cũng thích.',
              'Mình cùng chơi nhé.',
              'Chạy và nhảy cùng mình nhé.',
            ],
          ),
        };

    for (final entry in approvedSongLeadLessons.entries) {
      final lesson = lessons.singleWhere((lesson) => lesson.id == entry.key);
      expect(lesson.titleEn, entry.value.titleEn);
      expect(lesson.titleVi, entry.value.titleVi);
      expect(lesson.type, ListeningLessonType.standard);
      expect(
        lesson.sentences.map((sentence) => sentence.english).toList(),
        entry.value.english,
      );
      expect(
        lesson.sentences.map((sentence) => sentence.vietnamese).toList(),
        entry.value.vietnamese,
      );
    }

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
    await Scrollable.ensureVisible(
      tester.element(compactTopic),
      alignment: 0.4,
      duration: Duration.zero,
    );
    await tester.pump();
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
    expect(find.byKey(const Key('continue-listening-card')), findsOneWidget);
    expect(
      find.byKey(const Key('listening-bottom-navigation')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
