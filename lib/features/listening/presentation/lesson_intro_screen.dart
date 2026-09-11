import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/device/active_learning_module.dart';
import '../../../l10n/display_language.dart';
import '../application/lesson_guide_audio_library.dart';
import '../application/recorded_lesson_voice_prompt_service.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../application/lesson_media_service.dart';
import '../data/listening_progress_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import '../domain/lesson_star_flow.dart';
import '../domain/lesson_guide_flow.dart';
import 'active_learning_navigation.dart';
import 'lesson_practice_screen.dart';
import 'song_karaoke_screen.dart';

class LessonIntroScreen extends StatefulWidget {
  const LessonIntroScreen({
    required this.language,
    required this.startAge,
    required this.endAge,
    required this.topic,
    required this.lesson,
    required this.progressStore,
    required this.mediaService,
    this.controller,
    this.topicContent,
    this.contentGroup,
    this.levelContent,
    this.guideAudioLibrary,
    this.voicePromptService,
    this.autoAdvance = true,
    this.relearnFromBeginning = false,
    this.relearnTopicSequence = false,
    this.onTopicCompleted,
    super.key,
  });

  final DisplayLanguage language;
  final int startAge;
  final int endAge;
  final ListeningTopic topic;
  final ListeningLessonContent lesson;
  final ConversationController? controller;
  final ListeningTopicContent? topicContent;
  final ListeningContentAgeGroup? contentGroup;
  final ListeningLevelContent? levelContent;
  final ListeningProgressStore progressStore;
  final LessonMediaService mediaService;
  final LessonGuideAudioLibrary? guideAudioLibrary;
  final VoicePromptService? voicePromptService;
  final bool autoAdvance;
  final bool relearnFromBeginning;
  final bool relearnTopicSequence;
  final VoidCallback? onTopicCompleted;

  @override
  State<LessonIntroScreen> createState() => _LessonIntroScreenState();
}

class _LessonIntroScreenState extends State<LessonIntroScreen>
    with SingleTickerProviderStateMixin
    implements ActiveLearningModuleController {
  late final AnimationController _animationController;
  bool _introPlaybackFailed = false;
  bool _movingForward = false;
  bool _pausedForMainAssistant = false;
  int _introPlaybackRequest = 0;
  late final LessonGuideAudioLibrary _guideAudioLibrary;
  VoicePromptService? _voicePromptService;
  bool _ownsVoicePromptService = false;
  String? _guideText;
  ListeningResumeStage _resumeStage = ListeningResumeStage.core;
  ActiveLearningModuleRegistry? _activeModuleRegistry;
  Object? _activeModuleRegistration;

  @override
  ActiveLearningModuleKind get moduleKind =>
      ActiveLearningModuleKind.listeningLesson;

  @override
  bool get isPausedForMain => _pausedForMainAssistant;

  @override
  void initState() {
    super.initState();
    _guideAudioLibrary = widget.guideAudioLibrary ?? LessonGuideAudioLibrary();
    _voicePromptService = widget.voicePromptService == null
        ? null
        : createLessonVoicePromptService(
            mediaService: widget.mediaService,
            override: widget.voicePromptService,
            age: widget.startAge,
          );
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.92,
      upperBound: 1,
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _beginIntro());
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

  Future<void> _beginIntro() async {
    final request = ++_introPlaybackRequest;
    if (_usesGuideV2) {
      await _prepareGuideText();
    }
    if (!mounted ||
        _pausedForMainAssistant ||
        request != _introPlaybackRequest) {
      return;
    }
    // An authored intro clip may contain the first-time Hook. Relearn always
    // uses the dynamic Star line prepared above so the Hook cannot leak back in.
    final uri = _usesGuideV2 && widget.relearnFromBeginning
        ? null
        : widget.lesson.introAudioUri;
    if (uri == null) {
      try {
        await widget.mediaService.prepareSelectedLessonOutput();
        final prompt = _activeVoicePromptService;
        final text = _guideText ?? widget.lesson.intro;
        if (!kIsWeb && prompt is SelectedMediaOutputVoicePromptService) {
          await (prompt as SelectedMediaOutputVoicePromptService)
              .speakAndWaitOnSelectedMediaOutput(text);
        } else {
          await prompt.speakAndWait(text);
        }
      } catch (error, stackTrace) {
        debugPrint(
          'Lesson intro fallback failed for ${widget.lesson.id}: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
        if (!widget.relearnFromBeginning) {
          _showIntroPlaybackFailure();
          return;
        }
        // The remaining-Star reminder is helpful but must never become a gate
        // that leaves relearn parked on the intro screen.
      }
    } else {
      try {
        await widget.mediaService.playToCompletion(uri);
      } catch (error, stackTrace) {
        if (_pausedForMainAssistant || request != _introPlaybackRequest) {
          return;
        }
        debugPrint(
          'Lesson intro playback failed for ${widget.lesson.id} ($uri): $error',
        );
        debugPrintStack(stackTrace: stackTrace);
        _showIntroPlaybackFailure();
        return;
      }
    }
    if (!mounted ||
        _pausedForMainAssistant ||
        request != _introPlaybackRequest) {
      return;
    }
    if (_usesGuideV2) {
      try {
        await widget.progressStore.markLearningGuideOpened();
      } catch (error, stackTrace) {
        debugPrint(
          'Could not save lesson guide state for ${widget.lesson.id}: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
    }
    if (!mounted ||
        _pausedForMainAssistant ||
        request != _introPlaybackRequest) {
      return;
    }
    if (widget.autoAdvance && !_movingForward) {
      await _openLesson();
    }
  }

  Future<void> _prepareGuideText() async {
    final completed = await widget.progressStore.readLesson(widget.lesson.id);
    final currentSentence = await widget.progressStore.readCurrentSentence(
      widget.lesson.id,
    );
    final opened = await widget.progressStore.hasOpenedLearningGuide();
    var resumeStage = ListeningResumeStage.core;
    if (widget.lesson.usesV4Flow) {
      resumeStage = widget.relearnFromBeginning
          ? ListeningResumeStage.core
          : await widget.progressStore.readResumeStage(widget.lesson.id);
      if (!widget.relearnFromBeginning &&
          resumeStage == ListeningResumeStage.core &&
          completed >= widget.lesson.sentences.length &&
          widget.lesson.sentences.isNotEmpty &&
          !await widget.progressStore.hasCompletedV4LessonActivity(
            widget.lesson.id,
          )) {
        resumeStage = ListeningResumeStage.challenge;
      }
    }
    final hasStartedCore = widget.lesson.usesV4Flow
        ? await widget.progressStore.hasStartedLessonCore(widget.lesson.id)
        : currentSentence > 0;
    final isInProgress =
        !widget.relearnFromBeginning &&
        hasStartedCore &&
        completed < widget.lesson.sentences.length;
    if (widget.lesson.usesV4Flow) {
      final lesson = widget.lesson;
      final topicContent = widget.topicContent;
      final String text;
      if (resumeStage == ListeningResumeStage.rolePlay) {
        text = 'Mình tiếp tục đoạn hội thoại nhé.';
      } else if (resumeStage == ListeningResumeStage.challenge) {
        text = 'Mình làm lại phần thử thách nhé.';
      } else if (resumeStage == ListeningResumeStage.mission) {
        text = 'Mình tiếp tục Nhiệm vụ cuối Level nhé.';
      } else if (resumeStage == ListeningResumeStage.reinforcement) {
        text = 'Mình luyện nhanh vài phần trước nhé.';
      } else if (resumeStage == ListeningResumeStage.song) {
        // A song is optional enrichment after the lesson has already been
        // completed. If it was interrupted, continue after it instead of
        // resuming or replaying a partial song.
        text = 'Mình tiếp tục phần tiếp theo nhé.';
      } else if (isInProgress) {
        text = 'Mình học tiếp bài ${lesson.titleEn} nhé.';
      } else if (widget.relearnFromBeginning ||
          (completed >= lesson.sentences.length &&
              lesson.sentences.isNotEmpty)) {
        final earnedStars = await widget.progressStore.readEarnedStars(
          lesson.id,
        );
        final hasMissionStarSlots =
            await widget.progressStore.hasLessonMissionStarSlots(lesson.id) ||
            LessonStarFlow.hasEarnedMissionStar(earnedStars);
        final remainingStars = LessonStarFlow.remainingStarCount(
          lesson,
          earnedStars,
          includeMission: hasMissionStarSlots,
        );
        text = remainingStars > 0
            ? widget.startAge <= 10
                  ? 'Bài này bạn còn $remainingStars Ngôi sao chưa chinh phục. Mình cùng thử nhé!'
                  : 'Bài này bạn còn $remainingStars Ngôi sao chưa chinh phục.'
            : 'Mình học lại bài ${lesson.titleEn} nhé.';
      } else {
        final isFirstLessonInTopic = lesson.number == 1;
        final topicLead = isFirstLessonInTopic && topicContent != null
            ? 'Chủ đề ${topicContent.number}. '
            : '';
        final lessonLead = isFirstLessonInTopic
            ? 'Bài đầu tiên là ${lesson.titleEn}. '
            : 'Bài này là ${lesson.titleEn}. ';
        text = '$topicLead$lessonLead${lesson.entry?.text ?? ''} Bắt đầu nhé.'
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }
      if (mounted && !_pausedForMainAssistant) {
        setState(() {
          _guideText = text;
          _resumeStage = resumeStage;
        });
      }
      return;
    }
    final prompt = LessonGuideFlowV2.entry(
      lessonCode: widget.lesson.code,
      lessonTitleEn: widget.lesson.titleEn,
      kind: !opened
          ? LessonEntryGuideKind.first
          : isInProgress
          ? LessonEntryGuideKind.resume
          : LessonEntryGuideKind.newLesson,
    );
    if (mounted && !_pausedForMainAssistant) {
      setState(() => _guideText = prompt.text);
    }
  }

  void _showIntroPlaybackFailure() {
    if (!mounted || _movingForward) {
      return;
    }
    setState(() => _introPlaybackFailed = true);
  }

  @override
  void dispose() {
    final registration = _activeModuleRegistration;
    if (registration != null) {
      _activeModuleRegistry?.unregister(registration);
    }
    _introPlaybackRequest += 1;
    _animationController.dispose();
    if (!_movingForward) {
      widget.mediaService.stopPlayback();
      final voicePrompt = _voicePromptService;
      if (voicePrompt != null) {
        if (_ownsVoicePromptService) {
          unawaited(voicePrompt.dispose());
        } else {
          unawaited(voicePrompt.stop());
        }
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return DisplayLanguageScope(
      language: widget.language,
      child: IgnorePointer(
        ignoring: _pausedForMainAssistant,
        child: Scaffold(
          key: const Key('lesson-intro-screen'),
          backgroundColor: Colors.transparent,
          body: LearningScenery(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 30,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  tooltip: context.tr('Quay lại', '返回'),
                                ),
                                const Spacer(),
                                TextButton(
                                  key: const Key('skip-lesson-intro'),
                                  onPressed: _openLesson,
                                  style: TextButton.styleFrom(
                                    backgroundColor: isDark
                                        ? colorScheme.surfaceContainerHighest
                                        : Colors.white.withValues(alpha: 0.9),
                                    foregroundColor: isDark
                                        ? colorScheme.onSurface
                                        : AppColors.ink,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: Text(context.tr('Bỏ qua', '跳过')),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ScaleTransition(
                              scale: _animationController,
                              child: SizedBox(
                                width: 220,
                                height: 238,
                                child: Transform.scale(
                                  scale: 1.42,
                                  child: Image.asset(
                                    MascotAssets.wave,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(0, -18),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  22,
                                  20,
                                  22,
                                  20,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? colorScheme.surfaceContainer.withValues(
                                          alpha: 0.96,
                                        )
                                      : Colors.white.withValues(alpha: 0.94),
                                  borderRadius: BorderRadius.circular(26),
                                  border: isDark
                                      ? Border.all(color: colorScheme.outline)
                                      : null,
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: isDark
                                          ? Colors.black.withValues(alpha: 0.28)
                                          : const Color(0x24142451),
                                      blurRadius: 24,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _guideText ?? widget.lesson.intro,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontSize: 18,
                                    height: 1.48,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.graphic_eq_rounded,
                              color: AppColors.indigo,
                              size: 72,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _pausedForMainAssistant
                                  ? context.tr(
                                      'Bài học đang tạm dừng.',
                                      '课程已暂停。',
                                    )
                                  : _introPlaybackFailed
                                  ? context.tr(
                                      'Không thể phát lời mở đầu. Con hãy bấm Bỏ qua để tiếp tục.',
                                      '无法播放开场介绍，请点击跳过继续。',
                                    )
                                  : context.tr(
                                      'Đang phát lời mở đầu…',
                                      '正在播放开场介绍…',
                                    ),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: isDark
                                    ? colorScheme.primary
                                    : AppColors.indigoDark,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value:
                                    _introPlaybackFailed ||
                                        _pausedForMainAssistant
                                    ? 0
                                    : null,
                                minHeight: 7,
                                backgroundColor: isDark
                                    ? colorScheme.surfaceContainerHighest
                                    : Colors.white.withValues(alpha: 0.55),
                                color: isDark
                                    ? colorScheme.primary
                                    : AppColors.indigo,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Future<void> pauseForMainAssistant() async {
    if (_pausedForMainAssistant) {
      return;
    }
    _pausedForMainAssistant = true;
    _movingForward = false;
    _introPlaybackRequest += 1;
    _animationController.stop();
    if (mounted) {
      setState(() {});
    }
    await widget.mediaService.stopPlayback().catchError((Object _) {});
    await _voicePromptService?.stop().catchError((Object _) {});
  }

  void _resumeIntro() {
    if (!mounted || _movingForward) {
      return;
    }
    _pausedForMainAssistant = false;
    _introPlaybackFailed = false;
    _animationController.repeat(reverse: true);
    setState(() {});
    unawaited(_beginIntro());
  }

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    if (!mounted) {
      return const ActiveLearningCommandResult.unavailable();
    }
    switch (command) {
      case ActiveLearningCommand.stop:
        await pauseForMainAssistant();
        return const ActiveLearningCommandResult.handled(
          spokenReply: 'Đã dừng.',
        );
      case ActiveLearningCommand.resume:
      case ActiveLearningCommand.replayCurrent:
      case ActiveLearningCommand.restart:
        _resumeIntro();
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.nextItem:
        _pausedForMainAssistant = false;
        await _openLesson();
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.previousItem:
        return const ActiveLearningCommandResult.unavailable(
          spokenReply: 'Con đang ở phần đầu bài học rồi.',
        );
      case ActiveLearningCommand.nextLesson:
      case ActiveLearningCommand.previousLesson:
      case ActiveLearningCommand.vocabularyParentAdded:
      case ActiveLearningCommand.vocabularyPracticeAgain:
      case ActiveLearningCommand.vocabularyStars:
      case ActiveLearningCommand.vocabularyLatest:
      case ActiveLearningCommand.vocabularyAll:
        return const ActiveLearningCommandResult.unavailable(
          spokenReply: 'Con hãy vào bài học trước nhé.',
        );
      case ActiveLearningCommand.exitToHome:
        await pauseForMainAssistant();
        if (!mounted) {
          return const ActiveLearningCommandResult.unavailable();
        }
        Navigator.of(context).popUntil((route) => route.isFirst);
        return const ActiveLearningCommandResult.handled();
    }
  }

  Future<void> _openLesson() async {
    if (widget.lesson.usesV4Flow) {
      await _openV4Practice();
      return;
    }
    if (_usesSongKaraoke) {
      await _openSongKaraoke();
      return;
    }
    if (_movingForward || !mounted) {
      return;
    }
    _movingForward = true;
    await widget.mediaService.stopPlayback().catchError((Object _) {});
    if (!mounted || _pausedForMainAssistant) {
      _movingForward = false;
      return;
    }
    await pushReplacementForActiveLearning<void, void>(
      context,
      (_) => LessonPracticeScreen(
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
        isRelearn: widget.relearnFromBeginning,
        relearnTopicSequence: widget.relearnTopicSequence,
        guideAudioLibrary: _guideAudioLibrary,
        onTopicCompleted: widget.onTopicCompleted,
      ),
    );
  }

  Future<void> _openV4Practice() async {
    if (_movingForward || !mounted) {
      return;
    }
    _movingForward = true;
    await widget.mediaService.stopPlayback().catchError((Object _) {});
    if (!mounted || _pausedForMainAssistant) {
      _movingForward = false;
      return;
    }
    await pushReplacementForActiveLearning<void, void>(
      context,
      (_) => LessonPracticeScreen(
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
        guideAudioLibrary: _guideAudioLibrary,
        voicePromptService: _voicePromptService,
        initialResumeStage: _resumeStage,
        isRelearn: widget.relearnFromBeginning,
        relearnTopicSequence: widget.relearnTopicSequence,
        onTopicCompleted: widget.onTopicCompleted,
      ),
    );
  }

  Future<void> _openSongKaraoke() async {
    if (_movingForward || !mounted) {
      return;
    }
    _movingForward = true;
    await widget.mediaService.stopPlayback();
    if (!mounted || _pausedForMainAssistant) {
      _movingForward = false;
      return;
    }
    await pushReplacementForActiveLearning<void, void>(
      context,
      (_) => SongKaraokeScreen(
        language: widget.language,
        lesson: widget.lesson,
        mediaService: widget.mediaService,
        topicTitle:
            widget.topicContent?.titleEn ??
            widget.language.choose(widget.topic.titleVi, widget.topic.titleZh),
        practiceBuilder: _buildPracticeScreen,
      ),
    );
  }

  bool get _usesSongKaraoke =>
      shouldUseSongKaraoke(startAge: widget.startAge, lesson: widget.lesson);

  bool get _usesGuideV2 => widget.lesson.usesGuidedPractice;

  VoicePromptService get _activeVoicePromptService {
    final existing = _voicePromptService;
    if (existing != null) {
      return existing;
    }
    _ownsVoicePromptService = true;
    return _voicePromptService = widget.lesson.usesV4Flow
        ? createLessonVoicePromptService(
            mediaService: widget.mediaService,
            age: widget.startAge,
          )
        : createVoicePromptService();
  }

  Widget _buildPracticeScreen(BuildContext context) => LessonPracticeScreen(
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
    guideAudioLibrary: _guideAudioLibrary,
    isRelearn: widget.relearnFromBeginning,
    relearnTopicSequence: widget.relearnTopicSequence,
    onTopicCompleted: widget.onTopicCompleted,
  );
}
