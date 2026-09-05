import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/features/conversation/application/offline_language_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ML Kit offline Vietnamese-English translator', () {
    test('downloads both language models over Wi-Fi and translates', () async {
      final adapter = _FakeTranslationAdapter();
      final translator = MlKitOfflineVietnameseEnglishTranslator(
        adapter: adapter,
        enabled: true,
      );

      expect(await translator.modelsReady(), isFalse);
      expect(await translator.downloadModels(), isTrue);
      expect(adapter.downloads, <String>['vi:wifi', 'en:wifi']);
      expect(
        await translator.translate('Con muốn uống nước'),
        'Can I have some water?',
      );
      expect(adapter.translatedTexts, <String>['Con muốn uống nước']);

      await translator.close();
      expect(adapter.closed, isTrue);
    });

    test('does not download an already installed model', () async {
      final adapter = _FakeTranslationAdapter(installed: <String>{'vi'});
      final translator = MlKitOfflineVietnameseEnglishTranslator(
        adapter: adapter,
        enabled: true,
      );

      expect(await translator.downloadModels(), isTrue);
      expect(adapter.downloads, <String>['en:wifi']);
    });

    test('rejects translation while a language model is missing', () async {
      final translator = MlKitOfflineVietnameseEnglishTranslator(
        adapter: _FakeTranslationAdapter(),
        enabled: true,
      );

      await expectLater(
        translator.translate('Xin chào'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'OFFLINE_TRANSLATION_MODEL_UNAVAILABLE',
          ),
        ),
      );
    });
  });

  test(
    'Android Vosk recognizer sends WAV and vi-VN to native bridge',
    () async {
      const channel = MethodChannel('test_homi_offline_speech');
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return <String, dynamic>{
              'text': 'con muốn uống nước',
              'alternatives': <String>['con muốn dùng nước'],
              'confidence': 0.91,
            };
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final transcript =
          await const AndroidVoskVietnameseSpeechRecognizer(
            channel: channel,
          ).recognize(
            const AudioCapture(
              filePath: r'C:\recordings\turn.wav',
              mimeType: 'audio/wav',
              duration: Duration(seconds: 2),
              inputLabel: 'Mic điện thoại',
              isBluetoothInput: false,
              initialNoiseRms: null,
            ),
          );

      expect(received?.method, 'recognizeFile');
      expect(
        received?.arguments,
        containsPair('filePath', r'C:\recordings\turn.wav'),
      );
      expect(received?.arguments, containsPair('locale', 'vi-VN'));
      expect(transcript.text, 'con muốn uống nước');
      expect(transcript.alternatives, <String>['con muốn dùng nước']);
    },
  );

  test('iOS model manager enforces Wi-Fi-only native download', () async {
    const channel = MethodChannel('homi_offline_translation_models');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'model.status' => true,
            'model.requestDownload' => true,
            'translate' => 'Hello',
            _ => null,
          };
        });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final adapter = MlKitOfflineTranslationAdapter();
    expect(await adapter.isModelDownloaded('vi'), isTrue);
    expect(await adapter.downloadModel('en', wifiOnly: true), isTrue);
    expect(await adapter.translate('Xin chào'), 'Hello');

    final download = calls.singleWhere(
      (call) => call.method == 'model.requestDownload',
    );
    expect(download.arguments, containsPair('locale', 'en'));
    expect(download.arguments, containsPair('wifiOnly', true));
  });

  test('Apple speech assets are prepared for the requested locale', () async {
    const channel = MethodChannel('test_apple_speech_assets');
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return true;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    expect(
      await const AppleOfflineSpeechAssetService(
        channel: channel,
      ).prepareLocale('en-US'),
      isTrue,
    );
    expect(received?.method, 'speech.prepareLocale');
    expect(received?.arguments, containsPair('locale', 'en-US'));
    expect(received?.arguments, containsPair('requireOnDevice', true));
  });
}

class _FakeTranslationAdapter implements OfflineTranslationAdapter {
  _FakeTranslationAdapter({Set<String>? installed})
    : installed = installed ?? <String>{};

  final Set<String> installed;
  final List<String> downloads = <String>[];
  final List<String> translatedTexts = <String>[];
  bool closed = false;

  @override
  Future<bool> isModelDownloaded(String languageCode) async =>
      installed.contains(languageCode);

  @override
  Future<bool> downloadModel(
    String languageCode, {
    required bool wifiOnly,
  }) async {
    downloads.add('$languageCode:${wifiOnly ? 'wifi' : 'any'}');
    installed.add(languageCode);
    return true;
  }

  @override
  Future<String> translate(String text) async {
    translatedTexts.add(text);
    return 'Can I have some water?';
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
