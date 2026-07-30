import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/data/listening_progress_store.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_intro_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_review_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/song_karaoke_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  test('karaoke is limited to songs for ages six and older', () {
    final song = _song();
    expect(shouldUseSongKaraoke(startAge: 3, lesson: song), isFalse);
    expect(shouldUseSongKaraoke(startAge: 6, lesson: song), isTrue);
    expect(
      shouldUseSongKaraoke(startAge: 8, lesson: _standardLesson()),
      isFalse,
    );
  });

  test('dedicated karaoke timeline is read separately from practice lines', () {
    final lesson = ListeningLessonContent.fromJson(<String, Object?>{
      'sentences': <Object?>[
        <String, Object?>{
          'number': 1,
          'english': 'Practice line.',
          'vietnamese': 'Câu luyện tập.',
        },
      ],
      'karaokeLines': <Object?>[
        <String, Object?>{
          'number': 1,
          'english': 'Monday, Tuesday — off we go!',
          'karaokeStartMs': 1250,
          'karaokeEndMs': 6200,
        },
      ],
    });

    expect(lesson.sentences.single.english, 'Practice line.');
    final line = lesson.karaokeLines.single;
    expect(line.karaokeStart, const Duration(milliseconds: 1250));
    expect(line.karaokeEnd, const Duration(milliseconds: 6200));
  });

  testWidgets('song starts automatically after three seconds', (tester) async {
    await _usePhoneSurface(tester);
    final mediaService = _KaraokeMediaService();
    addTearDown(mediaService.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: _screen(
          mediaService: mediaService,
          autoPlayDelay: const Duration(seconds: 3),
        ),
      ),
    );
    await _precacheBackground(tester);
    await tester.pump();

    expect(mediaService.preloadCalls, 1);
    expect(mediaService.playCalls, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(mediaService.playCalls, 0);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(mediaService.playCalls, 1);
    expect(find.text('Tạm dừng'), findsOneWidget);
  });

  testWidgets('karaoke follows playback position line by line', (tester) async {
    await _usePhoneSurface(tester);
    final mediaService = _KaraokeMediaService(
      position: const Duration(seconds: 2),
      duration: const Duration(seconds: 12),
    );
    addTearDown(mediaService.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: _screen(
          mediaService: mediaService,
          autoPlayDelay: const Duration(days: 1),
        ),
      ),
    );
    await _precacheBackground(tester);
    await tester.pump();

    expect(find.text('Monday, Tuesday — off we go!'), findsOneWidget);
    expect(find.text('Wednesday, Thursday — learn and grow!'), findsOneWidget);

    mediaService.emitPosition(const Duration(seconds: 7));
    await tester.pump();
    await tester.pump();

    var currentLine = tester.widget<Text>(
      find.byKey(const Key('song-karaoke-current-line')),
    );
    expect(currentLine.textSpan?.toPlainText(), 'Monday, Tuesday — off we go!');

    mediaService.emitPosition(const Duration(seconds: 9));
    await tester.pump();
    await tester.pump();

    currentLine = tester.widget<Text>(
      find.byKey(const Key('song-karaoke-current-line')),
    );
    expect(
      currentLine.textSpan?.toPlainText(),
      'Wednesday, Thursday — learn and grow!',
    );
  });

  testWidgets('end dialog offers practice or confirmed exit', (tester) async {
    await _usePhoneSurface(tester);
    final mediaService = _KaraokeMediaService();
    addTearDown(mediaService.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: _screen(
          mediaService: mediaService,
          autoPlayDelay: const Duration(days: 1),
          practiceBuilder: (_) => const Scaffold(
            key: Key('song-practice-target'),
            body: Text('Practice'),
          ),
        ),
      ),
    );
    await _precacheBackground(tester);
    await tester.pump();

    await tester.tap(find.byKey(const Key('song-karaoke-end')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('song-karaoke-end-dialog')), findsOneWidget);
    expect(find.text('Luyện theo bài hát'), findsOneWidget);
    expect(find.text('Xác nhận thoát'), findsOneWidget);

    await tester.tap(find.byKey(const Key('song-karaoke-practice')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('song-practice-target')), findsOneWidget);
    expect(mediaService.stopCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('intro routes an eligible song to karaoke', (tester) async {
    await _usePhoneSurface(tester);
    final mediaService = _KaraokeMediaService();
    addTearDown(mediaService.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 6,
          endAge: 7,
          topic: listeningCatalogs[1].topics[4],
          lesson: _song(),
          progressStore: const _MemoryProgressStore(),
          mediaService: mediaService,
          autoAdvance: false,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-lesson-intro')));
    await tester.pumpAndSettle();

    expect(find.byType(SongKaraokeScreen), findsOneWidget);
    expect(find.byType(LessonReviewScreen), findsNothing);
    expect(mediaService.playCalls, 0);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(mediaService.playCalls, 1);
  });

  testWidgets('full song waits three seconds after intro audio completes', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _KaraokeMediaService();
    addTearDown(mediaService.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 6,
          endAge: 7,
          topic: listeningCatalogs[1].topics[4],
          lesson: _song(),
          progressStore: const _MemoryProgressStore(),
          mediaService: mediaService,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(mediaService.playToCompletionCalls, 1);
    expect(find.byType(SongKaraokeScreen), findsOneWidget);
    expect(mediaService.playCalls, 0);
    await tester.pump(const Duration(milliseconds: 2999));
    expect(mediaService.playCalls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(mediaService.playCalls, 1);
    expect(mediaService.stopCalls, 1);
  });

  testWidgets('ages three to five keep the existing song flow', (tester) async {
    await _usePhoneSurface(tester);
    final mediaService = _KaraokeMediaService();
    addTearDown(mediaService.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: LessonIntroScreen(
          language: DisplayLanguage.vietnamese,
          startAge: 3,
          endAge: 5,
          topic: listeningCatalogs.first.topics[1],
          lesson: _song(),
          progressStore: const _MemoryProgressStore(),
          mediaService: mediaService,
          autoAdvance: false,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('skip-lesson-intro')));
    await tester.pumpAndSettle();

    expect(find.byType(SongKaraokeScreen), findsNothing);
    expect(find.byType(LessonReviewScreen), findsOneWidget);
  });

  testWidgets('karaoke screen matches the selected visual direction', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final mediaService = _KaraokeMediaService(
      position: const Duration(seconds: 2),
      duration: const Duration(seconds: 36),
    );
    addTearDown(mediaService.dispose);

    await tester.pumpWidget(
      _TestApp(
        child: _screen(
          mediaService: mediaService,
          autoPlayDelay: const Duration(seconds: 3),
        ),
      ),
    );
    await _precacheBackground(tester);
    await tester.pump();

    await expectLater(
      find.byType(SongKaraokeScreen),
      matchesGoldenFile('goldens/song-karaoke-390x844.png'),
    );
  });
}

SongKaraokeScreen _screen({
  required _KaraokeMediaService mediaService,
  required Duration autoPlayDelay,
  WidgetBuilder? practiceBuilder,
}) {
  return SongKaraokeScreen(
    language: DisplayLanguage.vietnamese,
    lesson: _song(),
    mediaService: mediaService,
    topicTitle: 'Numbers, Days and Time',
    autoPlayDelay: autoPlayDelay,
    practiceBuilder:
        practiceBuilder ??
        (_) => const Scaffold(
          key: Key('song-practice-target'),
          body: Text('Practice'),
        ),
  );
}

ListeningLessonContent _song() => ListeningLessonContent(
  id: 'a067_t05_song01',
  number: 1,
  titleVi: 'Ngày vui và giờ học',
  titleEn: 'Days and Time',
  intro: 'Mình cùng nghe bài hát nhé!',
  outro: 'Con làm tốt lắm!',
  estimatedMinutes: 3,
  type: ListeningLessonType.song,
  introAudioUri: Uri.parse('asset:///assets/audio/song-intro.mp3'),
  fullAudioUri: Uri.parse('https://example.com/days-and-time.mp3'),
  sentences: const <ListeningSentenceContent>[
    ListeningSentenceContent(
      number: 1,
      english: 'Practice line.',
      vietnamese: 'Câu luyện tập.',
    ),
  ],
  karaokeLines: const <ListeningSentenceContent>[
    ListeningSentenceContent(
      number: 1,
      english: 'Monday, Tuesday — off we go!',
      vietnamese: '',
      karaokeStart: Duration.zero,
      karaokeEnd: Duration(seconds: 6),
    ),
    ListeningSentenceContent(
      number: 2,
      english: 'Wednesday, Thursday — learn and grow!',
      vietnamese: '',
      karaokeStart: Duration(seconds: 8),
      karaokeEnd: Duration(seconds: 12),
    ),
  ],
);

ListeningLessonContent _standardLesson() => ListeningLessonContent(
  id: 'standard-lesson',
  number: 1,
  titleVi: 'Bài học thường',
  titleEn: 'Standard lesson',
  intro: 'Bắt đầu nhé!',
  outro: 'Tốt lắm!',
  estimatedMinutes: 3,
  sentences: const <ListeningSentenceContent>[
    ListeningSentenceContent(
      number: 1,
      english: 'Hello.',
      vietnamese: 'Xin chào.',
    ),
  ],
);

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

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

class _KaraokeMediaService extends LessonMediaService {
  _KaraokeMediaService({
    this.position = Duration.zero,
    this.duration = const Duration(seconds: 36),
  });

  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();

  Duration position;
  Duration? duration;
  int playCalls = 0;
  int playToCompletionCalls = 0;
  int preloadCalls = 0;
  int stopCalls = 0;
  bool playing = false;
  bool _disposed = false;

  @override
  Stream<bool> get playbackPlayingStream => _playingController.stream;

  @override
  Stream<Duration> get playbackPositionStream => _positionController.stream;

  @override
  Stream<Duration?> get playbackDurationStream => _durationController.stream;

  @override
  Duration get playbackPosition => position;

  @override
  Duration? get playbackDuration => duration;

  @override
  Future<void> preload(Uri uri) async {
    preloadCalls += 1;
  }

  @override
  Future<void> unlockPlaybackForUserGesture() async {}

  @override
  Future<void> play(Uri uri) async {
    playCalls += 1;
    playing = true;
    if (!_disposed) {
      _playingController.add(true);
    }
  }

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    playToCompletionCalls += 1;
  }

  @override
  Future<void> stopPlayback() async {
    stopCalls += 1;
    playing = false;
    if (!_disposed) {
      _playingController.add(false);
    }
  }

  void emitPosition(Duration value) {
    position = value;
    if (!_disposed) {
      _positionController.add(value);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await Future.wait<void>(<Future<void>>[
      _playingController.close(),
      _positionController.close(),
      _durationController.close(),
    ]);
  }
}

class _MemoryProgressStore extends ListeningProgressStore {
  const _MemoryProgressStore();

  @override
  Future<Map<String, int>> readAll() async => const <String, int>{};

  @override
  Future<int> readLesson(String lessonId) async => 0;

  @override
  Future<int> readCurrentSentence(String lessonId) async => 0;

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

Future<void> _precacheBackground(WidgetTester tester) async {
  await tester.pump();
  final context = tester.element(find.byType(SongKaraokeScreen));
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/images/song-karaoke-sunrise.webp'),
      context,
    ),
  );
}

Future<void> _loadFonts() async {
  final regular = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final bold = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
  await Future.wait<void>(<Future<void>>[
    regular.load(),
    bold.load(),
    materialIcons.load(),
  ]);
}
