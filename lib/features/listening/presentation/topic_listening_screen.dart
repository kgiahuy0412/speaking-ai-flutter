import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../application/lesson_media_service.dart';
import '../data/listening_progress_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import 'lesson_recording_history_sheet.dart';
import 'listening_navigation_bar.dart';
import 'topic_lesson_list_screen.dart';

class TopicListeningScreen extends StatefulWidget {
  const TopicListeningScreen({
    required this.language,
    required this.childAge,
    this.controller,
    this.progressStore = const ListeningProgressStore(),
    super.key,
  });

  final DisplayLanguage language;
  final int childAge;
  final ConversationController? controller;
  final ListeningProgressStore progressStore;

  @override
  State<TopicListeningScreen> createState() => _TopicListeningScreenState();
}

class _TopicListeningScreenState extends State<TopicListeningScreen> {
  late int _selectedCatalogIndex;
  late final Future<ListeningContentCatalog> _contentFuture;
  ListeningContentCatalog? _contentCatalog;
  Map<String, int> _lessonProgress = const <String, int>{};
  late final LessonMediaService _historyMediaService;

  ListeningAgeCatalog get _catalog => listeningCatalogs[_selectedCatalogIndex];

  @override
  void initState() {
    super.initState();
    _selectedCatalogIndex = listeningCatalogs.lastIndexWhere(
      (catalog) => widget.childAge >= catalog.startAge,
    );
    if (_selectedCatalogIndex < 0) {
      _selectedCatalogIndex = 0;
    }
    _contentFuture = AssetListeningContentRepository().load();
    _historyMediaService = LessonMediaService();
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
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            key: const Key('topic-listening-screen'),
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverToBoxAdapter(child: _buildHeader(context)),
              ),
              SliverToBoxAdapter(child: _buildAgeSelector()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: _ContinueLearningCard(
                    topic: _catalog.topics[_catalog.continueTopicIndex],
                    progress: _topicProgress(_catalog.continueTopicIndex),
                    onPressed: () => _openTopic(
                      _catalog.topics[_catalog.continueTopicIndex],
                      _catalog.continueTopicIndex,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          context.tr('Chủ đề của con', '孩子的主题'),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      Text(
                        context.tr(
                          '${_catalog.topics.length} chủ đề',
                          '${_catalog.topics.length} 个主题',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.crossAxisExtent >= 720
                        ? 4
                        : constraints.crossAxisExtent >= 520
                        ? 3
                        : 2;
                    final textScale = MediaQuery.textScalerOf(context).scale(1);
                    final compactTwoColumnGrid =
                        crossAxisCount == 2 &&
                        (constraints.crossAxisExtent < 340 || textScale > 1.1);
                    return SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _TopicCard(
                          key: ValueKey('topic-${_catalog.id}-$index'),
                          topic: _catalog.topics[index],
                          progress: _topicProgress(index),
                          onPressed: () =>
                              _openTopic(_catalog.topics[index], index),
                        ),
                        childCount: _catalog.topics.length,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: crossAxisCount == 2
                            ? (compactTwoColumnGrid ? 0.76 : 0.93)
                            : 0.96,
                      ),
                    );
                  },
                ),
              ),
            ],
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
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: context.tr('Quay lại', '返回'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            context.tr('Luyện nghe theo chủ đề', '按主题练听力'),
            maxLines: 2,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontSize: 24),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          height: 48,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.lavender,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                'assets/images/mascot-robot.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAgeSelector() {
    return SizedBox(
      height: 66,
      child: ListView.separated(
        key: const Key('topic-age-selector'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        scrollDirection: Axis.horizontal,
        itemCount: listeningCatalogs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final catalog = listeningCatalogs[index];
          return _AgeChip(
            key: ValueKey('age-${catalog.id}'),
            label: context.tr(
              '${catalog.startAge}–${catalog.endAge}'
                  '${index == _selectedCatalogIndex ? ' tuổi' : ''}',
              '${catalog.startAge}–${catalog.endAge}'
                  '${index == _selectedCatalogIndex ? ' 岁' : ''}',
            ),
            selected: index == _selectedCatalogIndex,
            onPressed: () => setState(() => _selectedCatalogIndex = index),
          );
        },
      ),
    );
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          LessonRecordingHistorySheet(mediaService: _historyMediaService),
    );
  }

  Future<void> _loadContentAndProgress() async {
    try {
      final catalog = await _contentFuture;
      if (!mounted) {
        return;
      }
      setState(() {
        _contentCatalog = catalog;
      });
    } catch (_) {
      // The topic catalog remains usable while lesson content is unavailable.
    }
    try {
      final progress = await widget.progressStore.readAll();
      if (!mounted) {
        return;
      }
      setState(() {
        _lessonProgress = progress;
      });
    } catch (_) {
      // A fresh device simply starts without local lesson progress.
    }
  }

  Future<void> _reloadProgress() async {
    final progress = await widget.progressStore.readAll();
    if (!mounted) {
      return;
    }
    setState(() => _lessonProgress = progress);
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
        final completed = topic.completed.clamp(0, topic.total);
        return _TopicProgress(completed: completed, total: topic.total);
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

  Future<void> _openTopic(ListeningTopic topic, int topicIndex) async {
    try {
      final catalog = await _contentFuture;
      if (!mounted) {
        return;
      }
      final content = catalog.topic(
        startAge: _catalog.startAge,
        endAge: _catalog.endAge,
        topicNumber: topicIndex + 1,
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TopicLessonListScreen(
            language: widget.language,
            topic: topic,
            content: content,
            controller: widget.controller,
            progressStore: widget.progressStore,
          ),
        ),
      );
      await _reloadProgress();
    } catch (error) {
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
}

class _AgeChip extends StatelessWidget {
  const _AgeChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.indigo : AppColors.lavenderSoft,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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

class _ContinueLearningCard extends StatelessWidget {
  const _ContinueLearningCard({
    required this.topic,
    required this.progress,
    required this.onPressed,
  });

  final ListeningTopic topic;
  final _TopicProgress progress;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.lavenderSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.lavenderBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('continue-listening-card'),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 76,
                height: 76,
                child: Image.asset(
                  'assets/images/mascot-robot.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.tr('Tiếp tục học', '继续学习'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.indigo,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${context.tr(topic.titleVi, topic.titleZh)} · '
                      '${context.tr('Bài', '第')} ${progress.nextLesson}/${progress.total}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(child: _ProgressBar(value: progress.fraction)),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.play_circle_fill_rounded,
                          color: AppColors.indigo,
                          size: 30,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.progress,
    required this.onPressed,
    super.key,
  });

  final ListeningTopic topic;
  final _TopicProgress progress;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final title = context.tr(topic.titleVi, topic.titleZh);
    return Semantics(
      button: true,
      label: '$title, ${progress.completed}/${progress.total}',
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.lavenderBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: topic.background,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        topic.background,
                        Color.alphaBlend(
                          topic.foreground.withValues(alpha: 0.08),
                          topic.background,
                        ),
                      ],
                    ),
                  ),
                  child: Stack(
                    children: <Widget>[
                      if (topic.imagePath != null)
                        Positioned.fill(
                          child: Image.asset(
                            topic.imagePath!,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.medium,
                          ),
                        )
                      else
                        Center(
                          child: Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.82),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              topic.icon,
                              size: 46,
                              color: topic.foreground,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr(
                        '${progress.total} bài học',
                        '${progress.total} 课',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: <Widget>[
                        Expanded(child: _ProgressBar(value: progress.fraction)),
                        const SizedBox(width: 8),
                        Text(
                          '${progress.completed}/${progress.total}',
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicProgress {
  const _TopicProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  double get fraction => total == 0 ? 0 : completed / total;
  int get nextLesson => total == 0 ? 0 : (completed + 1).clamp(1, total);
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 7,
        backgroundColor: AppColors.lavenderBorder,
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.indigo),
      ),
    );
  }
}
