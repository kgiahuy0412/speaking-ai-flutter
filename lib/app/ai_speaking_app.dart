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
import '../core/device/active_learning_module.dart';
import '../core/device/aiv0_ble_control.dart';
import '../core/device/client_identity.dart';
import '../core/device/device_registration_service.dart';
import '../core/device/main_button_coordinator.dart';
import '../core/pwa/pwa_install_gate.dart';
import '../core/update/android_update_gate.dart';
import '../features/conversation/data/demo_conversation_repository.dart';
import '../features/conversation/data/next_conversation_repository.dart';
import '../features/conversation/domain/conversation_models.dart';
import '../features/conversation/domain/conversation_repository.dart';
import '../features/conversation/presentation/conversation_controller.dart';
import '../features/home/presentation/home_learning_shell.dart';
import '../features/listening/domain/listening_catalog.dart';
import '../features/listening/domain/listening_content.dart';
import '../features/voice_navigation/application/main_speaking_session_controller.dart';
import '../features/voice_navigation/application/main_speaking_command_resolver.dart';
import '../features/voice_navigation/application/voice_navigation_controller.dart';
import '../features/voice_navigation/data/web_batch_streaming_speech_input.dart';
import '../features/voice_navigation/presentation/main_voice_assistant_button.dart';
import '../l10n/display_language.dart';
import 'app_theme.dart';
import 'app_theme_mode.dart';
import 'mascot_assets.dart';

class AiSpeakingApp extends StatefulWidget {
  const AiSpeakingApp({super.key});

  @override
  State<AiSpeakingApp> createState() => _AiSpeakingAppState();
}

class _AiSpeakingAppState extends State<AiSpeakingApp> {
  late final AppConfig _config;
  ConversationController? _controller;
  VoiceNavigationController? _voiceNavigationController;
  AndroidStreamingSpeechInput? _androidStreamingSpeechInput;
  DeviceAudioCache? _deviceAudioCache;
  ConversationRepository? _repository;
  final ClientIdentity _clientIdentity = ClientIdentity();
  final AppThemeModeStore _themeModeStore = const AppThemeModeStore();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final ActiveLearningModuleRegistry _activeLearningModules =
      ActiveLearningModuleRegistry();
  late final MainSpeakingSessionController _mainSpeakingSessionController;
  late final MainButtonCoordinator _mainButtonCoordinator;
  final MainSpeakingCommandResolver _mainSpeakingCommandResolver =
      const MainSpeakingCommandResolver();
  DeviceRegistrationService? _deviceRegistrationService;
  ThemeMode _themeMode = ThemeMode.system;
  bool _themeModeChangedByUser = false;
  bool _isActivatingMainAssistant = false;
  bool _isStartingMainSpeakingTurn = false;
  bool _isFinishingMainSpeakingMode = false;
  bool _hasMainSpeakingTurnStarted = false;
  bool _isGlobalModalOpen = false;
  bool _backgroundWorkStarted = false;
  bool _activeModulePausedForMain = false;
  bool _singleSentenceMainModeActive = false;

  @override
  void initState() {
    super.initState();
    _config = AppConfig.fromEnvironment();
    _mainSpeakingSessionController = MainSpeakingSessionController();
    // Build the lightweight runtime before the first frame so the real home
    // screen appears immediately on both Android and web.
    _createRuntime();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBackgroundStartup();
    });
  }

  void _startBackgroundStartup() {
    _startBackgroundWork();
    unawaited(
      Future.wait<void>(<Future<void>>[
        _runStartupTask(() async {
          await _clientIdentity.getClientId();
        }),
        _runStartupTask(() async {
          await AssetListeningContentRepository().load();
        }),
        _runStartupTask(_loadThemeMode),
        _runStartupTask(_precacheHomeAssets),
      ]),
    );
    unawaited(_warmTopicImagesWhenIdle());
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

  Future<void> _warmTopicImagesWhenIdle() async {
    // Prioritize interactivity, then decode only the first visible topic cards
    // sequentially so entering the catalog does not cause a burst of work.
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) {
      return;
    }
    var catalogIndex = listeningCatalogs.lastIndexWhere(
      (catalog) => _config.childAge >= catalog.startAge,
    );
    if (catalogIndex < 0) {
      catalogIndex = 0;
    }
    for (final topic in listeningCatalogs[catalogIndex].topics.take(4)) {
      final imagePath = topic.imagePath;
      if (imagePath == null || !mounted) {
        continue;
      }
      await _runStartupTask(
        () => precacheImage(AssetImage(imagePath), context),
      );
    }
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
      enabled: supportsAndroidNativeSpeech && _config.enableLegacyBleAudio,
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
    final aiv0BleControl = MethodChannelAiv0BleControl(
      enabled: supportsAndroidNativeSpeech && _config.enableAiv0BleControl,
      draftProtocolConfirmed: _config.aiv0DraftProtocolConfirmed,
    );
    final streamingSpeechInput = supportsAndroidNativeSpeech
        ? AndroidStreamingSpeechInput()
        : null;
    _androidStreamingSpeechInput = streamingSpeechInput;
    final StreamingSpeechInput? voiceNavigationSpeechInput =
        streamingSpeechInput ??
        (kIsWeb
            ? WebBatchStreamingSpeechInput(
                audioInput: phoneMicrophoneInput,
                repository: repository,
                childAge: _config.childAge,
              )
            : null);
    final voiceNavigationController =
        voiceNavigationSpeechInput != null && _config.enableVoiceNavigation
        ? VoiceNavigationController(
            speechInput: voiceNavigationSpeechInput,
            // Android's recognizer is shared with ConversationController and
            // remains owned there. The Web adapter is exclusive to MAIN and
            // may close its own event streams with this controller.
            ownsSpeechInput: kIsWeb,
            voicePromptService: createVoicePromptService(),
            ownsVoicePromptService: true,
            activeLearningCommandHandler: _handleActiveLearningCommand,
          )
        : null;
    final controller = ConversationController(
      audioInput: PreferredAudioInput(
        preferred: _config.preferBleStreaming ? innotrikInput : null,
        fallback: phoneMicrophoneInput,
      ),
      streamingSpeechInput: streamingSpeechInput,
      hfpAudioControl: hfpAudioControl,
      aiv0BleControl: aiv0BleControl,
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
      // Open the Batch session on the record gesture on every browser so
      // session creation and chunk upload overlap the child's whole utterance.
      // No-speech turns are discarded by the adaptive upload gate.
      adaptiveWebUploadDelay: Duration.zero,
      initialAsrMode: supportsAndroidNativeSpeech
          ? AsrMode.androidStreaming
          : AsrMode.batchChunks,
      beforeRecordingStart: voiceNavigationController?.pause,
      recognizedSpeechCommandMatcher: _matchesMainSpeakingCommand,
      onRecognizedSpeechCommand: _handleMainSpeakingCommand,
    );
    final mainButtonCoordinator = MainButtonCoordinator(
      onScreenShortPress: _handleUnifiedMainShortPress,
      onBleShortPress: _handleUnifiedMainShortPress,
      onLongPress: _handleMainLongPress,
    );
    controller.setMainButtonDispatcher(mainButtonCoordinator.handle);
    _mainButtonCoordinator = mainButtonCoordinator;
    _repository = repository;
    _deviceAudioCache = deviceAudioCache;
    _controller = controller;
    _voiceNavigationController = voiceNavigationController;
    voiceNavigationController?.addListener(_synchronizeMainAssistantSession);
    controller.addListener(_synchronizeMainSpeakingSession);
  }

  void _startBackgroundWork() {
    if (_backgroundWorkStarted) {
      return;
    }
    _backgroundWorkStarted = true;
    final androidStreamingSpeechInput = _androidStreamingSpeechInput;
    if (androidStreamingSpeechInput != null) {
      unawaited(androidStreamingSpeechInput.prewarm());
    }
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

  Future<bool> _activateMainAssistant() async {
    final voiceController = _voiceNavigationController;
    final conversationController = _controller;
    if (_isActivatingMainAssistant ||
        voiceController == null ||
        conversationController == null) {
      return false;
    }

    if (_mainSpeakingSessionController.isActive) {
      return false;
    }

    if (conversationController.isBusy ||
        conversationController.isPlaybackPlaying) {
      return false;
    }

    setState(() => _isActivatingMainAssistant = true);

    try {
      final hasActiveModule = _activeLearningModules.hasActiveModule;
      if (hasActiveModule) {
        _activeModulePausedForMain = await _activeLearningModules
            .pauseForMainAssistant();
      }
      if (!mounted) {
        return false;
      }
      final activated = await voiceController.activateFromMainButton(
        activeLearning: hasActiveModule,
      );
      if (!activated && _activeModulePausedForMain) {
        await _resumeActiveModuleAfterMain();
      }
      return activated;
    } finally {
      if (mounted) {
        setState(() => _isActivatingMainAssistant = false);
      }
    }
  }

  Future<MainButtonActionResult> _handleUnifiedMainShortPress(
    MainButtonInputEvent event,
  ) async {
    final controller = _controller;
    // Keep the existing offline H20 diagnostic available until the real
    // hardware packet contract is confirmed.
    if (event.source == MainButtonSource.ble &&
        (controller?.h20HardwareTestModeEnabled ?? false)) {
      return controller!.handleBleMainShortPress(event);
    }
    if (_singleSentenceMainModeActive) {
      if (controller == null ||
          controller.isPreparingMicrophone ||
          controller.phase == ConversationPhase.processing ||
          controller.isPlaybackPlaying) {
        return MainButtonActionResult.busy;
      }
      await controller.onPrimaryAction();
      return MainButtonActionResult.accepted;
    }
    final activated = await _activateMainAssistant();
    return activated
        ? MainButtonActionResult.accepted
        : MainButtonActionResult.busy;
  }

  Future<ActiveLearningCommandResult> _handleActiveLearningCommand(
    ActiveLearningCommand command,
  ) async {
    _activeModulePausedForMain = false;
    final result = await _activeLearningModules.execute(command);
    final reply = result.spokenReply;
    if (!result.wasHandled && reply != null && reply.trim().isNotEmpty) {
      await _controller?.speakAssistantPrompt(reply);
    }
    return result;
  }

  void _synchronizeMainAssistantSession() {
    final voiceController = _voiceNavigationController;
    if (!_activeModulePausedForMain || voiceController == null) {
      return;
    }
    if (!voiceController.isMainButtonSessionActive &&
        !voiceController.isActive) {
      unawaited(_resumeActiveModuleAfterMain());
    }
  }

  Future<void> _resumeActiveModuleAfterMain() async {
    if (!_activeModulePausedForMain) {
      return;
    }
    _activeModulePausedForMain = false;
    await _activeLearningModules.execute(ActiveLearningCommand.resume);
  }

  Future<MainButtonActionResult> _handleMainLongPress(
    MainButtonInputEvent event,
  ) async {
    if (_singleSentenceMainModeActive) {
      final controller = _controller;
      if (controller == null) {
        return MainButtonActionResult.ignored;
      }
      final stopped = await controller.cancelSingleSentenceMainAction();
      if (stopped == MainButtonActionResult.busy) {
        return stopped;
      }
      if (mounted) {
        setState(() => _singleSentenceMainModeActive = false);
      } else {
        _singleSentenceMainModeActive = false;
      }
      final activated = await _activateMainAssistant();
      return activated
          ? MainButtonActionResult.accepted
          : MainButtonActionResult.busy;
    }

    final voiceController = _voiceNavigationController;
    if (voiceController?.isMainButtonSessionActive ?? false) {
      _activeModulePausedForMain = false;
      await voiceController!.pause();
      final stopped = await _activeLearningModules.execute(
        ActiveLearningCommand.stop,
      );
      if (stopped.wasHandled) {
        await _controller?.speakAssistantPrompt('Đã dừng.');
        return MainButtonActionResult.accepted;
      }
      return MainButtonActionResult.accepted;
    }

    final stoppedModule = await _activeLearningModules.execute(
      ActiveLearningCommand.stop,
    );
    if (stoppedModule.wasHandled) {
      _activeModulePausedForMain = false;
      await _controller?.speakAssistantPrompt('Đã dừng.');
      return MainButtonActionResult.accepted;
    }

    final controller = _controller;
    if (controller == null) {
      return MainButtonActionResult.ignored;
    }
    if (_mainSpeakingSessionController.state ==
        MainSpeakingSessionState.processing) {
      return MainButtonActionResult.busy;
    }
    final endedMainSpeakingSession = _mainSpeakingSessionController.isActive;
    if (endedMainSpeakingSession) {
      _hasMainSpeakingTurnStarted = false;
      _mainSpeakingSessionController.exit();
    }
    final result = await controller.stopCurrentMainAction();
    if (result != MainButtonActionResult.ignored) {
      return result;
    }
    if (endedMainSpeakingSession) {
      return MainButtonActionResult.accepted;
    }

    return MainButtonActionResult.ignored;
  }

  Future<void> _handleScreenMainLongPress() async {
    await _mainButtonCoordinator.handle(
      const MainButtonInputEvent(
        source: MainButtonSource.screen,
        gesture: MainButtonGesture.longPress,
      ),
    );
  }

  Future<void> _handleScreenMainRelease() async {
    await _mainButtonCoordinator.handle(
      const MainButtonInputEvent(
        source: MainButtonSource.screen,
        gesture: MainButtonGesture.release,
      ),
    );
  }

  void _startMainSpeakingMode() {
    if (mounted) {
      setState(() => _singleSentenceMainModeActive = false);
    } else {
      _singleSentenceMainModeActive = false;
    }
    _hasMainSpeakingTurnStarted = false;
    _mainSpeakingSessionController.enter();
    _synchronizeMainSpeakingSession();
  }

  void _setSingleSentenceMainMode(bool active) {
    if (_singleSentenceMainModeActive == active) {
      return;
    }
    if (active && _mainSpeakingSessionController.isActive) {
      _hasMainSpeakingTurnStarted = false;
      _mainSpeakingSessionController.exit();
    }
    if (mounted) {
      setState(() => _singleSentenceMainModeActive = active);
    } else {
      _singleSentenceMainModeActive = active;
    }
  }

  void _synchronizeMainSpeakingSession() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    _mainSpeakingSessionController.synchronize(
      isRecording: controller.isRecording,
      isBusy: controller.isBusy,
      isPlaying: controller.isPlaybackPlaying,
    );
    if (!_mainSpeakingSessionController.isActive ||
        _isFinishingMainSpeakingMode) {
      return;
    }

    final turnEndReason = controller.lastTurnEndReason;
    if (turnEndReason == ConversationTurnEndReason.commandHandled) {
      return;
    }
    if (_hasMainSpeakingTurnStarted &&
        controller.phase == ConversationPhase.idle &&
        (turnEndReason == ConversationTurnEndReason.noSpeech ||
            turnEndReason == ConversationTurnEndReason.tooShort)) {
      unawaited(_finishMainSpeakingMode(sayGoodbye: true));
      return;
    }
    if (_hasMainSpeakingTurnStarted &&
        (controller.phase == ConversationPhase.error ||
            turnEndReason == ConversationTurnEndReason.failed)) {
      unawaited(_finishMainSpeakingMode(sayGoodbye: false));
      return;
    }
    if (_mainSpeakingSessionController.isReady &&
        !_isStartingMainSpeakingTurn) {
      unawaited(_startNextMainSpeakingTurn());
    }
  }

  Future<void> _startNextMainSpeakingTurn() async {
    final controller = _controller;
    if (controller == null ||
        !_mainSpeakingSessionController.isActive ||
        _isStartingMainSpeakingTurn ||
        _isFinishingMainSpeakingMode ||
        controller.isBusy ||
        controller.isPlaybackPlaying) {
      return;
    }
    if (!controller.isInputAvailable) {
      await _finishMainSpeakingMode(sayGoodbye: false);
      return;
    }

    _isStartingMainSpeakingTurn = true;
    try {
      await controller.startRecording(
        noSpeechTimeout: const Duration(seconds: 10),
        speakNoSpeechPrompt: false,
      );
      _hasMainSpeakingTurnStarted = controller.isRecording;
    } finally {
      _isStartingMainSpeakingTurn = false;
    }
  }

  Future<void> _finishMainSpeakingMode({required bool sayGoodbye}) async {
    final controller = _controller;
    if (!_mainSpeakingSessionController.isActive ||
        _isFinishingMainSpeakingMode) {
      return;
    }
    _isFinishingMainSpeakingMode = true;
    _hasMainSpeakingTurnStarted = false;
    if (mounted) {
      setState(() => _isActivatingMainAssistant = true);
    }
    _mainSpeakingSessionController.exit();
    try {
      if (sayGoodbye && controller != null) {
        controller.clearMessage();
        await controller.speakAssistantPrompt('tạm biệt con nhé');
      }
    } finally {
      _isFinishingMainSpeakingMode = false;
      if (mounted) {
        setState(() => _isActivatingMainAssistant = false);
      }
    }
  }

  bool _matchesMainSpeakingCommand(String recognizedText) {
    return _mainSpeakingSessionController.isActive &&
        _mainSpeakingCommandResolver.resolve(recognizedText) ==
            MainSpeakingCommand.otherLearning;
  }

  Future<void> _handleMainSpeakingCommand(String recognizedText) async {
    final voiceController = _voiceNavigationController;
    final controller = _controller;
    if (!_mainSpeakingSessionController.isActive ||
        voiceController == null ||
        controller == null ||
        _isFinishingMainSpeakingMode) {
      return;
    }

    _isFinishingMainSpeakingMode = true;
    _hasMainSpeakingTurnStarted = false;
    _mainSpeakingSessionController.exit();
    controller.clearMessage();
    if (mounted) {
      setState(() => _isActivatingMainAssistant = true);
    }
    try {
      await voiceController.activateOtherLearningFromSpeaking();
    } finally {
      _isFinishingMainSpeakingMode = false;
      if (mounted) {
        setState(() => _isActivatingMainAssistant = false);
      }
    }
  }

  void _setGlobalModalOpen(bool isOpen) {
    if (!mounted || _isGlobalModalOpen == isOpen) return;
    setState(() => _isGlobalModalOpen = isOpen);
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
    _controller?.removeListener(_synchronizeMainSpeakingSession);
    _mainSpeakingSessionController.dispose();
    _voiceNavigationController?.removeListener(
      _synchronizeMainAssistantSession,
    );
    _voiceNavigationController?.dispose();
    _controller?.dispose();
    _deviceRegistrationService?.dispose();
    _deviceAudioCache?.dispose();
    _activeLearningModules.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Trợ lý giao tiếp',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildDarkAppTheme(),
      themeMode: _themeMode,
      builder: (context, child) {
        final voiceController = _voiceNavigationController;
        return ActiveLearningModuleScope(
          registry: _activeLearningModules,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              child ?? const SizedBox.shrink(),
              if (voiceController != null && !_isGlobalModalOpen)
                Positioned(
                  right: 16,
                  bottom: 0,
                  child: SafeArea(
                    minimum: const EdgeInsets.only(bottom: 88),
                    child: MainVoiceAssistantButton(
                      voiceController: voiceController,
                      conversationController: controller,
                      speakingSessionController: _mainSpeakingSessionController,
                      singleSentenceModeActive: _singleSentenceMainModeActive,
                      isActivationPending: _isActivatingMainAssistant,
                      onPressed: () async {
                        await _mainButtonCoordinator.handle(
                          const MainButtonInputEvent(
                            source: MainButtonSource.screen,
                            gesture: MainButtonGesture.shortPress,
                          ),
                        );
                      },
                      onLongPressed: _handleScreenMainLongPress,
                      onLongPressReleased: _handleScreenMainRelease,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      home: AndroidUpdateGate(
        config: _config,
        child: PwaInstallGate(
          child: HomeLearningShell(
            controller: controller,
            config: _config,
            voiceNavigationController: _voiceNavigationController,
            themeMode: _themeMode,
            onThemeModeChanged: _setThemeMode,
            onMainSpeakingModeStarted: _startMainSpeakingMode,
            onSingleSentenceModeChanged: _setSingleSentenceMainMode,
            onModalVisibilityChanged: _setGlobalModalOpen,
          ),
        ),
      ),
    );
  }
}
