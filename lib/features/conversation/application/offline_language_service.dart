import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../../../core/audio/audio_input.dart';

class OfflineSpeechTranscript {
  const OfflineSpeechTranscript({
    required this.text,
    this.alternatives = const <String>[],
    this.confidence,
  });

  final String text;
  final List<String> alternatives;
  final double? confidence;
}

abstract interface class OfflineVietnameseSpeechRecognizer {
  Future<OfflineSpeechTranscript> recognize(AudioCapture audio);
}

/// Reads the app-owned Vietnamese Vosk model on Android.
///
/// The controller invokes this only after the existing backend request fails,
/// so an online turn continues to use the production ASR pipeline unchanged.
class AndroidVoskVietnameseSpeechRecognizer
    implements OfflineVietnameseSpeechRecognizer {
  const AndroidVoskVietnameseSpeechRecognizer({
    MethodChannel channel = const MethodChannel('homi_offline_speech'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<OfflineSpeechTranscript> recognize(AudioCapture audio) async {
    final path = audio.filePath.trim();
    final isWav =
        audio.mimeType.toLowerCase().contains('wav') ||
        path.toLowerCase().endsWith('.wav');
    if (path.isEmpty || !isWav) {
      throw PlatformException(
        code: 'INVALID_RECORDED_AUDIO',
        message: 'Offline Vietnamese recognition requires a WAV recording.',
      );
    }

    final result = await _channel
        .invokeMapMethod<String, dynamic>('recognizeFile', <String, dynamic>{
          'filePath': path,
          'locale': 'vi-VN',
          'preferOnDevice': true,
          'requireOnDevice': true,
        });
    final transcript = '${result?['text'] ?? ''}'.trim();
    final alternatives = (result?['alternatives'] as List<dynamic>? ?? const [])
        .map((value) => '$value'.trim())
        .where((value) => value.isNotEmpty && value != transcript)
        .toList(growable: false);
    if (transcript.isEmpty) {
      throw PlatformException(
        code: 'OFFLINE_SPEECH_UNCLEAR',
        message: 'Vietnamese speech was not clear enough to recognize.',
      );
    }
    return OfflineSpeechTranscript(
      text: transcript,
      alternatives: alternatives,
      confidence: (result?['confidence'] as num?)?.toDouble(),
    );
  }
}

abstract interface class OfflineVietnameseEnglishTranslator {
  Future<bool> modelsReady();

  Future<bool> downloadModels({bool wifiOnly = true});

  Future<String> translate(String vietnameseText);

  Future<void> close();
}

abstract interface class OfflineTranslationAdapter {
  Future<bool> isModelDownloaded(String languageCode);

  Future<bool> downloadModel(String languageCode, {required bool wifiOnly});

  Future<String> translate(String text);

  Future<void> close();
}

class MlKitOfflineTranslationAdapter implements OfflineTranslationAdapter {
  MlKitOfflineTranslationAdapter()
    : _modelManager = OnDeviceTranslatorModelManager(),
      _translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.vietnamese,
        targetLanguage: TranslateLanguage.english,
      );

  static const MethodChannel _iosModelChannel = MethodChannel(
    'homi_offline_translation_models',
  );

  final OnDeviceTranslatorModelManager _modelManager;
  final OnDeviceTranslator _translator;

  bool get _usesIosWifiOnlyManager =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<bool> isModelDownloaded(String languageCode) {
    if (_usesIosWifiOnlyManager) {
      return _iosModelChannel
          .invokeMethod<bool>('model.status', <String, dynamic>{
            'locale': languageCode,
          })
          .then((value) => value ?? false);
    }
    return _modelManager.isModelDownloaded(languageCode);
  }

  @override
  Future<bool> downloadModel(String languageCode, {required bool wifiOnly}) {
    if (_usesIosWifiOnlyManager) {
      return _iosModelChannel
          .invokeMethod<bool>('model.requestDownload', <String, dynamic>{
            'locale': languageCode,
            'wifiOnly': wifiOnly,
          })
          .then((value) => value ?? false);
    }
    return _modelManager.downloadModel(languageCode, isWifiRequired: wifiOnly);
  }

  @override
  Future<String> translate(String text) {
    if (_usesIosWifiOnlyManager) {
      return _iosModelChannel
          .invokeMethod<String>('translate', <String, dynamic>{
            'locale': 'vi',
            'targetLocale': 'en',
            'text': text,
          })
          .then((value) => value ?? '');
    }
    return _translator.translateText(text);
  }

  @override
  Future<void> close() => _translator.close();
}

/// Shared Android/iOS on-device Vietnamese-to-English translation.
///
/// ML Kit downloads the Vietnamese and English language packs once, stores
/// them in the platform model store, and performs subsequent translations
/// without sending text or audio to a server.
class MlKitOfflineVietnameseEnglishTranslator
    implements OfflineVietnameseEnglishTranslator {
  MlKitOfflineVietnameseEnglishTranslator({
    OfflineTranslationAdapter? adapter,
    bool? enabled,
  }) : _adapter = adapter ?? MlKitOfflineTranslationAdapter(),
       _enabled =
           enabled ??
           (!kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.android ||
                   defaultTargetPlatform == TargetPlatform.iOS));

  static const String _vietnameseCode = 'vi';
  static const String _englishCode = 'en';

  final OfflineTranslationAdapter _adapter;
  final bool _enabled;
  Future<bool>? _downloadOperation;
  bool _closed = false;

  @override
  Future<bool> modelsReady() async {
    if (!_enabled || _closed) {
      return false;
    }
    try {
      final states = await Future.wait<bool>(<Future<bool>>[
        _adapter.isModelDownloaded(_vietnameseCode),
        _adapter.isModelDownloaded(_englishCode),
      ]);
      return states.every((ready) => ready);
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> downloadModels({bool wifiOnly = true}) {
    if (!_enabled || _closed) {
      return Future<bool>.value(false);
    }
    final active = _downloadOperation;
    if (active != null) {
      return active;
    }
    final operation = _downloadModels(wifiOnly: wifiOnly);
    _downloadOperation = operation;
    operation.then<void>(
      (_) {
        if (identical(_downloadOperation, operation)) {
          _downloadOperation = null;
        }
      },
      onError: (Object _, StackTrace stackTrace) {
        if (identical(_downloadOperation, operation)) {
          _downloadOperation = null;
        }
      },
    );
    return operation;
  }

  Future<bool> _downloadModels({required bool wifiOnly}) async {
    try {
      for (final languageCode in const <String>[
        _vietnameseCode,
        _englishCode,
      ]) {
        if (!await _adapter.isModelDownloaded(languageCode)) {
          final downloaded = await _adapter.downloadModel(
            languageCode,
            wifiOnly: wifiOnly,
          );
          if (!downloaded) {
            return false;
          }
        }
      }
      return modelsReady();
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('Offline translation model download skipped: $error');
      return false;
    }
  }

  @override
  Future<String> translate(String vietnameseText) async {
    final source = vietnameseText.trim();
    if (source.isEmpty) {
      return '';
    }
    if (!await modelsReady()) {
      throw PlatformException(
        code: 'OFFLINE_TRANSLATION_MODEL_UNAVAILABLE',
        message: 'Vietnamese and English translation models are not installed.',
      );
    }
    return (await _adapter.translate(source)).trim();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      await _adapter.close();
    } on MissingPluginException {
      // The service may be disposed by a widget test without a native host.
    }
  }
}

/// Requests the Apple Speech locale assets in advance. On iOS 26 the native
/// bridge downloads SpeechAnalyzer assets; on iOS 15.5-25 it validates that
/// SFSpeechRecognizer can perform on-device recognition for the locale.
class AppleOfflineSpeechAssetService {
  const AppleOfflineSpeechAssetService({
    MethodChannel channel = const MethodChannel('ailingo_speech'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<bool> prepareLocale(String locale) async {
    try {
      return await _channel.invokeMethod<bool>(
            'speech.prepareLocale',
            <String, dynamic>{
              'locale': locale,
              'preferOnDevice': true,
              'requireOnDevice': true,
            },
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      debugPrint('Apple offline speech locale $locale is unavailable: $error');
      return false;
    }
  }
}
