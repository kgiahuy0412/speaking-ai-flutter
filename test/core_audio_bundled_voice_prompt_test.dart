import 'dart:async';
import 'dart:convert';

import 'package:ai_speaking_flutter_app/core/audio/bundled_voice_prompt_library.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service_native.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/recorded_lesson_voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all generated speech is bundled, unique and uses the requested voice',
    () async {
      final index =
          jsonDecode(
                await rootBundle.loadString(
                  BundledVoicePromptLibrary.assetPath,
                ),
              )
              as Map<String, dynamic>;
      expect(index['voiceId'], 'nbv4fVbfyLxvuHzyIeDo');
      expect(index['languageCode'], 'vi');
      final clips = (index['clips'] as List).cast<Map<String, dynamic>>();
      expect(clips.length, greaterThan(600));
      expect(clips.map((c) => c['text']).toSet().length, clips.length);
      final assets = (await AssetManifest.loadFromAssetBundle(
        rootBundle,
      )).listAssets().toSet();
      for (final clip in clips) {
        expect(clip['locale'], 'vi-VN');
        expect(assets, contains(clip['asset']), reason: clip['text'] as String);
        expect(
          (await rootBundle.load(clip['asset'] as String)).lengthInBytes,
          greaterThan(1000),
        );
      }
    },
  );

  test(
    'exact Vietnamese lookup reuses curriculum and excludes other languages/SFX',
    () async {
      final library = BundledVoicePromptLibrary();
      expect(
        await library.assetFor(MainVoiceAssistantFlow.openingPrompt),
        'assets/audio/elevenlabs_vi/main_opening.mp3',
      );
      expect(
        await library.assetFor('  Bắt đầu   nhé. '),
        'assets/audio/homi_v4/system/DETAIL_TRANSITION.mp3',
      );
      expect(await library.assetFor('Bắt đầu nhé.', locale: 'en-US'), isNull);
      expect(await library.assetFor('Câu mới do phụ huynh nhập'), isNull);
      final contextualText = await library.assetFor('Nghe thật kỹ nhé.');
      if (contextualText != null) {
        expect(contextualText, startsWith('assets/audio/elevenlabs_vi/'));
      }
    },
  );

  test(
    'native speech keeps completion and H20/phone route flags with local MP3',
    () async {
      const channel = MethodChannel('test_recorded_completion');
      final finished = Completer<void>();
      final started = Completer<MethodCall>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        started.complete(call);
        await finished.future;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const service = MethodChannelVoicePromptService(channel: channel);
      var completed = false;
      final speech = service
          .speakAndWaitOnSelectedMediaOutput(
            MainVoiceAssistantFlow.openingPrompt,
          )
          .then((_) => completed = true);
      final call = await started.future;
      expect(call.method, 'speakAndWait');
      expect(
        call.arguments['assetPath'],
        'assets/audio/elevenlabs_vi/main_opening.mp3',
      );
      expect(call.arguments['forceMediaPlayback'], isTrue);
      expect(
        completed,
        isFalse,
        reason: 'Microphone must not start while MP3 plays.',
      );
      finished.complete();
      await speech;
      expect(completed, isTrue);
    },
  );

  test(
    'stop in another service instance cancels a pending asset lookup',
    () async {
      const channel = MethodChannel('test_recorded_cancel');
      final bundle = _DelayedBundle();
      final service = MethodChannelVoicePromptService(
        channel: channel,
        library: BundledVoicePromptLibrary(bundle: bundle),
      );
      const other = MethodChannelVoicePromptService(channel: channel);
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final pending = service.speakAndWait('Xin chào.');
      await bundle.started.future;
      await other.stop();
      bundle.ready.complete('{"clips":[]}');
      await pending;
      expect(calls, ['stop']);
    },
  );

  test(
    'a missing pack falls back to native TTS without hiding the prompt',
    () async {
      const channel = MethodChannel('test_recorded_missing');
      final service = MethodChannelVoicePromptService(
        channel: channel,
        library: BundledVoicePromptLibrary(bundle: _MissingBundle()),
      );
      MethodCall? received;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await service.speakAndWait('Xin chào.');
      expect(received?.method, 'speakAndWait');
      expect(received?.arguments['text'], 'Xin chào.');
      expect((received?.arguments as Map).containsKey('assetPath'), isFalse);
    },
  );

  test(
    'MAIN recorded service reaches new audio through the existing native fallback',
    () async {
      const channel = MethodChannel('test_recorded_main_flow');
      MethodCall? received;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final service = RecordedLessonVoicePromptService(
        mediaService: _Media(),
        fallback: const MethodChannelVoicePromptService(channel: channel),
      );
      await service.speakAndWait(MainVoiceAssistantFlow.openingPrompt);
      expect(
        received?.arguments['assetPath'],
        'assets/audio/elevenlabs_vi/main_opening.mp3',
      );
      expect(received?.arguments['forceMediaPlayback'], isTrue);
      await service.dispose();
    },
  );
}

class _MissingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => throw StateError('Missing test pack');
}

class _DelayedBundle extends CachingAssetBundle {
  final started = Completer<void>();
  final ready = Completer<String>();
  @override
  Future<String> loadString(String key, {bool cache = true}) {
    if (!started.isCompleted) started.complete();
    return ready.future;
  }

  @override
  Future<ByteData> load(String key) => throw UnimplementedError();
}

class _Media implements LessonMediaService {
  @override
  Future<void> prepareSelectedLessonOutput() async {}
  @override
  Future<void> stopPlayback() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
