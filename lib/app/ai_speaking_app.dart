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
import '../features/onboarding/presentation/startup_setup_screen.dart';
import '../features/settings/data/child_age_store.dart';
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
  PhoneMicrophoneInput? _phoneMicrophoneInput;
  MethodChannelAiv0BleControl? _aiv0BleControl;
  MethodChannelHfpAudioControl? _androidHfpAudioControl;
  WebBatchStreamingSpeechInput? _webBatchStreamingSpeechInput;
  DeviceAudioCache? _deviceAudioCache;
  ConversationRepository? _repository;
  final ClientIdentity _clientIdentity = ClientIdentity();
  final AppThemeModeStore _themeModeStore = const AppThemeModeStore();
  final ChildAgeStore _childAgeStore = const ChildAgeStore();
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
  bool _isHandlingMainSpeakingNoSpeech = false;
  bool _hasMainSpeakingTurnStarted = false;
  bool _isGlobalModalOpen = false;
  bool _backgroundWorkStarted = false;
  bool _activeModulePausedForMain = false;
  bool _singleSentenceMainModeActive = false;
  bool _isResumingActiveModule = false;
  bool _startupProfileLoading = true;
  bool _startupPermissionRequestInProgress = false;
  bool _microphonePermissionGranted = false;
  bool _bluetoothPermissionGranted = false;
  int? _childAge;
  int? _pendingStartupAge;
  String? _startupPermissionError;

  bool get _bluetoothPermissionRequired {
    return !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        (_config.enableAiv0BleControl || _config.enableHfpAudio);
  }

  bool get _startupReady =>
      !_startupProfileLoading &&
      _childAge != null &&
      _microphonePermissionGranted &&
      (!_bluetoothPermissionRequired || _bluetoothPermissionGranted);

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
      unawaited(_initializeStartupSetup());
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

  Future<void> _initializeStartupSetup() async {
    int? storedAge;
    try {
      storedAge = _validChildAge(await _childAgeStore.read());
    } catch (error) {
      debugPrint('Could not load child age: $error');
    }
    if (!mounted) {
      return;
    }
    if (storedAge != null) {
      _propagateChildAge(storedAge);
    }
    setState(() {
      _childAge = storedAge;
      _pendingStartupAge = storedAge;
      _startupProfileLoading = false;
    });
    await _requestStartupPermissions();
  }

  int? _validChildAge(int? age) {
    if (age == null) {
      return null;
    }
    for (final catalog in listeningCatalogs) {
      if (age >= catalog.startAge && age <= catalog.endAge) {
        return age;
      }
    }
    return null;
  }

  void _propagateChildAge(int age) {
    _controller?.setChildAge(age);
    _voiceNavigationController?.setChildAge(age);
    _webBatchStreamingSpeechInput?.setChildAge(age);
  }

  void _setChildAge(int age) {
    final validAge = _validChildAge(age);
    if (validAge == null) {
      return;
    }
    _propagateChildAge(validAge);
    if (mounted) {
      setState(() {
        _childAge = validAge;
        _pendingStartupAge = validAge;
      });
    } else {
      _childAge = validAge;
      _pendingStartupAge = validAge;
    }
    unawaited(
      _childAgeStore.write(validAge).catchError((Object error) {
        debugPrint('Could not persist child age: $error');
      }),
    );
    unawaited(_warmTopicImagesWhenIdle());
  }

  void _confirmStartupAge() {
    final age = _pendingStartupAge;
    if (age != null) {
      _setChildAge(age);
    }
  }

  Future<void> _requestStartupPermissions() async {
    if (_startupPermissionRequestInProgress) {
      return;
    }
    if (mounted) {
      setState(() {
        _startupPermissionRequestInProgress = true;
        _startupPermissionError = null;
      });
    }

    var microphoneGranted = false;
    var bluetoothGranted = !_bluetoothPermissionRequired;
    final errors = <String>[];
    try {
      microphoneGranted =
          await _phoneMicrophoneInput?.requestPermission() ?? false;
      if (!microphoneGranted) {
        errors.add('Cần cấp quyền Micro để nghe trẻ nói.');
      }
    } catch (error) {
      errors.add('Không thể yêu cầu quyền Micro: $error');
    }

    if (_bluetoothPermissionRequired) {
      try {
        if (_config.enableAiv0BleControl) {
          bluetoothGranted =
              await _aiv0BleControl?.requestPermissions() ?? false;
        } else {
          bluetoothGranted =
              await _androidHfpAudioControl?.requestPermissions() ?? false;
        }
        if (!bluetoothGranted) {
          errors.add(
            'Cần cấp quyền Thiết bị ở gần/Bluetooth để dùng cục AIV0.',
          );
        }
      } catch (error) {
        errors.add('Không thể yêu cầu quyền Bluetooth: $error');
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _microphonePermissionGranted = microphoneGranted;
      _bluetoothPermissionGranted = bluetoothGranted;
      _startupPermissionRequestInProgress = false;
      _startupPermissionError = errors.isEmpty ? null : errors.join('\n');
    });
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
    final childAge = _controller?.childAge ?? _config.childAge;
    var catalogIndex = listeningCatalogs.lastIndexWhere(
      (catalog) => childAge >= catalog.startAge,
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
    final MethodChannelHfpAudioControl? androidHfpAudioControl;
    final HfpAudioControl hfpAudioControl;
    if (kIsWeb) {
      androidHfpAudioControl = null;
      hfpAudioControl = BrowserHfpAudioControl(
        enabled: _config.enableHfpAudio,
        audioInput: phoneMicrophoneInput,
      );
    } else {
      androidHfpAudioControl = MethodChannelHfpAudioControl(
        enabled: supportsAndroidNativeSpeech && _config.enableHfpAudio,
      );
      hfpAudioControl = androidHfpAudioControl;
    }
    final aiv0BleControl = MethodChannelAiv0BleControl(
      enabled: supportsAndroidNativeSpeech && _config.enableAiv0BleControl,
      draftProtocolConfirmed: _config.aiv0DraftProtocolConfirmed,
    );
    final streamingSpeechInput = supportsAndroidNativeSpeech
        ? AndroidStreamingSpeechInput()
        : null;
    _androidStreamingSpeechInput = streamingSpeechInput;
    final WebBatchStreamingSpeechInput? webBatchStreamingSpeechInput;
    final StreamingSpeechInput? voiceNavigationSpeechInput;
    if (streamingSpeechInput != null) {
      webBatchStreamingSpeechInput = null;
      voiceNavigationSpeechInput = streamingSpeechInput;
    } else if (kIsWeb) {
      webBatchStreamingSpeechInput = WebBatchStreamingSpeechInput(
        audioInput: phoneMicrophoneInput,
        repository: repository,
        childAge: _config.childAge,
      );
      voiceNavigationSpeechInput = webBatchStreamingSpeechInput;
    } else {
      webBatchStreamingSpeechInput = null;
      voiceNavigationSpeechInput = null;
    }
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
    voiceNavigationController?.setChildAge(_config.childAge);
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
    _phoneMicrophoneInput = phoneMicrophoneInput;
    _aiv0BleControl = aiv0BleControl;
    _androidHfpAudioControl = androidHfpAudioControl;
    _webBatchStreamingSpeechInput = webBatchStreamingSpeechInput;
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
    if (!_startupReady) {
      return false;
    }
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
        if (!_activeModulePausedForMain) {
          return false;
        }
      }
      if (!mounted) {
        return false;
      }
      final activated = await voiceController.activateFromMainButton(
        activeLearning: hasActiveModule,
        activeLearningKind: _activeLearningModules.activeKind,
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
    if (!_startupReady) {
      return MainButtonActionResult.busy;
    }
    final controller = _controller;
    // Physical BLE MAIN and the on-screen MAIN must always have identical
    // application behavior. Hardware loopback remains available through the
    // explicit buttons in Settings; enabling diagnostics must not hijack the
    // child's physical MAIN button.
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
    ActiveLearningCommandResult result;
    try {
      result = await _activeLearningModules.execute(command);
    } catch (_) {
      result = const ActiveLearningCommandResult.busy(
        spokenReply: 'Bi cô chưa thực hiện được. Con thử lại nhé.',
      );
    }
    if (result.wasHandled) {
      _activeModulePausedForMain = false;
    }
    final reply = result.spokenReply;
    if (!result.wasHandled && reply != null && reply.trim().isNotEmpty) {
      await _controller?.speakAssistantPrompt(reply);
    }
    return result;
  }

  void _synchronizeMainAssistantSession() {
    final voiceController = _voiceNavigationController;
    if (!_activeModulePausedForMain ||
        _isActivatingMainAssistant ||
        voiceController == null) {
      return;
    }
    if (!voiceController.isMainButtonSessionActive &&
        !voiceController.isActive) {
      unawaited(_resumeActiveModuleAfterMain());
    }
  }

  Future<void> _resumeActiveModuleAfterMain() async {
    if (!_activeModulePausedForMain || _isResumingActiveModule) {
      return;
    }
    _isResumingActiveModule = true;
    try {
      final result = await _activeLearningModules.execute(
        ActiveLearningCommand.resume,
      );
      if (result.wasHandled ||
          !_activeLearningModules.hasActiveModule ||
          !_activeLearningModules.isActiveModulePaused) {
        _activeModulePausedForMain = false;
      }
    } catch (_) {
      // Keep the paused flag so a later assistant state change can retry.
    } finally {
      _isResumingActiveModule = false;
    }
  }

  Future<MainButtonActionResult> _handleMainLongPress(
    MainButtonInputEvent event,
  ) async {
    if (!_startupReady) {
      return MainButtonActionResult.busy;
    }
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
      await controller.speakAssistantPrompt('Đã dừng.');
      final activated = await _activateMainAssistant();
      return activated
          ? MainButtonActionResult.accepted
          : MainButtonActionResult.busy;
    }

    final voiceController = _voiceNavigationController;
    if (voiceController?.isMainButtonSessionActive ?? false) {
      // Keep an interrupted lesson paused. Otherwise the controller listener
      // would resume it while the child is still hearing "Đã dừng.".
      _activeModulePausedForMain = false;
      await voiceController!.pause();
      await _controller?.speakAssistantPrompt('Đã dừng.');
      return MainButtonActionResult.accepted;
    }

    final learningResult = await _toggleActiveLearningFromLongPress();
    if (learningResult != null) {
      return learningResult;
    }

    final controller = _controller;
    if (controller == null) {
      return MainButtonActionResult.ignored;
    }
    final endedMainSpeakingSession = _mainSpeakingSessionController.isActive;
    if (endedMainSpeakingSession) {
      _hasMainSpeakingTurnStarted = false;
      _mainSpeakingSessionController.exit();
    }
    final result = await controller.stopCurrentMainAction();
    if (result != MainButtonActionResult.ignored) {
      await controller.speakAssistantPrompt('Đã dừng.');
      return result;
    }
    if (endedMainSpeakingSession) {
      await controller.speakAssistantPrompt('Đã dừng.');
      return MainButtonActionResult.accepted;
    }

    return MainButtonActionResult.ignored;
  }

  Future<MainButtonActionResult?> _toggleActiveLearningFromLongPress() async {
    if (!_activeLearningModules.hasActiveModule) {
      return null;
    }

    if (_activeLearningModules.isActiveModulePaused) {
      try {
        await _controller?.speakAssistantPrompt('Cùng học tiếp nhé');
      } catch (_) {
        // A prompt failure must not leave the lesson permanently paused.
      }
      final resumed = await _activeLearningModules.execute(
        ActiveLearningCommand.resume,
      );
      if (resumed.wasHandled) {
        _activeModulePausedForMain = false;
      }
      return resumed.wasHandled
          ? MainButtonActionResult.accepted
          : MainButtonActionResult.ignored;
    }

    final stopped = await _activeLearningModules.execute(
      ActiveLearningCommand.stop,
    );
    if (!stopped.wasHandled) {
      return MainButtonActionResult.ignored;
    }
    _activeModulePausedForMain = false;
    await _controller?.speakAssistantPrompt('Đã dừng.');
    return MainButtonActionResult.accepted;
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
    _isHandlingMainSpeakingNoSpeech = false;
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
        _isFinishingMainSpeakingMode ||
        _isHandlingMainSpeakingNoSpeech) {
      return;
    }

    final turnEndReason = controller.lastTurnEndReason;
    if (turnEndReason == ConversationTurnEndReason.completed) {
      _mainSpeakingSessionController.markSpeechTurnCompleted();
    }
    if (turnEndReason == ConversationTurnEndReason.commandHandled) {
      return;
    }
    if (_hasMainSpeakingTurnStarted &&
        controller.phase == ConversationPhase.idle &&
        (turnEndReason == ConversationTurnEndReason.noSpeech ||
            turnEndReason == ConversationTurnEndReason.tooShort)) {
      unawaited(_handleMainSpeakingNoSpeech());
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
        noSpeechTimeout: const Duration(seconds: 6),
        speakNoSpeechPrompt: false,
      );
      _hasMainSpeakingTurnStarted = controller.isRecording;
    } finally {
      _isStartingMainSpeakingTurn = false;
    }
  }

  Future<void> _handleMainSpeakingNoSpeech() async {
    final controller = _controller;
    if (controller == null ||
        !_mainSpeakingSessionController.isActive ||
        _isHandlingMainSpeakingNoSpeech ||
        _isFinishingMainSpeakingMode) {
      return;
    }

    _isHandlingMainSpeakingNoSpeech = true;
    _hasMainSpeakingTurnStarted = false;
    final action = _mainSpeakingSessionController.registerNoSpeechTurn();
    var retry = false;
    try {
      if (action == MainSpeakingNoSpeechAction.retry) {
        controller.clearMessage();
        await controller.speakAssistantPrompt(
          'Cô chưa nghe thấy con nói. Con nói lại nhé.',
        );
        retry = true;
      } else {
        await _finishMainSpeakingMode(
          sayGoodbye: true,
          goodbyeText:
              'Tạm biệt con nhé, khi nào con cần gì hãy nhấn MAIN nhé.',
        );
      }
    } finally {
      _isHandlingMainSpeakingNoSpeech = false;
    }

    if (retry &&
        _mainSpeakingSessionController.isActive &&
        !_isFinishingMainSpeakingMode) {
      controller.clearMessage();
      await _startNextMainSpeakingTurn();
    }
  }

  Future<void> _finishMainSpeakingMode({
    required bool sayGoodbye,
    String goodbyeText = 'Tạm biệt con nhé.',
  }) async {
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
        await controller.speakAssistantPrompt(goodbyeText);
      }
    } finally {
      _isFinishingMainSpeakingMode = false;
      if (mounted) {
        setState(() => _isActivatingMainAssistant = false);
      }
    }
  }

  bool _matchesMainSpeakingCommand(String recognizedText) {
    // ConversationController owns every Vietnamese -> English recording flow.
    // Listening pronunciation recordings use their own controller, so this can
    // safely stay enabled for every conversation mode without swallowing an
    // English lesson answer.
    return _mainSpeakingCommandResolver.resolve(recognizedText) != null;
  }

  Future<void> _handleMainSpeakingCommand(String recognizedText) async {
    final voiceController = _voiceNavigationController;
    final controller = _controller;
    final isContinuousSpeaking = _mainSpeakingSessionController.isActive;
    final isSingleSentenceSpeaking = _singleSentenceMainModeActive;
    if (voiceController == null ||
        controller == null ||
        _isFinishingMainSpeakingMode) {
      return;
    }

    final command = _mainSpeakingCommandResolver.resolve(recognizedText);
    if (command == null) {
      return;
    }

    _isFinishingMainSpeakingMode = true;
    _hasMainSpeakingTurnStarted = false;
    if (isContinuousSpeaking) {
      _mainSpeakingSessionController.exit();
    }
    if (isSingleSentenceSpeaking) {
      _setSingleSentenceMainMode(false);
    }
    controller.clearMessage();
    if (mounted) {
      setState(() => _isActivatingMainAssistant = true);
    }
    try {
      // Both commands leave translation before any English result is shown or
      // played, then open the normal MAIN assistant routing menu. Keeping one
      // exit path avoids making the child remember a different gesture for the
      // single-sentence and continuous modes.
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
              if (voiceController != null &&
                  !_isGlobalModalOpen &&
                  _startupReady)
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
      home: _startupReady
          ? AndroidUpdateGate(
              config: _config,
              child: PwaInstallGate(
                child: HomeLearningShell(
                  controller: controller,
                  config: _config,
                  voiceNavigationController: _voiceNavigationController,
                  themeMode: _themeMode,
                  onThemeModeChanged: _setThemeMode,
                  onChildAgeChanged: _setChildAge,
                  onMainSpeakingModeStarted: _startMainSpeakingMode,
                  onSingleSentenceModeChanged: _setSingleSentenceMainMode,
                  onModalVisibilityChanged: _setGlobalModalOpen,
                ),
              ),
            )
          : StartupSetupScreen(
              profileLoading: _startupProfileLoading,
              permissionRequestInProgress: _startupPermissionRequestInProgress,
              microphoneGranted: _microphonePermissionGranted,
              bluetoothRequired: _bluetoothPermissionRequired,
              bluetoothGranted: _bluetoothPermissionGranted,
              selectedAge: _pendingStartupAge,
              permissionError: _startupPermissionError,
              onRetryPermissions: () => unawaited(_requestStartupPermissions()),
              onAgeSelected: (age) => setState(() => _pendingStartupAge = age),
              onConfirmAge: _confirmStartupAge,
            ),
    );
  }
}
