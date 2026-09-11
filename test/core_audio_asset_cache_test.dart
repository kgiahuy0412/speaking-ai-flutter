import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late Directory fixtureRoot;

  setUp(() async {
    fixtureRoot = await Directory(
      '${Directory.current.path}/.codex-tmp',
    ).create(recursive: true);
    fixture = await fixtureRoot.createTemp('asset-cache-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              call.method == 'getTemporaryDirectory' ? fixture.path : null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    final root = await fixtureRoot.resolveSymbolicLinks();
    final target = await fixture.resolveSymbolicLinks();
    if (!target.startsWith('$root${Platform.pathSeparator}asset-cache-')) {
      throw StateError('Unexpected test cache directory');
    }
    await Directory(target).delete(recursive: true);
  });

  test(
    'a fresh install without just_audio_cache can load bundled audio',
    () async {
      // Reproduce the plugin failure observed on the Android emulator.
      await expectLater(
        AudioPlayer.clearAssetCache(),
        throwsA(isA<FileSystemException>()),
      );
      await refreshBundledAudioAssetCache();
      // No failed cache future is propagated to the caller's setAsset step.
      final extracted = File(
        '${fixture.path}/just_audio_cache/assets/sample.mp3',
      );
      await extracted.parent.create(recursive: true);
      await extracted.writeAsBytes([0x49, 0x44, 0x33]);
      expect(await extracted.exists(), isTrue);
    },
  );

  test(
    'existing extracted assets are cleared and recordings stay intact',
    () async {
      final extracted = File('${fixture.path}/just_audio_cache/assets/old.mp3');
      await extracted.parent.create(recursive: true);
      await extracted.writeAsBytes([1, 2, 3]);
      final recording = File('${fixture.path}/recording.wav');
      await recording.writeAsBytes([4, 5, 6]);
      await refreshBundledAudioAssetCache();
      expect(await extracted.exists(), isFalse);
      expect(await recording.readAsBytes(), [4, 5, 6]);
    },
  );
}
