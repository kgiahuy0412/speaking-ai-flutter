import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/bundled_voice_prompt_library.dart';
import 'package:ai_speaking_flutter_app/core/audio/cloudinary_audio_library.dart';
import 'package:ai_speaking_flutter_app/core/audio/device_audio_cache.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service_native.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_guide_audio_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _url = 'https://res.cloudinary.com/test/video/upload/v1/hello.mp3';
const _asset = 'assets/audio/A-3-5/GUIDE_RECORD/hello.mp3';

class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final clip = <String, Object>{
      'asset': _asset,
      'id': 'HELLO',
      'kind': 'system',
      'text': 'Xin chào.',
      'locale': 'vi-VN',
      'audioUrl': _url,
      'url': _url,
    };
    final value = <String, Object>{
      'clips': [clip],
    };
    return ByteData.sublistView(utf8.encode(jsonEncode(value)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('guide discovery works without any bundled MP3 files', () async {
    final bundle = _Bundle();
    final manifest = CloudinaryAudioLibrary(bundle: bundle);
    expect(await manifest.uriForAsset(_asset), Uri.parse(_url));
    expect(await manifest.uriForAsset('missing.mp3'), isNull);
    final guides = LessonGuideAudioLibrary(bundle: bundle);
    expect(
      await guides.randomUri(LessonGuideCue.record, startAge: 3, endAge: 5),
      Uri.parse(_url),
    );
  });

  test(
    'native prompt awaits download and playback, preserving route flags',
    () async {
      const channel = MethodChannel('test_cloud_prompt_wait');
      final download = Completer<Uri?>();
      final playback = Completer<void>();
      final requested = Completer<Uri>();
      final started = Completer<MethodCall>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        started.complete(call);
        await playback.future;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final service = MethodChannelVoicePromptService(
        channel: channel,
        library: BundledVoicePromptLibrary(bundle: _Bundle()),
        audioFileResolver: (uri) {
          requested.complete(uri);
          return download.future;
        },
      );
      var complete = false;
      final speaking = service
          .speakAndWaitOnSelectedMediaOutput('Xin chào.')
          .then((_) => complete = true);
      expect(await requested.future, Uri.parse(_url));
      expect(started.isCompleted, isFalse);
      final file = Uri.file('${Directory.systemTemp.path}/cloud-prompt.mp3');
      download.complete(file);
      final call = await started.future;
      expect(call.arguments['filePath'], file.toFilePath());
      expect(call.arguments['assetPath'], isNull);
      expect(call.arguments['forceMediaPlayback'], isTrue);
      expect(complete, isFalse);
      playback.complete();
      await speaking;
      expect(complete, isTrue);
    },
  );

  test(
    'stop invalidates an in-flight remote download across service instances',
    () async {
      const channel = MethodChannel('test_cloud_prompt_stop');
      final download = Completer<Uri?>();
      final requested = Completer<void>();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final service = MethodChannelVoicePromptService(
        channel: channel,
        library: BundledVoicePromptLibrary(bundle: _Bundle()),
        audioFileResolver: (_) {
          requested.complete();
          return download.future;
        },
      );
      final pending = service.speakAndWait('Xin chào.');
      await requested.future;
      await const MethodChannelVoicePromptService(channel: channel).stop();
      download.complete(Uri.file('${Directory.systemTemp.path}/cancelled.mp3'));
      await pending;
      expect(calls, ['stop']);
    },
  );

  test(
    'unavailable remote audio uses device speech without a nonexistent asset',
    () async {
      const channel = MethodChannel('test_cloud_prompt_offline');
      MethodCall? received;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        received = call;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final service = MethodChannelVoicePromptService(
        channel: channel,
        library: BundledVoicePromptLibrary(bundle: _Bundle()),
        audioFileResolver: (_) async => null,
      );
      await service.speakAndWaitOnPhoneSpeaker('Xin chào.');
      expect(received?.arguments['text'], 'Xin chào.');
      expect(received?.arguments['filePath'], isNull);
      expect(received?.arguments['assetPath'], isNull);
      expect(received?.arguments['forcePhoneSpeaker'], isTrue);
    },
  );

  test(
    'downloaded Cloudinary recording survives cache recreation without network',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'homi-cloudinary-test-',
      );
      final first = DeviceAudioCache(
        client: MockClient((_) async => http.Response.bytes([1, 2, 3, 4], 200)),
        directoryProvider: () async => directory,
      );
      final local = await first.cache(Uri.parse(_url));
      expect(local?.scheme, 'file');
      first.dispose();
      var networkCalls = 0;
      final offline = DeviceAudioCache(
        client: MockClient((_) async {
          networkCalls++;
          throw const SocketException('offline');
        }),
        directoryProvider: () async => directory,
      );
      expect(await offline.cache(Uri.parse(_url)), local);
      expect(networkCalls, 0);
      expect(await File.fromUri(local!).readAsBytes(), [1, 2, 3, 4]);
      offline.dispose();
      await directory.delete(recursive: true);
    },
  );
}
