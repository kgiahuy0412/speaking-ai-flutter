import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../application/lesson_guide_audio_library.dart';
import '../application/lesson_media_service.dart';
import '../data/listening_progress_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import 'lesson_practice_screen.dart';

/// The V4 listen-first pass.  It deliberately does not record or evaluate an
/// answer: children first hear the complete authored lesson, then move to the
/// detailed target-by-target practice state machine.
class LessonOverviewScreen extends StatefulWidget {
  const LessonOverviewScreen({
    required this.language,
    required this.startAge,
    required this.endAge,
    required this.topic,
    required this.lesson,
    required this.progressStore,
    required this.mediaService,
    this.controller,
    this.topicContent,
    this.levelContent,
    this.guideAudioLibrary,
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
  final ListeningLevelContent? levelContent;
  final ListeningProgressStore progressStore;
  final LessonMediaService mediaService;
  final LessonGuideAudioLibrary? guideAudioLibrary;
  final VoidCallback? onTopicCompleted;

  @override
  State<LessonOverviewScreen> createState() => _LessonOverviewScreenState();
}

class _LessonOverviewScreenState extends State<LessonOverviewScreen> {
  static const _englishToVietnamesePause = Duration(seconds: 2);

  VoicePromptService? _voicePromptService;
  bool _ownsVoicePromptService = false;
  bool _playing = false;
  bool _movingForward = false;
  String _status = 'Chuẩn bị nghe tổng quan…';
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playOverview());
  }

  @override
  void dispose() {
    _request += 1;
    unawaited(widget.mediaService.stopPlayback());
    final voicePrompt = _voicePromptService;
    if (voicePrompt != null) {
      if (_ownsVoicePromptService) {
        unawaited(voicePrompt.dispose());
      } else {
        unawaited(voicePrompt.stop());
      }
    }
    super.dispose();
  }

  VoicePromptService get _prompt {
    final current = _voicePromptService;
    if (current != null) return current;
    _ownsVoicePromptService = true;
    return _voicePromptService = createVoicePromptService();
  }

  Future<void> _playOverview() async {
    if (_playing || _movingForward || !mounted) return;
    final request = ++_request;
    setState(() {
      _playing = true;
      _status = 'Bạn nghe qua nội dung trước nhé.';
    });
    try {
      await _prompt.speakAndWait('Bạn nghe qua nội dung trước nhé.');
      if (!mounted || request != _request) return;
      if (widget.lesson.overviewMode == ListeningOverviewMode.englishOnly) {
        await _playEnglishOnlyOverview(request);
      } else {
        await _playBilingualOverview(request);
      }
      if (!mounted || request != _request) return;
      setState(() => _status = 'Bây giờ mình học từng phần nhé.');
      await _prompt.speakAndWait('Bây giờ mình học từng phần nhé.');
      if (!mounted || request != _request) return;
      await _openPractice();
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _status = 'Chưa phát được phần nghe. Bạn có thể thử lại.');
    } finally {
      if (mounted && request == _request && !_movingForward) {
        setState(() => _playing = false);
      }
    }
  }

  Future<void> _playEnglishOnlyOverview(int request) async {
    final uri = widget.lesson.overviewAudioUri;
    if (uri != null) {
      setState(() => _status = 'Nghe toàn bộ bài bằng tiếng Anh…');
      await widget.mediaService.playToCompletion(uri);
      return;
    }
    final text = widget.lesson.sentences
        .map((sentence) => sentence.english)
        .where((value) => value.trim().isNotEmpty)
        .join(' ');
    if (text.isEmpty || request != _request) return;
    setState(() => _status = 'Nghe toàn bộ bài bằng tiếng Anh…');
    await _prompt.speakAndWait(text, locale: 'en-US');
  }

  Future<void> _playBilingualOverview(int request) async {
    for (final sentence in widget.lesson.sentences) {
      if (!mounted || request != _request) return;
      setState(() => _status = 'Đang nghe: ${sentence.english}');
      final englishUri = sentence.audioUri;
      if (englishUri != null) {
        await widget.mediaService.playToCompletion(englishUri);
      } else {
        await _prompt.speakAndWait(sentence.english, locale: 'en-US');
      }
      if (!mounted || request != _request) return;
      await Future<void>.delayed(_englishToVietnamesePause);
      if (!mounted || request != _request) return;
      final vietnameseUri = sentence.vietnameseAudioUri;
      if (vietnameseUri != null) {
        await widget.mediaService.playToCompletion(vietnameseUri);
      } else {
        await _prompt.speakAndWait(sentence.vietnamese, locale: 'vi-VN');
      }
    }
  }

  Future<void> _openPractice() async {
    if (_movingForward || !mounted) return;
    _movingForward = true;
    await widget.mediaService.stopPlayback();
    if (!mounted) return;
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
          levelContent: widget.levelContent,
          progressStore: widget.progressStore,
          mediaService: widget.mediaService,
          guideAudioLibrary: widget.guideAudioLibrary,
          onTopicCompleted: widget.onTopicCompleted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        key: const Key('lesson-overview-screen'),
        backgroundColor: Colors.transparent,
        body: LearningScenery(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 620;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
                          TextButton.icon(
                            onPressed: _playing ? null : _playOverview,
                            icon: const Icon(Icons.replay_rounded),
                            label: Text(context.tr('Nghe lại', '再听一次')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                SizedBox(
                                  height: compact ? 128 : 210,
                                  child: Image.asset(
                                    MascotAssets.listen,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                                SizedBox(height: compact ? 12 : 22),
                                Text(
                                  context.tr('Nghe tổng quan', '整体听力'),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  widget.lesson.titleEn,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: isDark
                                        ? colorScheme.primary
                                        : AppColors.indigo,
                                  ),
                                ),
                                SizedBox(height: compact ? 14 : 22),
                                Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(compact ? 14 : 20),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? colorScheme.surfaceContainer
                                              .withValues(alpha: 0.96)
                                        : Colors.white.withValues(alpha: 0.94),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Text(
                                    _status,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_playing)
                        const LinearProgressIndicator(minHeight: 7)
                      else
                        FilledButton.icon(
                          onPressed: _openPractice,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(context.tr('Học từng phần', '逐项学习')),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
