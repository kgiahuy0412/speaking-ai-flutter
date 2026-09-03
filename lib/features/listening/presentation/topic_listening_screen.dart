import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../application/lesson_media_service.dart';
import '../application/listening_voice_navigation_target.dart';
import '../data/listening_progress_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import 'lesson_recording_history_sheet.dart';
import 'listening_navigation_bar.dart';
import 'topic_lesson_list_screen.dart';

typedef TopicSelectionAfterCompletionPrompt =
    Future<void> Function({
      required int childAge,
      required List<int> completedTopicNumbers,
    });

typedef TopicLessonSelectionPrompt =
    Future<void> Function({
      required int childAge,
      required int topicNumber,
      required ListeningTopicContent topicContent,
      required List<int> completedLessonNumbers,
    });

class TopicListeningScreen extends StatefulWidget {
  const TopicListeningScreen({
    required this.language,
    required this.childAge,
    this.controller,
    this.onVoiceNavigationPause,
    this.onVoiceNavigationResume,
    this.initialVoiceTarget,
    this.onTopicSelected,
    this.onTopicSelectionAfterCompletion,
    this.onLessonSelectionRequested,
    this.onChildAgeChanged,
    this.onRequestParentAccess,
    this.contentFuture,
    this.progressStore = const ListeningProgressStore(),
    super.key,
  });

  final DisplayLanguage language;
  final int childAge;
  final ConversationController? controller;
  final Future<void> Function()? onVoiceNavigationPause;
  final VoidCallback? onVoiceNavigationResume;
  final ListeningVoiceNavigationTarget? initialVoiceTarget;
  final ValueChanged<int>? onTopicSelected;
  final TopicSelectionAfterCompletionPrompt? onTopicSelectionAfterCompletion;
  final TopicLessonSelectionPrompt? onLessonSelectionRequested;
  final ValueChanged<int>? onChildAgeChanged;
  final Future<bool> Function()? onRequestParentAccess;
  final Future<ListeningContentCatalog>? contentFuture;
  final ListeningProgressStore progressStore;

  @override
  State<TopicListeningScreen> createState() => _TopicListeningScreenState();
}

class _TopicListeningScreenState extends State<TopicListeningScreen> {
  static const double _contentMaxWidth = 760;

  late int _selectedCatalogIndex;
  late final Future<ListeningContentCatalog> _contentFuture;
  ListeningContentCatalog? _contentCatalog;
  Map<String, int> _lessonProgress = const <String, int>{};
  late final LessonMediaService _historyMediaService;
  bool _initialVoiceTargetHandled = false;

  ListeningAgeCatalog get _catalog => listeningCatalogs[_selectedCatalogIndex];

  @override
  void initState() {
    super.initState();
    final requestedAge = widget.initialVoiceTarget?.childAge ?? widget.childAge;
    _selectedCatalogIndex = listeningCatalogs.indexWhere(
      (catalog) =>
          requestedAge >= catalog.startAge && requestedAge <= catalog.endAge,
    );
    if (_selectedCatalogIndex < 0) {
      _selectedCatalogIndex = listeningCatalogs.lastIndexWhere(
        (catalog) => requestedAge >= catalog.startAge,
      );
      if (_selectedCatalogIndex < 0) {
        _selectedCatalogIndex = 0;
      }
    }
    _contentFuture =
        widget.contentFuture ?? AssetListeningContentRepository().load();
    _historyMediaService = LessonMediaService(
      hfpAudioControl: widget.controller?.learningAudioRouteControl,
    );
    unawaited(_loadContentAndProgress());
  }

  @override
  void dispose() {
    unawaited(_historyMediaService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LearningScenery(
          imageAlignment: Alignment.topCenter,
          overlayOpacity: 0.16,
          child: SafeArea(
            bottom: false,
            child: CustomScrollView(
              key: const Key('topic-listening-screen'),
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: _CenteredSection(
                    maxWidth: _contentMaxWidth,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _buildHeader(context),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _CenteredSection(
                    maxWidth: _contentMaxWidth,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _CurrentLessonGroupCard(
                      catalog: _catalog,
                      canChange:
                          widget.onChildAgeChanged != null &&
                          widget.onRequestParentAccess != null,
                      onChange: _changeLessonGroup,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _CenteredSection(
                    maxWidth: _contentMaxWidth,
                    padding: const EdgeInsets.fromLTRB(20, 26, 20, 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Expanded(
                          flex: 3,
                          child: Text(
                            context.tr('Hành trình của con', '孩子的学习旅程'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          flex: 2,
                          child: Text(
                            context.tr(
                              '${_catalog.topics.length} chủ đề',
                              '${_catalog.topics.length} 个主题',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant
                                      : AppColors.ink.withValues(alpha: 0.78),
                                  fontWeight: FontWeight.w700,
                                  shadows: _journeyTextShadowsFor(context),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _CenteredSection(
                    maxWidth: _contentMaxWidth,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 30),
                    child: _TopicJourney(
                      catalogId: _catalog.id,
                      topics: _catalog.topics,
                      progressFor: _topicProgress,
                      onTopicPressed: _openTopic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: ListeningNavigationBar(
          onCommunication: () => Navigator.of(context).pop(),
          onHistory: _showHistory,
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: <Widget>[
        IconButton.filled(
          onPressed: () => Navigator.of(context).pop(),
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
            context.tr('Chủ đề', '主题'),
            maxLines: 1,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontSize: 24),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 50,
          height: 50,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerHighest
                : const Color(0xF8FFFDF9),
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Image.asset(
            MascotAssets.avatar,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ],
    );
  }

  void _showHistory() => unawaited(_openHistory());

  Future<void> _changeLessonGroup() async {
    final requestParentAccess = widget.onRequestParentAccess;
    final onChildAgeChanged = widget.onChildAgeChanged;
    if (requestParentAccess == null || onChildAgeChanged == null) {
      return;
    }

    await widget.onVoiceNavigationPause?.call();
    try {
      if (!await requestParentAccess() || !mounted) {
        return;
      }
      final selectedIndex = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _LessonGroupPickerSheet(
          catalogs: listeningCatalogs,
          selectedIndex: _selectedCatalogIndex,
        ),
      );
      if (selectedIndex == null ||
          selectedIndex == _selectedCatalogIndex ||
          !mounted) {
        return;
      }
      final selectedCatalog = listeningCatalogs[selectedIndex];
      setState(() => _selectedCatalogIndex = selectedIndex);
      onChildAgeChanged(selectedCatalog.startAge);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Đã đổi sang nhóm ${selectedCatalog.startAge}–${selectedCatalog.endAge} tuổi.',
              '已切换到 ${selectedCatalog.startAge}–${selectedCatalog.endAge} 岁课程组。',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        widget.onVoiceNavigationResume?.call();
      }
    }
  }

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
            LessonRecordingHistorySheet(mediaService: _historyMediaService),
      );
    } finally {
      if (mounted) {
        widget.onVoiceNavigationResume?.call();
      }
    }
  }

  Future<void> _loadContentAndProgress() async {
    try {
      final catalog = await _contentFuture;
      if (!mounted) {
        return;
      }
      setState(() => _contentCatalog = catalog);
      unawaited(_openInitialVoiceTarget());
    } catch (_) {
      // The topic catalog remains usable while lesson content is unavailable.
    }
    try {
      final progress = await widget.progressStore.readAll();
      if (!mounted) {
        return;
      }
      setState(() => _lessonProgress = progress);
    } catch (_) {
      // A fresh device simply starts without local lesson progress.
    }
  }

  Future<Map<String, int>> _reloadProgress() async {
    final progress = await widget.progressStore.readAll();
    if (!mounted) {
      return progress;
    }
    setState(() => _lessonProgress = progress);
    return progress;
  }

  _TopicProgress _topicProgress(int topicIndex) {
    try {
      final content = _contentCatalog?.topic(
        startAge: _catalog.startAge,
        endAge: _catalog.endAge,
        topicNumber: topicIndex + 1,
      );
      if (content == null || content.lessons.isEmpty) {
        final topic = _catalog.topics[topicIndex];
        return _TopicProgress(
          completed: topic.completed.clamp(0, topic.total),
          total: topic.total,
        );
      }
      final completed = content.lessons.where((lesson) {
        return (_lessonProgress[lesson.id] ?? 0) >= lesson.sentences.length;
      }).length;
      return _TopicProgress(
        completed: completed,
        total: content.lessons.length,
      );
    } catch (_) {
      final topic = _catalog.topics[topicIndex];
      return _TopicProgress(
        completed: topic.completed.clamp(0, topic.total),
        total: topic.total,
      );
    }
  }

  Future<void> _openInitialVoiceTarget() async {
    final target = widget.initialVoiceTarget;
    if (_initialVoiceTargetHandled || target == null || !mounted) {
      return;
    }
    _initialVoiceTargetHandled = true;
    final topicIndex = target.resolveTopicIndex(_catalog);
    if (topicIndex == null) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    await _openTopic(
      _catalog.topics[topicIndex],
      topicIndex,
      initialLessonNumber: target.openLesson
          ? target.resolvedLessonNumber
          : null,
      requestVoiceLessonSelection: false,
    );
  }

  Future<void> _openTopic(
    ListeningTopic topic,
    int topicIndex, {
    int? initialLessonNumber,
    bool requestVoiceLessonSelection = true,
  }) async {
    try {
      final catalog = await _contentFuture;
      if (!mounted) {
        return;
      }
      widget.onTopicSelected?.call(topicIndex);
      final selectedAgeCatalog = _catalog;
      final content = catalog.topic(
        startAge: selectedAgeCatalog.startAge,
        endAge: selectedAgeCatalog.endAge,
        topicNumber: topicIndex + 1,
      );
      var topicCompletedDuringVisit = false;
      final route = Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TopicLessonListScreen(
            language: widget.language,
            startAge: selectedAgeCatalog.startAge,
            endAge: selectedAgeCatalog.endAge,
            topic: topic,
            content: content,
            controller: widget.controller,
            onVoiceNavigationPause: widget.onVoiceNavigationPause,
            onVoiceNavigationResume: widget.onVoiceNavigationResume,
            progressStore: widget.progressStore,
            initialLessonNumber: initialLessonNumber,
            onTopicCompleted: () => topicCompletedDuringVisit = true,
          ),
        ),
      );
      final lessonPrompt = widget.onLessonSelectionRequested;
      if (requestVoiceLessonSelection &&
          initialLessonNumber == null &&
          lessonPrompt != null) {
        await Future<void>.delayed(Duration.zero);
        try {
          await lessonPrompt(
            childAge: selectedAgeCatalog.startAge,
            topicNumber: topicIndex + 1,
            topicContent: content,
            completedLessonNumbers: _completedLessonNumbers(content),
          );
        } catch (error, stackTrace) {
          debugPrint('Could not start the lesson selection prompt: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
      await route;
      final progressAfter = await _reloadProgress();
      if (topicCompletedDuringVisit) {
        final completedTopicNumbers = _completedTopicNumbers(
          catalog,
          selectedAgeCatalog,
          progressAfter,
        );
        final prompt = widget.onTopicSelectionAfterCompletion;
        if (prompt != null) {
          try {
            await prompt(
              childAge: selectedAgeCatalog.startAge,
              completedTopicNumbers: completedTopicNumbers,
            );
          } catch (error, stackTrace) {
            debugPrint(
              'Could not start the post-completion topic prompt: $error',
            );
            debugPrintStack(stackTrace: stackTrace);
          }
        }
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Chưa tải được nội dung bài học. Vui lòng thử lại.',
              '暂时无法加载课程内容，请重试。',
            ),
          ),
        ),
      );
    }
  }

  bool _isTopicCompleted(
    ListeningTopicContent content,
    Map<String, int> progress,
  ) {
    return content.lessons.isNotEmpty &&
        content.lessons.every(
          (lesson) => (progress[lesson.id] ?? 0) >= lesson.sentences.length,
        );
  }

  List<int> _completedLessonNumbers(ListeningTopicContent content) {
    return content.lessons
        .where(
          (lesson) =>
              (_lessonProgress[lesson.id] ?? 0) >= lesson.sentences.length,
        )
        .map((lesson) => lesson.number)
        .toList(growable: false);
  }

  List<int> _completedTopicNumbers(
    ListeningContentCatalog catalog,
    ListeningAgeCatalog ageCatalog,
    Map<String, int> progress,
  ) {
    final completed = <int>[];
    for (var index = 0; index < ageCatalog.topics.length; index += 1) {
      try {
        final content = catalog.topic(
          startAge: ageCatalog.startAge,
          endAge: ageCatalog.endAge,
          topicNumber: index + 1,
        );
        if (_isTopicCompleted(content, progress)) {
          completed.add(index + 1);
        }
      } catch (_) {
        // Topics without loadable lesson content cannot be marked completed.
      }
    }
    return completed;
  }
}

class _CenteredSection extends StatelessWidget {
  const _CenteredSection({
    required this.maxWidth,
    required this.padding,
    required this.child,
  });

  final double maxWidth;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _CurrentLessonGroupCard extends StatelessWidget {
  const _CurrentLessonGroupCard({
    required this.catalog,
    required this.canChange,
    required this.onChange,
  });

  final ListeningAgeCatalog catalog;
  final bool canChange;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark
          ? colorScheme.surface.withValues(alpha: 0.96)
          : const Color(0xECFFFDF9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(
          color: isDark
              ? colorScheme.outline.withValues(alpha: 0.7)
              : const Color(0x99FFFFFF),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.indigo.withValues(alpha: 0.11),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.school_rounded, color: AppColors.indigo),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.tr('Nhóm bài học hiện tại', '当前课程组'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark ? colorScheme.primary : AppColors.indigo,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.tr(
                      '${catalog.startAge}–${catalog.endAge} tuổi',
                      '${catalog.startAge}–${catalog.endAge} 岁',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              enabled: canChange,
              label: context.tr('Phụ huynh thay đổi nhóm bài học', '家长更改课程组'),
              child: TextButton.icon(
                key: const Key('topic-age-selector'),
                onPressed: canChange ? onChange : null,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.lock_outline_rounded, size: 20),
                label: Text(context.tr('Đổi', '更改')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonGroupPickerSheet extends StatefulWidget {
  const _LessonGroupPickerSheet({
    required this.catalogs,
    required this.selectedIndex,
  });

  final List<ListeningAgeCatalog> catalogs;
  final int selectedIndex;

  @override
  State<_LessonGroupPickerSheet> createState() =>
      _LessonGroupPickerSheetState();
}

class _LessonGroupPickerSheetState extends State<_LessonGroupPickerSheet> {
  late int _selectedIndex = widget.selectedIndex;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              context.tr('Chọn nhóm bài học', '选择课程组'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'Phụ huynh chọn nội dung phù hợp với khả năng hiện tại của trẻ. Lựa chọn này sẽ áp dụng cho Chủ đề và trợ lý MAIN.',
                '家长请选择适合孩子当前能力的内容。此选择将同时应用于主题课程和 MAIN 助手。',
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.catalogs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final catalog = widget.catalogs[index];
                  final selected = index == _selectedIndex;
                  return Material(
                    color: selected
                        ? Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.7)
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      key: ValueKey(
                        'age-${catalog.startAge}-${catalog.endAge}',
                      ),
                      onTap: () => setState(() => _selectedIndex = index),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              selected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                context.tr(
                                  '${catalog.startAge}–${catalog.endAge} tuổi',
                                  '${catalog.startAge}–${catalog.endAge} 岁',
                                ),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              context.tr(
                                '${catalog.topics.length} chủ đề',
                                '${catalog.topics.length} 个主题',
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
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                const Icon(Icons.verified_user_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('Đã xác thực khu vực phụ huynh', '已验证家长区域'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton(
              key: const Key('apply-topic-age'),
              onPressed: () => Navigator.of(context).pop(_selectedIndex),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(context.tr('Áp dụng', '应用')),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _TopicProgressResolver = _TopicProgress Function(int index);
typedef _TopicPressed = Future<void> Function(ListeningTopic topic, int index);

class _TopicJourney extends StatelessWidget {
  const _TopicJourney({
    required this.catalogId,
    required this.topics,
    required this.progressFor,
    required this.onTopicPressed,
  });

  final String catalogId;
  final List<ListeningTopic> topics;
  final _TopicProgressResolver progressFor;
  final _TopicPressed onTopicPressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1, 2);
        final rowHeight = 168.0 + ((textScale - 1) * 150);
        final sideWidth = (width * 0.34).clamp(110.0, 190.0).toDouble();
        final imageSize = (sideWidth - 16).clamp(88.0, 124.0).toDouble();
        const checkpointWidth = 40.0;

        return SizedBox(
          height: rowHeight * topics.length,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const Key('topic-journey-path'),
                    painter: _JourneyPathPainter(
                      itemCount: topics.length,
                      rowHeight: rowHeight,
                      checkpointInset: sideWidth + (checkpointWidth / 2),
                    ),
                  ),
                ),
              ),
              Column(
                children: List<Widget>.generate(topics.length, (index) {
                  final topic = topics[index];
                  final progress = progressFor(index);
                  return SizedBox(
                    height: rowHeight,
                    child: _JourneyTopicStop(
                      topicKey: ValueKey('topic-$catalogId-$index'),
                      actionKey: ValueKey('topic-action-$catalogId-$index'),
                      topic: topic,
                      progress: progress,
                      imageSize: imageSize,
                      sideWidth: sideWidth,
                      checkpointWidth: checkpointWidth,
                      imageOnLeft: index.isEven,
                      onPressed: () => onTopicPressed(topic, index),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _JourneyTopicStop extends StatelessWidget {
  const _JourneyTopicStop({
    required this.topicKey,
    required this.actionKey,
    required this.topic,
    required this.progress,
    required this.imageSize,
    required this.sideWidth,
    required this.checkpointWidth,
    required this.imageOnLeft,
    required this.onPressed,
  });

  final Key topicKey;
  final Key actionKey;
  final ListeningTopic topic;
  final _TopicProgress progress;
  final double imageSize;
  final double sideWidth;
  final double checkpointWidth;
  final bool imageOnLeft;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final title = context.tr(topic.titleVi, topic.titleZh);
    final image = SizedBox(
      width: sideWidth,
      child: Align(
        alignment: imageOnLeft ? Alignment.centerRight : Alignment.centerLeft,
        child: _TopicCircleImage(key: topicKey, topic: topic, size: imageSize),
      ),
    );
    final checkpoint = SizedBox(
      width: checkpointWidth,
      child: _JourneyCheckpoint(completed: progress.fraction >= 1),
    );
    final details = Expanded(
      child: _TopicDetails(
        title: title,
        progress: progress,
        alignRight: !imageOnLeft,
        actionKey: actionKey,
        onPressed: onPressed,
      ),
    );

    return Semantics(
      button: true,
      label: '$title, ${progress.completed}/${progress.total}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(32),
          splashColor: AppColors.indigo.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: imageOnLeft
                  ? <Widget>[image, checkpoint, details]
                  : <Widget>[details, checkpoint, image],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicCircleImage extends StatelessWidget {
  const _TopicCircleImage({required this.topic, required this.size, super.key});

  final ListeningTopic topic;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainerHighest : Colors.white,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.13),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: ColoredBox(
          color: topic.background,
          child: topic.imagePath == null
              ? Icon(topic.icon, size: size * 0.48, color: topic.foreground)
              : Image.asset(
                  topic.imagePath!,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                ),
        ),
      ),
    );
  }
}

class _JourneyCheckpoint extends StatelessWidget {
  const _JourneyCheckpoint({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: completed ? AppColors.success : AppColors.indigo,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? colorScheme.surface : Colors.white,
            width: 3,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.indigo.withValues(alpha: 0.22),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(
          completed ? Icons.check_rounded : Icons.star_rounded,
          color: Colors.white,
          size: 19,
        ),
      ),
    );
  }
}

class _TopicDetails extends StatelessWidget {
  const _TopicDetails({
    required this.title,
    required this.progress,
    required this.alignRight,
    required this.actionKey,
    required this.onPressed,
  });

  final String title;
  final _TopicProgress progress;
  final bool alignRight;
  final Key actionKey;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final alignment = alignRight
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final textAlignment = alignRight ? TextAlign.right : TextAlign.left;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: alignment,
        children: <Widget>[
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlignment,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: isDark ? colorScheme.onSurface : AppColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              shadows: _journeyTextShadowsFor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
              '${progress.total} bài học · ${progress.completed}/${progress.total}',
              '${progress.total} 课 · ${progress.completed}/${progress.total}',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlignment,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? colorScheme.onSurfaceVariant
                  : AppColors.ink.withValues(alpha: 0.78),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              shadows: _journeyTextShadowsFor(context),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: actionKey,
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(92, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: Text(
              context.tr(
                progress.completed == 0
                    ? 'Bắt đầu'
                    : progress.fraction >= 1
                    ? 'Học lại'
                    : 'Tiếp tục',
                progress.completed == 0
                    ? '开始'
                    : progress.fraction >= 1
                    ? '重学'
                    : '继续',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _journeyTextShadows = <Shadow>[
  Shadow(color: Colors.white, blurRadius: 2),
  Shadow(color: Colors.white, blurRadius: 7),
  Shadow(color: Colors.white, offset: Offset(0, 1), blurRadius: 3),
];

List<Shadow> _journeyTextShadowsFor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const <Shadow>[
        Shadow(color: Colors.black54, blurRadius: 3),
        Shadow(color: Colors.black38, blurRadius: 7),
      ]
    : _journeyTextShadows;

class _JourneyPathPainter extends CustomPainter {
  const _JourneyPathPainter({
    required this.itemCount,
    required this.rowHeight,
    required this.checkpointInset,
  });

  final int itemCount;
  final double rowHeight;
  final double checkpointInset;

  @override
  void paint(Canvas canvas, Size size) {
    if (itemCount < 2) {
      return;
    }

    Offset pointFor(int index) => Offset(
      index.isEven ? checkpointInset : size.width - checkpointInset,
      rowHeight * (index + 0.5),
    );

    final path = Path();
    var current = pointFor(0);
    path.moveTo(current.dx, current.dy);
    for (var index = 1; index < itemCount; index++) {
      final next = pointFor(index);
      final middleY = (current.dy + next.dy) / 2;
      path.cubicTo(current.dx, middleY, next.dx, middleY, next.dx, next.dy);
      current = next;
    }

    final haloPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.74)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, haloPaint);

    final dashPaint = Paint()
      ..color = AppColors.indigo.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 8).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), dashPaint);
        distance += 14;
      }
    }
  }

  @override
  bool shouldRepaint(_JourneyPathPainter oldDelegate) {
    return itemCount != oldDelegate.itemCount ||
        rowHeight != oldDelegate.rowHeight ||
        checkpointInset != oldDelegate.checkpointInset;
  }
}

class _TopicProgress {
  const _TopicProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  double get fraction => total == 0 ? 0 : completed / total;
}
