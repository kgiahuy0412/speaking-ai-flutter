import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/homi_ui.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../core/audio/streaming_speech_input.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/device/active_learning_module.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../../vocabulary/data/vocabulary_store.dart';
import '../../vocabulary/domain/vocabulary_entry.dart';
import '../application/lesson_attempt_evaluator.dart';
import '../application/lesson_guide_audio_library.dart';
import '../application/lesson_completion_choice_recognizer.dart';
import '../application/lesson_media_service.dart';
import '../data/active_listening_session_store.dart';
import '../data/listening_progress_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import '../domain/authored_question_selector.dart';
import '../domain/lesson_guide_flow.dart';
import '../domain/v4_completion_flow.dart';
import 'active_learning_navigation.dart';
import 'lesson_challenge_screen.dart';
import 'lesson_mission_screen.dart';
import 'lesson_intro_screen.dart';
import 'lesson_recording_history_sheet.dart';
import 'lesson_review_screen.dart';
import 'listening_navigation_bar.dart';
import 'listening_route_names.dart';
import 'v4_song_stage_screen.dart';

class LessonPracticeScreen extends StatefulWidget {
  const LessonPracticeScreen({
    required this.language,
    required this.startAge,
    required this.endAge,
    required this.topic,
    required this.lesson,
    required this.progressStore,
    required this.mediaService,
    this.vocabularyStore = const VocabularyStore(),
    this.controller,
    this.guideAudioLibrary,
    this.attemptEvaluator,
    this.completionChoiceRecognizer,
    this.voicePromptService,
    this.topicContent,
    this.contentGroup,
    this.levelContent,
    this.initialResumeStage = ListeningResumeStage.core,
    this.isRelearn = false,
    this.onTopicCompleted,
    super.key,
  });

  final DisplayLanguage language;
  final int startAge;
  final int endAge;
  final ListeningTopic topic;
  final ListeningLessonContent lesson;
  final ConversationController? controller;
  final ListeningProgressStore progressStore;
  final LessonMediaService mediaService;
  final VocabularyStore vocabularyStore;
  final LessonGuideAudioLibrary? guideAudioLibrary;
  final LessonAttemptEvaluator? attemptEvaluator;
  final LessonCompletionChoiceRecognizer? completionChoiceRecognizer;
  final VoicePromptService? voicePromptService;
  final ListeningTopicContent? topicContent;
  final ListeningContentAgeGroup? contentGroup;
  final ListeningLevelContent? levelContent;
  final ListeningResumeStage initialResumeStage;
  final bool isRelearn;
  final VoidCallback? onTopicCompleted;

  @override
  State<LessonPracticeScreen> createState() => _LessonPracticeScreenState();
}

class _LessonPracticeScreenState extends State<LessonPracticeScreen>
    implements ActiveLearningModuleController {
  static const Duration _mainPauseCleanupTimeout = Duration(seconds: 2);
  static int _v4ChallengeCounter = 0;
  static int _v4MissionCounter = 0;
  static final Map<String, List<String>> _previousV4ChallengeIds =
      <String, List<String>>{};
  int _sentenceIndex = 0;
  bool _recording = false;
  bool _mediaBusy = false;
  bool _evaluatingAttempt = false;
  String? _recordingPath;
  Duration? _recordingDuration;
  String? _message;
  bool _showSkip = false;
  _LessonCoachPopupKind? _coachPopupKind;
  final Set<int> _skippedSentenceIndexes = <int>{};
  final Set<int> _needsPracticeSentenceIndexes = <int>{};
  Timer? _idleReminderTimer;
  Timer? _coachPopupTimer;
  Timer? _praiseFireworksTimer;
  Timer? _recordingAutoStopTimer;
  late final LessonGuideAudioLibrary _guideAudioLibrary;
  late final LessonAttemptEvaluator _attemptEvaluator;
  late final bool _ownsAttemptEvaluator;
  late final VoicePromptService _voicePromptService;
  late final LessonCompletionChoiceRecognizer _completionChoiceRecognizer;
  late final bool _ownsVoicePromptService;
  bool _ownedVoicePromptReleased = false;
  late final bool _ownsCompletionChoiceRecognizer;
  int _attemptNumber = 1;
  bool _guidedSequenceStarted = false;
  bool _recordingStartPending = false;
  Future<void>? _recordingDeviceStartInProgress;
  int _recordingStartRequest = 0;
  int _praiseFireworksSequence = 0;
  bool _praiseFireworksVisible = false;
  bool _handingOffMediaPlayback = false;
  bool _completionChoiceRecording = false;
  bool _completionChoiceStopping = false;
  bool _pausedForMainAssistant = false;
  bool _virtualCommandPending = false;
  int _newStarsThisLesson = 0;
  bool _v4CompletionChoiceVisible = false;
  V4CompletionStage? _activeV4CompletionStage;
  List<V4CompletionAction> _activeV4CompletionActions =
      const <V4CompletionAction>[];
  int _completionChoiceGeneration = 0;
  int _mainPauseGeneration = 0;
  int _recordingLifecycleGeneration = 0;
  int _attemptEvaluationRequest = 0;
  ActiveLearningModuleRegistry? _activeModuleRegistry;
  Object? _activeModuleRegistration;

  ListeningSentenceContent get _sentence =>
      widget.lesson.sentences[_sentenceIndex];

  bool get _usesGuideV2 => widget.lesson.usesGuidedPractice;

  LessonGuidePrompt get _repeatTargetPrompt => widget.lesson.usesV4Flow
      ? LessonGuideFlowV2.repeatTarget
      : LessonGuideFlowV2.afterSample;

  IOSStreamingSpeechInput? get _iosLessonSpeechInput =>
      widget.controller?.iosLessonSpeechInput;

  bool get _usesIosNativeLessonRecognition =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      _usesGuideV2 &&
      _ownsAttemptEvaluator &&
      _iosLessonSpeechInput != null;

  @override
  ActiveLearningModuleKind get moduleKind =>
      ActiveLearningModuleKind.listeningLesson;

  @override
  bool get isPausedForMain => _pausedForMainAssistant;

  @override
  void initState() {
    super.initState();
    _guideAudioLibrary = widget.guideAudioLibrary ?? LessonGuideAudioLibrary();
    _ownsAttemptEvaluator = widget.attemptEvaluator == null;
    _attemptEvaluator =
        widget.attemptEvaluator ?? createDefaultLessonAttemptEvaluator();
    _ownsVoicePromptService = widget.voicePromptService == null;
    _voicePromptService =
        widget.voicePromptService ?? createVoicePromptService();
    _ownsCompletionChoiceRecognizer = widget.completionChoiceRecognizer == null;
    _completionChoiceRecognizer =
        widget.completionChoiceRecognizer ??
        BackendLessonCompletionChoiceRecognizer();
    unawaited(_loadStartingPoint());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = ActiveLearningModuleScope.maybeOf(context);
    if (identical(registry, _activeModuleRegistry)) {
      return;
    }
    final oldRegistry = _activeModuleRegistry;
    final oldRegistration = _activeModuleRegistration;
    if (oldRegistry != null && oldRegistration != null) {
      oldRegistry.unregister(oldRegistration);
    }
    _activeModuleRegistry = registry;
    _activeModuleRegistration = registry?.register(this);
  }

  @override
  void dispose() {
    final registration = _activeModuleRegistration;
    if (registration != null) {
      _activeModuleRegistry?.unregister(registration);
    }
    _recordingStartRequest += 1;
    _recordingLifecycleGeneration += 1;
    _attemptEvaluationRequest += 1;
    _completionChoiceGeneration += 1;
    _cancelIdleReminder();
    _coachPopupTimer?.cancel();
    _praiseFireworksTimer?.cancel();
    _recordingAutoStopTimer?.cancel();
    if (_recording) {
      if (_usesIosNativeLessonRecognition && !_completionChoiceRecording) {
        unawaited(_iosLessonSpeechInput!.cancel());
      } else {
        widget.mediaService.cancelRecording();
      }
    }
    if (!_handingOffMediaPlayback) {
      widget.mediaService.stopPlayback();
    }
    if (_ownsVoicePromptService && !_ownedVoicePromptReleased) {
      _ownedVoicePromptReleased = true;
      _voicePromptService.dispose();
    }
    if (_ownsCompletionChoiceRecognizer) {
      _completionChoiceRecognizer.dispose();
    }
    final attemptEvaluator = _attemptEvaluator;
    if (_ownsAttemptEvaluator &&
        attemptEvaluator is DisposableLessonAttemptEvaluator) {
      (attemptEvaluator as DisposableLessonAttemptEvaluator).dispose();
    }
    super.dispose();
  }

  Future<void> _cancelLessonAttemptCapture() async {
    if (_usesIosNativeLessonRecognition && !_completionChoiceRecording) {
      await _iosLessonSpeechInput!.cancel().catchError((Object _) {});
      return;
    }
    await widget.mediaService.cancelRecording().catchError((Object _) {});
  }

  Future<void> _loadStartingPoint() async {
    final currentSentence = await widget.progressStore.readCurrentSentence(
      widget.lesson.id,
    );
    Set<int> skippedSentences = <int>{};
    Set<int> needsPracticeSentences = <int>{};
    try {
      skippedSentences = await widget.progressStore.readSkippedSentences(
        widget.lesson.id,
      );
      needsPracticeSentences = await widget.progressStore
          .readNeedsPracticeSentences(widget.lesson.id);
    } catch (_) {
      // A fresh or restricted browser session starts without skip markers.
    }
    final sentenceIndex = currentSentence.clamp(
      0,
      widget.lesson.sentences.length - 1,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sentenceIndex = sentenceIndex;
      _skippedSentenceIndexes
        ..clear()
        ..addAll(skippedSentences);
      _needsPracticeSentenceIndexes
        ..clear()
        ..addAll(needsPracticeSentences);
    });
    if (widget.lesson.usesV4Flow &&
        widget.initialResumeStage != ListeningResumeStage.core) {
      await _resumeV4Stage(widget.initialResumeStage);
      return;
    }
    if (widget.lesson.usesV4Flow) {
      try {
        await widget.progressStore.markLessonCoreStarted(widget.lesson.id);
      } catch (_) {
        // Resume metadata is best-effort; the lesson itself remains usable.
      }
    }
    await _activateCurrentSentence(autoPlay: true);
  }

  Future<void> _resumeV4Stage(ListeningResumeStage stage) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    switch (stage) {
      case ListeningResumeStage.challenge:
      case ListeningResumeStage.rolePlay:
      case ListeningResumeStage.song:
      case ListeningResumeStage.mission:
      case ListeningResumeStage.reinforcement:
        await _openReview(resumeStage: stage);
        return;
      case ListeningResumeStage.completed:
        await _showV4CompletionChoice(announceLevel: false);
        return;
      case ListeningResumeStage.core:
        await _activateCurrentSentence(autoPlay: true);
        return;
    }
  }

  Future<void> _activateCurrentSentence({
    required bool autoPlay,
    bool restoreExistingRecording = true,
  }) async {
    _cancelIdleReminder();
    _hideCoachPopup();
    if (mounted) {
      setState(() {
        _showSkip = false;
        _message = null;
        _attemptNumber = 1;
        _guidedSequenceStarted = false;
      });
    }
    if (restoreExistingRecording) {
      await _loadRecording();
    } else if (mounted) {
      setState(() {
        _recordingPath = null;
        _recordingDuration = null;
      });
    }
    if (autoPlay && !_pausedForMainAssistant) {
      await _startGuidedSentenceSequence();
    }
    _scheduleIdleReminder();
  }

  Future<void> _loadRecording() async {
    final path = await widget.mediaService.existingRecording(
      lessonId: widget.lesson.id,
      sentenceNumber: _sentence.number,
      sentenceId: _sentence.id,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _recordingPath = path;
      _recordingDuration = null;
    });
  }

  @override
  Future<void> pauseForMainAssistant() async {
    _pausedForMainAssistant = true;
    _mainPauseGeneration += 1;
    _recordingStartRequest += 1;
    _recordingLifecycleGeneration += 1;
    _attemptEvaluationRequest += 1;
    _cancelIdleReminder();
    _hideCoachPopup();
    _recordingAutoStopTimer?.cancel();
    _recordingAutoStopTimer = null;

    final shouldCancelRecording =
        _recording ||
        _completionChoiceRecording ||
        _recordingStartPending ||
        _recordingDeviceStartInProgress != null;
    final wasCompletionChoiceRecording = _completionChoiceRecording;
    final pendingDeviceStart = _recordingDeviceStartInProgress;
    // The request/generation guards already make a late completion stale.
    // Detach it now so a native start that never returns cannot own the module
    // lifecycle or poison the next MAIN gesture.
    _recordingDeviceStartInProgress = null;
    if (mounted) {
      setState(() {
        _recording = false;
        _completionChoiceRecording = false;
        _completionChoiceStopping = false;
        _recordingStartPending = false;
        _mediaBusy = false;
        _evaluatingAttempt = false;
        _message = 'Bài học đang tạm dừng.';
      });
    }

    // Issue every ownership release now and bound the group as one operation.
    // Never await a stale start here: its request/generation is invalid and a
    // late callback must not cancel the new recognizer owned by MAIN.
    final cleanup = <Future<void>>[
      if (shouldCancelRecording)
        wasCompletionChoiceRecording
            ? widget.mediaService.cancelRecording()
            : _cancelLessonAttemptCapture(),
      widget.mediaService.stopPlayback(),
      _voicePromptService.stop(),
    ];
    if (pendingDeviceStart != null) {
      unawaited(pendingDeviceStart.catchError((Object _) {}));
    }
    await _boundedMainPauseCleanup(
      Future.wait<void>(cleanup).then<void>((_) {}),
    );
  }

  Future<void> _boundedMainPauseCleanup(Future<void> operation) async {
    try {
      await operation.timeout(_mainPauseCleanupTimeout);
    } catch (_) {
      // The request and lifecycle generations above invalidate this operation.
      // Cleanup must remain finite so MAIN can take microphone ownership.
    }
  }

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    if (!mounted) {
      return const ActiveLearningCommandResult.unavailable();
    }
    if (_v4CompletionChoiceVisible) {
      final action = _completionActionForMainCommand(command);
      if (action != null) {
        await _cancelCompletionChoiceCapture();
        if (mounted) Navigator.of(context).pop(action);
        return const ActiveLearningCommandResult.handled();
      }
    }
    switch (command) {
      case ActiveLearningCommand.stop:
        await pauseForMainAssistant();
        if (mounted) {
          setState(() => _message = 'Đã dừng. Nhấn MAIN để tiếp tục.');
        }
        return const ActiveLearningCommandResult.handled(
          spokenReply: 'Đã dừng.',
        );
      case ActiveLearningCommand.resume:
        _pausedForMainAssistant = false;
        _guidedSequenceStarted = false;
        setState(() {
          // Resuming from MAIN always creates a fresh attempt. Keeping the
          // previous path here made the guided sequence return early and left
          // the microphone closed after "Cùng học tiếp nhé".
          _recordingPath = null;
          _recordingDuration = null;
          _message = null;
          _showSkip = false;
        });
        await _startRecording();
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.replayCurrent:
        _pausedForMainAssistant = false;
        _guidedSequenceStarted = false;
        await _playSample();
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.nextItem:
        _pausedForMainAssistant = false;
        await _advanceToNext(autoPlaySentence: true);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.previousItem:
        if (_sentenceIndex == 0) {
          return const ActiveLearningCommandResult.unavailable(
            spokenReply: 'Con đang ở câu đầu tiên rồi.',
          );
        }
        _pausedForMainAssistant = false;
        await _previous(autoPlaySentence: true);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.nextLesson:
        final nextLesson = _nextLessonInTopic;
        if (nextLesson == null) {
          return const ActiveLearningCommandResult.unavailable(
            spokenReply:
                'Con đã học xong chủ đề này rồi. Con chọn tiếp chủ đề mới nhé.',
          );
        }
        _pausedForMainAssistant = false;
        await _openNextLesson(nextLesson);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.previousLesson:
        final previousLesson = _previousLessonInTopic;
        if (previousLesson == null) {
          return const ActiveLearningCommandResult.unavailable(
            spokenReply: 'Con đang ở bài đầu tiên rồi.',
          );
        }
        _pausedForMainAssistant = false;
        await _openNextLesson(previousLesson);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.restart:
        _pausedForMainAssistant = false;
        await _restartCurrentLesson();
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.vocabularyPracticeAgain:
      case ActiveLearningCommand.vocabularyStars:
        return const ActiveLearningCommandResult.unavailable();
      case ActiveLearningCommand.exitToHome:
        await pauseForMainAssistant();
        if (!mounted) {
          return const ActiveLearningCommandResult.unavailable();
        }
        Navigator.of(context).popUntil((route) => route.isFirst);
        return const ActiveLearningCommandResult.handled();
    }
  }

  Future<void> _runVirtualLessonCommand(ActiveLearningCommand command) async {
    if (_virtualCommandPending || !mounted) {
      return;
    }
    setState(() => _virtualCommandPending = true);
    final registry = _activeModuleRegistry;
    final result = registry == null
        ? await _interruptAndHandleLocally(command)
        : await registry.interruptAndExecute(command);
    if (!mounted) {
      return;
    }
    setState(() {
      _virtualCommandPending = false;
      if (result.spokenReply case final reply? when reply.trim().isNotEmpty) {
        _message = reply;
      }
    });
  }

  Future<ActiveLearningCommandResult> _interruptAndHandleLocally(
    ActiveLearningCommand command,
  ) async {
    await pauseForMainAssistant();
    return handleMainCommand(command);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.lesson.sentences.length;
    final interactionBusy = _recording || _mediaBusy || _evaluatingAttempt;
    return DisplayLanguageScope(
      language: widget.language,
      child: IgnorePointer(
        ignoring: _pausedForMainAssistant,
        child: Scaffold(
          key: const Key('lesson-practice-screen'),
          backgroundColor: Colors.transparent,
          body: LearningScenery(
            imageAlignment: Alignment.center,
            overlayOpacity: 0.14,
            child: Stack(
              children: <Widget>[
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: <Widget>[
                      _LessonHeader(
                        current: _sentenceIndex + 1,
                        total: total,
                        onBack: _exitLesson,
                      ),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                12,
                                20,
                                24,
                              ),
                              child: Column(
                                children: <Widget>[
                                  _SentenceCard(
                                    sentence: _sentence,
                                    lessonType: widget.lesson.type,
                                    current: _sentenceIndex + 1,
                                    total: total,
                                    onPlaySample: _playSample,
                                    onPlayVietnamese: _playVietnamese,
                                  ),
                                  if (_recordingPath == null) ...<Widget>[
                                    const SizedBox(height: 14),
                                    const _LessonCoachHint(),
                                    const SizedBox(height: 14),
                                  ] else
                                    const SizedBox(height: 18),
                                  _RecordButton(
                                    recording: _recording,
                                    busy: _mediaBusy || _evaluatingAttempt,
                                    onTap: _toggleRecording,
                                    onLongPressStart: _startRecording,
                                    onLongPressEnd: _stopRecording,
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    child: _recordingPath == null
                                        ? const SizedBox(height: 14)
                                        : Padding(
                                            key: ValueKey(_recordingPath),
                                            padding: const EdgeInsets.only(
                                              top: 16,
                                            ),
                                            child: _RecordingCard(
                                              duration: _recordingDuration,
                                              onPlay: _playRecording,
                                            ),
                                          ),
                                  ),
                                  if (_message != null) ...<Widget>[
                                    const SizedBox(height: 12),
                                    Text(
                                      _message!,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: AppColors.muted),
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  if (_recordingPath != null)
                                    _PostRecordingActions(
                                      busy: interactionBusy,
                                      onPlaySample: _playSample,
                                      onPlayRecording: _playRecording,
                                      onRecordAgain: _startRecording,
                                      onContinue: _continue,
                                      onPrevious: _previous,
                                      canGoPrevious: _sentenceIndex > 0,
                                      finalSentence:
                                          _sentenceIndex == total - 1,
                                    )
                                  else
                                    _LessonNavigationActions(
                                      current: _sentenceIndex,
                                      total: total,
                                      busy: interactionBusy,
                                      onPrevious: _previous,
                                      onContinue: _continue,
                                    ),
                                  if (_showSkip &&
                                      _recordingPath == null) ...<Widget>[
                                    const SizedBox(height: 10),
                                    TextButton.icon(
                                      key: const Key('skip-lesson-sentence'),
                                      onPressed: interactionBusy ? null : _skip,
                                      icon: const Icon(
                                        Icons.fast_forward_rounded,
                                      ),
                                      label: Text(
                                        context.tr('Bỏ qua câu này', '跳过本句'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 70,
                  right: 6,
                  child: _VirtualLessonControls(
                    pending: _virtualCommandPending,
                    canGoPrevious: _sentenceIndex > 0,
                    onPrevious: () => _runVirtualLessonCommand(
                      ActiveLearningCommand.previousItem,
                    ),
                    onReplay: () => _runVirtualLessonCommand(
                      ActiveLearningCommand.replayCurrent,
                    ),
                    onNext: () => _runVirtualLessonCommand(
                      ActiveLearningCommand.nextItem,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    key: const Key('lesson-praise-fireworks-interaction'),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      reverseDuration: const Duration(milliseconds: 180),
                      child: _praiseFireworksVisible
                          ? _LessonPraiseFireworks(
                              key: ValueKey(_praiseFireworksSequence),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AbsorbPointer(
                    key: const Key('lesson-coach-popup-interaction-blocker'),
                    absorbing:
                        _coachPopupKind ==
                            _LessonCoachPopupKind.firstReminder ||
                        _coachPopupKind == _LessonCoachPopupKind.secondReminder,
                    child: IgnorePointer(
                      ignoring:
                          _coachPopupKind !=
                              _LessonCoachPopupKind.firstReminder &&
                          _coachPopupKind !=
                              _LessonCoachPopupKind.secondReminder,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        reverseDuration: Duration.zero,
                        transitionBuilder: (child, animation) {
                          final curved = CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutBack,
                            reverseCurve: Curves.easeInCubic,
                          );
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(scale: curved, child: child),
                          );
                        },
                        child: _coachPopupKind == null
                            ? const SizedBox.shrink()
                            : _LessonCoachPopup(
                                key: ValueKey(_coachPopupKind),
                                kind: _coachPopupKind!,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: ListeningNavigationBar(
            onCommunication: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            onHistory: _showHistory,
          ),
        ),
      ),
    );
  }

  Future<void> _playSample() async {
    _pausedForMainAssistant = false;
    _cancelIdleReminder();
    _hideCoachPopup();
    if (_usesGuideV2) {
      await _runMediaAction(() async {
        await _playBilingualSentenceSample();
        if (_pausedForMainAssistant) {
          return;
        }
        await _playPrompt(_repeatTargetPrompt);
      });
      if (mounted && !_pausedForMainAssistant && _recordingPath == null) {
        await _startRecording();
      }
      return;
    }
    final uri = _sentence.audioUri;
    if (uri == null) {
      if (_usesGuideV2) {
        await _runMediaAction(
          () => _voicePromptService.speakAndWait(
            _sentence.english,
            locale: 'en-US',
          ),
        );
        if (mounted && _recordingPath == null) {
          await _playPrompt(_repeatTargetPrompt);
          await _startRecording();
        }
        return;
      }
      _setMessage(
        context.tr(
          'Audio mẫu sẽ sẵn sàng sau khi cập nhật thư viện Cloudinary.',
          'Cloudinary 音频库更新后即可播放示范音频。',
        ),
      );
      _scheduleIdleReminder();
      return;
    }
    await _runMediaAction(() => _playSampleThenInviteRecording(uri));
    if (_usesGuideV2 && mounted && _recordingPath == null) {
      await _startRecording();
    }
    if (_recordingPath == null) {
      _scheduleIdleReminder();
    }
  }

  Future<void> _playVietnamese() async {
    _cancelIdleReminder();
    _hideCoachPopup();
    final uri = _sentence.vietnameseAudioUri;
    if (uri == null) {
      _setMessage(
        context.tr(
          'Audio tiếng Việt sẽ được gắn sau. Nút đã sẵn sàng.',
          '越南语音频稍后接入，按钮已准备好。',
        ),
      );
      if (_recordingPath == null) {
        _scheduleIdleReminder();
      }
      return;
    }
    await _runMediaAction(() => _playLessonAudioThenRecordGuide(uri));
    if (_recordingPath == null) {
      _scheduleIdleReminder();
    }
  }

  Future<void> _playRecording() async {
    _cancelIdleReminder();
    _hideCoachPopup();
    final path = _recordingPath;
    if (path == null) {
      return;
    }
    final parsed = Uri.tryParse(path);
    final uri = parsed != null && parsed.hasScheme ? parsed : Uri.file(path);
    await _runMediaAction(() => widget.mediaService.play(uri));
  }

  Future<void> _playAttemptRecordingToCompletion(
    LessonRecording recording,
  ) async {
    final parsed = Uri.tryParse(recording.filePath);
    final uri = parsed != null && parsed.hasScheme
        ? parsed
        : Uri.file(recording.filePath);
    final requestedTimeout = recording.duration + const Duration(seconds: 5);
    final timeout = requestedTimeout < const Duration(seconds: 10)
        ? const Duration(seconds: 10)
        : requestedTimeout;
    try {
      await widget.mediaService.playToCompletion(uri, timeout: timeout);
    } catch (error) {
      // Playback must not discard a valid attempt. Scoring can still continue
      // and the recording card remains available for a manual replay.
      debugPrint('HOMI lesson attempt playback failed: $error');
    }
  }

  Future<void> _runMediaAction(Future<void> Function() action) async {
    if (_mediaBusy || _recording) {
      return;
    }
    final pauseGeneration = _mainPauseGeneration;
    setState(() {
      _mediaBusy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      _setMessage(error.toString());
    } finally {
      if (mounted && pauseGeneration == _mainPauseGeneration) {
        setState(() => _mediaBusy = false);
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_completionChoiceRecording) {
      await _stopCompletionChoiceRecording();
      return;
    }
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_pausedForMainAssistant || _recording || _mediaBusy) {
      return;
    }
    final request = ++_recordingStartRequest;
    final iosSpeechInput = _usesIosNativeLessonRecognition
        ? _iosLessonSpeechInput
        : null;
    _cancelIdleReminder();
    _hideCoachPopup();
    setState(() {
      _mediaBusy = true;
      _recordingStartPending = true;
      _message = null;
    });
    try {
      final readyCuePlayer = _voicePromptService;
      if (readyCuePlayer is SpeechReadyCuePlayer) {
        await (readyCuePlayer as SpeechReadyCuePlayer).playSpeechReadyCue();
      }
      if (!mounted || request != _recordingStartRequest) {
        return;
      }
      final Future<void> deviceStart;
      if (iosSpeechInput != null) {
        final recordingPath = await widget.mediaService.recordingPath(
          lessonId: widget.lesson.id,
          sentenceNumber: _sentence.number,
          extension: 'wav',
        );
        if (!mounted || request != _recordingStartRequest) {
          return;
        }
        deviceStart = iosSpeechInput.startLessonEnglishRecognitionWithRecording(
          recordingPath,
        );
      } else {
        deviceStart = widget.mediaService.startRecording(
          lessonId: widget.lesson.id,
          sentenceNumber: _sentence.number,
          lessonTitle: widget.lesson.titleVi,
          sentenceId: _sentence.id,
          english: _sentence.english,
          vietnamese: _sentence.vietnamese,
        );
      }
      _recordingDeviceStartInProgress = deviceStart;
      try {
        await deviceStart;
      } finally {
        if (identical(_recordingDeviceStartInProgress, deviceStart)) {
          _recordingDeviceStartInProgress = null;
        }
      }
      if (!mounted || request != _recordingStartRequest) {
        // The owner that invalidated this request already cancelled its native
        // turn. Cancelling here can arrive late and kill a newer MAIN turn.
        if (iosSpeechInput == null) {
          await widget.mediaService.cancelRecording();
        }
        return;
      }
      if (mounted) {
        setState(() {
          _recording = true;
          _mediaBusy = false;
          _recordingStartPending = false;
        });
        if (_usesGuideV2) {
          _recordingAutoStopTimer?.cancel();
          _recordingAutoStopTimer = Timer(
            const Duration(seconds: 6),
            () => unawaited(_stopRecording()),
          );
        }
      }
    } catch (error) {
      _recordingAutoStopTimer?.cancel();
      _recordingAutoStopTimer = null;
      if (request != _recordingStartRequest) {
        // Stale starts have no authority over the current microphone owner.
        if (iosSpeechInput == null) {
          await widget.mediaService.cancelRecording();
        }
        return;
      }
      if (mounted) {
        setState(() {
          _mediaBusy = false;
          _recordingStartPending = false;
        });
      }
      _setMessage(error.toString());
    }
  }

  Future<void> _stopRecording() async {
    if (_completionChoiceRecording) {
      await _stopCompletionChoiceRecording();
      return;
    }
    _recordingAutoStopTimer?.cancel();
    _recordingAutoStopTimer = null;
    if (_recordingStartPending && !_recording) {
      _recordingStartRequest += 1;
      _recordingStartPending = false;
      await _boundedMainPauseCleanup(_cancelLessonAttemptCapture());
      await widget.mediaService.stopPlayback();
      if (mounted) {
        setState(() => _mediaBusy = false);
      }
      return;
    }
    if (!_recording || _mediaBusy) {
      return;
    }
    final recordingGeneration = _recordingLifecycleGeneration;
    setState(() => _mediaBusy = true);
    try {
      final iosSpeechInput = _usesIosNativeLessonRecognition
          ? _iosLessonSpeechInput
          : null;
      if (iosSpeechInput != null) {
        await _stopIosNativeLessonAttempt(
          iosSpeechInput,
          recordingGeneration: recordingGeneration,
        );
        return;
      }
      final recording = await widget.mediaService.stopRecording();
      if (!mounted ||
          _pausedForMainAssistant ||
          recordingGeneration != _recordingLifecycleGeneration) {
        return;
      }
      setState(() {
        _recording = false;
        _recordingPath = recording.filePath;
        _recordingDuration = recording.duration;
        _message = null;
        _skippedSentenceIndexes.remove(_sentenceIndex);
      });
      try {
        await widget.progressStore.clearSkippedSentence(
          widget.lesson.id,
          _sentenceIndex,
        );
      } catch (_) {
        // The successful recording remains usable even if progress sync fails.
      }
      await _playAttemptRecordingToCompletion(recording);
      if (!mounted ||
          _pausedForMainAssistant ||
          recordingGeneration != _recordingLifecycleGeneration) {
        return;
      }
      setState(() => _mediaBusy = false);
      if (_usesGuideV2) {
        final evaluationRequest = ++_attemptEvaluationRequest;
        final evaluatedSentenceIndex = _sentenceIndex;
        final evaluatedSentence = _sentence;
        final evaluatedAttemptNumber = _attemptNumber;
        setState(() => _evaluatingAttempt = true);
        var shouldOpenMicrophoneAgain = false;
        try {
          shouldOpenMicrophoneAgain = await _evaluateAttempt(
            recording,
            evaluationRequest: evaluationRequest,
            sentenceIndex: evaluatedSentenceIndex,
            sentence: evaluatedSentence,
            attemptNumber: evaluatedAttemptNumber,
          );
        } finally {
          if (mounted && evaluationRequest == _attemptEvaluationRequest) {
            setState(() => _evaluatingAttempt = false);
          }
        }
        if (shouldOpenMicrophoneAgain) {
          await _reopenRecordingAfterUnclear(
            evaluationRequest: evaluationRequest,
            sentenceIndex: evaluatedSentenceIndex,
            sentenceId: evaluatedSentence.id,
          );
        }
      } else {
        _showPraiseFireworks();
        unawaited(_playGuideCue(LessonGuideCue.praise));
      }
    } catch (error) {
      if (!mounted ||
          _pausedForMainAssistant ||
          recordingGeneration != _recordingLifecycleGeneration) {
        return;
      }
      if (mounted) {
        setState(() {
          _recording = false;
          _mediaBusy = false;
        });
      }
      _setMessage(error.toString());
      if (_recordingPath == null) {
        _scheduleIdleReminder();
      }
    }
  }

  Future<void> _stopIosNativeLessonAttempt(
    IOSStreamingSpeechInput speechInput, {
    required int recordingGeneration,
  }) async {
    LessonAttemptOutcome outcome;
    Duration? captureDuration;
    LessonRecording? recording;
    try {
      final capture = await speechInput.stop();
      captureDuration = capture.duration;
      final recordedAudio = capture.recordedAudio;
      if (recordedAudio != null) {
        recording = LessonRecording(
          filePath: recordedAudio.filePath,
          duration: recordedAudio.duration,
        );
      }
      final recognizedCandidates = <String>{
        capture.sourceText,
        ...capture.alternatives,
      };
      outcome =
          recognizedCandidates.any(
            (candidate) => matchesRecognizedLessonEnglish(
              _sentence.english,
              candidate,
              acceptedVariants: _sentence.recognitionVariants,
              requireAllExpectedTokens: _sentence.requiresAllExpectedTokens,
            ),
          )
          ? LessonAttemptOutcome.good
          : LessonAttemptOutcome.retry;
      debugPrint(
        'HOMI iOS lesson recognition completed: '
        'candidateCount=${recognizedCandidates.length}, outcome=$outcome',
      );
    } on StreamingSpeechInputException catch (error) {
      final recordedAudio = speechInput.takeLessonRecordingAudioCapture();
      if (recordedAudio != null) {
        recording = LessonRecording(
          filePath: recordedAudio.filePath,
          duration: recordedAudio.duration,
        );
        captureDuration = recordedAudio.duration;
      }
      outcome = LessonAttemptOutcome.unclear;
      debugPrint(
        'HOMI iOS lesson recognition returned no usable speech: '
        'code=${error.code ?? 'unknown'}',
      );
    }

    if (!mounted ||
        _pausedForMainAssistant ||
        recordingGeneration != _recordingLifecycleGeneration) {
      return;
    }
    final evaluationRequest = ++_attemptEvaluationRequest;
    final evaluatedSentenceIndex = _sentenceIndex;
    final evaluatedSentence = _sentence;
    final evaluatedAttemptNumber = _attemptNumber;
    setState(() {
      _recording = false;
      _recordingPath = recording?.filePath;
      _recordingDuration = recording?.duration ?? captureDuration;
      _message = null;
      _skippedSentenceIndexes.remove(_sentenceIndex);
    });
    final completedRecording = recording;
    if (completedRecording != null) {
      try {
        await widget.mediaService.registerExternalRecording(
          recording: completedRecording,
          lessonId: widget.lesson.id,
          lessonTitle: widget.lesson.titleVi,
          sentenceId: evaluatedSentence.id,
          sentenceNumber: evaluatedSentence.number,
          english: evaluatedSentence.english,
          vietnamese: evaluatedSentence.vietnamese,
        );
      } catch (error) {
        debugPrint(
          'HOMI could not archive the Apple Speech lesson WAV: $error',
        );
      }
      await _playAttemptRecordingToCompletion(completedRecording);
      if (!_isCurrentEvaluation(
        evaluationRequest,
        evaluatedSentenceIndex,
        evaluatedSentence.id,
      )) {
        return;
      }
    }
    setState(() {
      _mediaBusy = false;
      _evaluatingAttempt = true;
    });
    try {
      await widget.progressStore.clearSkippedSentence(
        widget.lesson.id,
        evaluatedSentenceIndex,
      );
    } catch (_) {
      // Recognition and scoring do not depend on progress persistence.
    }
    var shouldOpenMicrophoneAgain = false;
    try {
      shouldOpenMicrophoneAgain = await _applyAttemptOutcome(
        outcome,
        evaluationRequest: evaluationRequest,
        sentenceIndex: evaluatedSentenceIndex,
        sentence: evaluatedSentence,
        attemptNumber: evaluatedAttemptNumber,
      );
    } finally {
      if (mounted && evaluationRequest == _attemptEvaluationRequest) {
        setState(() => _evaluatingAttempt = false);
      }
    }
    if (shouldOpenMicrophoneAgain) {
      await _reopenRecordingAfterUnclear(
        evaluationRequest: evaluationRequest,
        sentenceIndex: evaluatedSentenceIndex,
        sentenceId: evaluatedSentence.id,
      );
    }
  }

  Future<bool> _evaluateAttempt(
    LessonRecording recording, {
    required int evaluationRequest,
    required int sentenceIndex,
    required ListeningSentenceContent sentence,
    required int attemptNumber,
  }) async {
    final outcome = await _attemptEvaluator.evaluate(
      lessonCode: widget.lesson.code,
      sentenceId: sentence.id,
      expectedEnglish: sentence.english,
      recordingPath: recording.filePath,
      recordingDuration: recording.duration,
      attemptNumber: attemptNumber,
      childAge: widget.startAge,
      acceptedVariants: sentence.recognitionVariants,
      requireAllExpectedTokens: sentence.requiresAllExpectedTokens,
    );
    if (!_isCurrentEvaluation(evaluationRequest, sentenceIndex, sentence.id)) {
      return false;
    }
    return _applyAttemptOutcome(
      outcome,
      evaluationRequest: evaluationRequest,
      sentenceIndex: sentenceIndex,
      sentence: sentence,
      attemptNumber: attemptNumber,
    );
  }

  Future<bool> _applyAttemptOutcome(
    LessonAttemptOutcome outcome, {
    required int evaluationRequest,
    required int sentenceIndex,
    required ListeningSentenceContent sentence,
    required int attemptNumber,
  }) async {
    if (!_isCurrentEvaluation(evaluationRequest, sentenceIndex, sentence.id)) {
      return false;
    }
    switch (outcome) {
      case LessonAttemptOutcome.good:
        if (!widget.lesson.usesV4Flow) {
          await _saveSentenceToVocabulary(
            VocabularyCollection.star,
            sentence: sentence,
          );
        }
        if (!_isCurrentEvaluation(
          evaluationRequest,
          sentenceIndex,
          sentence.id,
        )) {
          return false;
        }
        try {
          await widget.progressStore.clearNeedsPracticeSentence(
            widget.lesson.id,
            sentenceIndex,
          );
        } catch (_) {
          // A restricted browser session must not block the lesson flow.
        }
        if (!_isCurrentEvaluation(
          evaluationRequest,
          sentenceIndex,
          sentence.id,
        )) {
          return false;
        }
        _needsPracticeSentenceIndexes.remove(sentenceIndex);
        _showPraiseFireworks();
        setState(() => _message = LessonGuideFlowV2.good.text);
        await _playPrompt(LessonGuideFlowV2.good);
        // V4 introduces a first-ever star only after the normal correct-answer
        // feedback. This preserves the authored order: praise, star, then the
        // one-time explanation of what stars mean.
        if (widget.lesson.usesV4Flow) {
          await _awardLessonStar(
            starId: 'core:${sentence.id}',
            english: sentence.english,
            vietnamese: sentence.vietnamese,
            vocabularyId: sentence.id,
          );
        }
        if (!_isCurrentEvaluation(
          evaluationRequest,
          sentenceIndex,
          sentence.id,
        )) {
          return false;
        }
        await _advanceToNext(autoPlaySentence: true);
        return false;
      case LessonAttemptOutcome.unclear:
        // NO_RESPONSE/ASR is not a valid scored attempt. Keep the same attempt
        // number and sentence until speech is recognized or the child skips.
        const prompt = LessonGuideFlowV2.unclear;
        setState(() {
          _recordingPath = null;
          _recordingDuration = null;
          _message = prompt.text;
        });
        try {
          await _playPrompt(prompt);
        } catch (error) {
          // The child must still get a fresh recording turn when the spoken
          // feedback ends with a playback/TTS error.
          debugPrint('HOMI unclear feedback playback failed: $error');
        }
        return _isCurrentEvaluation(
          evaluationRequest,
          sentenceIndex,
          sentence.id,
        );
      case LessonAttemptOutcome.retry:
        if (attemptNumber >= 2) {
          await _markNeedsPracticeAndAdvance(
            evaluationRequest: evaluationRequest,
            sentenceIndex: sentenceIndex,
            sentence: sentence,
          );
          return false;
        }
        const prompt = LessonGuideFlowV2.retryFirst;
        setState(() {
          _attemptNumber = 2;
          _recordingPath = null;
          _recordingDuration = null;
          _message = prompt.text;
        });
        await _playPrompt(prompt);
        if (!_isCurrentEvaluation(
          evaluationRequest,
          sentenceIndex,
          sentence.id,
        )) {
          return false;
        }
        // The authored second attempt begins only after the full model is
        // replayed in English and Vietnamese, followed by the invitation.
        await _playSample();
        return false;
      case LessonAttemptOutcome.needsPractice:
        await _markNeedsPracticeAndAdvance(
          evaluationRequest: evaluationRequest,
          sentenceIndex: sentenceIndex,
          sentence: sentence,
        );
        return false;
    }
  }

  Future<void> _reopenRecordingAfterUnclear({
    required int evaluationRequest,
    required int sentenceIndex,
    required String sentenceId,
  }) async {
    if (!_isCurrentEvaluation(evaluationRequest, sentenceIndex, sentenceId)) {
      return;
    }
    await widget.mediaService.stopPlayback().catchError((Object _) {});
    await Future<void>.delayed(
      LessonGuideFlowV2.unclearRetryMicrophoneSettleDelay,
    );
    if (!_isCurrentEvaluation(evaluationRequest, sentenceIndex, sentenceId) ||
        _recording) {
      return;
    }
    await _startRecording();
  }

  bool _isCurrentEvaluation(
    int evaluationRequest,
    int sentenceIndex,
    String sentenceId,
  ) =>
      mounted &&
      !_pausedForMainAssistant &&
      evaluationRequest == _attemptEvaluationRequest &&
      sentenceIndex == _sentenceIndex &&
      sentenceId == _sentence.id;

  Future<void> _markSentenceNeedsPractice(
    int sentenceIndex,
    ListeningSentenceContent sentence,
  ) async {
    _needsPracticeSentenceIndexes.add(sentenceIndex);
    try {
      await widget.progressStore.saveNeedsPracticeSentence(
        widget.lesson.id,
        sentenceIndex,
      );
    } catch (_) {
      // Keep the in-memory retry queue when persistence is unavailable.
    }
    await _saveSentenceToVocabulary(
      VocabularyCollection.review,
      sentence: sentence,
    );
  }

  Future<void> _markNeedsPracticeAndAdvance({
    required int evaluationRequest,
    required int sentenceIndex,
    required ListeningSentenceContent sentence,
  }) async {
    await _markSentenceNeedsPractice(sentenceIndex, sentence);
    if (!_isCurrentEvaluation(evaluationRequest, sentenceIndex, sentence.id)) {
      return;
    }
    setState(() {
      _recordingPath = null;
      _recordingDuration = null;
      _message = LessonGuideFlowV2.needsPractice.text;
    });
    await _playPrompt(LessonGuideFlowV2.needsPractice);
    if (!_isCurrentEvaluation(evaluationRequest, sentenceIndex, sentence.id)) {
      return;
    }
    await _advanceToNext(autoPlaySentence: true);
  }

  Future<void> _saveSentenceToVocabulary(
    VocabularyCollection collection, {
    required ListeningSentenceContent sentence,
  }) async {
    try {
      await widget.vocabularyStore.upsertLessonSentence(
        lessonCode: widget.lesson.code,
        sentenceId: sentence.id,
        english: sentence.english,
        vietnamese: sentence.vietnamese,
        collection: collection,
      );
    } catch (_) {
      // Local vocabulary persistence must never interrupt the active lesson.
    }
  }

  Future<bool> _saveAuthoredAnswerToStarsResult(
    String starId,
    String english,
    String vietnamese,
  ) {
    return _awardLessonStar(
      starId: starId,
      english: english,
      vietnamese: vietnamese,
      vocabularyId: starId,
    );
  }

  V4CompletionAction? _completionActionForMainCommand(
    ActiveLearningCommand command,
  ) {
    if (command == ActiveLearningCommand.stop) {
      return V4CompletionAction.stop;
    }
    if (command == ActiveLearningCommand.restart) {
      return switch (_activeV4CompletionStage) {
        V4CompletionStage.topicEnd => V4CompletionAction.relearn,
        V4CompletionStage.courseEnd => V4CompletionAction.relearn,
        V4CompletionStage.courseRelearnLevel =>
          V4CompletionAction.relearnLevel1,
        _ => V4CompletionAction.relearnCurrentLesson,
      };
    }
    if (command == ActiveLearningCommand.nextItem ||
        command == ActiveLearningCommand.nextLesson ||
        command == ActiveLearningCommand.resume) {
      return switch (_activeV4CompletionStage) {
        V4CompletionStage.lessonEnd => V4CompletionAction.nextLesson,
        V4CompletionStage.topicEnd => V4CompletionAction.nextTopic,
        V4CompletionStage.nextLevel => V4CompletionAction.startNextLevel,
        V4CompletionStage.courseEnd => V4CompletionAction.requestNewCourse,
        _ => null,
      };
    }
    return null;
  }

  Future<bool> _awardLessonStar({
    required String starId,
    required String english,
    required String vietnamese,
    required String vocabularyId,
  }) async {
    final totalBefore = await widget.progressStore.readTotalEarnedStars();
    final isNew = await widget.progressStore.awardStar(
      widget.lesson.id,
      starId,
    );
    await widget.vocabularyStore.upsertLessonSentence(
      lessonCode: widget.lesson.code,
      sentenceId: vocabularyId,
      english: english,
      vietnamese: vietnamese,
      collection: VocabularyCollection.star,
    );
    if (!isNew) return false;
    _newStarsThisLesson += 1;
    if (totalBefore == 0 &&
        mounted &&
        !starId.startsWith('roleplay:') &&
        !starId.contains('-roleplay-')) {
      await _voicePromptService.speakAndWait(
        'Bạn vừa nhận một Ngôi sao! Mỗi khi nghe âm thanh này, HOMI sẽ thêm một Ngôi sao vào bộ sưu tập của bạn.',
      );
    }
    return true;
  }

  Future<void> _continue() => _advanceToNext(autoPlaySentence: false);

  Future<void> _advanceToNext({required bool autoPlaySentence}) async {
    if (_recording || _mediaBusy) {
      return;
    }
    _cancelIdleReminder();
    _hideCoachPopup();
    await widget.progressStore.saveLesson(widget.lesson.id, _sentenceIndex + 1);
    if (!mounted) {
      return;
    }
    if (_sentenceIndex == widget.lesson.sentences.length - 1) {
      await widget.progressStore.saveCurrentSentence(
        widget.lesson.id,
        _sentenceIndex,
      );
      // V4 ends the core practice with its authored role-play/challenge
      // activity, not the legacy spoken "restart or next lesson" prompt.
      if (widget.lesson.usesV4Flow) {
        await _openReview();
        return;
      }
      if (_usesGuideV2) {
        if (mounted) {
          setState(() => _mediaBusy = true);
        }
        try {
          await _playPrompt(
            LessonGuideFlowV2.ending(
              lessonCode: widget.lesson.code,
              lessonTitleEn: widget.lesson.titleEn,
            ),
          );
          await _playPrompt(LessonGuideFlowV2.completionChoice);
        } finally {
          if (mounted) {
            setState(() => _mediaBusy = false);
          }
        }
        await _listenForCompletionChoice();
        return;
      }
      await _openReview();
      return;
    }
    final nextSentence = _sentenceIndex + 1;
    await widget.progressStore.saveCurrentSentence(
      widget.lesson.id,
      nextSentence,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sentenceIndex = nextSentence;
      _recordingPath = null;
      _recordingDuration = null;
      _message = null;
    });
    await _activateCurrentSentence(autoPlay: autoPlaySentence);
  }

  Future<void> _previous({bool autoPlaySentence = false}) async {
    if (_sentenceIndex == 0) {
      return;
    }
    _cancelIdleReminder();
    _hideCoachPopup();
    if (!_usesGuideV2) {
      await _playGuideCueWithBusyState(LessonGuideCue.praise);
    }
    if (!mounted) {
      return;
    }
    final previousSentence = _sentenceIndex - 1;
    await widget.progressStore.saveCurrentSentence(
      widget.lesson.id,
      previousSentence,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _sentenceIndex = previousSentence;
      _recordingPath = null;
      _recordingDuration = null;
      _message = null;
    });
    // Returning to an earlier sentence is a new guided attempt even when that
    // sentence has an archived recording. The archived file remains available
    // in history, but must not suppress the sample -> prompt -> mic sequence.
    await _activateCurrentSentence(
      autoPlay: autoPlaySentence,
      restoreExistingRecording: false,
    );
  }

  Future<void> _exitLesson() async {
    _cancelIdleReminder();
    _hideCoachPopup();
    await widget.progressStore.saveCurrentSentence(
      widget.lesson.id,
      _sentenceIndex,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _skip() async {
    _cancelIdleReminder();
    _hideCoachPopup();
    _skippedSentenceIndexes.add(_sentenceIndex);
    try {
      await widget.progressStore.saveSkippedSentence(
        widget.lesson.id,
        _sentenceIndex,
      );
    } catch (_) {
      // Keep the current-session marker when local persistence is unavailable.
    }
    if (mounted) {
      setState(() {
        _showSkip = false;
        _message = context.tr(
          'Không sao, mình đánh dấu “Chưa ghi âm” và học tiếp nhé.',
          '没关系，已标记为“尚未录音”，继续学习吧。',
        );
      });
    }
    if (_usesGuideV2) {
      await _playPrompt(LessonGuideFlowV2.needsPractice);
    } else {
      await _playGuideCueWithBusyState(LessonGuideCue.skip);
    }
    await _advanceToNext(autoPlaySentence: true);
  }

  Future<void> _openReview({
    ListeningResumeStage resumeStage = ListeningResumeStage.core,
  }) async {
    _cancelIdleReminder();
    _hideCoachPopup();
    if (widget.lesson.usesV4Flow) {
      final completedActivity = await widget.progressStore
          .hasCompletedV4LessonActivity(widget.lesson.id);
      final resumeAfterChallenge = switch (resumeStage) {
        ListeningResumeStage.song ||
        ListeningResumeStage.mission ||
        ListeningResumeStage.reinforcement ||
        ListeningResumeStage.completed => true,
        _ => completedActivity,
      };
      if (!resumeAfterChallenge) {
        final hasRolePlay =
            widget.startAge >= 8 &&
            widget.lesson.rolePlay != null &&
            widget.lesson.rolePlay!.turns.isNotEmpty;
        final startAfterRolePlay =
            hasRolePlay && resumeStage == ListeningResumeStage.challenge;
        await widget.progressStore.saveResumeStage(
          widget.lesson.id,
          hasRolePlay && !startAfterRolePlay
              ? ListeningResumeStage.rolePlay
              : ListeningResumeStage.challenge,
        );
        if (widget.lesson.hasV4SongStage) {
          await _voicePromptService.speakAndWait(
            v4SongPrealert(widget.lesson.songTitle!),
          );
        } else {
          await _voicePromptService.speakAndWait(v4ChallengeIntro);
        }
        if (!mounted) return;
        final selectedChallenges = const AuthoredQuestionSelector()
            .selectChallengesForLesson(
              widget.lesson,
              seed: _stableChallengeSeed(widget.lesson.id),
              counter: _v4ChallengeCounter++,
              previousChallengeIds:
                  _previousV4ChallengeIds[widget.lesson.id] ?? const <String>[],
            );
        if (selectedChallenges.length != 2) {
          await _reportInvalidChallengeContent();
          return;
        }
        _previousV4ChallengeIds[widget.lesson.id] = selectedChallenges
            .map((challenge) => challenge.id)
            .toList(growable: false);
        final completed = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => LessonChallengeScreen(
              language: widget.language,
              startAge: widget.startAge,
              lesson: widget.lesson,
              challenges: selectedChallenges,
              mediaService: widget.mediaService,
              attemptEvaluator: _attemptEvaluator,
              voicePromptService: _voicePromptService,
              onStarEarnedWithResult: _saveAuthoredAnswerToStarsResult,
              startAfterRolePlay: startAfterRolePlay,
              onRolePlayCompleted: () => widget.progressStore.saveResumeStage(
                widget.lesson.id,
                ListeningResumeStage.challenge,
              ),
              showRolePlayOpeningHint:
                  !widget.isRelearn && resumeStage == ListeningResumeStage.core,
              iosSpeechInput: _usesIosNativeLessonRecognition
                  ? _iosLessonSpeechInput
                  : null,
            ),
          ),
        );
        if (!mounted || completed != true) return;
        await widget.progressStore.markV4LessonActivityCompleted(
          widget.lesson.id,
        );
        await _announceV4ActivityMilestone();
        if (!mounted) return;
      }

      final shouldOpenSong =
          widget.lesson.hasV4SongStage &&
          resumeStage != ListeningResumeStage.song &&
          resumeStage != ListeningResumeStage.mission &&
          resumeStage != ListeningResumeStage.reinforcement &&
          resumeStage != ListeningResumeStage.completed;
      if (shouldOpenSong) {
        await widget.progressStore.saveResumeStage(
          widget.lesson.id,
          ListeningResumeStage.song,
        );
        // Persisting `song` before opening it makes an interrupted song
        // skippable on re-entry, as the lesson itself is already complete.
        if (!await _openV4SongStageIfNeeded()) return;
      }
      final missionCompleted = await _runV4LevelMissionIfNeeded(
        resumeReinforcement: resumeStage == ListeningResumeStage.reinforcement,
      );
      if (!mounted || !missionCompleted) return;
      await widget.progressStore.saveResumeStage(
        widget.lesson.id,
        ListeningResumeStage.completed,
      );
      await _showV4CompletionChoice();
      return;
    }
    final unrecordedSentenceIndexes = await _readUnrecordedSentenceIndexes();
    if (!mounted) {
      return;
    }
    final nextLesson = _nextLessonInTopic;
    final result = await Navigator.of(context).push<LessonReviewAction>(
      MaterialPageRoute<LessonReviewAction>(
        builder: (_) => LessonReviewScreen(
          language: widget.language,
          lesson: widget.lesson,
          mediaService: widget.mediaService,
          unrecordedSentenceIndexes: unrecordedSentenceIndexes,
          mode: LessonReviewMode.learned,
          hasNextLesson: nextLesson != null,
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    switch (result) {
      case LessonReviewAction.nextLesson:
        if (nextLesson != null) {
          await _openNextLesson(nextLesson);
        } else {
          _returnToListening();
        }
        return;
      case LessonReviewAction.restartLesson:
        await _restartCurrentLesson();
        return;
      case LessonReviewAction.returnToListening:
        _returnToListening();
        return;
    }
  }

  Future<void> _announceV4ActivityMilestone() async {
    final topic = widget.topicContent;
    if (topic == null || _nextLessonInTopic != null) {
      final earnedStars = await widget.progressStore.readEarnedStars(
        widget.lesson.id,
      );
      final rolePlayStars =
          widget.lesson.rolePlay?.turns
              .where((turn) => turn.speaker == ListeningRolePlaySpeaker.child)
              .length ??
          0;
      final availableStars = widget.lesson.sentences.length + rolePlayStars + 2;
      if (availableStars > 0 && earnedStars.length >= availableStars) {
        await _voicePromptService.speakAndWait(
          'Excellent! Bạn đã hoàn thành bài học và chinh phục đủ tất cả Ngôi sao rồi!',
        );
        return;
      }
      if (_newStarsThisLesson > 0) {
        await _voicePromptService.speakAndWait(
          'Giỏi lắm! Bạn đã hoàn thành bài học và có thêm $_newStarsThisLesson Ngôi sao!',
        );
        return;
      }
      await _voicePromptService.speakAndWait(
        'Giỏi lắm! Bạn đã hoàn thành bài học rồi.',
      );
      return;
    }
    if (_isLastLessonInLevel) {
      await _voicePromptService.speakAndWait(
        'Tuyệt lắm! Bạn đã hoàn thành chủ đề cuối của Level này rồi!',
      );
      return;
    }
    await _voicePromptService.speakAndWait(
      'Tuyệt lắm! Bạn đã hoàn thành chủ đề ${topic.titleEn} rồi!',
    );
  }

  Future<void> _showV4CompletionChoice({bool announceLevel = true}) async {
    if (!mounted || _v4CompletionChoiceVisible) return;
    final level = widget.levelContent;
    if (_isLastLessonInLevel && level != null) {
      if (level.number >= 3) {
        final courseId = '${widget.startAge}-${widget.endAge}';
        await widget.progressStore.markCourseCompleted(courseId);
        await widget.progressStore.markCourseCompletionEventCreated(courseId);
        if (announceLevel) {
          await _voicePromptService.speakAndWait(
            'Excellent! Bạn đã hoàn thành toàn bộ khóa học rồi!',
          );
        }
        final action = await _showV4Choice(
          V4CompletionStage.courseEnd,
          const <V4CompletionAction>[
            V4CompletionAction.requestNewCourse,
            V4CompletionAction.relearn,
            V4CompletionAction.stop,
          ],
        );
        if (!mounted) return;
        if (action == V4CompletionAction.requestNewCourse) {
          await _voicePromptService.speakAndWait(
            'Bạn nhờ ba mẹ chọn khóa học mới trên điện thoại nhé.',
          );
          _returnToListening();
          return;
        }
        if (action == V4CompletionAction.relearn) {
          final selected = await _showV4Choice(
            V4CompletionStage.courseRelearnLevel,
            const <V4CompletionAction>[
              V4CompletionAction.relearnLevel1,
              V4CompletionAction.relearnLevel2,
              V4CompletionAction.relearnLevel3,
              V4CompletionAction.stop,
            ],
          );
          await _handleV4CompletionAction(selected);
          return;
        }
        await _handleV4CompletionAction(action);
        return;
      }
      if (announceLevel) {
        await _voicePromptService.speakAndWait(
          'Tuyệt lắm! Bạn đã hoàn thành Level ${level.number} rồi!',
        );
      }
      final action = await _showV4Choice(
        V4CompletionStage.nextLevel,
        const <V4CompletionAction>[
          V4CompletionAction.startNextLevel,
          V4CompletionAction.stop,
        ],
        nextLevel: level.number + 1,
      );
      await _handleV4CompletionAction(action);
      return;
    }

    final nextLesson = _nextLessonInTopic;
    if (nextLesson != null) {
      final action = await _showV4Choice(
        V4CompletionStage.lessonEnd,
        const <V4CompletionAction>[
          V4CompletionAction.nextLesson,
          V4CompletionAction.relearnCurrentLesson,
          V4CompletionAction.stop,
        ],
      );
      await _handleV4CompletionAction(action);
      return;
    }

    widget.onTopicCompleted?.call();
    final action = await _showV4Choice(
      V4CompletionStage.topicEnd,
      const <V4CompletionAction>[
        V4CompletionAction.nextTopic,
        V4CompletionAction.relearn,
        V4CompletionAction.stop,
      ],
    );
    if (action == V4CompletionAction.relearn) {
      final scopeAction = await _showV4Choice(
        V4CompletionStage.topicRelearnScope,
        const <V4CompletionAction>[
          V4CompletionAction.relearnTopic,
          V4CompletionAction.relearnCurrentLesson,
          V4CompletionAction.stop,
        ],
      );
      await _handleV4CompletionAction(scopeAction);
      return;
    }
    await _handleV4CompletionAction(action);
  }

  Future<V4CompletionAction?> _showV4Choice(
    V4CompletionStage stage,
    List<V4CompletionAction> actions, {
    int? nextLevel,
  }) async {
    if (!mounted) return null;
    final prompt = v4CompletionPrompt(stage, nextLevel: nextLevel);
    await _voicePromptService.speakAndWait(prompt);
    if (!mounted) return null;
    _v4CompletionChoiceVisible = true;
    _activeV4CompletionStage = stage;
    _activeV4CompletionActions = List<V4CompletionAction>.unmodifiable(actions);
    final resultFuture = showModalBottomSheet<V4CompletionAction>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  prompt,
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'HOMI đang mở micro để nghe lựa chọn. Bạn cũng có thể chạm nút bên dưới.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                for (
                  var index = 0;
                  index < actions.length;
                  index++
                ) ...<Widget>[
                  if (index > 0) const SizedBox(height: 10),
                  if (actions[index] == V4CompletionAction.stop)
                    OutlinedButton.icon(
                      key: ValueKey('v4-choice-${actions[index].name}'),
                      onPressed: () => unawaited(
                        _selectV4CompletionAction(sheetContext, actions[index]),
                      ),
                      icon: const Icon(Icons.stop_rounded),
                      label: Text(v4CompletionActionLabel(actions[index])),
                    )
                  else
                    FilledButton.icon(
                      key: ValueKey('v4-choice-${actions[index].name}'),
                      onPressed: () => unawaited(
                        _selectV4CompletionAction(sheetContext, actions[index]),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(v4CompletionActionLabel(actions[index])),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    // showModalBottomSheet pushes its route synchronously. Yield one microtask
    // so route/listener setup settles, but do not wait for a frame callback:
    // frames may be suspended after the screen is locked or HOMI is covered.
    await Future<void>.delayed(Duration.zero);
    if (mounted &&
        _v4CompletionChoiceVisible &&
        _activeV4CompletionStage == stage) {
      unawaited(_listenForCompletionChoice());
    }
    final result = await resultFuture;
    await _cancelCompletionChoiceCapture();
    _v4CompletionChoiceVisible = false;
    _activeV4CompletionStage = null;
    _activeV4CompletionActions = const <V4CompletionAction>[];
    return result;
  }

  Future<void> _selectV4CompletionAction(
    BuildContext sheetContext,
    V4CompletionAction action,
  ) async {
    await _cancelCompletionChoiceCapture();
    if (sheetContext.mounted) {
      Navigator.of(sheetContext).pop(action);
    }
  }

  Future<void> _handleV4CompletionAction(V4CompletionAction? action) async {
    if (!mounted || action == null || action == V4CompletionAction.stop) {
      _returnToListening();
      return;
    }
    switch (action) {
      case V4CompletionAction.nextLesson:
        final next = _nextLessonInTopic;
        if (next != null) await _openNextLesson(next);
        return;
      case V4CompletionAction.relearnCurrentLesson:
        await _openRelearnCurrentLesson();
        return;
      case V4CompletionAction.nextTopic:
        final nextTopic = _adjacentTopic(1);
        if (nextTopic != null) await _openContentTopic(nextTopic);
        return;
      case V4CompletionAction.relearnTopic:
        final topic = widget.topicContent;
        if (topic != null) await _openContentTopic(topic, relearn: true);
        return;
      case V4CompletionAction.startNextLevel:
        final nextLevel = widget.contentGroup?.level(
          (widget.levelContent?.number ?? 0) + 1,
        );
        if (nextLevel != null) await _openLevel(nextLevel);
        return;
      case V4CompletionAction.relearnLevel1:
        final level = widget.contentGroup?.level(1);
        if (level != null) await _openLevel(level, relearn: true);
        return;
      case V4CompletionAction.relearnLevel2:
        final level = widget.contentGroup?.level(2);
        if (level != null) await _openLevel(level, relearn: true);
        return;
      case V4CompletionAction.relearnLevel3:
        final level = widget.contentGroup?.level(3);
        if (level != null) await _openLevel(level, relearn: true);
        return;
      case V4CompletionAction.requestNewCourse:
      case V4CompletionAction.relearn:
      case V4CompletionAction.stop:
        _returnToListening();
        return;
    }
  }

  ListeningTopicContent? _adjacentTopic(int offset) {
    final group = widget.contentGroup;
    final current = widget.topicContent;
    if (group == null || current == null) return null;
    final index = group.topics.indexWhere((topic) => topic.id == current.id);
    final nextIndex = index + offset;
    if (index < 0 || nextIndex < 0 || nextIndex >= group.topics.length) {
      return null;
    }
    return group.topics[nextIndex];
  }

  Future<void> _openLevel(
    ListeningLevelContent level, {
    bool relearn = false,
  }) async {
    final group = widget.contentGroup;
    if (group == null || level.topicNumbers.isEmpty) return;
    final firstTopicNumber = level.topicNumbers.first;
    final topic = group.topics
        .where((candidate) => candidate.number == firstTopicNumber)
        .firstOrNull;
    if (topic != null) await _openContentTopic(topic, relearn: relearn);
  }

  Future<void> _openContentTopic(
    ListeningTopicContent topic, {
    bool relearn = false,
  }) async {
    if (topic.lessons.isEmpty || !mounted) return;
    final lesson = topic.lessons.first;
    unawaited(
      const ActiveListeningSessionStore().save(
        childAge: widget.startAge,
        topicNumber: topic.number,
        lessonNumber: lesson.number,
      ),
    );
    await widget.progressStore.saveCurrentSentence(lesson.id, 0);
    if (relearn) {
      await widget.progressStore.clearV4LessonActivityCompleted(lesson.id);
      await widget.progressStore.saveResumeStage(
        lesson.id,
        ListeningResumeStage.core,
      );
    }
    final ageCatalog = listeningCatalogs.firstWhere(
      (catalog) =>
          catalog.startAge == widget.startAge &&
          catalog.endAge == widget.endAge,
    );
    final topicIndex = (topic.number - 1).clamp(
      0,
      ageCatalog.topics.length - 1,
    );
    await widget.mediaService.stopPlayback();
    if (!mounted) return;
    _handingOffMediaPlayback = true;
    await pushReplacementForActiveLearning<void, void>(
      context,
      (_) => LessonIntroScreen(
        language: widget.language,
        startAge: widget.startAge,
        endAge: widget.endAge,
        topic: ageCatalog.topics[topicIndex],
        lesson: lesson,
        controller: widget.controller,
        topicContent: topic,
        contentGroup: widget.contentGroup,
        levelContent: widget.contentGroup?.level(topic.levelNumber),
        progressStore: widget.progressStore,
        mediaService: widget.mediaService,
        relearnFromBeginning: relearn,
        onTopicCompleted: widget.onTopicCompleted,
      ),
    );
  }

  Future<bool> _openV4SongStageIfNeeded() async {
    if (!widget.lesson.hasV4SongStage) {
      return true;
    }
    final songTitle = widget.lesson.songTitle!.trim();
    final action = await Navigator.of(context).push<V4SongStageAction>(
      MaterialPageRoute<V4SongStageAction>(
        builder: (_) => V4SongStageScreen(
          language: widget.language,
          songTitle: songTitle,
          songAudioId: widget.lesson.songAudioId,
          songAudioUri: widget.lesson.songAudioUri,
          mediaService: widget.mediaService,
          voicePromptService: _voicePromptService,
        ),
      ),
    );
    return mounted && action != null;
  }

  static int _stableChallengeSeed(String value) {
    return value.codeUnits.fold<int>(0, (seed, unit) => seed * 31 + unit);
  }

  bool get _isLastLessonInLevel {
    final topic = widget.topicContent;
    final level = widget.levelContent;
    return widget.lesson.usesV4Flow &&
        topic != null &&
        level != null &&
        level.topicNumbers.isNotEmpty &&
        level.topicNumbers.last == topic.number &&
        topic.lessons.isNotEmpty &&
        topic.lessons.last.id == widget.lesson.id;
  }

  Future<bool> _runV4LevelMissionIfNeeded({
    bool resumeReinforcement = false,
  }) async {
    final level = widget.levelContent;
    if (!_isLastLessonInLevel) {
      return true;
    }
    if (level == null ||
        level.missionBank.length < LessonMissionResult.requiredQuestionCount) {
      return _reportInvalidMissionContent();
    }
    if (await widget.progressStore.hasPassedLevelMission(level.id)) {
      return true;
    }

    var missionAttempt = await widget.progressStore.readMissionAttempt(
      level.id,
    );
    var savedSelection = await widget.progressStore.readMissionSelection(
      level.id,
    );
    var savedAnswers = await widget.progressStore.readMissionAnswers(level.id);
    final weakTargetIds = await widget.progressStore.readMissionWeakTargets(
      level.id,
    );
    var isResumingMission =
        savedSelection.length == LessonMissionResult.requiredQuestionCount;
    if (resumeReinforcement && isResumingMission && weakTargetIds.isNotEmpty) {
      final savedMissions = <ListeningMissionContent>[
        for (final id in savedSelection)
          ...level.missionBank.where((mission) => mission.id == id),
      ];
      await _playMissionRemediation(
        savedMissions,
        LessonMissionResult(
          answers: const <LessonMissionAnswer>[],
          score: 0,
          total: savedMissions.length,
          weakTargetIds: weakTargetIds.toList(growable: false),
        ),
      );
      if (!mounted) return false;
      await _voicePromptService.speakAndWait(
        'Xong rồi. Mình thử lại Nhiệm vụ cuối Level nhé.',
      );
      savedSelection = const <String>[];
      savedAnswers = const <String, bool>{};
      isResumingMission = false;
      await widget.progressStore.saveMissionSelection(level.id, savedSelection);
    }
    await widget.progressStore.saveResumeStage(
      widget.lesson.id,
      ListeningResumeStage.mission,
    );
    if (!isResumingMission && !resumeReinforcement) {
      await _voicePromptService.speakAndWait(v4MissionIntro);
      if (!mounted) return false;
    }

    final selector = const AuthoredQuestionSelector();
    final excludedQuestionIds = <String>{};
    final seed = _stableChallengeSeed(level.id);

    while (mounted) {
      var missions =
          savedSelection.length == LessonMissionResult.requiredQuestionCount
          ? <ListeningMissionContent>[
              for (final id in savedSelection)
                ...level.missionBank.where((mission) => mission.id == id),
            ]
          : selector.selectMissionsForLevel(
              level,
              seed: seed,
              counter: _v4MissionCounter++,
              excludedQuestionIds: excludedQuestionIds,
              weakTargetIds: weakTargetIds,
            );
      // Once every authored prompt has been used, begin a new rotation rather
      // than inventing a question or silently treating an incomplete mission
      // as a pass.
      if (missions.length != LessonMissionResult.requiredQuestionCount) {
        excludedQuestionIds.clear();
        missions = selector.selectMissionsForLevel(
          level,
          seed: seed,
          counter: _v4MissionCounter++,
          weakTargetIds: weakTargetIds,
        );
      }
      if (missions.length != LessonMissionResult.requiredQuestionCount) {
        return _reportInvalidMissionContent();
      }
      if (savedSelection.isEmpty) {
        savedAnswers = const <String, bool>{};
        await widget.progressStore.saveMissionSelection(
          level.id,
          missions.map((mission) => mission.id).toList(growable: false),
        );
        missionAttempt += 1;
        await widget.progressStore.saveMissionAttempt(level.id, missionAttempt);
      }
      if (!mounted) {
        return false;
      }

      final result = await Navigator.of(context).push<LessonMissionResult>(
        MaterialPageRoute<LessonMissionResult>(
          builder: (_) => LessonMissionScreen(
            language: widget.language,
            startAge: widget.startAge,
            lesson: widget.lesson,
            missions: missions,
            mediaService: widget.mediaService,
            attemptEvaluator: _attemptEvaluator,
            voicePromptService: _voicePromptService,
            onStarEarnedWithResult: _saveAuthoredAnswerToStarsResult,
            initialAnswers: savedAnswers,
            onAnswerResolved: (answer) =>
                widget.progressStore.saveMissionAnswer(
                  level.id,
                  answer.missionId,
                  correct: answer.correct,
                ),
            iosSpeechInput: _usesIosNativeLessonRecognition
                ? _iosLessonSpeechInput
                : null,
            levelTitle: 'Level ${level.number}: ${level.titleVi}',
          ),
        ),
      );
      if (!mounted || result == null) {
        return false;
      }
      if (result.passed) {
        await widget.progressStore.markLevelMissionPassed(level.id);
        await widget.progressStore.clearMissionSession(level.id);
        return mounted;
      }

      excludedQuestionIds.addAll(missions.map((mission) => mission.id));
      weakTargetIds
        ..clear()
        ..addAll(result.weakTargetIds);
      await widget.progressStore.saveMissionWeakTargets(
        level.id,
        weakTargetIds,
      );
      await widget.progressStore.saveResumeStage(
        widget.lesson.id,
        ListeningResumeStage.reinforcement,
      );
      if (!mounted) {
        return false;
      }
      if (missionAttempt <= 1) {
        await _voicePromptService.speakAndWait(
          'Mình luyện nhanh vài phần rồi thử lại nhé.',
        );
      } else {
        final continueLearning = await _askContinueAfterMissionFailure();
        if (!continueLearning) return false;
      }
      await _playMissionRemediation(missions, result);
      if (!mounted) {
        return false;
      }
      await _voicePromptService.speakAndWait(
        'Xong rồi. Mình thử lại Nhiệm vụ cuối Level nhé.',
      );
      savedSelection = const <String>[];
      savedAnswers = const <String, bool>{};
      await widget.progressStore.saveMissionSelection(level.id, savedSelection);
      await widget.progressStore.saveResumeStage(
        widget.lesson.id,
        ListeningResumeStage.mission,
      );
    }
    return false;
  }

  Future<bool> _reportInvalidMissionContent() async {
    const message =
        'Nhiệm vụ cuối Level chưa đủ 4 câu hỏi. Bạn cập nhật nội dung rồi thử lại nhé.';
    if (mounted) setState(() => _message = message);
    try {
      await _voicePromptService.speakAndWait(message);
    } catch (_) {
      // The visible error still blocks an invalid Level completion.
    }
    return false;
  }

  Future<void> _reportInvalidChallengeContent() async {
    const message =
        'Phần thử thách chưa đủ 2 câu hỏi. Bạn cập nhật nội dung rồi thử lại nhé.';
    if (mounted) setState(() => _message = message);
    try {
      await _voicePromptService.speakAndWait(message);
    } catch (_) {
      // The visible error still blocks invalid lesson completion.
    }
  }

  Future<bool> _askContinueAfterMissionFailure() async {
    const prompt =
        'Mình luyện lại thêm một lần nữa nhé. Bạn muốn luyện tiếp hay dừng lại?';
    await _voicePromptService.speakAndWait(prompt);
    if (!mounted) return false;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                prompt,
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('mission-continue-reinforcement'),
                onPressed: () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Luyện tiếp'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('mission-stop-reinforcement'),
                onPressed: () => Navigator.of(sheetContext).pop(false),
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Dừng lại'),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _playMissionRemediation(
    List<ListeningMissionContent> missions,
    LessonMissionResult result,
  ) async {
    final weakTargets = result.weakTargetIds.toSet();
    final reviewedTargets = <String>{};
    final reinforcementMissions = <ListeningMissionContent>[];
    for (final mission in missions) {
      if (!weakTargets.contains(mission.coverageTargetId) ||
          !reviewedTargets.add(mission.coverageTargetId)) {
        continue;
      }
      reinforcementMissions.add(mission);
    }
    if (reinforcementMissions.isEmpty || !mounted) return;
    await Navigator.of(context).push<LessonMissionResult>(
      MaterialPageRoute<LessonMissionResult>(
        builder: (_) => LessonMissionScreen(
          language: widget.language,
          startAge: widget.startAge,
          lesson: widget.lesson,
          missions: reinforcementMissions,
          mediaService: widget.mediaService,
          attemptEvaluator: _attemptEvaluator,
          voicePromptService: _voicePromptService,
          iosSpeechInput: _usesIosNativeLessonRecognition
              ? _iosLessonSpeechInput
              : null,
          isReinforcement: true,
          levelTitle: 'Củng cố Level ${widget.levelContent?.number ?? ''}',
        ),
      ),
    );
  }

  ListeningLessonContent? get _nextLessonInTopic {
    final content = widget.topicContent;
    if (content == null) {
      return null;
    }
    final lessons =
        content.lessons.any((lesson) => lesson.id == widget.lesson.id)
        ? content.lessons
        : content.songs.any((lesson) => lesson.id == widget.lesson.id)
        ? content.songs
        : const <ListeningLessonContent>[];
    final currentIndex = lessons.indexWhere(
      (lesson) => lesson.id == widget.lesson.id,
    );
    if (currentIndex < 0 || currentIndex >= lessons.length - 1) {
      return null;
    }
    return lessons[currentIndex + 1];
  }

  ListeningLessonContent? get _previousLessonInTopic {
    final content = widget.topicContent;
    if (content == null) {
      return null;
    }
    final lessons =
        content.lessons.any((lesson) => lesson.id == widget.lesson.id)
        ? content.lessons
        : content.songs.any((lesson) => lesson.id == widget.lesson.id)
        ? content.songs
        : const <ListeningLessonContent>[];
    final currentIndex = lessons.indexWhere(
      (lesson) => lesson.id == widget.lesson.id,
    );
    if (currentIndex <= 0) {
      return null;
    }
    return lessons[currentIndex - 1];
  }

  Future<void> _openNextLesson(ListeningLessonContent lesson) async {
    await widget.mediaService.stopPlayback();
    final topicNumber = widget.topicContent?.number;
    if (topicNumber != null) {
      unawaited(
        const ActiveListeningSessionStore().save(
          childAge: widget.startAge,
          topicNumber: topicNumber,
          lessonNumber: lesson.number,
        ),
      );
    }
    await widget.progressStore.saveCurrentSentence(lesson.id, 0);
    if (lesson.usesV4Flow) {
      await widget.progressStore.saveResumeStage(
        lesson.id,
        ListeningResumeStage.core,
      );
    }
    if (!mounted) {
      return;
    }
    // The next intro reuses this media service and may start before Flutter
    // disposes the replaced practice route. Do not let the old route's
    // dispose() stop the new route's intro audio.
    _handingOffMediaPlayback = true;
    await pushReplacementForActiveLearning<void, void>(
      context,
      (_) => LessonIntroScreen(
        language: widget.language,
        startAge: widget.startAge,
        endAge: widget.endAge,
        topic: widget.topic,
        lesson: lesson,
        controller: widget.controller,
        topicContent: widget.topicContent,
        contentGroup: widget.contentGroup,
        levelContent: widget.levelContent,
        progressStore: widget.progressStore,
        mediaService: widget.mediaService,
        onTopicCompleted: widget.onTopicCompleted,
      ),
    );
  }

  Future<void> _restartCurrentLesson() async {
    _recordingStartRequest += 1;
    _recordingLifecycleGeneration += 1;
    _attemptEvaluationRequest += 1;
    _recordingAutoStopTimer?.cancel();
    _recordingAutoStopTimer = null;
    await widget.mediaService.stopPlayback();
    if (_recording || _recordingStartPending) {
      await _cancelLessonAttemptCapture();
    }
    try {
      await widget.mediaService.deleteRecordingsForLesson(widget.lesson.id);
    } catch (_) {
      // Local storage can be unavailable in a restricted browser session. The
      // lesson progress is still reset so the child can start again.
    }
    try {
      await widget.progressStore.clearSkippedSentences(widget.lesson.id);
      await widget.progressStore.clearNeedsPracticeSentences(widget.lesson.id);
      if (widget.lesson.usesV4Flow) {
        await widget.progressStore.clearV4LessonActivityCompleted(
          widget.lesson.id,
        );
        await widget.progressStore.saveResumeStage(
          widget.lesson.id,
          ListeningResumeStage.core,
        );
      }
    } catch (_) {
      // Restarting still works when local progress storage is unavailable.
    }
    await widget.progressStore.saveCurrentSentence(widget.lesson.id, 0);
    if (!mounted) {
      return;
    }
    setState(() {
      _sentenceIndex = 0;
      _skippedSentenceIndexes.clear();
      _needsPracticeSentenceIndexes.clear();
      _recordingPath = null;
      _recordingDuration = null;
      _recording = false;
      _recordingStartPending = false;
      _mediaBusy = false;
      _message = null;
    });
    await _activateCurrentSentence(autoPlay: true);
  }

  Future<void> _openRelearnCurrentLesson() async {
    await widget.progressStore.saveCurrentSentence(widget.lesson.id, 0);
    await widget.progressStore.clearV4LessonActivityCompleted(widget.lesson.id);
    await widget.progressStore.saveResumeStage(
      widget.lesson.id,
      ListeningResumeStage.core,
    );
    await widget.mediaService.stopPlayback();
    if (!mounted) return;
    _handingOffMediaPlayback = true;
    await pushReplacementForActiveLearning<void, void>(
      context,
      (_) => LessonIntroScreen(
        language: widget.language,
        startAge: widget.startAge,
        endAge: widget.endAge,
        topic: widget.topic,
        lesson: widget.lesson,
        controller: widget.controller,
        topicContent: widget.topicContent,
        contentGroup: widget.contentGroup,
        levelContent: widget.levelContent,
        progressStore: widget.progressStore,
        mediaService: widget.mediaService,
        relearnFromBeginning: true,
        onTopicCompleted: widget.onTopicCompleted,
      ),
    );
  }

  Future<void> _listenForCompletionChoice() async {
    if (!mounted ||
        _pausedForMainAssistant ||
        _completionChoiceRecording ||
        _completionChoiceStopping) {
      return;
    }
    final pauseGeneration = _mainPauseGeneration;
    final choiceGeneration = ++_completionChoiceGeneration;
    setState(() {
      _mediaBusy = true;
      _recordingStartPending = true;
      _message = 'Đang mở micro để nghe lựa chọn của con…';
    });
    try {
      final readyCuePlayer = _voicePromptService;
      if (readyCuePlayer is SpeechReadyCuePlayer) {
        await (readyCuePlayer as SpeechReadyCuePlayer).playSpeechReadyCue();
      }
      if (!mounted ||
          _pausedForMainAssistant ||
          pauseGeneration != _mainPauseGeneration ||
          choiceGeneration != _completionChoiceGeneration) {
        return;
      }
      final deviceStart = widget.mediaService.startRecording(
        lessonId: '${widget.lesson.id}-completion-choice',
        sentenceNumber: 0,
        lessonTitle: widget.lesson.titleVi,
        sentenceId: '${widget.lesson.id}-completion-choice',
        saveToHistory: false,
      );
      _recordingDeviceStartInProgress = deviceStart;
      try {
        await deviceStart;
      } finally {
        if (identical(_recordingDeviceStartInProgress, deviceStart)) {
          _recordingDeviceStartInProgress = null;
        }
      }
      if (!mounted ||
          _pausedForMainAssistant ||
          pauseGeneration != _mainPauseGeneration ||
          choiceGeneration != _completionChoiceGeneration) {
        await widget.mediaService.cancelRecording();
        return;
      }
      setState(() {
        _completionChoiceRecording = true;
        _recording = true;
        _recordingStartPending = false;
        _mediaBusy = false;
        _message = _activeV4CompletionStage == null
            ? 'Con nói “Luyện lại từ đầu” hoặc “Bài tiếp theo” nhé.'
            : 'HOMI đang nghe lựa chọn của con…';
      });
      _recordingAutoStopTimer?.cancel();
      _recordingAutoStopTimer = Timer(
        const Duration(seconds: 6),
        () => unawaited(_stopCompletionChoiceRecording()),
      );
    } catch (error) {
      if (_pausedForMainAssistant ||
          pauseGeneration != _mainPauseGeneration ||
          choiceGeneration != _completionChoiceGeneration) {
        await widget.mediaService.cancelRecording().catchError((Object _) {});
        return;
      }
      if (!mounted) return;
      setState(() {
        _recordingStartPending = false;
        _mediaBusy = false;
        _recording = false;
      });
      if (_v4CompletionChoiceVisible && _activeV4CompletionStage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa mở được micro. Con chạm một nút để chọn nhé.'),
          ),
        );
      } else {
        await _showCompletionChoiceFallback(error.toString());
      }
    }
  }

  Future<void> _stopCompletionChoiceRecording() async {
    if (!_completionChoiceRecording || _completionChoiceStopping) {
      return;
    }
    _completionChoiceStopping = true;
    final choiceGeneration = _completionChoiceGeneration;
    _recordingAutoStopTimer?.cancel();
    _recordingAutoStopTimer = null;
    if (mounted) {
      setState(() {
        _mediaBusy = true;
        _message = 'Đang nghe câu trả lời của con…';
      });
    }
    LessonRecording? recording;
    try {
      recording = await widget.mediaService.stopRecording();
      if (mounted) {
        setState(() {
          _completionChoiceRecording = false;
          _recording = false;
          _message = 'Đang nhận diện lựa chọn…';
        });
      }
      final transcript = await _completionChoiceRecognizer.transcribe(
        recording,
      );
      if (choiceGeneration != _completionChoiceGeneration) return;
      final v4Stage = _activeV4CompletionStage;
      if (_v4CompletionChoiceVisible && v4Stage != null) {
        final action = const V4CompletionChoiceResolver().resolve(
          transcript,
          stage: v4Stage,
          allowedActions: _activeV4CompletionActions,
        );
        if (!mounted) return;
        if (action == null) {
          setState(() {
            _mediaBusy = false;
            _message = 'Cô chưa nghe rõ lựa chọn. Con chạm một nút nhé.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cô chưa nghe rõ lựa chọn. Con có thể chạm một nút bên dưới.',
              ),
            ),
          );
          return;
        }
        Navigator.of(context).pop(action);
        return;
      }
      final choice = const LessonCompletionChoiceResolver().resolve(transcript);
      if (!mounted) {
        return;
      }
      if (choice == null) {
        await _showCompletionChoiceFallback(
          'Cô nghe được “$transcript” nhưng chưa rõ lựa chọn của con.',
        );
        return;
      }
      setState(() => _mediaBusy = false);
      await _handleCompletionChoice(choice);
    } catch (error) {
      if (mounted) {
        setState(() {
          _completionChoiceRecording = false;
          _recording = false;
        });
        if (_v4CompletionChoiceVisible && _activeV4CompletionStage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Chưa nhận diện được giọng nói. Con chạm một nút để chọn nhé.',
              ),
            ),
          );
        } else {
          await _showCompletionChoiceFallback(error.toString());
        }
      }
    } finally {
      if (recording != null) {
        await widget.mediaService
            .deleteRecording(recording.filePath)
            .catchError((Object _) {});
      }
      _completionChoiceStopping = false;
      if (mounted) {
        setState(() => _mediaBusy = false);
      }
    }
  }

  Future<void> _cancelCompletionChoiceCapture() async {
    _completionChoiceGeneration += 1;
    _recordingAutoStopTimer?.cancel();
    _recordingAutoStopTimer = null;
    final shouldCancel =
        _completionChoiceRecording ||
        _recordingStartPending ||
        _recordingDeviceStartInProgress != null;
    _completionChoiceRecording = false;
    if (mounted) {
      setState(() {
        _recording = false;
        _recordingStartPending = false;
        _mediaBusy = false;
      });
    }
    if (shouldCancel && !_completionChoiceStopping) {
      await widget.mediaService.cancelRecording().catchError((Object _) {});
    }
  }

  Future<void> _handleCompletionChoice(LessonCompletionChoice choice) async {
    switch (choice) {
      case LessonCompletionChoice.restartLesson:
        await _restartCurrentLesson();
        return;
      case LessonCompletionChoice.nextLesson:
        final nextLesson = _nextLessonInTopic;
        if (nextLesson != null) {
          await _openNextLesson(nextLesson);
          return;
        }
        if (mounted) {
          setState(() => _mediaBusy = true);
        }
        try {
          await _playPrompt(LessonGuideFlowV2.topicCompleted);
        } finally {
          if (mounted) {
            setState(() => _mediaBusy = false);
          }
        }
        // The lesson and Main assistant use separate Dart service instances
        // backed by the same native Android TTS engine. Release this route's
        // owned service before opening the next prompt so dispose() cannot
        // stop Bi cô's topic-selection question during the pop transition.
        await _releaseOwnedVoicePromptService();
        widget.onTopicCompleted?.call();
        _returnToListening();
        return;
    }
  }

  Future<void> _releaseOwnedVoicePromptService() async {
    if (!_ownsVoicePromptService || _ownedVoicePromptReleased) {
      return;
    }
    _ownedVoicePromptReleased = true;
    await _voicePromptService.dispose();
  }

  Future<void> _showCompletionChoiceFallback(String reason) async {
    if (!mounted) {
      return;
    }
    await _playPrompt(LessonGuideFlowV2.completionChoiceUnclear);
    if (!mounted) {
      return;
    }
    setState(() {
      _mediaBusy = false;
      _message = 'Cô chưa nghe rõ. Con chọn một nút bên dưới nhé.';
    });
    final action = await showModalBottomSheet<_CompletionChoiceFallbackAction>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: false,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Con muốn học thế nào?',
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                reason.replaceFirst('Bad state: ', ''),
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('restart-lesson-choice'),
                onPressed: () => Navigator.of(
                  sheetContext,
                ).pop(_CompletionChoiceFallbackAction.restart),
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Luyện lại từ đầu'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('next-lesson-choice'),
                onPressed: () => Navigator.of(
                  sheetContext,
                ).pop(_CompletionChoiceFallbackAction.next),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Bài tiếp theo'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('retry-voice-choice'),
                onPressed: () => Navigator.of(
                  sheetContext,
                ).pop(_CompletionChoiceFallbackAction.retry),
                icon: const Icon(Icons.mic_rounded),
                label: const Text('Nói lại lựa chọn'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _CompletionChoiceFallbackAction.restart:
        await _handleCompletionChoice(LessonCompletionChoice.restartLesson);
        return;
      case _CompletionChoiceFallbackAction.next:
        await _handleCompletionChoice(LessonCompletionChoice.nextLesson);
        return;
      case _CompletionChoiceFallbackAction.retry:
        await _playPrompt(LessonGuideFlowV2.completionChoice);
        await _listenForCompletionChoice();
        return;
    }
  }

  void _returnToListening() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).popUntil(
      (route) =>
          route.settings.name == ListeningRouteNames.topicCatalog ||
          route.isFirst,
    );
  }

  Future<Set<int>> _readUnrecordedSentenceIndexes() async {
    final recordings = await Future.wait<String?>(
      widget.lesson.sentences.map(
        (sentence) => widget.mediaService.existingRecording(
          lessonId: widget.lesson.id,
          sentenceNumber: sentence.number,
          sentenceId: sentence.id,
        ),
      ),
    );
    return <int>{
      for (var index = 0; index < recordings.length; index++)
        if (recordings[index] == null) index,
      ..._needsPracticeSentenceIndexes,
    };
  }

  void _scheduleIdleReminder() {
    _cancelIdleReminder();
    if (_usesGuideV2 || !mounted || _recording || _recordingPath != null) {
      return;
    }
    _idleReminderTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _recording || _recordingPath != null) {
        return;
      }
      setState(() => _message = null);
      _showCoachPopup(
        _LessonCoachPopupKind.firstReminder,
        onDismissed: _scheduleSecondIdleReminder,
      );
      unawaited(_playGuideCue(LessonGuideCue.idleFirst));
    });
  }

  void _scheduleSecondIdleReminder() {
    if (!mounted || _recording || _recordingPath != null) {
      return;
    }
    _idleReminderTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _recording || _recordingPath != null) {
        return;
      }
      setState(() {
        _showSkip = true;
        _message = null;
      });
      _showCoachPopup(_LessonCoachPopupKind.secondReminder);
      unawaited(_playGuideCue(LessonGuideCue.idleSecond));
    });
  }

  void _cancelIdleReminder() {
    _idleReminderTimer?.cancel();
    _idleReminderTimer = null;
  }

  Future<Uri?> _randomGuideUri(LessonGuideCue cue) async {
    try {
      return await _guideAudioLibrary.randomUri(
        cue,
        startAge: widget.startAge,
        endAge: widget.endAge,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _playGuideCue(LessonGuideCue cue) async {
    final uri = await _randomGuideUri(cue);
    if (uri == null || !mounted) {
      return false;
    }
    try {
      await widget.mediaService.playToCompletion(
        uri,
        timeout: const Duration(seconds: 10),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startGuidedSentenceSequence() async {
    if (_pausedForMainAssistant ||
        _guidedSequenceStarted ||
        _recording ||
        _mediaBusy) {
      return;
    }
    final sampleUri = _sentence.audioUri;
    if (!_usesGuideV2) {
      if (sampleUri != null) {
        await _runMediaAction(() => widget.mediaService.play(sampleUri));
      }
      return;
    }
    if (_recordingPath != null) {
      return;
    }
    _guidedSequenceStarted = true;
    final pauseGeneration = _mainPauseGeneration;
    if (mounted) {
      setState(() {
        _mediaBusy = true;
        _message = widget.lesson.usesV4Flow
            ? _sentence.english
            : LessonGuideFlowV2.beforeSentence.text;
      });
    }
    try {
      if (!widget.lesson.usesV4Flow) {
        await _playPrompt(LessonGuideFlowV2.beforeSentence);
        if (_pausedForMainAssistant ||
            pauseGeneration != _mainPauseGeneration) {
          return;
        }
        await Future<void>.delayed(LessonGuideFlowV2.guideToSamplePause);
        if (!mounted ||
            _pausedForMainAssistant ||
            pauseGeneration != _mainPauseGeneration) {
          return;
        }
      }
      await _playBilingualSentenceSample();
      if (_pausedForMainAssistant || pauseGeneration != _mainPauseGeneration) {
        return;
      }
      await _playPrompt(_repeatTargetPrompt);
    } catch (error) {
      _setMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() => _mediaBusy = false);
      }
    }
    if (mounted && !_pausedForMainAssistant && _recordingPath == null) {
      await _startRecording();
    }
  }

  Future<void> _playPrompt(LessonGuidePrompt prompt) async {
    if (!mounted || _pausedForMainAssistant) {
      return;
    }
    final pauseGeneration = _mainPauseGeneration;
    setState(() => _message = prompt.text);
    final uri = await _guideAudioLibrary.uriForAudioCode(prompt.audioCode);
    if (!mounted ||
        _pausedForMainAssistant ||
        pauseGeneration != _mainPauseGeneration) {
      return;
    }
    if (uri != null) {
      await widget.mediaService.playToCompletion(
        uri,
        timeout: const Duration(seconds: 16),
      );
      return;
    }
    await widget.mediaService.prepareSelectedLessonOutput();
    await _speakLessonPrompt(prompt.text);
  }

  Future<void> _speakLessonPrompt(
    String text, {
    String locale = 'vi-VN',
  }) async {
    final promptService = _voicePromptService;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        promptService is SelectedMediaOutputVoicePromptService) {
      await (promptService as SelectedMediaOutputVoicePromptService)
          .speakAndWaitOnSelectedMediaOutput(text, locale: locale);
      return;
    }
    await promptService.speakAndWait(text, locale: locale);
  }

  Future<void> _playBilingualSentenceSample() async {
    final englishUri = await _resolveAuthoredAudio(
      _sentence.audioUri,
      _sentence.englishAudioId,
    );
    if (englishUri != null) {
      await widget.mediaService.playToCompletion(englishUri);
    } else {
      await widget.mediaService.prepareSelectedLessonOutput();
      await _speakLessonPrompt(_sentence.english, locale: 'en-US');
    }
    if (!mounted || _pausedForMainAssistant) {
      return;
    }
    await Future<void>.delayed(LessonGuideFlowV2.englishToVietnamesePause);
    if (!mounted || _pausedForMainAssistant) {
      return;
    }
    final vietnameseUri = await _resolveAuthoredAudio(
      _sentence.vietnameseAudioUri,
      _sentence.vietnameseAudioId,
    );
    if (vietnameseUri != null) {
      await widget.mediaService.playToCompletion(vietnameseUri);
    } else {
      await widget.mediaService.prepareSelectedLessonOutput();
      await _speakLessonPrompt(_sentence.vietnamese, locale: 'vi-VN');
    }
  }

  Future<Uri?> _resolveAuthoredAudio(Uri? uri, String? audioId) async {
    if (uri != null) return uri;
    final id = audioId?.trim();
    if (id == null || id.isEmpty) return null;
    return _guideAudioLibrary.uriForAudioCode(id);
  }

  Future<void> _playSampleThenInviteRecording(Uri uri) async {
    if (!_usesGuideV2) {
      await _playLessonAudioThenRecordGuide(uri);
      return;
    }
    await widget.mediaService.playToCompletion(uri);
    if (!mounted) {
      return;
    }
    await _playPrompt(_repeatTargetPrompt);
  }

  Future<void> _playLessonAudioThenRecordGuide(Uri uri) async {
    await widget.mediaService.playToCompletion(uri);
    if (!mounted) {
      return;
    }
    await _playGuideCue(LessonGuideCue.record);
  }

  Future<void> _playGuideCueWithBusyState(LessonGuideCue cue) async {
    if (!mounted) {
      return;
    }
    setState(() => _mediaBusy = true);
    try {
      await _playGuideCue(cue);
    } finally {
      if (mounted) {
        setState(() => _mediaBusy = false);
      }
    }
  }

  void _showCoachPopup(
    _LessonCoachPopupKind kind, {
    VoidCallback? onDismissed,
  }) {
    _coachPopupTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() => _coachPopupKind = kind);
    const displayDuration = Duration(milliseconds: 2500);
    _coachPopupTimer = Timer(displayDuration, () {
      if (!mounted || _coachPopupKind != kind) {
        return;
      }
      setState(() => _coachPopupKind = null);
      _coachPopupTimer = null;
      onDismissed?.call();
    });
  }

  void _showPraiseFireworks() {
    _praiseFireworksTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _praiseFireworksSequence += 1;
      _praiseFireworksVisible = true;
    });
    _praiseFireworksTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || !_praiseFireworksVisible) {
        return;
      }
      setState(() => _praiseFireworksVisible = false);
      _praiseFireworksTimer = null;
    });
  }

  void _hideCoachPopup() {
    _coachPopupTimer?.cancel();
    _coachPopupTimer = null;
    _praiseFireworksTimer?.cancel();
    _praiseFireworksTimer = null;
    if (mounted && (_coachPopupKind != null || _praiseFireworksVisible)) {
      setState(() {
        _coachPopupKind = null;
        _praiseFireworksVisible = false;
      });
    }
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          LessonRecordingHistorySheet(mediaService: widget.mediaService),
    );
  }

  void _setMessage(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _message = _childFriendlyMessage(message));
  }

  String _childFriendlyMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('credential') ||
        normalized.contains('installation') ||
        normalized.contains('xác thực')) {
      return 'HOMI đang làm mới kết nối. Con nhấn ghi âm lại nhé.';
    }
    return message;
  }
}

class _LessonHeader extends StatelessWidget {
  const _LessonHeader({
    required this.current,
    required this.total,
    required this.onBack,
  });

  final int current;
  final int total;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      child: Row(
        children: <Widget>[
          IconButton.filled(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: context.tr('Quay lại', '返回'),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(52),
              backgroundColor: isDark
                  ? colorScheme.surfaceContainerHighest
                  : const Color(0xF8FFFDF9),
              foregroundColor: isDark ? colorScheme.onSurface : AppColors.ink,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? colorScheme.surfaceContainer
                  : const Color(0xF8FFFDF9),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: isDark ? colorScheme.outline : const Color(0xCCFFFFFF),
                width: 1.3,
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x22142451),
                  blurRadius: 16,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: Text(
              context.tr('Câu $current/$total', '第 $current/$total 句'),
              style: TextStyle(
                color: isDark ? colorScheme.onSurface : AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark
                  ? colorScheme.surfaceContainer
                  : const Color(0xF8FFFDF9),
              border: Border.all(
                color: isDark ? colorScheme.outline : const Color(0xCCFFFFFF),
                width: 1.3,
              ),
            ),
            child: const Icon(Icons.star_rounded, color: Color(0xFFFFC75B)),
          ),
        ],
      ),
    );
  }
}

class _SentenceCard extends StatelessWidget {
  const _SentenceCard({
    required this.sentence,
    required this.lessonType,
    required this.current,
    required this.total,
    required this.onPlaySample,
    required this.onPlayVietnamese,
  });

  final ListeningSentenceContent sentence;
  final ListeningLessonType lessonType;
  final int current;
  final int total;
  final VoidCallback onPlaySample;
  final VoidCallback onPlayVietnamese;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final englishSize = sentence.english.length > 55
        ? 28.0
        : sentence.english.length > 30
        ? 34.0
        : 46.0;
    return HomiSurface(
      constraints: const BoxConstraints(minHeight: 300),
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      color: isDark
          ? colorScheme.surfaceContainer.withValues(alpha: 0.97)
          : null,
      elevated: true,
      child: Column(
        children: <Widget>[
          if (lessonType != ListeningLessonType.standard) ...<Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: lessonType == ListeningLessonType.song
                    ? (isDark
                          ? Color.alphaBlend(
                              colorScheme.error.withValues(alpha: 0.12),
                              colorScheme.surfaceContainerHighest,
                            )
                          : const Color(0xFFFFF1F5))
                    : (isDark
                          ? colorScheme.surfaceContainerHighest
                          : AppColors.lavenderSoft),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    lessonType == ListeningLessonType.song
                        ? Icons.music_note_rounded
                        : Icons.forum_rounded,
                    size: 18,
                    color: lessonType == ListeningLessonType.song
                        ? AppColors.coral
                        : AppColors.indigo,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    lessonType == ListeningLessonType.song
                        ? context.tr(
                            'Dòng $current/$total',
                            '歌词 $current/$total',
                          )
                        : context.tr(
                            '${sentence.voice.isEmpty ? 'Lượt thoại' : sentence.voice} · $current/$total',
                            '${sentence.voice.isEmpty ? '对话角色' : sentence.voice} · $current/$total',
                          ),
                    style: TextStyle(
                      color: isDark
                          ? colorScheme.onSurface
                          : AppColors.indigoDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],
          Text(
            sentence.english,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? colorScheme.onSurface : AppColors.ink,
              fontSize: englishSize,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            sentence.vietnamese,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: isDark ? colorScheme.primary : AppColors.indigo,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 20),
          const HomiWaveform(
            key: Key('lesson-sample-waveform'),
            active: true,
            width: 230,
            height: 48,
            semanticLabel: 'Dạng sóng câu mẫu',
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('play-lesson-sample'),
                  onPressed: onPlaySample,
                  icon: const Icon(Icons.volume_up_rounded),
                  label: Text(context.tr('Nghe mẫu', '听示范')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: isDark
                        ? colorScheme.surfaceContainerHighest
                        : AppColors.lavenderSoft,
                    foregroundColor: isDark
                        ? colorScheme.primary
                        : AppColors.indigoDark,
                    side: BorderSide(
                      color: isDark
                          ? colorScheme.outline
                          : AppColors.lavenderBorder,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('play-vietnamese-meaning'),
                  onPressed: onPlayVietnamese,
                  icon: const Icon(Icons.translate_rounded),
                  label: Text(context.tr('Nghe tiếng Việt', '听越南语')),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: isDark
                        ? colorScheme.surfaceContainerHighest
                        : AppColors.accentPinkSoft,
                    foregroundColor: isDark
                        ? colorScheme.primary
                        : AppColors.accentPink,
                    side: BorderSide(
                      color: isDark ? colorScheme.outline : AppColors.peach,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VirtualLessonControls extends StatelessWidget {
  const _VirtualLessonControls({
    required this.pending,
    required this.canGoPrevious,
    required this.onPrevious,
    required this.onReplay,
    required this.onNext,
  });

  final bool pending;
  final bool canGoPrevious;
  final VoidCallback onPrevious;
  final VoidCallback onReplay;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: context.tr(
        'Điều khiển AIV0 thử nghiệm trong bài luyện câu',
        '句子练习中的 AIV0 测试控制',
      ),
      child: Container(
        key: const Key('virtual-lesson-controls'),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x24142451),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _VirtualLessonButton(
              key: const Key('virtual-lesson-previous'),
              icon: Icons.skip_previous_rounded,
              label: context.tr('Câu trước', '上一句'),
              onPressed: !pending && canGoPrevious ? onPrevious : null,
            ),
            _VirtualLessonButton(
              key: const Key('virtual-lesson-replay'),
              icon: Icons.replay_rounded,
              label: context.tr('Nghe lại câu', '重听本句'),
              onPressed: pending ? null : onReplay,
            ),
            _VirtualLessonButton(
              key: const Key('virtual-lesson-next'),
              icon: Icons.skip_next_rounded,
              label: context.tr('Câu sau', '下一句'),
              onPressed: pending ? null : onNext,
            ),
          ],
        ),
      ),
    );
  }
}

class _VirtualLessonButton extends StatelessWidget {
  const _VirtualLessonButton({
    required super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      tooltip: label,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.recording,
    required this.busy,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  final bool recording;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      liveRegion: recording,
      label: recording
          ? context.tr('Đang ghi âm, thả để lưu', '正在录音，松开保存')
          : context.tr('Nhấn và giữ để ghi âm', '长按录音'),
      child: GestureDetector(
        onTap: busy ? null : onTap,
        onLongPressStart: busy ? null : (_) => onLongPressStart(),
        onLongPressEnd: busy ? null : (_) => onLongPressEnd(),
        child: AnimatedContainer(
          key: const Key('record-lesson-sentence'),
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: recording ? AppColors.coral : AppColors.indigo,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x303D4DD6),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (busy || recording)
                const HomiWaveform(
                  active: true,
                  width: 50,
                  height: 26,
                  color: Colors.white,
                )
              else
                const Icon(Icons.mic_rounded, color: Colors.white, size: 34),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  context.tr(
                    recording ? 'Thả để lưu bản ghi' : 'Nhấn và giữ để ghi âm',
                    recording ? '松开保存录音' : '长按录音',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonPraiseFireworks extends StatefulWidget {
  const _LessonPraiseFireworks({super.key});

  @override
  State<_LessonPraiseFireworks> createState() => _LessonPraiseFireworksState();
}

class _LessonPraiseFireworksState extends State<_LessonPraiseFireworks>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('lesson-praise-fireworks'),
      liveRegion: true,
      label: context.tr('Con làm tuyệt lắm!', '你做得太棒了！'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final leftProgress = _controller.value;
              final rightProgress = (_controller.value + 0.18) % 1.0;
              final top = constraints.maxHeight * 0.28;
              return Stack(
                children: <Widget>[
                  Positioned(
                    key: const Key('lesson-praise-fireworks-left'),
                    left: 6,
                    top: top,
                    child: _PraiseFireworkBurst(
                      progress: leftProgress,
                      flipHorizontally: false,
                    ),
                  ),
                  Positioned(
                    key: const Key('lesson-praise-fireworks-right'),
                    right: 6,
                    top: top,
                    child: _PraiseFireworkBurst(
                      progress: rightProgress,
                      flipHorizontally: true,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PraiseFireworkBurst extends StatelessWidget {
  const _PraiseFireworkBurst({
    required this.progress,
    required this.flipHorizontally,
  });

  final double progress;
  final bool flipHorizontally;

  @override
  Widget build(BuildContext context) {
    final rise = Curves.easeOutCubic.transform(progress);
    final fade = (1 - ((progress - 0.7) / 0.3)).clamp(0.0, 1.0).toDouble();
    final scale = 0.72 + (Curves.easeOutBack.transform(progress) * 0.34);
    return Transform.translate(
      offset: Offset(0, 70 - (rise * 132)),
      child: Opacity(
        opacity: fade,
        child: Transform.scale(
          scale: scale,
          child: Transform.flip(
            flipX: flipHorizontally,
            child: const SizedBox(
              width: 104,
              height: 168,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned(
                    left: 28,
                    bottom: 8,
                    child: Icon(
                      Icons.celebration_rounded,
                      color: Color(0xFFFFB84D),
                      size: 48,
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 54,
                    child: Icon(
                      Icons.star_rounded,
                      color: AppColors.periwinkle,
                      size: 30,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 34,
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.coral,
                      size: 28,
                    ),
                  ),
                  Positioned(
                    left: 39,
                    top: 2,
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFFFFC75B),
                      size: 25,
                    ),
                  ),
                  Positioned(
                    right: 17,
                    top: 82,
                    child: Icon(
                      Icons.star_rounded,
                      color: AppColors.indigo,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _LessonCoachPopupKind { firstReminder, secondReminder }

enum _CompletionChoiceFallbackAction { restart, next, retry }

class _LessonCoachPopup extends StatefulWidget {
  const _LessonCoachPopup({required this.kind, super.key});

  final _LessonCoachPopupKind kind;

  @override
  State<_LessonCoachPopup> createState() => _LessonCoachPopupState();
}

class _LessonCoachPopupState extends State<_LessonCoachPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondReminder = widget.kind == _LessonCoachPopupKind.secondReminder;
    final title = switch (widget.kind) {
      _LessonCoachPopupKind.firstReminder => context.tr(
        'Đến lượt con rồi!',
        '轮到你啦！',
      ),
      _LessonCoachPopupKind.secondReminder => context.tr(
        'Mình thử nhẹ nhàng nhé',
        '我们轻松试一试吧',
      ),
    };
    final message = switch (widget.kind) {
      _LessonCoachPopupKind.firstReminder => context.tr(
        'Nhấn và giữ nút micro để đọc theo câu mẫu nhé.',
        '请长按麦克风按钮，跟着示范句朗读。',
      ),
      _LessonCoachPopupKind.secondReminder => context.tr(
        'Con có thể nghe mẫu lại, nói chậm hơn hoặc chọn bỏ qua câu này.',
        '你可以重听示范、慢慢说，或选择跳过本句。',
      ),
    };
    final surface = secondReminder
        ? const Color(0xFFFFF7EA)
        : AppColors.mintSoft;
    final border = secondReminder
        ? const Color(0xFFFFD89A)
        : AppColors.lavenderBorder;
    final accent = secondReminder
        ? const Color(0xFFE58A2B)
        : AppColors.primaryNavy;

    return Semantics(
      liveRegion: true,
      label: '$title. $message',
      child: ColoredBox(
        color: const Color(0x24142451),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                key: Key('lesson-coach-popup-${widget.kind.name}'),
                color: surface,
                elevation: 18,
                shadowColor: const Color(0x553D4DD6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                  side: BorderSide(color: border, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        height: 132,
                        width: 210,
                        child: AnimatedBuilder(
                          animation: _controller,
                          builder: (context, child) {
                            final progress = _controller.value;
                            return Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: <Widget>[
                                Positioned(
                                  left: 8,
                                  top: 24 - (progress * 8),
                                  child: Transform.rotate(
                                    angle: -0.2 + (progress * 0.18),
                                    child: Icon(
                                      Icons.auto_awesome_rounded,
                                      color: const Color(0xFFFFB84D),
                                      size: 34,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 12,
                                  top: 14 + (progress * 8),
                                  child: Icon(
                                    secondReminder
                                        ? Icons.favorite_rounded
                                        : Icons.star_rounded,
                                    color: secondReminder
                                        ? AppColors.coral
                                        : AppColors.periwinkle,
                                    size: 31,
                                  ),
                                ),
                                Transform.translate(
                                  offset: Offset(0, -5 * progress),
                                  child: Transform.rotate(
                                    angle: -0.025 + (progress * 0.05),
                                    child: Transform.scale(
                                      scale: 0.97 + (progress * 0.05),
                                      child: child,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                          child: Image.asset(
                            MascotAssets.wave,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: accent,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.ink,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LessonCoachHint extends StatelessWidget {
  const _LessonCoachHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return HomiSurface(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(8, 6, 18, 6),
      color: isDark
          ? colorScheme.surfaceContainer.withValues(alpha: 0.96)
          : null,
      elevated: true,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 58,
            height: 58,
            child: Image.asset(
              MascotAssets.speak,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr('Nghe mẫu rồi đọc lại thật rõ nhé!', '先听示范，再清楚地跟读吧！'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: isDark ? colorScheme.onSurface : AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostRecordingActions extends StatelessWidget {
  const _PostRecordingActions({
    required this.busy,
    required this.onPlaySample,
    required this.onPlayRecording,
    required this.onRecordAgain,
    required this.onContinue,
    required this.onPrevious,
    required this.canGoPrevious,
    required this.finalSentence,
  });

  final bool busy;
  final VoidCallback onPlaySample;
  final VoidCallback onPlayRecording;
  final VoidCallback onRecordAgain;
  final VoidCallback onContinue;
  final VoidCallback onPrevious;
  final bool canGoPrevious;
  final bool finalSentence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final actions = <Widget>[
      _CompactAction(
        icon: Icons.volume_up_rounded,
        label: context.tr('Nghe câu mẫu', '听示范'),
        onPressed: busy ? null : onPlaySample,
      ),
      _CompactAction(
        icon: Icons.play_circle_rounded,
        label: context.tr('Nghe bản ghi', '听录音'),
        onPressed: busy ? null : onPlayRecording,
      ),
      _CompactAction(
        icon: Icons.mic_rounded,
        label: context.tr('Ghi âm lại', '重新录音'),
        onPressed: busy ? null : onRecordAgain,
      ),
      _CompactAction(
        key: const Key('continue-lesson-sentence'),
        icon: finalSentence
            ? Icons.fact_check_rounded
            : Icons.arrow_forward_rounded,
        label: context.tr(
          finalSentence ? 'Ôn tập' : 'Câu tiếp theo',
          finalSentence ? '复习' : '下一句',
        ),
        filled: true,
        onPressed: busy ? null : onContinue,
      ),
    ];
    return Column(
      children: <Widget>[
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 2.45,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: actions,
        ),
        if (canGoPrevious) ...<Widget>[
          const SizedBox(height: 4),
          TextButton.icon(
            key: const Key('previous-lesson-sentence'),
            onPressed: busy ? null : onPrevious,
            style: TextButton.styleFrom(
              backgroundColor: isDark
                  ? colorScheme.surfaceContainer
                  : Colors.white,
              disabledBackgroundColor: isDark
                  ? colorScheme.surfaceContainer.withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.72),
            ),
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(context.tr('Câu trước', '上一句')),
          ),
        ],
      ],
    );
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label, textAlign: TextAlign.center, maxLines: 2),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label, textAlign: TextAlign.center, maxLines: 2),
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.primary
            : AppColors.indigo,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surfaceContainer
            : const Color(0xF2FFFDF9),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.outline
              : const Color(0xCCFFFFFF),
          width: 1.2,
        ),
      ),
    );
  }
}

class _LessonNavigationActions extends StatelessWidget {
  const _LessonNavigationActions({
    required this.current,
    required this.total,
    required this.busy,
    required this.onPrevious,
    required this.onContinue,
  });

  final int current;
  final int total;
  final bool busy;
  final VoidCallback onPrevious;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('previous-lesson-sentence'),
            onPressed: current == 0 || busy ? null : onPrevious,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(62),
              foregroundColor: isDark ? colorScheme.primary : AppColors.indigo,
              backgroundColor: isDark
                  ? colorScheme.surfaceContainer
                  : Colors.white,
              disabledBackgroundColor: isDark
                  ? colorScheme.surfaceContainer.withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.72),
              side: BorderSide(
                color: isDark ? colorScheme.outline : AppColors.lavenderBorder,
              ),
              textStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(context.tr('Câu trước', '上一句'), maxLines: 1),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            key: const Key('continue-lesson-sentence'),
            onPressed: busy ? null : onContinue,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(62),
              textStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            iconAlignment: IconAlignment.end,
            icon: Icon(
              current == total - 1
                  ? Icons.fact_check_rounded
                  : Icons.arrow_forward_rounded,
            ),
            label: Text(
              context.tr(
                current == total - 1 ? 'Ôn tập' : 'Tiếp tục',
                current == total - 1 ? '复习' : '继续',
              ),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.duration, required this.onPlay});

  final Duration? duration;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final seconds = duration?.inSeconds.clamp(0, 99);
    final durationLabel = seconds == null
        ? context.tr('Đã lưu', '已保存')
        : '00:${seconds.toString().padLeft(2, '0')}';
    return HomiSurface(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: isDark ? colorScheme.surfaceContainer : AppColors.lavenderSoft,
      borderColor: isDark ? colorScheme.outline : AppColors.lavenderBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.tr('Bản ghi của con', '孩子的录音'),
            style: TextStyle(
              color: isDark ? colorScheme.onSurface : AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: <Widget>[
              IconButton(
                key: const Key('play-lesson-recording'),
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                tooltip: context.tr('Nghe lại', '回放'),
              ),
              const Expanded(
                child: Center(child: HomiWaveform(width: 160, height: 36)),
              ),
              Text(
                durationLabel,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompletionSheet extends StatefulWidget {
  const _CompletionSheet({
    required this.message,
    required this.onClose,
    required this.onReview,
  });

  final String message;
  final VoidCallback onClose;
  final VoidCallback onReview;

  @override
  State<_CompletionSheet> createState() => _CompletionSheetState();
}

class _CompletionSheetState extends State<_CompletionSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _celebrationController;

  @override
  void initState() {
    super.initState();
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 680;
    final mascotSize = compact ? 170.0 : 220.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, compact ? 0 : 6, 24, 28),
      child: Column(
        key: const Key('completion-celebration'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: double.infinity,
            height: mascotSize + 34,
            child: AnimatedBuilder(
              animation: _celebrationController,
              builder: (context, child) {
                final progress = _celebrationController.value;
                final pulse = 0.96 + (progress * 0.08);
                return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: 18,
                      top: 34 - (progress * 12),
                      child: Transform.rotate(
                        angle: -0.18 + (progress * 0.2),
                        child: const Icon(
                          Icons.celebration_rounded,
                          color: Color(0xFFFF9C6C),
                          size: 46,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 26,
                      top: 14 + (progress * 10),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFFFFC75B),
                        size: 42,
                      ),
                    ),
                    Positioned(
                      left: 42,
                      bottom: 18 + (progress * 8),
                      child: const Icon(
                        Icons.star_rounded,
                        color: AppColors.periwinkle,
                        size: 34,
                      ),
                    ),
                    Positioned(
                      right: 48,
                      bottom: 28 - (progress * 6),
                      child: const Icon(
                        Icons.favorite_rounded,
                        color: AppColors.coral,
                        size: 34,
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(0, -6 * progress),
                      child: Transform.scale(scale: pulse, child: child),
                    ),
                  ],
                );
              },
              child: SizedBox(
                width: mascotSize,
                height: mascotSize,
                child: Image.asset(
                  MascotAssets.sing,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
          Text(
            context.tr('Con đã hoàn thành!', '学习完成！'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppColors.indigoDark,
              fontSize: compact ? 28 : 32,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.45),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('finish-listening-lesson'),
              onPressed: widget.onClose,
              icon: const Icon(Icons.check_circle_rounded),
              label: Text(context.tr('Về chủ đề', '返回主题')),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                textStyle: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('review-listening-lesson'),
            onPressed: widget.onReview,
            icon: const Icon(Icons.replay_rounded),
            label: Text(context.tr('Luyện lại từ đầu', '从头复习')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: AppColors.indigo,
              textStyle: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
