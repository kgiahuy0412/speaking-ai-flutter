import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../l10n/display_language.dart';
import '../application/lesson_guide_audio_library.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../application/lesson_media_service.dart';
import '../data/listening_progress_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import '../domain/lesson_guide_flow.dart';
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
    this.guideAudioLibrary,
    this.voicePromptService,
    this.autoAdvance = true,
    super.key,
  });

  final DisplayLanguage language;
  final int startAge;
  final int endAge;
  final ListeningTopic topic;
  final ListeningLessonContent lesson;
  final ConversationController? controller;
  final ListeningTopicContent? topicContent;
  final ListeningProgressStore progressStore;
  final LessonMediaService mediaService;
  final LessonGuideAudioLibrary? guideAudioLibrary;
  final VoicePromptService? voicePromptService;
  final bool autoAdvance;

  @override
  State<LessonIntroScreen> createState() => _LessonIntroScreenState();
}

class _LessonIntroScreenState extends State<LessonIntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  bool _introPlaybackFailed = false;
  bool _movingForward = false;
  late final LessonGuideAudioLibrary _guideAudioLibrary;
  late final VoicePromptService _voicePromptService;
  late final bool _ownsVoicePromptService;
  String? _guideText;

  @override
  void initState() {
    super.initState();
    _guideAudioLibrary = widget.guideAudioLibrary ?? LessonGuideAudioLibrary();
    _ownsVoicePromptService = widget.voicePromptService == null;
    _voicePromptService =
        widget.voicePromptService ?? createVoicePromptService();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.92,
      upperBound: 1,
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _beginIntro());
  }

  Future<void> _beginIntro() async {
    if (_usesSongKaraoke || !_usesGuideV2) {
      await _playLegacyIntro();
      return;
    }
    final completed = await widget.progressStore.readLesson(widget.lesson.id);
    final currentSentence = await widget.progressStore.readCurrentSentence(
      widget.lesson.id,
    );
    final opened = await widget.progressStore.hasOpenedLearningGuide();
    final isInProgress =
        currentSentence > 0 && completed < widget.lesson.sentences.length;
    final prompt = LessonGuideFlowV2.entry(
      lessonCode: widget.lesson.code,
      lessonTitleEn: widget.lesson.titleEn,
      kind: !opened
          ? LessonEntryGuideKind.first
          : isInProgress
          ? LessonEntryGuideKind.resume
          : LessonEntryGuideKind.newLesson,
    );
    if (mounted) {
      setState(() => _guideText = prompt.text);
    }
    Uri? guideUri;
    try {
      guideUri = await _guideAudioLibrary.uriForAudioCode(prompt.audioCode);
      if (guideUri != null) {
        await widget.mediaService.playToCompletion(guideUri);
      } else {
        await _voicePromptService.speakAndWait(prompt.text);
      }
      await widget.progressStore.markLearningGuideOpened();
      if (!widget.autoAdvance || !mounted || _movingForward) {
        return;
      }
      await _openOverview();
    } catch (error, stackTrace) {
      debugPrint(
        'Lesson intro playback failed for ${widget.lesson.id} '
        '($guideUri): $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      _showIntroPlaybackFailure();
    }
  }

  Future<void> _playLegacyIntro() async {
    final uri = widget.lesson.introAudioUri;
    if (uri == null) {
      _showIntroPlaybackFailure();
      return;
    }
    try {
      await widget.mediaService.playToCompletion(uri);
      if (widget.autoAdvance && mounted && !_movingForward) {
        await _openOverview();
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Lesson intro playback failed for ${widget.lesson.id} ($uri): $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      _showIntroPlaybackFailure();
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
    _animationController.dispose();
    if (_ownsVoicePromptService) {
      _voicePromptService.dispose();
    }
    if (!_movingForward) {
      widget.mediaService.stopPlayback();
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
                                onPressed: _openOverview,
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
                            _introPlaybackFailed
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
                              value: _introPlaybackFailed ? 0 : null,
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
    );
  }

  Future<void> _openOverview() async {
    if (_usesSongKaraoke) {
      await _openSongKaraoke();
      return;
    }
    if (_movingForward || !mounted) {
      return;
    }
    _movingForward = true;
    await widget.mediaService.stopPlayback();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => LessonPracticeScreen(
          language: widget.language,
          startAge: widget.startAge,
          endAge: widget.endAge,
          topic: widget.topic,
          lesson: widget.lesson,
          controller: widget.controller,
          topicContent: widget.topicContent,
          progressStore: widget.progressStore,
          mediaService: widget.mediaService,
          guideAudioLibrary: _guideAudioLibrary,
        ),
      ),
    );
  }

  Future<void> _openSongKaraoke() async {
    if (_movingForward || !mounted) {
      return;
    }
    _movingForward = true;
    await widget.mediaService.stopPlayback();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => SongKaraokeScreen(
          language: widget.language,
          lesson: widget.lesson,
          mediaService: widget.mediaService,
          topicTitle:
              widget.topicContent?.titleEn ??
              widget.language.choose(
                widget.topic.titleVi,
                widget.topic.titleZh,
              ),
          practiceBuilder: _buildPracticeScreen,
        ),
      ),
    );
  }

  bool get _usesSongKaraoke =>
      shouldUseSongKaraoke(startAge: widget.startAge, lesson: widget.lesson);

  bool get _usesGuideV2 =>
      RegExp(r'^A\d+_T\d+_L\d+$').hasMatch(widget.lesson.code);

  Widget _buildPracticeScreen(BuildContext context) => LessonPracticeScreen(
    language: widget.language,
    startAge: widget.startAge,
    endAge: widget.endAge,
    topic: widget.topic,
    lesson: widget.lesson,
    controller: widget.controller,
    topicContent: widget.topicContent,
    progressStore: widget.progressStore,
    mediaService: widget.mediaService,
    guideAudioLibrary: _guideAudioLibrary,
  );
}
