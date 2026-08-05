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
import '../core/audio/voice_prompt_service.dart';
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
import '../features/home/presentation/home_learning_shell.dart';
import '../features/listening/domain/listening_content.dart';
import '../features/onboarding/application/onboarding_progress_store.dart';
import '../l10n/display_language.dart';
import 'app_theme.dart';
import 'app_theme_mode.dart';
import 'mascot_assets.dart';
import 'startup_splash_screen.dart';

const appStartupMinimumDuration = Duration(seconds: 1);

class AiSpeakingApp extends StatefulWidget {
  const AiSpeakingApp({super.key});

  @override
  State<AiSpeakingApp> createState() => _AiSpeakingAppState();
}

class _AiSpeakingAppState extends State<AiSpeakingApp> {
  late final AppConfig _config;
  ConversationController? _controller;
  DeviceAudioCache? _deviceAudioCache;
  ConversationRepository? _repository;
  final ClientIdentity _clientIdentity = ClientIdentity();
  final AppThemeModeStore _themeModeStore = const AppThemeModeStore();
  DeviceRegistrationService? _deviceRegistrationService;
  ThemeMode _themeMode = ThemeMode.system;
  bool _themeModeChangedByUser = false;
  bool _startupComplete = false;
  bool _backgroundWorkStarted = false;

  static const _startupHoldMilliseconds = int.fromEnvironment(
    'STARTUP_SPLASH_MIN_MS',
    defaultValue: 0,
  );

  @override
  void initState() {
    super.initState();
    _config = AppConfig.fromEnvironment();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_beginStartup());
    });
  }

  Duration get _minimumSplashDuration {
    if (_startupHoldMilliseconds > 0) {
      return Duration(milliseconds: _startupHoldMilliseconds);
    }
    return appStartupMinimumDuration;
  }

  Future<void> _beginStartup() async {
    final stopwatch = Stopwatch()..start();
    final startupTasks = Future.wait<void>(<Future<void>>[
      _runStartupTask(() async {
        await _clientIdentity.getClientId();
      }),
      _runStartupTask(() async {
        await AssetListeningContentRepository().load();
      }),
      _runStartupTask(_loadThemeMode),
      _runStartupTask(_precacheHomeAssets),
    ]);
    // These tasks fill shared local caches while the logo is visible. They are
    // deliberately non-blocking and may finish after the home screen appears.
    unawaited(startupTasks);

    // The first Flutter frame is already visible. Runtime services can now
    // initialize without leaving Android or the browser on an empty surface.
    await Future<void>.delayed(const Duration(milliseconds: 32));
    if (!mounted) {
      return;
    }
    _createRuntime();

    final remaining = _minimumSplashDuration - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (!mounted) {
      return;
    }
    setState(() => _startupComplete = true);
    _startBackgroundWork();
  }

  Future<void> _runStartupTask(Future<void> Function() task) async {
    try {
      await task();
    } catch (error, stackTrace) {
      debugPrint('Startup preload was skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _precacheHomeAssets() async {
    await Future.wait<void>(<Future<void>>[
      precacheImage(const AssetImage(MascotAssets.scenery), context),
      precacheImage(const AssetImage(MascotAssets.avatar), context),
    ]);
  }

  void _createRuntime() {
    final ConversationRepository repository = _config.useDemoBackend
        ? const DemoConversationRepository()
        : NextConversationRepository(
            config: _config,
            clientIdProvider: _clientIdentity.getClientId,
          );
    final deviceAudioCache = DeviceAudioCache();
    final supportsAndroidNativeSpeech =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
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
    final controller = ConversationController(
      audioInput: PreferredAudioInput(
        preferred: _config.preferBleStreaming ? innotrikInput : null,
        fallback: phoneMicrophoneInput,
      ),
      streamingSpeechInput: supportsAndroidNativeSpeech
          ? AndroidStreamingSpeechInput()
          : null,
      hfpAudioControl: hfpAudioControl,
      playbackService: JustAudioPlaybackService(cache: deviceAudioCache),
      voicePromptService: createVoicePromptService(),
      repository: repository,
      offlineIntentRecognizer: supportsAndroidNativeSpeech
          ? MethodChannelOfflineIntentRecognizer()
          : null,
      displayLanguageStore: const DisplayLanguageStore(),
      childAge: _config.childAge,
      preferBleStreaming: _config.preferBleStreaming,
      realtimeBatchFallback: _config.realtimeBatchFallback,
      realtimeFallbackBufferBytes: _config.realtimeFallbackBufferBytes,
      // iOS browsers all use WebKit. Open their Batch session on the record
      // gesture so network upload overlaps the entire utterance; keep the
      // existing adaptive delay for other web platforms.
      adaptiveWebUploadDelay:
          kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
          ? Duration.zero
          : kIsWeb
          ? const Duration(seconds: 8)
          : Duration.zero,
      initialAsrMode: supportsAndroidNativeSpeech
          ? AsrMode.androidStreaming
          : AsrMode.batchChunks,
    );
    _repository = repository;
    _deviceAudioCache = deviceAudioCache;
    _controller = controller;
  }

  void _startBackgroundWork() {
    if (_backgroundWorkStarted) {
      return;
    }
    _backgroundWorkStarted = true;
    final repository = _repository;
    final controller = _controller;
    final deviceAudioCache = _deviceAudioCache;
    if (repository == null || controller == null || deviceAudioCache == null) {
      return;
    }
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
    if (!kIsWeb) {
      unawaited(
        _warmRecentAudioWhenIdle(repository, deviceAudioCache, controller),
      );
    }
  }

  Future<void> _loadThemeMode() async {
    final storedMode = await _themeModeStore.read();
    if (!mounted || _themeModeChangedByUser || storedMode == _themeMode) {
      return;
    }
    setState(() => _themeMode = storedMode);
  }

  void _setThemeMode(ThemeMode mode) {
    _themeModeChangedByUser = true;
    if (mode == _themeMode) {
      unawaited(
        _themeModeStore.write(mode).catchError((Object error) {
          debugPrint('Cannot persist app theme mode: $error');
        }),
      );
      return;
    }
    setState(() => _themeMode = mode);
    unawaited(
      _themeModeStore.write(mode).catchError((Object error) {
        debugPrint('Cannot persist app theme mode: $error');
      }),
    );
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
    ConversationController controller,
  ) async {
    await Future<void>.delayed(const Duration(seconds: 10));
    while (mounted && controller.isBusy) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (!mounted) {
      return;
    }
    try {
      // Backend warm-up is capped at 200 reviewed rules and runs in the
      // background. It creates each shared TTS asset at most once.
      await repository.warmAudioCache();
      // Keep the child's most useful recent audio on the device as well.
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
    _controller?.dispose();
    _deviceRegistrationService?.dispose();
    _deviceAudioCache?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final appContent = _startupComplete && controller != null
        ? KeyedSubtree(
            key: const ValueKey('app-content'),
            child: AndroidUpdateGate(
              config: _config,
              child: PwaInstallGate(
                child: HomeLearningShell(
                  controller: controller,
                  config: _config,
                  themeMode: _themeMode,
                  onThemeModeChanged: _setThemeMode,
                  onboardingStore:
                      const SharedPreferencesOnboardingProgressStore(),
                ),
              ),
            ),
          )
        : const KeyedSubtree(
            key: ValueKey('startup-content'),
            child: StartupSplashScreen(),
          );

    return MaterialApp(
      title: 'Trợ lý giao tiếp',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildDarkAppTheme(),
      themeMode: _themeMode,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: appContent,
      ),
    );
  }
}
