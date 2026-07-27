import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../l10n/display_language.dart';
import '../application/lesson_media_service.dart';
import '../data/lesson_recording_history_store.dart';

class LessonRecordingHistorySheet extends StatefulWidget {
  const LessonRecordingHistorySheet({required this.mediaService, super.key});

  final LessonMediaService mediaService;

  @override
  State<LessonRecordingHistorySheet> createState() =>
      _LessonRecordingHistorySheetState();
}

class _LessonRecordingHistorySheetState
    extends State<LessonRecordingHistorySheet> {
  late Future<List<LessonRecordingHistoryEntry>> _future;
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _future = widget.mediaService.historyStore.readAll();
  }

  @override
  void dispose() {
    unawaited(widget.mediaService.stopPlayback());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.tr('Bản ghi luyện nghe', '听力练习录音'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          context.tr(
                            'Tối đa 3 bản ghi thành công gần nhất cho mỗi câu',
                            '每句最多保留最近 3 条成功录音',
                          ),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: context.tr('Đóng', '关闭'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<LessonRecordingHistoryEntry>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final entries = snapshot.data ?? const [];
                    if (entries.isEmpty) {
                      return Center(
                        child: Text(
                          context.tr(
                            'Chưa có bản ghi luyện nghe nào.',
                            '还没有听力练习录音。',
                          ),
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: AppColors.muted),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _HistoryRecordingCard(
                          entry: entry,
                          playing: _playingId == entry.id,
                          onPlay: () => _play(entry),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _play(LessonRecordingHistoryEntry entry) async {
    setState(() => _playingId = entry.id);
    final parsed = Uri.tryParse(entry.filePath);
    final uri = parsed != null && parsed.hasScheme
        ? parsed
        : Uri.file(entry.filePath);
    try {
      await widget.mediaService.play(uri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Không thể phát bản ghi này. Con có thể ghi lại câu mới.',
                '无法播放这条录音，可以重新录制。',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _playingId = null);
      }
    }
  }
}

class _HistoryRecordingCard extends StatelessWidget {
  const _HistoryRecordingCard({
    required this.entry,
    required this.playing,
    required this.onPlay,
  });

  final LessonRecordingHistoryEntry entry;
  final bool playing;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.lavenderBorder),
      ),
      child: Row(
        children: <Widget>[
          IconButton.filledTonal(
            onPressed: onPlay,
            icon: Icon(
              playing ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
            ),
            tooltip: context.tr('Nghe bản ghi', '播放录音'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.english,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (entry.vietnamese.isNotEmpty)
                  Text(
                    entry.vietnamese,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.indigo),
                  ),
                const SizedBox(height: 3),
                Text(
                  context.tr(
                    '${entry.lessonTitle} · Câu ${entry.sentenceNumber}',
                    '${entry.lessonTitle} · 第 ${entry.sentenceNumber} 句',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          Text(
            _duration(entry.duration),
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _duration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 99);
    return '00:${seconds.toString().padLeft(2, '0')}';
  }
}
