import 'dart:async';
import 'dart:convert';

import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/homi_audio_library.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/recorded_lesson_voice_prompt_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a parent platform TTS service cannot bypass recorded audio', () async {
    final media = _Media();
    final native = createVoicePromptService();
    final nativeCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('ailingo_voice_prompt'), (
          call,
        ) async {
          nativeCalls.add(call.method);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('ailingo_voice_prompt'),
            null,
          );
    });
    final service = createLessonVoicePromptService(
      mediaService: media,
      override: native,
      age: 4,
    );
    expect(service, isA<RecordedLessonVoicePromptService>());
    await speakRecordedLessonPrompt(
      service,
      'A. Apple.',
      locale: 'en-US',
      audioId: 'C35-L1-T01-B01-T01_EN',
    );
    expect(media.played.single.path, endsWith('/C35-L1-T01-B01-T01_EN.mp3'));
    expect(nativeCalls, isEmpty);
    await service.dispose();
    expect(nativeCalls, isEmpty, reason: 'The parent owns native TTS.');
  });

  test('custom voice output remains an explicit override', () {
    final custom = _Voice();
    expect(
      createLessonVoicePromptService(mediaService: _Media(), override: custom),
      same(custom),
    );
  });

  test('an index read failure can recover on the next prompt', () async {
    final bundle = _RecoveringBundle();
    final library = HomiAudioLibrary(bundle: bundle);
    final media = _Media();
    final fallback = _Voice();
    final service = RecordedLessonVoicePromptService(
      mediaService: media,
      fallback: fallback,
      library: library,
    );
    await service.speakRecordedAndWait(
      'Bắt đầu nhé.',
      audioId: 'DETAIL_TRANSITION',
    );
    expect(fallback.spoken, ['vi-VN|Bắt đầu nhé.']);
    expect(media.played, isEmpty);
    await service.speakRecordedAndWait(
      'Bắt đầu nhé.',
      audioId: 'DETAIL_TRANSITION',
    );
    expect(media.played.single.path, endsWith('/DETAIL_TRANSITION.mp3'));
    expect(fallback.spoken, hasLength(1));
    expect(bundle.reads, 2);
  });

  test('all imported clips are declared in the Flutter bundle', () async {
    final index =
        jsonDecode(await rootBundle.loadString(HomiAudioLibrary.assetPath))
            as Map<String, dynamic>;
    final clips = (index['clips'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final assets = (await AssetManifest.loadFromAssetBundle(
      rootBundle,
    )).listAssets().toSet();
    expect(clips, hasLength(4916));
    expect(clips.map((c) => c['id']).toSet(), hasLength(clips.length));
    for (final clip in clips) {
      expect(assets, contains(clip['asset']), reason: clip['id'] as String);
    }
    final catalog =
        jsonDecode(
              await rootBundle.loadString('assets/data/listening_lessons.json'),
            )
            as Map<String, dynamic>;
    final targets = (catalog['groups'] as List<dynamic>)
        .expand((g) => g['topics'] as List<dynamic>)
        .expand((t) => t['lessons'] as List<dynamic>)
        .expand((l) => l['sentences'] as List<dynamic>)
        .toList();
    expect(targets.where((t) => t['audioUrl'] != null), hasLength(600));
    expect(
      targets.where((t) => t['vietnameseAudioUrl'] != null),
      hasLength(600),
    );
    expect(
      targets.where((t) => t['audioUrl'] == null).single['id'],
      'C1112-L2-T04-B01-T03',
    );
    for (final kind in [
      'system',
      'feedback',
      'core',
      'hook',
      'challenge',
      'mission',
      'sfx',
    ]) {
      final sample = clips.firstWhere((c) => c['kind'] == kind);
      final bytes = await rootBundle.load(sample['asset'] as String);
      expect(bytes.lengthInBytes, greaterThan(100), reason: kind);
    }
  });

  test('production IDs and dynamic text select their recorded clips', () async {
    final library = HomiAudioLibrary();
    expect(
      (await library.uriForAudioCode('CORE_SPEAK_01'))?.path,
      endsWith('/system/CORE_SPEAK_01.mp3'),
    );
    expect(
      (await library.resolve(text: 'Mình học tiếp bài One to Ten nhé.'))?.id,
      'RESUME_CORE_LESSON_TABLE_004',
    );
    expect(
      (await library.resolve(text: 'Bắt đầu Level 2.'))?.id,
      'LEVEL_INTRO_2',
    );
    expect(
      (await library.resolve(
        text: 'Quả táo: Apple hay Ball?',
        audioId: 'C35-L1-T01-B01-Q01_PROMPT',
      ))?.id,
      'C35-L1-T01-B01-Q01_PROMPT',
    );
    expect(
      await library.resolve(
        text: 'A different question',
        audioId: 'C35-L1-T01-B01-Q01_PROMPT',
      ),
      isNull,
    );
    // Do not leak a contextual SFX into a role-play scenario with the same text.
    expect(await library.resolve(text: 'Nghe thật kỹ nhé.'), isNull);
  });

  test(
    'feedback rotates within the correct age and includes English locale',
    () async {
      final library = HomiAudioLibrary();
      final ids = <String>[];
      for (var i = 0; i < 4; i++) {
        ids.add(
          (await library.resolve(
            text: 'Đúng rồi!',
            feedbackState: 'CORRECT',
            age: 4,
          ))!.id,
        );
      }
      expect(ids.take(3).toSet(), hasLength(3));
      expect(ids[3], ids[0]);
      final older = await library.resolve(
        text: 'Exactly.',
        feedbackState: 'CORRECT',
        age: 14,
      );
      expect(older!.age, '13-15');
      expect(older.locale, 'en-US');
    },
  );

  test('intro plays system, complete hook, and transition in order', () async {
    final media = _Media();
    final fallback = _Voice();
    final service = RecordedLessonVoicePromptService(
      mediaService: media,
      fallback: fallback,
    );
    await service.speakAndWait(
      'Bài này là Count With Me. Nghe thật kỹ nhé. Bắt đầu nhé.',
    );
    expect(media.played.map((u) => u.path.split('/').last), [
      'NEXT_LESSON_INTRO_LESSON_TABLE_005.mp3',
      'C35-L1-T02-B02_ENTRY.mp3',
      'DETAIL_TRANSITION.mp3',
    ]);
    expect(fallback.spoken, isEmpty);
    expect(media.played.where((u) => u.path.contains('/sfx/')), isEmpty);
  });

  test('resume plays only the resume cue, without the hook or intro', () async {
    final media = _Media();
    final service = RecordedLessonVoicePromptService(
      mediaService: media,
      fallback: _Voice(),
    );
    await service.speakAndWait('Mình học tiếp bài Count With Me nhé.');
    expect(
      media.played.single.path,
      endsWith('RESUME_CORE_LESSON_TABLE_005.mp3'),
    );
  });

  test(
    'missing and failed clips fall back to speech on the selected route',
    () async {
      final media = _Media()..failPlayback = true;
      final fallback = _Voice();
      final service = RecordedLessonVoicePromptService(
        mediaService: media,
        fallback: fallback,
      );
      await service.speakRecordedAndWait(
        'A. Apple.',
        locale: 'en-US',
        audioId: 'C35-L1-T01-B01-T01_EN',
      );
      await service.speakRecordedAndWait(
        'Taxi.',
        locale: 'en-US',
        audioId: 'C1112-L2-T04-B01-T03_EN',
      );
      expect(fallback.spoken, ['en-US|A. Apple.', 'en-US|Taxi.']);
      expect(media.selectedPrepares, 2);
      expect(media.played, hasLength(1));
    },
  );

  test('stop during a pending index load cannot start audio later', () async {
    final bundle = _DelayedBundle();
    final media = _Media();
    final fallback = _Voice();
    final service = RecordedLessonVoicePromptService(
      mediaService: media,
      fallback: fallback,
      library: HomiAudioLibrary(bundle: bundle),
    );
    final operation = service.speakAndWait('Bắt đầu nhé.');
    await service.stop();
    bundle.ready.complete(jsonEncode({'clips': [], 'sequences': []}));
    await operation;
    expect(media.played, isEmpty);
    expect(fallback.spoken, isEmpty);
  });

  test('stop midway through intro prevents later segments and TTS', () async {
    final media = _Media()..holdPlayback = true;
    final fallback = _Voice();
    final service = RecordedLessonVoicePromptService(
      mediaService: media,
      fallback: fallback,
    );
    final operation = service.speakAndWait(
      'Bài này là Count With Me. Nghe thật kỹ nhé. Bắt đầu nhé.',
    );
    await media.started.future;
    await service.stop();
    await operation;
    expect(media.played, hasLength(1));
    expect(fallback.spoken, isEmpty);
  });

  test('stop releases a stalled native TTS waiter immediately', () async {
    final fallback = _StalledVoice();
    final service = RecordedLessonVoicePromptService(
      mediaService: _Media(),
      fallback: fallback,
    );
    final operation = service.speakAndWait('Unrecorded prompt');
    await fallback.started.future;
    await service.stop();
    await operation.timeout(const Duration(seconds: 1));
  });

  test(
    'an idle prompt service does not stop a song on the shared media player',
    () async {
      final media = _Media();
      final service = RecordedLessonVoicePromptService(
        mediaService: media,
        fallback: _Voice(),
      );
      await service.speakAndWait('Bắt đầu nhé.');
      await service.stop();
      expect(media.stops, 0);
    },
  );

  test(
    'a rebinding owns its cancellation but not the borrowed fallback',
    () async {
      final media = _Media(), fallback = _Voice();
      final original = RecordedLessonVoicePromptService(
        mediaService: media,
        fallback: fallback,
      );
      final rebound = createLessonVoicePromptService(
        mediaService: media,
        override: original,
        age: 8,
      );
      expect(identical(original, rebound), isFalse);
      await rebound.dispose();
      expect(fallback.disposals, 0);
    },
  );
}

class _Media extends LessonMediaService {
  final played = <Uri>[];
  final started = Completer<void>();
  Completer<void>? _completion;
  bool failPlayback = false;
  bool holdPlayback = false;
  int selectedPrepares = 0;
  int stops = 0;

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
  }) async {
    played.add(uri);
    if (!started.isCompleted) started.complete();
    if (failPlayback) throw StateError('Unavailable clip');
    if (holdPlayback) await (_completion = Completer<void>()).future;
  }

  @override
  Future<void> prepareSelectedLessonOutput() async {
    selectedPrepares++;
  }

  @override
  Future<void> stopPlayback() async {
    stops++;
    final completion = _completion;
    if (completion != null && !completion.isCompleted) completion.complete();
  }
}

class _Voice
    implements VoicePromptService, SelectedMediaOutputVoicePromptService {
  final spoken = <String>[];
  int disposals = 0;
  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spoken.add('$locale|$text');
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);
  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) => speak(text, locale: locale);
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _DelayedBundle extends CachingAssetBundle {
  final ready = Completer<String>();
  @override
  Future<String> loadString(String key, {bool cache = true}) => ready.future;
  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

class _StalledVoice extends _Voice {
  final started = Completer<void>();
  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) {
    started.complete();
    return Completer<void>().future;
  }
}

class _RecoveringBundle extends CachingAssetBundle {
  int reads = 0;

  @override
  Future<ByteData> load(String key) async {
    if (++reads == 1) throw StateError('Asset sync is not ready');
    return ByteData.sublistView(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'clips': [
              {
                'id': 'DETAIL_TRANSITION',
                'asset': 'assets/audio/homi_v4/system/DETAIL_TRANSITION.mp3',
                'kind': 'system',
                'text': 'Bắt đầu nhé.',
                'locale': 'vi-VN',
              },
            ],
            'sequences': [],
          }),
        ),
      ),
    );
  }
}
