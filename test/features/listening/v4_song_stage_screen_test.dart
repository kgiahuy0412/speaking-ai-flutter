import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/v4_song_stage_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('announces SONG_START_CUE, shows the title, and can skip', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final prompts = _FakeVoicePromptService();
    final media = _FakeLessonMediaService();
    V4SongStageAction? result;

    await tester.pumpWidget(
      _host(
        songTitle: 'Count with Me',
        mediaService: media,
        voicePromptService: prompts,
        onResult: (value) => result = value,
      ),
    );
    await tester.tap(find.byKey(const Key('open-v4-song-stage')));
    await tester.pumpAndSettle();

    expect(v4SongStartCueAudioId, 'SONG_START_CUE');
    expect(v4SongPrealertAudioId, 'SONG_PREALERT');
    expect(
      v4SongPrealert('Count with Me'),
      'Tiếp theo là hai câu thử thách. Xong rồi mình nghe bài hát Count with Me nhé.',
    );
    expect(prompts.spoken, <String>['Bây giờ cùng nghe Count with Me nhé.']);
    expect(find.byKey(const Key('v4-song-stage-screen')), findsOneWidget);
    expect(find.byKey(const Key('v4-song-stage-title')), findsOneWidget);
    expect(find.text('Count with Me'), findsOneWidget);
    expect(find.byKey(const Key('v4-song-stage-play')), findsNothing);

    await tester.tap(find.byKey(const Key('v4-song-stage-skip')));
    await tester.pumpAndSettle();

    expect(result, V4SongStageAction.skipped);
    expect(media.stopPlaybackCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('plays only an explicit future V4 song URI and can continue', (
    tester,
  ) async {
    await _usePhoneSurface(tester);
    final prompts = _FakeVoicePromptService();
    final media = _FakeLessonMediaService();
    const source = 'https://audio.example/v4/count-with-me.mp3';
    final songUri = Uri.parse(source);
    V4SongStageAction? result;

    await tester.pumpWidget(
      _host(
        songTitle: 'Count with Me',
        mediaService: media,
        voicePromptService: prompts,
        songAudioId: 'C35-L1-T02-B02_SONG',
        songAudioUri: songUri,
        onResult: (value) => result = value,
      ),
    );
    await tester.tap(find.byKey(const Key('open-v4-song-stage')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('v4-song-stage-play')));
    await tester.pumpAndSettle();

    expect(media.playedToCompletion, <Uri>[songUri]);
    expect(find.text('Bạn đã nghe xong bài hát rồi.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('v4-song-stage-continue')));
    await tester.pumpAndSettle();

    expect(result, V4SongStageAction.continued);
  });
}

Widget _host({
  required String songTitle,
  required LessonMediaService mediaService,
  required VoicePromptService voicePromptService,
  required ValueChanged<V4SongStageAction?> onResult,
  String? songAudioId,
  Uri? songAudioUri,
}) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const Key('open-v4-song-stage'),
            onPressed: () async {
              final result = await Navigator.of(context)
                  .push<V4SongStageAction>(
                    MaterialPageRoute<V4SongStageAction>(
                      builder: (_) => V4SongStageScreen(
                        language: DisplayLanguage.vietnamese,
                        songTitle: songTitle,
                        songAudioId: songAudioId,
                        songAudioUri: songAudioUri,
                        mediaService: mediaService,
                        voicePromptService: voicePromptService,
                      ),
                    ),
                  );
              onResult(result);
            },
            child: const Text('Mở bài hát'),
          ),
        ),
      ),
    ),
  );
}

class _FakeVoicePromptService implements VoicePromptService {
  final List<String> spoken = <String>[];

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spoken.add(text);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);

  @override
  Future<void> stop() async {}
}

class _FakeLessonMediaService extends LessonMediaService {
  final List<Uri> playedToCompletion = <Uri>[];
  int stopPlaybackCalls = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
  }) async {
    playedToCompletion.add(uri);
  }

  @override
  Future<void> stopPlayback() async {
    stopPlaybackCalls += 1;
  }
}

Future<void> _usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}
