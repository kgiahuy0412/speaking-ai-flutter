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
import '../features/privacy/data/privacy_consent_store.dart';
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

class _AiSpeakingAppState extends State<AiSpeakingApp>
    with WidgetsBindingObserver {
  late final AppConfig _config;
  ConversationController? _controller;
  VoiceNavigationController? _voiceNavigationController;
  AndroidStreamingSpeechInput? _nativeStreamingSpeechInput;
  PhoneMicrophoneInput? _phoneMicrophoneInput;
  MethodChannelAiv0BleControl? _aiv0BleControl;
  MethodChannelHfpAudioControl? _nativeHfpAudioControl;
  WebBatchStreamingSpeechInput? _webBatchStreamingSpeechInput;
  DeviceAudioCache? _deviceAudioCache;
  ConversationRepository? _repository;
  final ClientIdentity _clientIdentity = ClientIdentity();
  final AppThemeModeStore _themeModeStore = const AppThemeModeStore();
  final ChildAgeStore _childAgeStore = const ChildAgeStore();
  final PrivacyConsentStore _privacyConsentStore = const PrivacyConsentStore();
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
  bool _isResumingActiveModule = false;
  bool _startupProfileLoading = true;
  bool _startupPermissionRequestInProgress = false;
  bool _microphonePermissionGranted = false;
  bool _bluetoothPermissionGranted = false;
  bool _privacyConsentGranted = false;
  bool _limitedModeSelected = false;
  int? _childAge;
  int? _pendingStartupAge;
  String? _startupPermissionError;
  DateTime? _lastAiv0AutoConnectAttempt;
  DateTime? _suppressH20AutoConnectUntil;
  bool _restoreHfpAfterPhysicalMain = false;
  bool _isRestoringHfpAfterPhysicalMain = false;

  bool get _bluetoothPermissionRequired {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS) &&
        (_config.enableAiv0BleControl || _config.enableHfpAudio);
  }

  bool get _startupReady =>
      !_startupProfileLoading &&
      _childAge != null &&
      (_privacyConsentGranted || _limitedModeSelected);

  bool get _voiceAccessEnabled =>
      _privacyConsentGranted && _microphonePermissionGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _config = AppConfig.fromEnvironment();
    _mainSpeakingSessionController = MainSpeakingSessionController();
    _mainSpeakingSessionController.addListener(
      _synchronizePendingMainSpeakingAudioHandoff,
    );
    // Build the lightweight runtime before the first frame so the real home
    // screen appears immediately on both Android and web.
    _createRuntime();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBackgroundStartup();
      unawaited(_initializeStartupSetup());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    // Flutter state is recreated after a cold launch/TestFlight update, while
    // iOS keeps the system permission grants. Refresh them whenever the app
    // returns to the foreground so MAIN does not stay hidden after the user
    // grants Microphone/Speech/Bluetooth access in Settings.
    if (_privacyConsentGranted) {
      unawaited(_requestStartupPermissions());
    } else if (_bluetoothPermissionGranted) {
      unawaited(_autoConnectH20Ble());
    }
  }

  void _startBackgroundStartup() {
    unawaited(
      Future.wait<void>(<Future<void>>[
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
    var storedConsent = false;
    var storedLimitedMode = false;
    try {
      final values = await Future.wait<Object?>(<Future<Object?>>[
        _childAgeStore.read(),
        _privacyConsentStore.readGranted(),
        _privacyConsentStore.readLimitedMode(),
      ]);
      storedAge = _validChildAge(values[0] as int?);
      storedConsent = values[1] as bool;
      storedLimitedMode = values[2] as bool;
    } catch (error) {
      debugPrint('Could not load startup privacy/profile state: $error');
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
      _privacyConsentGranted =
          storedConsent && _config.privacyReleaseConfigurationComplete;
      _limitedModeSelected = storedLimitedMode && !_privacyConsentGranted;
      _startupProfileLoading = false;
    });
    if (_privacyConsentGranted) {
      _startBackgroundWork();
      // Stored parental consent allows us to query the existing native grants.
      // Without this refresh `_microphonePermissionGranted` remains false on
      // every cold launch even though iOS already authorized the app, hiding
      // both the virtual MAIN entry point and the physical MAIN action.
      unawaited(_requestStartupPermissions());
    }
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
    if (age != null && _privacyConsentGranted) {
      _setChildAge(age);
      _startBackgroundWork();
    }
  }

  Future<void> _grantPrivacyConsent() async {
    if (!_config.privacyReleaseConfigurationComplete) {
      return;
    }
    await _privacyConsentStore.grant();
    if (!mounted) {
      return;
    }
    setState(() {
      _privacyConsentGranted = true;
      _limitedModeSelected = false;
      _startupPermissionError = null;
    });
    _startBackgroundWork();
  }

  Future<void> _continueWithoutVoice() async {
    final age = _pendingStartupAge;
    if (age == null) {
      return;
    }
    await _privacyConsentStore.chooseLimitedMode();
    if (!mounted) {
      return;
    }
    _setChildAge(age);
    setState(() {
      _limitedModeSelected = true;
      _microphonePermissionGranted = false;
      _bluetoothPermissionGranted = false;
      _startupPermissionError = null;
    });
  }

  Future<void> _requestStartupPermissions() async {
    if (_startupPermissionRequestInProgress || !_privacyConsentGranted) {
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
              await _nativeHfpAudioControl?.requestPermissions() ?? false;
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
    if (bluetoothGranted && _config.enableAiv0BleControl) {
      unawaited(_autoConnectH20Ble());
    }
  }

  Future<void> _showPrivacySetup() async {
    await _privacyConsentStore.clearLimitedMode();
    if (mounted) {
      setState(() => _limitedModeSelected = false);
    }
  }

  Future<void> _revokePrivacyConsent() async {
    final controller = _controller;
    if (controller != null) {
      await controller.clearHistory();
    }
    await _privacyConsentStore.revoke();
    await _childAgeStore.clear();
    await _clientIdentity.resetClientId();
    await _voiceNavigationController?.pause();
    _backgroundWorkStarted = false;
    _deviceRegistrationService = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _privacyConsentGranted = false;
      _limitedModeSelected = false;
      _microphonePermissionGranted = false;
      _bluetoothPermissionGranted = false;
      _childAge = null;
      _pendingStartupAge = null;
      _startupPermissionError = null;
    });
  }

  Future<void> _autoConnectH20Ble() async {
    final control = _aiv0BleControl;
    final controller = _controller;
    final voiceController = _voiceNavigationController;
    final now = DateTime.now();
    if (control == null ||
        controller == null ||
        controller.isBusy ||
        _isActivatingMainAssistant ||
        _mainSpeakingSessionController.isActive ||
        (voiceController?.isMainButtonSessionActive ?? false) ||
        (voiceController?.isActive ?? false) ||
        (_suppressH20AutoConnectUntil?.isAfter(now) ?? false)) {
      return;
    }
    final lastAttempt = _lastAiv0AutoConnectAttempt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(seconds: 10)) {
      return;
    }
    _lastAiv0AutoConnectAttempt = now;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // H20 exposes Classic Bluetooth HFP and BLE Control as two transports.
      // Activating HFP after BLE is connected makes iOS renegotiate the audio
      // profile and some H20 firmware revisions briefly drop their GATT link.
      // Select the already-paired HFP route first, let it settle, and connect
      // BLE last so both transports finish in a stable state.
      var hfpConnected = false;
      for (var attempt = 0; attempt < 3; attempt += 1) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
        final currentVoiceController = _voiceNavigationController;
        if ((_suppressH20AutoConnectUntil?.isAfter(DateTime.now()) ?? false) ||
            _isActivatingMainAssistant ||
            _mainSpeakingSessionController.isActive ||
            (currentVoiceController?.isMainButtonSessionActive ?? false) ||
            (currentVoiceController?.isActive ?? false)) {
          return;
        }
        hfpConnected = await controller.autoConnectH20Hfp(
          bleDeviceName:
              control.status.deviceName ?? controller.aiv0BleStatus.deviceName,
        );
        if (hfpConnected) {
          debugPrint('H20 HFP microphone selected automatically.');
          await Future<void>.delayed(const Duration(milliseconds: 250));
          break;
        }
      }
      if (!hfpConnected) {
        debugPrint(
          'H20 HFP is not available yet; pair it once in iOS Bluetooth Settings.',
        );
      }
    }

    final bleConnected =
        controller.canUseAiv0Ble || await control.autoConnectKnownOrNearby();
    if (!bleConnected) {
      return;
    }
    debugPrint('H20 BLE Control connected automatically.');
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        !controller.usesHfpInput) {
      debugPrint(
        'BLE is ready while HFP remains unavailable; phone microphone stays active.',
      );
    }
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
    final supportsAppleNativeSpeech =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final supportsNativeSpeech =
        supportsAndroidNativeSpeech || supportsAppleNativeSpeech;
    final supportsNativeBluetooth =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final innotrikInput = InnotrikBleAudioInput(
      enabled: supportsAndroidNativeSpeech && _config.enableLegacyBleAudio,
    );
    final phoneMicrophoneInput = PhoneMicrophoneInput();
    final MethodChannelHfpAudioControl? nativeHfpAudioControl;
    final HfpAudioControl hfpAudioControl;
    if (kIsWeb) {
      nativeHfpAudioControl = null;
      hfpAudioControl = BrowserHfpAudioControl(
        enabled: _config.enableHfpAudio,
        audioInput: phoneMicrophoneInput,
      );
    } else {
      nativeHfpAudioControl = MethodChannelHfpAudioControl(
        enabled: supportsNativeBluetooth && _config.enableHfpAudio,
      );
      hfpAudioControl = nativeHfpAudioControl;
    }
    final aiv0BleControl = MethodChannelAiv0BleControl(
      enabled: supportsNativeBluetooth && _config.enableAiv0BleControl,
      draftProtocolConfirmed: _config.aiv0DraftProtocolConfirmed,
    );
    final AndroidStreamingSpeechInput? streamingSpeechInput =
        supportsAndroidNativeSpeech
        ? AndroidStreamingSpeechInput()
        : supportsAppleNativeSpeech
        ? IOSStreamingSpeechInput(audioRouteControl: hfpAudioControl)
        : null;
    _nativeStreamingSpeechInput = streamingSpeechInput;
    final WebBatchStreamingSpeechInput? webBatchStreamingSpeechInput;
    final StreamingSpeechInput? voiceNavigationSpeechInput;
    final bool voiceNavigationOwnsSpeechInput;
    if (streamingSpeechInput != null) {
      // Android and iOS use the same single native speech pipeline. In
      // particular, iOS MAIN must not silently switch to recorded-audio Batch
      // recognition when Apple Speech or the selected route fails: that hid the
      // original native error and allowed two independent session lifecycles to
      // cancel each other after the assistant prompt.
      webBatchStreamingSpeechInput = null;
      voiceNavigationSpeechInput = streamingSpeechInput;
      voiceNavigationOwnsSpeechInput = false;
    } else if (kIsWeb) {
      webBatchStreamingSpeechInput = WebBatchStreamingSpeechInput(
        audioInput: phoneMicrophoneInput,
        repository: repository,
        childAge: _config.childAge,
      );
      voiceNavigationSpeechInput = webBatchStreamingSpeechInput;
      voiceNavigationOwnsSpeechInput = true;
    } else {
      webBatchStreamingSpeechInput = null;
      voiceNavigationSpeechInput = null;
      voiceNavigationOwnsSpeechInput = false;
    }
    final voiceNavigationController =
        voiceNavigationSpeechInput != null && _config.enableVoiceNavigation
        ? VoiceNavigationController(
            speechInput: voiceNavigationSpeechInput,
            // Native speech is shared with ConversationController and released
            // explicitly by either controller before the other starts.
            ownsSpeechInput: voiceNavigationOwnsSpeechInput,
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
      initialAsrMode: supportsNativeSpeech
          ? AsrMode.androidStreaming
          : AsrMode.batchChunks,
      voiceDataProcessingAllowed: () => _voiceAccessEnabled,
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
    _nativeHfpAudioControl = nativeHfpAudioControl;
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
    final nativeStreamingSpeechInput = _nativeStreamingSpeechInput;
    if (nativeStreamingSpeechInput != null) {
      unawaited(nativeStreamingSpeechInput.prewarm());
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

  Future<bool> _activateMainAssistant({String? inputLabelOverride}) async {
    if (!_startupReady || !_voiceAccessEnabled) {
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
        inputLabelOverride: inputLabelOverride,
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
    if (!_startupReady || !_voiceAccessEnabled) {
      return MainButtonActionResult.busy;
    }
    String? inputLabelOverride;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        event.source == MainButtonSource.ble) {
      // A physical MAIN press may arrive while the H20 diagnostics sheet is
      // open. Dismiss it first so the child can see the microphone state on the
      // global MAIN button instead of listening behind an opaque modal.
      if (_isGlobalModalOpen) {
        await (_navigatorKey.currentState?.maybePop() ??
            Future<bool>.value(false));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }

      // Do not let an app-resume callback start a new BLE scan while the MAIN
      // command owns the microphone. BLE control and the already-selected HFP
      // audio route are independent links on H20, so keep both connections and
      // let IOSStreamingSpeechInput use the already-selected HFP route directly.
      _suppressH20AutoConnectUntil = DateTime.now().add(
        const Duration(seconds: 45),
      );
      final controller = _controller;
      final h20State = controller?.h20ConnectionState();
      // An idle iOS session commonly reports H20 as A2DP until recording asks
      // for the two-way HFP/SCO route. Requiring routeActive here prevented the
      // MAIN turn from ever reaching IOSStreamingSpeechInput.startAudioRoute(),
      // which is the owner responsible for activating and verifying HFP.
      // Require a selected HFP input instead. The speech input still fails the
      // turn if HFP cannot be activated and never falls back to the phone mic.
      if (h20State == null || !h20State.canStartStrictHfpTurn) {
        debugPrint(
          'H20 MAIN ignored: BLE is connected but no HFP input is selected.',
        );
        return MainButtonActionResult.busy;
      }
      inputLabelOverride = 'Mic H20 qua HFP';
    }

    // Physical BLE MAIN and the on-screen MAIN now share the same assistant and
    // microphone route. The iOS-only block above only closes diagnostics and
    // suppresses redundant BLE scans; it no longer forces a different mic.
    final activated = await _activateMainAssistant(
      inputLabelOverride: inputLabelOverride,
    );
    if (!activated && _restoreHfpAfterPhysicalMain) {
      unawaited(_restoreHfpSelectionAfterPhysicalMain());
    }
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
    if (voiceController == null) {
      return;
    }
    if (!voiceController.isMainButtonSessionActive &&
        !voiceController.isActive) {
      if (_restoreHfpAfterPhysicalMain &&
          !_mainSpeakingSessionController.isActive) {
        unawaited(_restoreHfpSelectionAfterPhysicalMain());
      }
      if (_activeModulePausedForMain && !_isActivatingMainAssistant) {
        unawaited(_resumeActiveModuleAfterMain());
      }
    }
  }

  Future<void> _restoreHfpSelectionAfterPhysicalMain() async {
    if (!_restoreHfpAfterPhysicalMain ||
        _isRestoringHfpAfterPhysicalMain ||
        !_canRestoreHfpAfterMainFlow ||
        !mounted) {
      return;
    }
    _isRestoringHfpAfterPhysicalMain = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!_canRestoreHfpAfterMainFlow) {
        return;
      }
      final controller = _controller;
      final ble = _aiv0BleControl;
      if (controller == null ||
          ble == null ||
          controller.isBusy ||
          !controller.canUseAiv0Ble) {
        return;
      }
      for (var attempt = 0; attempt < 3; attempt += 1) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (!_canRestoreHfpAfterMainFlow) {
          return;
        }
        final restored = await controller.autoConnectH20Hfp(
          bleDeviceName:
              ble.status.deviceName ?? controller.aiv0BleStatus.deviceName,
        );
        if (restored) {
          _restoreHfpAfterPhysicalMain = false;
          return;
        }
      }
    } finally {
      _isRestoringHfpAfterPhysicalMain = false;
    }
  }

  bool get _canRestoreHfpAfterMainFlow {
    final voiceController = _voiceNavigationController;
    final conversationController = _controller;
    return !_mainSpeakingSessionController.isActive &&
        !_isStartingMainSpeakingTurn &&
        !_isFinishingMainSpeakingMode &&
        !_isHandlingMainSpeakingNoSpeech &&
        !_isActivatingMainAssistant &&
        !(conversationController?.isBusy ?? false) &&
        !(conversationController?.isPlaybackPlaying ?? false) &&
        !(voiceController?.isMainButtonSessionActive ?? false) &&
        !(voiceController?.isActive ?? false);
  }

  void _synchronizePendingMainSpeakingAudioHandoff() {
    if (!_mainSpeakingSessionController.isActive &&
        _restoreHfpAfterPhysicalMain) {
      unawaited(_restoreHfpSelectionAfterPhysicalMain());
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
      if (_restoreHfpAfterPhysicalMain) {
        unawaited(_restoreHfpSelectionAfterPhysicalMain());
      }
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
    if (!_voiceAccessEnabled) {
      return;
    }
    _hasMainSpeakingTurnStarted = false;
    _isHandlingMainSpeakingNoSpeech = false;
    _mainSpeakingSessionController.enter();
    _synchronizeMainSpeakingSession();
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
      if (!_mainSpeakingSessionController.isActive &&
          _restoreHfpAfterPhysicalMain) {
        unawaited(_restoreHfpSelectionAfterPhysicalMain());
      }
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
    var recordingStarted = false;
    try {
      await controller.startRecording(
        noSpeechTimeout: const Duration(seconds: 6),
        speakNoSpeechPrompt: false,
      );
      recordingStarted = controller.isRecording;

      _hasMainSpeakingTurnStarted = recordingStarted;
    } finally {
      _isStartingMainSpeakingTurn = false;
    }

    if (!recordingStarted && _mainSpeakingSessionController.isActive) {
      await _finishMainSpeakingMode(
        sayGoodbye: true,
        goodbyeText:
            'Cô chưa mở được micro để dịch liên tục. Con kiểm tra quyền micro rồi thử lại nhé.',
      );
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
      if (_restoreHfpAfterPhysicalMain) {
        unawaited(_restoreHfpSelectionAfterPhysicalMain());
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
    controller.clearMessage();
    if (mounted) {
      setState(() => _isActivatingMainAssistant = true);
    }
    try {
      // A stop command only ends hands-free translation. Requests to learn
      // something else reopen the normal MAIN routing menu.
      if (command == MainSpeakingCommand.stop && isContinuousSpeaking) {
        await controller.speakAssistantPrompt('Đã dừng dịch liên tục.');
      } else {
        await voiceController.activateOtherLearningFromSpeaking();
      }
    } finally {
      _isFinishingMainSpeakingMode = false;
      if (mounted) {
        setState(() => _isActivatingMainAssistant = false);
      }
      if (command == MainSpeakingCommand.stop &&
          isContinuousSpeaking &&
          _restoreHfpAfterPhysicalMain) {
        unawaited(_restoreHfpSelectionAfterPhysicalMain());
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
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_synchronizeMainSpeakingSession);
    _mainSpeakingSessionController.removeListener(
      _synchronizePendingMainSpeakingAudioHandoff,
    );
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
      title: 'HOMI App',
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
                  _startupReady &&
                  _voiceAccessEnabled)
                Positioned(
                  right: 16,
                  bottom: 0,
                  child: SafeArea(
                    minimum: const EdgeInsets.only(bottom: 88),
                    child: MainVoiceAssistantButton(
                      voiceController: voiceController,
                      conversationController: controller,
                      speakingSessionController: _mainSpeakingSessionController,
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
                  onModalVisibilityChanged: _setGlobalModalOpen,
                  privacyConsentGranted: _privacyConsentGranted,
                  voiceAccessEnabled: _voiceAccessEnabled,
                  onRequestVoiceAccess: () =>
                      unawaited(_requestStartupPermissions()),
                  onManagePrivacyConsent: () => unawaited(_showPrivacySetup()),
                  onRevokePrivacyConsent: _revokePrivacyConsent,
                ),
              ),
            )
          : StartupSetupScreen(
              profileLoading: _startupProfileLoading,
              permissionRequestInProgress: _startupPermissionRequestInProgress,
              privacyConfigurationComplete:
                  _config.privacyReleaseConfigurationComplete,
              privacyConsentGranted: _privacyConsentGranted,
              microphoneGranted: _microphonePermissionGranted,
              bluetoothRequired: _bluetoothPermissionRequired,
              bluetoothGranted: _bluetoothPermissionGranted,
              selectedAge: _pendingStartupAge,
              aiSubprocessors: _config.disclosedAiSubprocessors,
              dataRetentionSummary: _config.disclosedDataRetention,
              privacyPolicyUri: _config.privacyPolicyUri,
              termsUri: _config.termsUri,
              supportUri: _config.supportUri,
              permissionError: _startupPermissionError,
              onGrantPrivacyConsent: _grantPrivacyConsent,
              onContinueWithoutVoice: _continueWithoutVoice,
              onRetryPermissions: () => unawaited(_requestStartupPermissions()),
              onAgeSelected: (age) => setState(() => _pendingStartupAge = age),
              onConfirmAge: _confirmStartupAge,
            ),
    );
  }
}
