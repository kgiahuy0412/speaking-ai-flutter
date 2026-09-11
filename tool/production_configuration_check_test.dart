// Run explicitly with the same --dart-define-from-file as the release build.
import 'package:ai_speaking_flutter_app/config/app_config.dart';
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
    'release bundles native notices and the new recorded audio pack',
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
        (asset) =>
            asset.startsWith('assets/audio/homi_v4/') && asset.endsWith('.mp3'),
      );
      expect(recordedAssets.length, 4916);
    },
  );
}
