import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../../home/presentation/homi_bottom_navigation.dart';
import '../application/lesson_media_service.dart';
import '../data/listening_progress_store.dart';
import '../data/active_listening_session_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import '../domain/listening_curriculum_flow.dart';
import 'active_learning_navigation.dart';
import 'lesson_intro_screen.dart';
import 'lesson_recording_history_sheet.dart';
import 'song_karaoke_screen.dart';

class TopicLessonListScreen extends StatefulWidget {
  const TopicLessonListScreen({
    required this.language,
    required this.startAge,
    required this.endAge,
    required this.topic,
    required this.content,
    this.contentGroup,
    this.levelContent,
    this.controller,
    this.onMainPressed,
    this.onVocabularyRequested,
    this.onVoiceNavigationPause,
    this.onVoiceNavigationResume,
    this.progressStore = const ListeningProgressStore(),
    this.mediaService,
    this.voicePromptService,
    this.initialLessonNumber,
    this.relearnInitialLesson = false,
    this.relearnTopicSequence = false,
    this.onTopicCompleted,
    super.key,
  });

  final DisplayLanguage language;
  final int startAge;
  final int endAge;
  final ListeningTopic topic;
  final ListeningTopicContent content;
  final ListeningContentAgeGroup? contentGroup;
  final ListeningLevelContent? levelContent;
  final ConversationController? controller;
  final Future<void> Function()? onMainPressed;
  final VoidCallback? onVocabularyRequested;
  final Future<void> Function()? onVoiceNavigationPause;
  final VoidCallback? onVoiceNavigationResume;
  final ListeningProgressStore progressStore;
  final LessonMediaService? mediaService;
  final VoicePromptService? voicePromptService;
  final int? initialLessonNumber;
  final bool relearnInitialLesson;
  final bool relearnTopicSequence;
  final VoidCallback? onTopicCompleted;

  bool get showsSongs => startAge >= 6 && content.songs.isNotEmpty;

  @override
  State<TopicLessonListScreen> createState() => _TopicLessonListScreenState();
}

class _TopicLessonListScreenState extends State<TopicLessonListScreen> {
  late final LessonMediaService _mediaService;
  late Future<_TopicLessonProgressSnapshot> _progressFuture;
  late final bool _ownsMediaService;
  late final VoicePromptService _voicePromptService;
  late final bool _ownsVoicePromptService;
  bool _initialLessonOpened = false;

  @override
  void initState() {
    super.initState();
    _ownsMediaService = widget.mediaService == null;
    _mediaService =
        widget.mediaService ??
        LessonMediaService(
          hfpAudioControl: widget.controller?.createLearningAudioRouteControl(),
          audioTurnCoordinator: widget.controller?.audioTurnCoordinator,
        );
    _ownsVoicePromptService = widget.voicePromptService == null;
    _voicePromptService =
        widget.voicePromptService ??
        createVoicePromptService(
          coordinator: widget.controller?.audioTurnCoordinator,
          owner: AudioTurnOwner.listeningLesson,
        );
    _progressFuture = _loadProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openInitialLesson());
    });
  }

  @override
  void dispose() {
    if (_ownsVoicePromptService) {
      unawaited(_voicePromptService.dispose());
    }
    if (_ownsMediaService) {
      _mediaService.dispose();
    }
    super.dispose();
  }

  Future<_TopicLessonProgressSnapshot> _loadProgress() async {
    final lessonProgress = await widget.progressStore.readAll();
    final completedV4LessonActivities = await widget.progressStore
        .readCompletedV4LessonActivities();
    return _TopicLessonProgressSnapshot(
      lessonProgress: lessonProgress,
      completedV4LessonActivities: completedV4LessonActivities,
    );
  }

  bool _isLessonCompleted(
    ListeningLessonContent lesson,
    int completedSentences,
    Set<String> completedV4LessonActivities,
  ) {
    final completedCore =
        completedSentences >= lesson.sentences.length &&
        lesson.sentences.isNotEmpty;
    return completedCore &&
        (!lesson.usesV4Flow || completedV4LessonActivities.contains(lesson.id));
  }

  @override
  Widget build(BuildContext context) {
    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        key: const Key('topic-lesson-list-screen'),
        backgroundColor: Colors.transparent,
        body: LearningScenery(
          overlayOpacity: 0.36,
          child: Stack(
            children: <Widget>[
              SafeArea(
                bottom: false,
                child: FutureBuilder<_TopicLessonProgressSnapshot>(
                  future: _progressFuture,
                  builder: (context, snapshot) {
                    final progress =
                        snapshot.data ??
                        const _TopicLessonProgressSnapshot.empty();
                    return CustomScrollView(
                      slivers: <Widget>[
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          sliver: SliverToBoxAdapter(
                            child: _Header(
                              title: context.tr(
                                widget.content.titleVi,
                                widget.topic.titleZh,
                              ),
                              onBack: _goBack,
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          sliver: SliverToBoxAdapter(
                            child: _TopicHero(widget: widget),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              context.tr('Hành trình học', '学习旅程'),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: AppColors.indigoDark,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 42),
                          sliver: SliverList.separated(
                            itemCount: widget.content.lessons.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              indent: 72,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Theme.of(context).colorScheme.outlineVariant
                                  : AppColors.mintBorder,
                            ),
                            itemBuilder: (context, index) {
                              final lesson = widget.content.lessons[index];
                              final completed =
                                  (progress.lessonProgress[lesson.id] ?? 0)
                                      .clamp(0, lesson.sentences.length);
                              final lessonCompleted = _isLessonCompleted(
                                lesson,
                                completed,
                                progress.completedV4LessonActivities,
                              );
                              final lessonUnlocked =
                                  ListeningCurriculumFlow.lessonUnlocked(
                                    widget.content,
                                    index,
                                    progress.lessonProgress,
                                    progress.completedV4LessonActivities,
                                  );
                              return _LessonPathCard(
                                key: ValueKey('lesson-${lesson.id}'),
                                lesson: lesson,
                                completedSentences: completed,
                                isCompleted: lessonCompleted,
                                isLocked: !lessonUnlocked,
                                needsV4Challenge:
                                    lesson.usesV4Flow &&
                                    completed >= lesson.sentences.length &&
                                    !lessonCompleted,
                                isLast:
                                    index == widget.content.lessons.length - 1,
                                onPressed: () => _startLesson(
                                  lesson,
                                  reviewFromBeginning:
                                      lesson.sentences.isNotEmpty &&
                                      lessonCompleted,
                                ),
                              );
                            },
                          ),
                        ),
                        if (widget.showsSongs) ...<Widget>[
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                            sliver: SliverToBoxAdapter(
                              child: Row(
                                children: <Widget>[
                                  const Icon(
                                    Icons.music_note_rounded,
                                    color: AppColors.coral,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      context.tr('Bài hát & chant', '歌曲与节奏歌'),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ),
                                  Text(
                                    context.tr(
                                      '${widget.content.songs.length} bài',
                                      '${widget.content.songs.length} 首',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: AppColors.muted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                            sliver: SliverList.separated(
                              itemCount: widget.content.songs.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final song = widget.content.songs[index];
                                final completed =
                                    (progress.lessonProgress[song.id] ?? 0)
                                        .clamp(0, song.sentences.length);
                                final lessonCompleted = _isLessonCompleted(
                                  song,
                                  completed,
                                  progress.completedV4LessonActivities,
                                );
                                return _LessonPathCard(
                                  key: ValueKey('song-${song.id}'),
                                  lesson: song,
                                  completedSentences: completed,
                                  isCompleted: lessonCompleted,
                                  isLocked: false,
                                  needsV4Challenge:
                                      song.usesV4Flow &&
                                      completed >= song.sentences.length &&
                                      !lessonCompleted,
                                  isLast:
                                      index == widget.content.songs.length - 1,
                                  onPressed: () => _startLesson(
                                    song,
                                    reviewFromBeginning:
                                        song.sentences.isNotEmpty &&
                                        lessonCompleted,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              Positioned(
                right: 4,
                bottom: -22,
                child: IgnorePointer(
                  child: Image.asset(
                    MascotAssets.wave,
                    width: 156,
                    height: 156,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: KeyedSubtree(
          key: const Key('listening-bottom-navigation'),
          child: HomiBottomNavigation(
            selectedIndex: 1,
            onConversation: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            onTopics: _goBack,
            onMain: widget.onMainPressed == null
                ? null
                : () => unawaited(widget.onMainPressed!()),
            onVocabulary: _openVocabulary,
            onHistory: _showHistory,
            conversationKey: const Key('listening-conversation-tab'),
            topicsKey: const Key('listening-topics-tab'),
            mainKey: const Key('listening-main-button'),
            vocabularyKey: const Key('listening-vocabulary-tab'),
            historyKey: const Key('listening-history-tab'),
          ),
        ),
      ),
    );
  }

  void _goBack() => Navigator.of(context).pop();

  void _openVocabulary() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onVocabularyRequested?.call();
  }

  Future<void> _openInitialLesson() async {
    final lessonNumber = widget.initialLessonNumber;
    if (_initialLessonOpened || lessonNumber == null || !mounted) {
      return;
    }
    _initialLessonOpened = true;
    if (widget.content.lessons.isEmpty) {
      return;
    }
    ListeningLessonContent? lesson;
    for (final candidate in widget.content.lessons) {
      if (candidate.number == lessonNumber) {
        lesson = candidate;
        break;
      }
    }
    if (lesson == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Chủ đề này chưa có Bài $lessonNumber. Con hãy chọn một bài đang hiển thị nhé.',
              '这个主题还没有第 $lessonNumber 课，请选择当前显示的课程。',
            ),
          ),
        ),
      );
      return;
    }
    await _startLesson(
      lesson,
      reviewFromBeginning: widget.relearnInitialLesson,
    );
  }

  Future<void> _startLesson(
    ListeningLessonContent lesson, {
    required bool reviewFromBeginning,
  }) async {
    final pendingRelearn = await widget.progressStore.hasLessonPendingRelearn(
      lesson.id,
    );
    final startFromBeginning = reviewFromBeginning || pendingRelearn;
    final lessonIndex = widget.content.lessons.indexWhere(
      (candidate) => candidate.id == lesson.id,
    );
    if (lessonIndex > 0) {
      final progress = await _loadProgress();
      final unlocked = ListeningCurriculumFlow.lessonUnlocked(
        widget.content,
        lessonIndex,
        progress.lessonProgress,
        progress.completedV4LessonActivities,
      );
      if (!unlocked) {
        final previous = widget.content.lessons[lessonIndex - 1];
        final message = 'Bạn cần học xong Bài ${previous.number} trước nhé.';
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
        await _voicePromptService.speakAndWait(message);
        return;
      }
    }
    unawaited(
      const ActiveListeningSessionStore().save(
        childAge: widget.startAge,
        topicNumber: widget.content.number,
        lessonNumber: lesson.number,
      ),
    );
    final unlockFuture =
        shouldUseSongKaraoke(startAge: widget.startAge, lesson: lesson)
        ? _mediaService.unlockPlaybackForUserGesture()
        : null;
    if (startFromBeginning) {
      await widget.progressStore.saveCurrentSentence(lesson.id, 0);
      if (lesson.usesV4Flow) {
        await widget.progressStore.clearV4LessonActivityCompleted(lesson.id);
        await widget.progressStore.saveResumeStage(
          lesson.id,
          ListeningResumeStage.core,
        );
      }
    }
    await unlockFuture;
    if (!mounted) {
      return;
    }
    await widget.onVoiceNavigationPause?.call();
    try {
      if (!mounted) {
        return;
      }
      await pushForActiveLearning<void>(
        context,
        (_) => LessonIntroScreen(
          language: widget.language,
          startAge: widget.startAge,
          endAge: widget.endAge,
          topic: widget.topic,
          lesson: lesson,
          controller: widget.controller,
          topicContent: widget.content,
          contentGroup: widget.contentGroup,
          levelContent: widget.levelContent,
          progressStore: widget.progressStore,
          mediaService: _mediaService,
          voicePromptService: _voicePromptService,
          relearnFromBeginning: startFromBeginning,
          relearnTopicSequence: widget.relearnTopicSequence || pendingRelearn,
          onTopicCompleted: widget.onTopicCompleted,
        ),
      );
    } finally {
      if (mounted) {
        widget.onVoiceNavigationResume?.call();
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _progressFuture = _loadProgress();
    });
  }

  void _showHistory() => unawaited(_openHistory());

  Future<void> _openHistory() async {
    await widget.onVoiceNavigationPause?.call();
    try {
      if (!mounted) {
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) =>
            LessonRecordingHistorySheet(mediaService: _mediaService),
      );
    } finally {
      if (mounted) {
        widget.onVoiceNavigationResume?.call();
      }
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
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
            foregroundColor: isDark ? colorScheme.primary : AppColors.ink,
            elevation: 3,
            shadowColor: const Color(0x24142451),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: isDark ? colorScheme.onSurface : AppColors.indigoDark,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerHighest
                : const Color(0xF8FFFDF9),
            shape: BoxShape.circle,
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x24142451),
                blurRadius: 16,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Icon(
            Icons.person_rounded,
            color: isDark ? colorScheme.primary : AppColors.indigo,
          ),
        ),
      ],
    );
  }
}

class _TopicLessonProgressSnapshot {
  const _TopicLessonProgressSnapshot({
    required this.lessonProgress,
    required this.completedV4LessonActivities,
  });

  const _TopicLessonProgressSnapshot.empty()
    : lessonProgress = const <String, int>{},
      completedV4LessonActivities = const <String>{};

  final Map<String, int> lessonProgress;
  final Set<String> completedV4LessonActivities;
}

class _TopicHero extends StatelessWidget {
  const _TopicHero({required this.widget});

  final TopicLessonListScreen widget;

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AspectRatio(
          aspectRatio: 1.45,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(54),
              topRight: Radius.circular(76),
              bottomLeft: Radius.circular(68),
              bottomRight: Radius.circular(44),
            ),
            child: ColoredBox(
              color: widget.topic.background,
              child: widget.topic.imagePath == null
                  ? Icon(
                      widget.topic.icon,
                      color: widget.topic.foreground,
                      size: 76,
                    )
                  : Image.asset(
                      widget.topic.imagePath!,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (widget.showsSongs) ...<Widget>[
          Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1E8),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                context.tr(
                  '♫ ${content.songs.length} bài hát/chant',
                  '♫ ${content.songs.length} 首歌曲/节奏歌',
                ),
                style: const TextStyle(
                  color: AppColors.coral,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: isDark ? colorScheme.surfaceContainer : Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: <BoxShadow>[
              if (!isDark)
                const BoxShadow(
                  color: Color(0x14244883),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.menu_book_rounded,
                      color: isDark ? colorScheme.primary : AppColors.indigo,
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        context.tr(
                          '${content.lessons.length} bài nhỏ',
                          '${content.lessons.length} 节小课',
                        ),
                        maxLines: 1,
                        style: TextStyle(
                          color: isDark ? colorScheme.onSurface : AppColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 22,
                child: VerticalDivider(
                  color: isDark
                      ? colorScheme.outlineVariant
                      : AppColors.lavenderBorder,
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: isDark ? colorScheme.primary : AppColors.indigo,
                      size: 21,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        context.tr(
                          '${content.sentenceCount} câu',
                          '${content.sentenceCount} 句',
                        ),
                        maxLines: 1,
                        style: TextStyle(
                          color: isDark ? colorScheme.onSurface : AppColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LessonPathCard extends StatelessWidget {
  const _LessonPathCard({
    required this.lesson,
    required this.completedSentences,
    required this.isCompleted,
    required this.isLocked,
    required this.needsV4Challenge,
    required this.isLast,
    required this.onPressed,
    super.key,
  });

  final ListeningLessonContent lesson;
  final int completedSentences;
  final bool isCompleted;
  final bool isLocked;
  final bool needsV4Challenge;
  final bool isLast;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = lesson.sentences.length;
    final progress = total == 0 ? 0.0 : completedSentences / total;
    final completed = isCompleted;
    return Semantics(
      button: true,
      label: 'Bài ${lesson.number}, ${lesson.titleVi}',
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 52,
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: lesson.number == 1 || completedSentences > 0
                              ? AppColors.indigo
                              : AppColors.softNavy,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x243D4DD6),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          isLocked
                              ? Icons.lock_rounded
                              : lesson.type == ListeningLessonType.song
                              ? Icons.music_note_rounded
                              : lesson.type == ListeningLessonType.dialogue
                              ? Icons.forum_rounded
                              : Icons.star_rounded,
                          color: isLocked
                              ? Colors.white
                              : lesson.type == ListeningLessonType.song
                              ? Colors.white
                              : const Color(0xFFFFD36A),
                          size: 28,
                        ),
                      ),
                      if (!isLast)
                        Container(
                          width: 5,
                          height: 126,
                          color: AppColors.periwinkle,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        context.tr(
                          'Bài ${lesson.number} · ${lesson.titleVi}',
                          '第 ${lesson.number} 课 · ${lesson.titleVi}',
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 10,
                        runSpacing: 5,
                        children: <Widget>[
                          _Metadata(
                            icon: lesson.type == ListeningLessonType.song
                                ? Icons.lyrics_rounded
                                : lesson.type == ListeningLessonType.dialogue
                                ? Icons.forum_rounded
                                : Icons.chat_bubble_outline_rounded,
                            label: context.tr(
                              lesson.type == ListeningLessonType.song
                                  ? '$total dòng'
                                  : lesson.type == ListeningLessonType.dialogue
                                  ? 'Hội thoại · $total câu'
                                  : '$total câu',
                              lesson.type == ListeningLessonType.dialogue
                                  ? '对话 · $total 句'
                                  : '$total 句',
                            ),
                          ),
                          _Metadata(
                            icon: Icons.schedule_rounded,
                            label: context.tr(
                              '${lesson.estimatedMinutes} phút',
                              '${lesson.estimatedMinutes} 分钟',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 7,
                                backgroundColor: AppColors.lavenderBorder,
                                color: AppColors.accentPink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$completedSentences/$total',
                            style: TextStyle(
                              color: isDark
                                  ? colorScheme.onSurfaceVariant
                                  : AppColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          key: ValueKey('start-lesson-${lesson.id}'),
                          onPressed: onPressed,
                          child: Text(
                            context.tr(
                              completedSentences == 0
                                  ? isLocked
                                        ? 'Chưa mở khóa'
                                        : 'Học ngay'
                                  : needsV4Challenge
                                  ? 'Hoàn thành thử thách'
                                  : completed
                                  ? 'Ôn lại'
                                  : 'Học tiếp',
                              completedSentences == 0
                                  ? isLocked
                                        ? '尚未解锁'
                                        : '立即学习'
                                  : needsV4Challenge
                                  ? '完成挑战'
                                  : completed
                                  ? '复习'
                                  : '继续学习',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          icon,
          size: 17,
          color: isDark ? colorScheme.onSurfaceVariant : AppColors.muted,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isDark ? colorScheme.onSurfaceVariant : AppColors.muted,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
