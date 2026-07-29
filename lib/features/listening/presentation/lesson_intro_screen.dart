import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../application/lesson_media_service.dart';
import '../data/listening_progress_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import 'lesson_practice_screen.dart';
import 'lesson_review_screen.dart';
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
  final bool autoAdvance;

  @override
  State<LessonIntroScreen> createState() => _LessonIntroScreenState();
}

class _LessonIntroScreenState extends State<LessonIntroScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  Timer? _advanceTimer;
  bool _movingForward = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.92,
      upperBound: 1,
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _beginIntro());
  }

  Future<void> _beginIntro() async {
    final uri = widget.lesson.introAudioUri;
    if (uri != null) {
      try {
        await widget.mediaService.playToCompletion(uri);
        if (!widget.autoAdvance || !mounted || _movingForward) {
          return;
        }
        _advanceTimer = Timer(
          const Duration(milliseconds: 350),
          _continueToLesson,
        );
        return;
      } catch (_) {
        // If remote audio cannot start or finish, use the bounded text-based
        // fallback below so a weak network never traps the child here.
      }
    }
    if (!widget.autoAdvance || !mounted) {
      return;
    }
    final words = widget.lesson.intro.trim().split(RegExp(r'\s+')).length;
    final seconds = (words / 3).ceil().clamp(5, 14);
    _advanceTimer = Timer(Duration(seconds: seconds), _continueToLesson);
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _animationController.dispose();
    widget.mediaService.stopPlayback();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        key: const Key('lesson-intro-screen'),
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(
              'assets/images/lesson-intro-stage.webp',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
            SafeArea(
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
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.9,
                                    ),
                                    foregroundColor: AppColors.ink,
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
                                    'assets/images/mascot-robot.png',
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
                                  color: Colors.white.withValues(alpha: 0.94),
                                  borderRadius: BorderRadius.circular(26),
                                  boxShadow: const <BoxShadow>[
                                    BoxShadow(
                                      color: Color(0x24142451),
                                      blurRadius: 24,
                                      offset: Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  widget.lesson.intro,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
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
                              context.tr('Đang phát lời mở đầu…', '正在播放开场介绍…'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: AppColors.indigoDark),
                            ),
                            const SizedBox(height: 14),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                minHeight: 7,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.55,
                                ),
                                color: AppColors.indigo,
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
          ],
        ),
      ),
    );
  }

  Future<void> _continueToLesson() async {
    if (_movingForward || !mounted) {
      return;
    }
    _movingForward = true;
    _advanceTimer?.cancel();
    await widget.mediaService.stopPlayback();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => _usesSongKaraoke
            ? SongKaraokeScreen(
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
              )
            : _buildPracticeScreen(context),
      ),
    );
  }

  Future<void> _openOverview() async {
    if (_usesSongKaraoke) {
      await _continueToLesson();
      return;
    }
    if (_movingForward || !mounted) {
      return;
    }
    _movingForward = true;
    _advanceTimer?.cancel();
    await widget.mediaService.stopPlayback();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => LessonReviewScreen(
          language: widget.language,
          lesson: widget.lesson,
          mediaService: widget.mediaService,
          learnNowBuilder: (_) => LessonPracticeScreen(
            language: widget.language,
            startAge: widget.startAge,
            endAge: widget.endAge,
            topic: widget.topic,
            lesson: widget.lesson,
            controller: widget.controller,
            topicContent: widget.topicContent,
            progressStore: widget.progressStore,
            mediaService: widget.mediaService,
          ),
        ),
      ),
    );
  }

  bool get _usesSongKaraoke =>
      shouldUseSongKaraoke(startAge: widget.startAge, lesson: widget.lesson);

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
  );
}
