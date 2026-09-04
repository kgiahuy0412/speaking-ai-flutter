import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../config/app_config.dart';
import '../../../l10n/display_language.dart';
import '../../../core/platform/background_learning_session.dart';
import '../../../core/platform/platform_access_policy.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../../conversation/presentation/conversation_screen.dart';
import '../../listening/application/listening_voice_navigation_target.dart';
import '../../listening/domain/listening_content.dart';
import '../../listening/presentation/listening_route_names.dart';
import '../../listening/presentation/topic_listening_screen.dart';
import '../../onboarding/application/onboarding_progress_store.dart';
import '../../onboarding/presentation/user_onboarding_tour.dart';
import '../../privacy/presentation/parental_gate.dart';
import '../../settings/presentation/history_sheet.dart';
import '../../settings/presentation/settings_sheet.dart';
import '../../vocabulary/domain/vocabulary_entry.dart';
import '../../vocabulary/presentation/vocabulary_home_screen.dart';
import '../../voice_navigation/application/voice_navigation_controller.dart';
import '../../voice_navigation/application/voice_navigation_intent_resolver.dart';
import 'home_mode_rail.dart';

class HomeLearningShell extends StatefulWidget {
  const HomeLearningShell({
    required this.controller,
    required this.config,
    this.voiceNavigationController,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.onChildAgeChanged,
    this.onMainSpeakingModeStarted,
    this.onModalVisibilityChanged,
    this.privacyConsentGranted = false,
    this.voiceAccessEnabled = true,
    this.onRequestVoiceAccess,
    this.onManagePrivacyConsent,
    this.onRevokePrivacyConsent,
    this.onboardingStore,
    this.listeningContentFuture,
    this.parentAccessGate,
    this.backgroundLearningSession,
    super.key,
  });

  final ConversationController controller;
  final AppConfig config;
  final VoiceNavigationController? voiceNavigationController;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<int>? onChildAgeChanged;
  final VoidCallback? onMainSpeakingModeStarted;
  final ValueChanged<bool>? onModalVisibilityChanged;
  final bool privacyConsentGranted;
  final bool voiceAccessEnabled;
  final VoidCallback? onRequestVoiceAccess;
  final VoidCallback? onManagePrivacyConsent;
  final Future<void> Function()? onRevokePrivacyConsent;
  final OnboardingProgressStore? onboardingStore;
  final Future<ListeningContentCatalog>? listeningContentFuture;
  final Future<bool> Function(BuildContext context)? parentAccessGate;
  final BackgroundLearningSessionControl? backgroundLearningSession;

  @override
  State<HomeLearningShell> createState() => _HomeLearningShellState();
}

class _HomeLearningShellState extends State<HomeLearningShell>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  int _page = 0;
  bool _openingTopics = false;
  Completer<void>? _topicRouteClosedCompleter;
  bool _tutorialActive = false;
  int _tutorialStep = 0;
  Timer? _voiceNavigationRestartTimer;
  late AppLifecycleState _appLifecycleState;
  bool _voiceNavigationPausedForOverlay = false;
  bool _voiceNavigationHelpShown = false;
  int? _activeVoiceTopicIndex;
  late final BackgroundLearningSessionControl _backgroundLearningSession;
  StreamSubscription<BackgroundLearningEvent>? _backgroundLearningSubscription;
  bool _backgroundLearningActive = false;
  bool _startingBackgroundLearning = false;

  final GlobalKey _speakActionKey = GlobalKey(
    debugLabel: 'onboarding-speak-action',
  );
  final GlobalKey _resultPanelKey = GlobalKey(
    debugLabel: 'onboarding-result-panel',
  );
  final GlobalKey _vocabularyTabKey = GlobalKey(
    debugLabel: 'onboarding-vocabulary-tab',
  );
  final GlobalKey _topicTabKey = GlobalKey(debugLabel: 'onboarding-topic-tab');
  final GlobalKey _historyButtonKey = GlobalKey(
    debugLabel: 'onboarding-history-button',
  );
  final GlobalKey _settingsButtonKey = GlobalKey(
    debugLabel: 'onboarding-settings-button',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appLifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _pageController = PageController();
    _backgroundLearningSession =
        widget.backgroundLearningSession ??
        MethodChannelBackgroundLearningSession();
    _attachVoiceNavigationHandler();
    widget.controller.addListener(_onConversationControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureBackgroundLearningStarted());
      _scheduleVoiceNavigationListening(
        delay: const Duration(milliseconds: 450),
      );
    });
    if (widget.onboardingStore != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showTutorialOnFirstUse());
      });
    }
  }

  @override
  void didUpdateWidget(HomeLearningShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onConversationControllerChanged);
      widget.controller.addListener(_onConversationControllerChanged);
    }
    if (oldWidget.voiceNavigationController !=
        widget.voiceNavigationController) {
      oldWidget.voiceNavigationController?.setIntentHandler(null);
      unawaited(oldWidget.voiceNavigationController?.pause());
      _attachVoiceNavigationHandler();
    }
    if (oldWidget.config.enableVoiceNavigation !=
            widget.config.enableVoiceNavigation ||
        oldWidget.config.autoStartVoiceNavigation !=
            widget.config.autoStartVoiceNavigation) {
      _attachVoiceNavigationHandler();
      if (_continuousVoiceNavigationEnabled) {
        _scheduleVoiceNavigationListening();
      } else {
        _voiceNavigationRestartTimer?.cancel();
        unawaited(widget.voiceNavigationController?.pause());
      }
    }
    if (oldWidget.voiceAccessEnabled != widget.voiceAccessEnabled) {
      if (widget.voiceAccessEnabled) {
        unawaited(_ensureBackgroundLearningStarted());
      } else {
        _backgroundLearningActive = false;
        unawaited(_backgroundLearningSession.stop());
        unawaited(widget.voiceNavigationController?.pause());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceNavigationRestartTimer?.cancel();
    widget.controller.removeListener(_onConversationControllerChanged);
    widget.voiceNavigationController?.setIntentHandler(null);
    unawaited(widget.voiceNavigationController?.pause());
    unawaited(_backgroundLearningSubscription?.cancel());
    unawaited(_backgroundLearningSession.stop());
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      unawaited(_ensureBackgroundLearningStarted());
      _scheduleVoiceNavigationListening();
      return;
    }
    if (state == AppLifecycleState.detached) {
      _backgroundLearningActive = false;
      unawaited(_backgroundLearningSession.stop());
    } else if (_backgroundLearningActive && widget.voiceAccessEnabled) {
      // Android's foreground service and iOS audio/BLE background modes own
      // this deliberate learning session. Keep an already-running recognizer
      // alive while the screen is locked or a silent app covers HOMI.
      _scheduleVoiceNavigationListening();
      return;
    }
    _voiceNavigationRestartTimer?.cancel();
    unawaited(widget.voiceNavigationController?.pause());
  }

  Future<void> _ensureBackgroundLearningStarted() async {
    if (!mounted ||
        !widget.voiceAccessEnabled ||
        _backgroundLearningActive ||
        _startingBackgroundLearning ||
        kIsWeb) {
      return;
    }
    _startingBackgroundLearning = true;
    final active = await _backgroundLearningSession.start();
    _startingBackgroundLearning = false;
    if (!mounted) {
      if (active) {
        await _backgroundLearningSession.stop();
      }
      return;
    }
    _backgroundLearningActive = active;
    if (active) {
      _backgroundLearningSubscription ??= _backgroundLearningSession.events
          .listen(_handleBackgroundLearningEvent);
      _scheduleVoiceNavigationListening();
    }
  }

  void _handleBackgroundLearningEvent(BackgroundLearningEvent event) {
    if (!mounted) return;
    _backgroundLearningActive = false;
    _voiceNavigationRestartTimer?.cancel();
    unawaited(widget.voiceNavigationController?.pause());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return DisplayLanguageScope(
          language: widget.controller.displayLanguage,
          child: PopScope<void>(
            canPop: _page == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _page == 1) {
                _showConversation();
              }
            },
            child: Stack(
              children: <Widget>[
                PageView(
                  key: const Key('home-learning-page-view'),
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) => setState(() => _page = page),
                  children: <Widget>[
                    ConversationScreen(
                      controller: widget.controller,
                      config: widget.config,
                      themeMode: widget.themeMode,
                      onThemeModeChanged: widget.onThemeModeChanged,
                      onChildAgeChanged: widget.onChildAgeChanged,
                      onStartTutorial: _startTutorial,
                      speakActionKey: _speakActionKey,
                      resultPanelKey: _resultPanelKey,
                      historyButtonKey: _historyButtonKey,
                      settingsButtonKey: _settingsButtonKey,
                      onModalVisibilityChanged: widget.onModalVisibilityChanged,
                      privacyConsentGranted: widget.privacyConsentGranted,
                      voiceAccessEnabled: widget.voiceAccessEnabled,
                      onRequestVoiceAccess: widget.onRequestVoiceAccess,
                      onManagePrivacyConsent: widget.onManagePrivacyConsent,
                      onRevokePrivacyConsent: widget.onRevokePrivacyConsent,
                      onOpenHistory: _showHistory,
                      onOpenSettings: _showSettings,
                    ),
                    VocabularyHomeScreen(
                      isReady: widget.controller.isInputAvailable,
                      isActive: _page == 1,
                      translator: (input) async {
                        final translation = await widget.controller
                            .translateVocabulary(input);
                        return VocabularyTranslation(
                          englishText: translation.englishText,
                          vietnameseText: translation.vietnameseText,
                        );
                      },
                      onReturnToConversation: _showConversation,
                      onHistory: _showHistory,
                      onSettings: _showSettings,
                    ),
                  ],
                ),
                Align(
                  alignment: const Alignment(-1, -0.20),
                  child: KeyedSubtree(
                    key: _vocabularyTabKey,
                    child: HomeModeRail(
                      key: const Key('vocabulary-edge-tab'),
                      edge: HomeRailEdge.left,
                      label: _page == 0
                          ? context.tr('Từ vựng', '词汇')
                          : context.tr('Giao tiếp', '沟通'),
                      icon: _page == 0
                          ? Icons.chat_bubble_rounded
                          : Icons.mic_rounded,
                      color: AppColors.indigo,
                      onPressed: _page == 0
                          ? _showVocabulary
                          : _showConversation,
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(1, -0.05),
                  child: KeyedSubtree(
                    key: _topicTabKey,
                    child: HomeModeRail(
                      key: const Key('topic-listening-edge-tab'),
                      edge: HomeRailEdge.right,
                      label: context.tr('Chủ đề', '主题'),
                      icon: Icons.headphones_rounded,
                      color: const Color(0xFF7443D8),
                      onPressed: _openTopicListening,
                    ),
                  ),
                ),
                if (_tutorialActive)
                  Positioned.fill(
                    child: UserOnboardingTour(
                      steps: _tutorialSteps,
                      currentIndex: _tutorialStep,
                      onPrevious: _tutorialStep == 0
                          ? null
                          : _previousTutorialStep,
                      onNext: _nextTutorialStep,
                      onSkip: _skipTutorial,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Duration get _motionDuration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 420);

  void _attachVoiceNavigationHandler() {
    widget.voiceNavigationController?.setIntentHandler(
      widget.config.enableVoiceNavigation ? _handleVoiceNavigationIntent : null,
    );
  }

  bool get _continuousVoiceNavigationEnabled =>
      widget.config.enableVoiceNavigation &&
      widget.config.autoStartVoiceNavigation &&
      widget.voiceAccessEnabled &&
      widget.voiceNavigationController != null &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  bool get _canStartVoiceNavigationListening =>
      mounted &&
      _continuousVoiceNavigationEnabled &&
      (_appLifecycleState == AppLifecycleState.resumed ||
          (_backgroundLearningActive &&
              _appLifecycleState != AppLifecycleState.detached)) &&
      !_voiceNavigationPausedForOverlay &&
      !_tutorialActive &&
      !widget.controller.isBusy &&
      !widget.controller.isPlaybackPlaying &&
      widget.controller.isInputAvailable;

  void _onConversationControllerChanged() {
    // This listener owns Android's optional, always-on wake-word session only.
    // iOS uses the same VoiceNavigationController for an explicit MAIN turn.
    // Pausing when continuous navigation is disabled therefore cancelled an
    // iOS MAIN turn whenever BLE/HFP diagnostics notified the conversation
    // controller -- often only a few milliseconds after beginMainTurn().
    if (!_continuousVoiceNavigationEnabled) {
      _voiceNavigationRestartTimer?.cancel();
      return;
    }
    if (widget.controller.isBusy || widget.controller.isPlaybackPlaying) {
      _voiceNavigationRestartTimer?.cancel();
      unawaited(widget.voiceNavigationController?.pause());
      return;
    }
    _scheduleVoiceNavigationListening();
  }

  void _scheduleVoiceNavigationListening({
    Duration delay = const Duration(milliseconds: 300),
  }) {
    _voiceNavigationRestartTimer?.cancel();
    if (!_canStartVoiceNavigationListening) {
      return;
    }
    _voiceNavigationRestartTimer = Timer(delay, () {
      _voiceNavigationRestartTimer = null;
      _startVoiceNavigationListening();
    });
  }

  void _startVoiceNavigationListening() {
    if (!_canStartVoiceNavigationListening) {
      return;
    }
    if (!_voiceNavigationHelpShown) {
      _voiceNavigationHelpShown = true;
      _showVoiceNavigationMessage(
        widget.controller.displayLanguage == DisplayLanguage.simplifiedChinese
            ? '请先说：“Hey HOMI”，听到回应后再说想打开的功能。'
            : 'Hãy nói “Hey HOMI”. Khi HOMI trả lời, bạn hãy nói chức năng muốn mở.',
      );
    }
    widget.voiceNavigationController?.startContinuous();
  }

  Future<void> _pauseVoiceNavigation(String reason) async {
    _voiceNavigationPausedForOverlay = true;
    _voiceNavigationRestartTimer?.cancel();
    await widget.voiceNavigationController?.pause();
  }

  void _resumeVoiceNavigation() {
    _voiceNavigationPausedForOverlay = false;
    _scheduleVoiceNavigationListening();
  }

  Future<void> _handleVoiceNavigationIntent(
    VoiceNavigationIntent intent,
  ) async {
    if (!mounted || _tutorialActive) {
      return;
    }
    await _executeVoiceNavigation(intent);
  }

  Future<void> _executeVoiceNavigation(VoiceNavigationIntent intent) async {
    final useChinese =
        widget.controller.displayLanguage == DisplayLanguage.simplifiedChinese;
    final destinationLabel = intent.openLesson
        ? useChinese
              ? '第 ${intent.lessonNumber ?? 1} 课'
              : 'Bài ${intent.lessonNumber ?? 1}'
        : switch (intent.destination) {
            VoiceNavigationDestination.conversation =>
              useChinese ? '沟通' : 'Giao tiếp',
            VoiceNavigationDestination.vocabulary =>
              useChinese ? '词汇' : 'Từ vựng',
            VoiceNavigationDestination.topics => useChinese ? '主题' : 'Chủ đề',
            VoiceNavigationDestination.history =>
              useChinese ? '历史记录' : 'Lịch sử',
            VoiceNavigationDestination.settings =>
              useChinese ? '设置' : 'Cài đặt',
          };
    if (intent.destination != VoiceNavigationDestination.topics) {
      await _closeTopicListeningIfNeeded();
      if (!mounted) {
        return;
      }
    }
    _showVoiceNavigationMessage(
      useChinese
          ? '已识别语音指令，正在打开$destinationLabel。'
          : 'Đã nhận lệnh giọng nói. Đang mở $destinationLabel.',
    );

    switch (intent.destination) {
      case VoiceNavigationDestination.conversation:
        _showConversation();
        if (intent.enterMainSpeakingMode) {
          widget.onMainSpeakingModeStarted?.call();
        }
      case VoiceNavigationDestination.vocabulary:
        _showVocabulary();
      case VoiceNavigationDestination.topics:
        final fallbackTopicIndex = _activeVoiceTopicIndex;
        final target = ListeningVoiceNavigationTarget(
          recognizedText: intent.recognizedText,
          openLesson: intent.openLesson,
          topicNumber: intent.topicNumber,
          lessonNumber: intent.lessonNumber,
          childAge: intent.childAge,
          fallbackTopicIndex: fallbackTopicIndex,
        );
        if (_openingTopics) {
          await _closeTopicListeningIfNeeded();
        }
        if (mounted) {
          unawaited(_openTopicListening(initialVoiceTarget: target));
        }
      case VoiceNavigationDestination.history:
        _showHistory();
      case VoiceNavigationDestination.settings:
        _showSettings();
    }
  }

  Future<void> _closeTopicListeningIfNeeded() async {
    if (!_openingTopics || !mounted) {
      return;
    }
    final closed = _topicRouteClosedCompleter?.future;
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (closed != null) {
      await closed;
    }
  }

  void _showVoiceNavigationMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<UserOnboardingStep> get _tutorialSteps => <UserOnboardingStep>[
    UserOnboardingStep(
      kind: UserOnboardingStepKind.welcome,
      title: context.tr('Chào mừng đến với HOMI', '欢迎使用 HOMI'),
      description: context.tr(
        'Mình sẽ chỉ cho bạn những khu vực quan trọng để bắt đầu học thật dễ dàng.',
        '接下来带你快速认识几个重要功能，轻松开始学习。',
      ),
      icon: Icons.waving_hand_rounded,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: context.tr('Bắt đầu nói', '开始说话'),
      description: context.tr(
        'Chạm nút micro, nói một câu tiếng Việt và HOMI sẽ giúp chuyển sang tiếng Anh.',
        '点击麦克风，说一句越南语，HOMI 会帮你转换成英语。',
      ),
      icon: Icons.mic_rounded,
      targetKey: _speakActionKey,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: context.tr('Xem và nghe kết quả', '查看并收听结果'),
      description: context.tr(
        'Câu tiếng Việt, bản dịch tiếng Anh và nút nghe lại đều xuất hiện trong khu vực này.',
        '越南语原句、英语翻译和重播按钮都会显示在这里。',
      ),
      icon: Icons.translate_rounded,
      targetKey: _resultPanelKey,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: context.tr('Học từ vựng', '学习词汇'),
      description: context.tr(
        'Mở kho từ vựng để lưu từ mới, nghe phát âm và luyện tập lại bất cứ lúc nào.',
        '打开词汇库，保存新词、收听发音，并随时复习。',
      ),
      icon: Icons.chat_bubble_rounded,
      targetKey: _vocabularyTabKey,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: context.tr('Luyện nghe theo chủ đề', '主题听力练习'),
      description: context.tr(
        'Chọn chủ đề phù hợp với độ tuổi để học câu mẫu, luyện nói và nghe bài hát.',
        '选择适合年龄的主题，学习例句、练习口语并听儿歌。',
      ),
      icon: Icons.headphones_rounded,
      targetKey: _topicTabKey,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: context.tr('Xem lại lịch sử', '查看历史记录'),
      description: context.tr(
        'Những câu đã luyện gần đây được lưu ở đây để bạn có thể xem và nghe lại.',
        '最近练习过的句子会保存在这里，方便查看和重听。',
      ),
      icon: Icons.history_rounded,
      targetKey: _historyButtonKey,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.spotlight,
      title: context.tr('Micro và thiết bị INNOTRIK', '麦克风和 INNOTRIK 设备'),
      description: context.tr(
        'Bạn vẫn dùng được micro hiện tại. Mở Cài đặt khi cần đổi giao diện, ngôn ngữ hoặc kết nối micro INNOTRIK qua HFP.',
        '你可以继续使用当前麦克风；需要切换主题、语言或通过 HFP 连接 INNOTRIK 麦克风时，请打开设置。',
      ),
      icon: Icons.settings_outlined,
      targetKey: _settingsButtonKey,
    ),
    UserOnboardingStep(
      kind: UserOnboardingStepKind.complete,
      title: context.tr('Bạn đã sẵn sàng!', '你已经准备好了！'),
      description: context.tr(
        'Hãy thử nói một câu tiếng Việt để bắt đầu nhé.',
        '现在说一句越南语开始体验吧。',
      ),
      icon: Icons.celebration_rounded,
    ),
  ];

  Future<void> _showTutorialOnFirstUse() async {
    final store = widget.onboardingStore;
    if (store == null) {
      return;
    }
    try {
      final shouldShow = await store.shouldShow();
      if (!shouldShow || !mounted) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (mounted) {
        _startTutorial();
      }
    } catch (error, stackTrace) {
      debugPrint('Could not read onboarding progress: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _startTutorial() {
    if (!mounted || _tutorialActive) {
      return;
    }
    unawaited(_pauseVoiceNavigation('onboarding_tutorial'));
    if (_page != 0 && _pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    setState(() {
      _page = 0;
      _tutorialStep = 0;
      _tutorialActive = true;
    });
  }

  void _previousTutorialStep() {
    if (!_tutorialActive || _tutorialStep <= 0) {
      return;
    }
    setState(() => _tutorialStep -= 1);
    _revealCurrentTutorialTarget();
  }

  void _nextTutorialStep() {
    if (!_tutorialActive) {
      return;
    }
    if (_tutorialStep < _tutorialSteps.length - 1) {
      setState(() => _tutorialStep += 1);
      _revealCurrentTutorialTarget();
      return;
    }
    unawaited(_finishTutorial(startSpeaking: true));
  }

  void _skipTutorial() => unawaited(_finishTutorial());

  void _revealCurrentTutorialTarget() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tutorialActive) {
        return;
      }
      final targetContext =
          _tutorialSteps[_tutorialStep].targetKey?.currentContext;
      if (targetContext != null) {
        unawaited(
          Scrollable.ensureVisible(
            targetContext,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: 0.5,
          ),
        );
      }
    });
  }

  Future<void> _finishTutorial({bool startSpeaking = false}) async {
    if (mounted) {
      setState(() {
        _tutorialActive = false;
        _tutorialStep = 0;
      });
    }
    if (startSpeaking) {
      unawaited(widget.controller.onPrimaryAction());
    }
    _resumeVoiceNavigation();
    final store = widget.onboardingStore;
    if (store == null) {
      return;
    }
    try {
      await store.markSeen();
    } catch (error, stackTrace) {
      debugPrint('Could not save onboarding progress: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _showVocabulary() {
    _pageController.animateToPage(
      1,
      duration: _motionDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _showConversation() {
    _pageController.animateToPage(
      0,
      duration: _motionDuration,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openTopicListening({
    ListeningVoiceNavigationTarget? initialVoiceTarget,
  }) async {
    if (_openingTopics) {
      return;
    }
    _openingTopics = true;
    final routeClosedCompleter = Completer<void>();
    _topicRouteClosedCompleter = routeClosedCompleter;
    try {
      if (!mounted) {
        return;
      }
      final routeDuration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260);
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          settings: const RouteSettings(name: ListeningRouteNames.topicCatalog),
          transitionDuration: routeDuration,
          reverseTransitionDuration: routeDuration,
          pageBuilder: (_, _, _) => TopicListeningScreen(
            language: widget.controller.displayLanguage,
            childAge: widget.controller.childAge,
            controller: widget.controller,
            onVoiceNavigationPause: () =>
                _pauseVoiceNavigation('listening_media_opened'),
            onVoiceNavigationResume: _resumeVoiceNavigation,
            initialVoiceTarget: initialVoiceTarget,
            onTopicSelected: (index) => _activeVoiceTopicIndex = index,
            onChildAgeChanged: widget.onChildAgeChanged,
            onRequestParentAccess: _requestParentAccess,
            onLessonSelectionRequested:
                ({
                  required childAge,
                  required topicNumber,
                  required topicContent,
                  required completedLessonNumbers,
                }) async {
                  await widget.voiceNavigationController
                      ?.activateLessonSelectionForTopic(
                        childAge: childAge,
                        topicNumber: topicNumber,
                        topicContent: topicContent,
                        completedLessonNumbers: completedLessonNumbers,
                      );
                },
            onTopicSelectionAfterCompletion:
                ({required childAge, required completedTopicNumbers}) async {
                  await widget.voiceNavigationController
                      ?.activateTopicSelectionAfterCompletion(
                        childAge: childAge,
                        completedTopicNumbers: completedTopicNumbers,
                      );
                },
            contentFuture: widget.listeningContentFuture,
          ),
          transitionsBuilder: (_, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: child),
            );
          },
        ),
      );
    } finally {
      _openingTopics = false;
      _activeVoiceTopicIndex = null;
      if (identical(_topicRouteClosedCompleter, routeClosedCompleter)) {
        _topicRouteClosedCompleter = null;
      }
      if (!routeClosedCompleter.isCompleted) {
        routeClosedCompleter.complete();
      }
      if (mounted) {
        _resumeVoiceNavigation();
      }
    }
  }

  void _showSettings() {
    unawaited(_openParentSettings());
  }

  Future<void> _openParentSettings() async {
    if (!await _requestSettingsAccess()) {
      return;
    }
    await _pauseVoiceNavigation('settings_opened');
    await _openSettingsSheet();
  }

  Future<bool> _requestSettingsAccess() {
    final gate = widget.parentAccessGate;
    if (gate != null) {
      return gate(context);
    }
    if (PlatformAccessPolicy.bypassesSettingsAuthentication(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      return Future<bool>.value(true);
    }
    return showParentalGate(context);
  }

  Future<void> _openSettingsSheet() async {
    await widget.controller.markParentDiagnosticsOpened();
    if (!mounted) return;
    widget.onModalVisibilityChanged?.call(true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => SettingsSheet(
          controller: widget.controller,
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          onChildAgeChanged: widget.onChildAgeChanged,
          onStartTutorial: _startTutorial,
          config: widget.config,
          privacyConsentGranted: widget.privacyConsentGranted,
          voiceAccessEnabled: widget.voiceAccessEnabled,
          onRequestVoiceAccess: widget.onRequestVoiceAccess,
          onManagePrivacyConsent: widget.onManagePrivacyConsent,
          onRevokePrivacyConsent: widget.onRevokePrivacyConsent,
        ),
      );
    } finally {
      widget.onModalVisibilityChanged?.call(false);
    }
    if (mounted && !_tutorialActive) {
      _resumeVoiceNavigation();
    }
  }

  void _showHistory() {
    unawaited(_openParentHistory());
  }

  Future<void> _openParentHistory() async {
    if (!await _requestParentAccess()) {
      return;
    }
    await _pauseVoiceNavigation('history_opened');
    await _openHistorySheet();
  }

  Future<bool> _requestParentAccess() {
    final gate = widget.parentAccessGate;
    return gate == null ? showParentalGate(context) : gate(context);
  }

  Future<void> _openHistorySheet() async {
    widget.onModalVisibilityChanged?.call(true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => HistorySheet(controller: widget.controller),
      );
    } finally {
      widget.onModalVisibilityChanged?.call(false);
    }
    if (mounted) {
      _resumeVoiceNavigation();
    }
  }
}
