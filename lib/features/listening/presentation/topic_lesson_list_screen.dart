import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../../settings/presentation/history_sheet.dart';
import '../application/lesson_media_service.dart';
import '../data/listening_progress_store.dart';
import '../domain/listening_catalog.dart';
import '../domain/listening_content.dart';
import 'lesson_intro_screen.dart';
import 'listening_navigation_bar.dart';

class TopicLessonListScreen extends StatefulWidget {
  const TopicLessonListScreen({
    required this.language,
    required this.topic,
    required this.content,
    this.controller,
    this.progressStore = const ListeningProgressStore(),
    this.mediaService,
    super.key,
  });

  final DisplayLanguage language;
  final ListeningTopic topic;
  final ListeningTopicContent content;
  final ConversationController? controller;
  final ListeningProgressStore progressStore;
  final LessonMediaService? mediaService;

  @override
  State<TopicLessonListScreen> createState() => _TopicLessonListScreenState();
}

class _TopicLessonListScreenState extends State<TopicLessonListScreen> {
  late final LessonMediaService _mediaService;
  late Future<Map<String, int>> _progressFuture;
  late final bool _ownsMediaService;

  @override
  void initState() {
    super.initState();
    _ownsMediaService = widget.mediaService == null;
    _mediaService = widget.mediaService ?? LessonMediaService();
    _progressFuture = widget.progressStore.readAll();
  }

  @override
  void dispose() {
    if (_ownsMediaService) {
      _mediaService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DisplayLanguageScope(
      language: widget.language,
      child: Scaffold(
        key: const Key('topic-lesson-list-screen'),
        body: SafeArea(
          bottom: false,
          child: FutureBuilder<Map<String, int>>(
            future: _progressFuture,
            builder: (context, snapshot) {
              final progress = snapshot.data ?? const <String, int>{};
              return CustomScrollView(
                slivers: <Widget>[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    sliver: SliverToBoxAdapter(child: _Header(onBack: _goBack)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _TopicHero(widget: widget),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.auto_awesome_rounded,
                            color: AppColors.periwinkle,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr('Hành trình học', '学习旅程'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFFC75B),
                            size: 23,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    sliver: SliverList.separated(
                      itemCount: widget.content.lessons.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final lesson = widget.content.lessons[index];
                        final completed = (progress[lesson.id] ?? 0).clamp(
                          0,
                          lesson.sentences.length,
                        );
                        return _LessonPathCard(
                          key: ValueKey('lesson-${lesson.id}'),
                          lesson: lesson,
                          completedSentences: completed,
                          isLast: index == widget.content.lessons.length - 1,
                          onPressed: () => _startLesson(lesson),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: ListeningNavigationBar(
          onCommunication: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          onHistory: widget.controller == null ? null : _showHistory,
        ),
      ),
    );
  }

  void _goBack() => Navigator.of(context).pop();

  Future<void> _startLesson(ListeningLessonContent lesson) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LessonIntroScreen(
          language: widget.language,
          topic: widget.topic,
          lesson: lesson,
          controller: widget.controller,
          progressStore: widget.progressStore,
          mediaService: _mediaService,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _progressFuture = widget.progressStore.readAll();
    });
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => HistorySheet(controller: widget.controller!),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: context.tr('Quay lại', '返回'),
        ),
        const Spacer(),
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: AppColors.lavender,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_rounded, color: AppColors.indigo),
        ),
      ],
    );
  }
}

class _TopicHero extends StatelessWidget {
  const _TopicHero({required this.widget});

  final TopicLessonListScreen widget;

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          context.tr(content.titleVi, widget.topic.titleZh),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 14),
        AspectRatio(
          aspectRatio: 1.58,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
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
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.lavenderSoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(
                      Icons.menu_book_rounded,
                      color: AppColors.indigo,
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
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                height: 22,
                child: VerticalDivider(color: AppColors.lavenderBorder),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppColors.indigo,
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
                        style: const TextStyle(
                          color: AppColors.ink,
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
    required this.isLast,
    required this.onPressed,
    super.key,
  });

  final ListeningLessonContent lesson;
  final int completedSentences;
  final bool isLast;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final total = lesson.sentences.length;
    final progress = total == 0 ? 0.0 : completedSentences / total;
    return Semantics(
      button: true,
      label: 'Bài ${lesson.number}, ${lesson.titleVi}',
      child: Material(
        color: AppColors.lavenderSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.lavenderBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
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
                          color: AppColors.indigo,
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
                        child: const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFD36A),
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
                            icon: Icons.chat_bubble_outline_rounded,
                            label: context.tr('$total câu', '$total 句'),
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
                                color: AppColors.indigo,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$completedSentences/$total',
                            style: const TextStyle(
                              color: AppColors.muted,
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
                              completedSentences == 0 ? 'Học ngay' : 'Học tiếp',
                              completedSentences == 0 ? '立即学习' : '继续学习',
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 17, color: AppColors.muted),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.muted,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
