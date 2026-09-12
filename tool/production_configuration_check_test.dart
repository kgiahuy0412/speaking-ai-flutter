// Run explicitly with the same --dart-define-from-file as the release build.
import 'dart:convert';

import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/audio/cloudinary_audio_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('release uses production services and complete privacy disclosures', () {
    const configuredBackend = String.fromEnvironment('BACKEND_BASE_URL');
    expect(configuredBackend, isNotEmpty);
    final expectedBackend = Uri.parse(configuredBackend);
    expect(expectedBackend.scheme, 'https');
    expect(expectedBackend.host, isNot(anyOf('localhost', 'example.com')));
    final config = AppConfig.fromEnvironment();
    expect(config.useDemoBackend, isFalse);
    expect(config.backendBaseUri, expectedBackend);
    expect(config.privacyReleaseConfigurationComplete, isTrue);
    for (final uri in <Uri?>[
      config.privacyPolicyUri,
      config.termsUri,
      config.supportUri,
    ]) {
      expect(uri?.scheme, 'https');
      expect(uri?.host, isNot('example.com'));
    }
    for (final provider in <String>[
      'Railway',
      'Cloudflare',
      'Cloudinary',
      'Google ML Kit',
    ]) {
      expect(config.disclosedAiSubprocessors, contains(provider));
    }
  });

  test(
    'release bundles native notices and Cloudinary links without recordings',
    () async {
      expect(
        await rootBundle.loadString('THIRD_PARTY_NOTICES.md'),
        allOf(contains('Vosk API'), contains('Java Native Access')),
      );
      expect(
        await rootBundle.loadString('assets/legal/APACHE-2.0.txt'),
        contains('END OF TERMS AND CONDITIONS'),
      );
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final recordedAssets = manifest.listAssets().where(
        (asset) => RegExp(
          r'\.(mp3|wav|m4a|aac|ogg|flac)$',
          caseSensitive: false,
        ).hasMatch(asset),
      );
      expect(recordedAssets, isEmpty);
      expect(manifest.listAssets(), contains(CloudinaryAudioLibrary.assetPath));

      final library = CloudinaryAudioLibrary();
      final identifiers = await library.assetIdentifiers();
      expect(identifiers.length, 5833);
      for (final asset in identifiers) {
        final uri = await library.uriForAsset(asset);
        expect(uri?.scheme, 'https');
        expect(uri?.host, 'res.cloudinary.com');
        expect(uri?.path, startsWith('/ysc2jlrt/video/upload/'));
      }
      for (final indexPath in <String>[
        'assets/data/homi_audio_index.json',
        'assets/data/elevenlabs_prompt_index.json',
      ]) {
        final index =
            jsonDecode(await rootBundle.loadString(indexPath))
                as Map<String, dynamic>;
        for (final raw in index['clips'] as List<dynamic>) {
          final clip = raw as Map<String, dynamic>;
          expect(clip['audioUrl'], isNotEmpty);
          expect(
            (await library.uriForAsset(clip['asset'] as String)).toString(),
            clip['audioUrl'],
          );
        }
      }
    },
  );
}
