import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/audio/audio_playback_service.dart';
import '../core/audio/browser_hfp_audio_control.dart';
import '../core/audio/device_audio_cache.dart';
import '../core/audio/hfp_audio_control.dart';
import '../core/audio/innotrik_ble_audio_input.dart';
import '../core/audio/offline_intent_recognizer.dart';
import '../core/audio/phone_microphone_input.dart';
import '../core/audio/preferred_audio_input.dart';
import '../core/audio/streaming_speech_input.dart';
import '../core/device/android_device_hardware.dart';
import '../core/device/client_identity.dart';
import '../core/device/device_registration_service.dart';
import '../core/pwa/pwa_install_gate.dart';
import '../core/update/android_update_gate.dart';
import '../features/conversation/data/demo_conversation_repository.dart';
import '../features/conversation/data/next_conversation_repository.dart';
import '../features/conversation/domain/conversation_models.dart';
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
  DeviceRegistrationService? _deviceRegistrationService;

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
    final supportsAndroidNativeSpeech =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (supportsAndroidNativeSpeech && !_config.useDemoBackend) {
      final registrationService = DeviceRegistrationService(
        config: _config,
        clientIdProvider: _clientIdentity.getClientId,
        hardwareProvider: const AndroidDeviceHardwareReader().read,
      );
      _deviceRegistrationService = registrationService;
      unawaited(_registerDevice(registrationService));
    }
    final innotrikInput = InnotrikBleAudioInput(
      enabled: supportsAndroidNativeSpeech && _config.enableInnotrikBle,
    );
    final phoneMicrophoneInput = PhoneMicrophoneInput();
    final HfpAudioControl hfpAudioControl = kIsWeb
        ? BrowserHfpAudioControl(
            enabled: _config.enableHfpAudio,
            audioInput: phoneMicrophoneInput,
          )
        : MethodChannelHfpAudioControl(
            enabled: supportsAndroidNativeSpeech && _config.enableHfpAudio,
          );
    _controller = ConversationController(
      audioInput: PreferredAudioInput(
        preferred: _config.preferBleStreaming ? innotrikInput : null,
        fallback: phoneMicrophoneInput,
      ),
      streamingSpeechInput: supportsAndroidNativeSpeech
          ? AndroidStreamingSpeechInput()
          : null,
      hfpAudioControl: hfpAudioControl,
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
      initialAsrMode: supportsAndroidNativeSpeech
          ? AsrMode.androidStreaming
          : AsrMode.batchChunks,
    );
    if (!kIsWeb) {
      unawaited(_warmRecentAudioWhenIdle(repository, _deviceAudioCache));
    }
  }

  Future<void> _registerDevice(
    DeviceRegistrationService registrationService,
  ) async {
    try {
      await registrationService.register();
      debugPrint('Android device hardware registered.');
    } catch (error, stackTrace) {
      debugPrint('Android device registration was skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _warmRecentAudioWhenIdle(
    ConversationRepository repository,
    DeviceAudioCache deviceCache,
  ) async {
    await Future<void>.delayed(const Duration(seconds: 10));
    while (mounted && _controller.isBusy) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (!mounted) {
      return;
    }
    try {
      // Warm only audio that this child actually used. Global warmup and the
      // full exact-rule catalog compete with the first recording and become
      // increasingly expensive as the rule set grows.
      await _warmCommonRuleAudio(repository, deviceCache);
    } catch (error, stackTrace) {
      debugPrint('Audio cache warm-up was skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
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
    await deviceCache.warm(commonUris.map((item) => item.uri), limit: 12);
  }

  @override
  void dispose() {
    _controller.dispose();
    _deviceRegistrationService?.dispose();
    _deviceAudioCache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trợ lý giao tiếp',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: AndroidUpdateGate(
        config: _config,
        child: PwaInstallGate(
          child: ConversationScreen(controller: _controller, config: _config),
        ),
      ),
    );
  }
}
