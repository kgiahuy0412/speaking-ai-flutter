import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/audio/learning_audio_dependencies.dart';
import '../../../l10n/display_language.dart';
import '../application/lesson_guide_audio_library.dart';
import '../application/lesson_media_service.dart';
import '../data/listening_progress_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import '../../../core/navigation/active_learning_navigation.dart';
import 'lesson_practice_screen.dart';

/// Compatibility route for old deep links. New navigation no longer opens this
/// route; an old link is forwarded directly into the lesson.
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
    this.contentGroup,
    this.levelContent,
    this.guideAudioLibrary,
    this.voicePromptService,
    this.englishSentencePause,
    this.isRelearn = false,
    this.onTopicCompleted,
    super.key,
  });

  final DisplayLanguage language;
  final int startAge;
  final int endAge;
  final ListeningTopic topic;
  final ListeningLessonContent lesson;
  final LearningAudioDependencies? controller;
  final ListeningTopicContent? topicContent;
  final ListeningContentAgeGroup? contentGroup;
  final ListeningLevelContent? levelContent;
  final ListeningProgressStore progressStore;
  final LessonMediaService mediaService;
  final LessonGuideAudioLibrary? guideAudioLibrary;
  final VoicePromptService? voicePromptService;
  final Duration? englishSentencePause;
  final bool isRelearn;
  final VoidCallback? onTopicCompleted;

  @override
  State<LessonOverviewScreen> createState() => _LessonOverviewScreenState();
}

class _LessonOverviewScreenState extends State<LessonOverviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_forward()));
  }

  Future<void> _forward() async {
    if (!mounted) return;
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
        guideAudioLibrary: widget.guideAudioLibrary,
        voicePromptService: widget.voicePromptService,
        isRelearn: widget.isRelearn,
        onTopicCompleted: widget.onTopicCompleted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    key: Key('lesson-forward-screen'),
    body: Center(child: CircularProgressIndicator()),
  );
}
