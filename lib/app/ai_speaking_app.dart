import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/audio/audio_playback_service.dart';
import '../core/audio/device_audio_cache.dart';
import '../core/audio/innotrik_ble_audio_input.dart';
import '../core/audio/offline_intent_recognizer.dart';
import '../core/audio/phone_microphone_input.dart';
import '../core/audio/preferred_audio_input.dart';
import '../core/audio/streaming_speech_input.dart';
import '../core/device/client_identity.dart';
import '../features/conversation/data/demo_conversation_repository.dart';
import '../features/conversation/data/next_conversation_repository.dart';
import '../features/conversation/domain/conversation_repository.dart';
import '../features/conversation/presentation/conversation_controller.dart';
import '../features/conversation/presentation/conversation_screen.dart';
import '../l10n/display_language.dart';
import 'app_theme.dart';

class AiSpeakingApp extends StatefulWidget {
  const AiSpeakingApp({super.key});

  @override
  State<AiSpeakingApp> createState() => _AiSpeakingAppState();
}

class _AiSpeakingAppState extends State<AiSpeakingApp> {
  late final AppConfig _config;
  late final ConversationController _controller;
  late final DeviceAudioCache _deviceAudioCache;
  final ClientIdentity _clientIdentity = ClientIdentity();

  @override
  void initState() {
    super.initState();
    _config = AppConfig.fromEnvironment();
    final ConversationRepository repository = _config.useDemoBackend
        ? const DemoConversationRepository()
        : NextConversationRepository(
            config: _config,
            clientIdProvider: _clientIdentity.getClientId,
          );
    _deviceAudioCache = DeviceAudioCache();
    unawaited(_warmAudioCaches(repository, _deviceAudioCache));
    final supportsAndroidNativeSpeech =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    _controller = ConversationController(
      audioInput: PreferredAudioInput(
        preferred: _config.preferBleStreaming
            ? const InnotrikBleAudioInput()
            : null,
        fallback: PhoneMicrophoneInput(),
      ),
      streamingSpeechInput: supportsAndroidNativeSpeech
          ? AndroidStreamingSpeechInput()
          : null,
      playbackService: JustAudioPlaybackService(cache: _deviceAudioCache),
      repository: repository,
      offlineIntentRecognizer: supportsAndroidNativeSpeech
          ? MethodChannelOfflineIntentRecognizer()
          : null,
      displayLanguageStore: const DisplayLanguageStore(),
      childAge: _config.childAge,
      preferBleStreaming: _config.preferBleStreaming,
      realtimeBatchFallback: _config.realtimeBatchFallback,
      realtimeFallbackBufferBytes: _config.realtimeFallbackBufferBytes,
    );
  }

  Future<void> _warmAudioCaches(
    ConversationRepository repository,
    DeviceAudioCache deviceCache,
  ) async {
    try {
      await Future.wait<void>([
        repository.warmAudioCache(),
        _warmCommonRuleAudio(repository, deviceCache),
        _warmOfflineIntentAudio(repository, deviceCache),
      ]);
    } catch (error, stackTrace) {
      debugPrint('Audio cache warm-up was skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _warmOfflineIntentAudio(
    ConversationRepository repository,
    DeviceAudioCache deviceCache,
  ) async {
    if (repository is! OfflineIntentCatalogRepository) {
      return;
    }
    final manifest = await (repository as OfflineIntentCatalogRepository)
        .fetchOfflineIntentManifest();
    await deviceCache.warm(
      manifest.items.map((item) => item.audioUri),
      limit: 50,
    );
  }

  Future<void> _warmCommonRuleAudio(
    ConversationRepository repository,
    DeviceAudioCache deviceCache,
  ) async {
    final history = await repository.fetchHistory();
    const fastSources = <String>{
      'phrase_rule',
      'keyword_rule',
      'promoted_rule',
      'semantic_cache',
      'text_cache',
    };
    final ranked = <String, ({Uri uri, int score})>{};
    for (var index = 0; index < history.length; index += 1) {
      final item = history[index];
      final uri = item.audioUri;
      if (uri == null || !fastSources.contains(item.textSource)) {
        continue;
      }
      final key = uri.toString();
      final current = ranked[key];
      ranked[key] = (
        uri: uri,
        score: (current?.score ?? 0) + 100 - index.clamp(0, 99).toInt(),
      );
    }
    final commonUris = ranked.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    await deviceCache.warm(commonUris.map((item) => item.uri));
  }

  @override
  void dispose() {
    _controller.dispose();
    _deviceAudioCache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trợ lý giao tiếp',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: ConversationScreen(controller: _controller, config: _config),
    );
  }
}
