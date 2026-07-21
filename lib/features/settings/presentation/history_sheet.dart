import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../conversation/domain/conversation_models.dart';
import '../../conversation/presentation/conversation_controller.dart';

enum _HistoryFilter { all, approved, rejected, pending }

class HistorySheet extends StatefulWidget {
  const HistorySheet({required this.controller, super.key});

  final ConversationController controller;

  @override
  State<HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<HistorySheet> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _busyItems = <String>{};

  List<ConversationHistoryItem> _items = const <ConversationHistoryItem>[];
  _HistoryFilter _filter = _HistoryFilter.all;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final items = await widget.controller.loadHistory();
      if (!mounted) {
        return;
      }
      items.sort((left, right) => right.createdAt.compareTo(left.createdAt));
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  List<ConversationHistoryItem> get _visibleItems {
    final query = _searchController.text.trim().toLowerCase();
    return _items
        .where((item) {
          final matchesFilter = switch (_filter) {
            _HistoryFilter.all => true,
            _HistoryFilter.approved =>
              item.reviewStatus == HistoryReviewStatus.approved,
            _HistoryFilter.rejected =>
              item.reviewStatus == HistoryReviewStatus.rejected,
            _HistoryFilter.pending =>
              item.reviewStatus == HistoryReviewStatus.pending,
          };
          final matchesQuery =
              query.isEmpty ||
              item.vietnameseText.toLowerCase().contains(query) ||
              item.englishText.toLowerCase().contains(query);
          return matchesFilter && matchesQuery;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final sheetHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.84,
      760.0,
    );
    final visibleItems = _visibleItems;

    return SafeArea(
      child: SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _HistoryHeader(
                count: _items.length,
                onRefresh: () => _loadHistory(),
                onClear: _items.isEmpty ? null : _confirmClearHistory,
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Tìm câu tiếng Việt hoặc tiếng Anh',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Xóa nội dung tìm kiếm',
                        ),
                  filled: true,
                  fillColor: AppColors.lavenderSoft,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _HistoryFilter.values
                      .map(
                        (filter) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_filterLabel(filter)),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _HistoryBody(
                  loading: _loading,
                  error: _error,
                  hasAnyItems: _items.isNotEmpty,
                  items: visibleItems,
                  busyItems: _busyItems,
                  onRetry: () => _loadHistory(),
                  onPlay: _playItem,
                  onReview: _reviewItem,
                  onDelete: _confirmDeleteItem,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _playItem(ConversationHistoryItem item) async {
    if (_busyItems.contains(item.conversationId)) {
      return;
    }
    setState(() => _busyItems.add(item.conversationId));
    try {
      await widget.controller.playHistoryItem(item);
    } catch (error) {
      _showMessage(_friendlyError(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _busyItems.remove(item.conversationId));
      }
    }
  }

  Future<void> _reviewItem(ConversationHistoryItem item, bool approved) async {
    if (_busyItems.contains(item.conversationId)) {
      return;
    }
    final index = _items.indexWhere(
      (candidate) => candidate.conversationId == item.conversationId,
    );
    if (index < 0) {
      return;
    }

    final previousItem = _items[index];
    setState(() {
      _busyItems.add(item.conversationId);
      _items = List<ConversationHistoryItem>.of(_items)
        ..[index] = item.copyWithReview(approved);
    });

    try {
      final learning = await widget.controller.reviewHistoryItem(
        item,
        approved,
      );
      if (mounted) {
        setState(() {
          _items = List<ConversationHistoryItem>.of(_items)
            ..[index] = item.copyWithReview(approved, learning: learning);
        });
      }
      _showMessage(
        learning.message.isNotEmpty
            ? learning.message
            : approved
            ? 'Đã đánh dấu Đúng ý.'
            : 'Đã đánh dấu Sai ý.',
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _items = List<ConversationHistoryItem>.of(_items)
            ..[index] = previousItem;
        });
      }
      _showMessage(_friendlyError(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _busyItems.remove(item.conversationId));
      }
    }
  }

  Future<void> _confirmDeleteItem(ConversationHistoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa lượt nói này?'),
        content: Text('“${item.vietnameseText}” sẽ bị xóa khỏi lịch sử.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _busyItems.add(item.conversationId));
    try {
      await widget.controller.deleteHistoryItem(item);
      if (!mounted) {
        return;
      }
      setState(() {
        _items = _items
            .where(
              (candidate) => candidate.conversationId != item.conversationId,
            )
            .toList(growable: false);
      });
      _showMessage('Đã xóa lượt nói.');
    } catch (error) {
      _showMessage(_friendlyError(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _busyItems.remove(item.conversationId));
      }
    }
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa toàn bộ lịch sử?'),
        content: const Text(
          'Thao tác này xóa tất cả lượt nói đang lưu trên backend và không thể hoàn tác.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Xóa tất cả'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.controller.clearHistory();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = const <ConversationHistoryItem>[];
        _loading = false;
      });
      _showMessage('Đã xóa toàn bộ lịch sử.');
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
      }
      _showMessage(_friendlyError(error), isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? Theme.of(context).colorScheme.error
              : AppColors.ink,
        ),
      );
  }

  String _friendlyError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '');
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({
    required this.count,
    required this.onRefresh,
    required this.onClear,
    required this.onClose,
  });

  final int count;
  final VoidCallback onRefresh;
  final VoidCallback? onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Lịch sử gần đây',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '$count lượt đã lưu',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Làm mới lịch sử',
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: onClear,
          icon: const Icon(Icons.delete_sweep_outlined),
          tooltip: 'Xóa toàn bộ lịch sử',
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Đóng',
        ),
      ],
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({
    required this.loading,
    required this.error,
    required this.hasAnyItems,
    required this.items,
    required this.busyItems,
    required this.onRetry,
    required this.onPlay,
    required this.onReview,
    required this.onDelete,
  });

  final bool loading;
  final String? error;
  final bool hasAnyItems;
  final List<ConversationHistoryItem> items;
  final Set<String> busyItems;
  final VoidCallback onRetry;
  final ValueChanged<ConversationHistoryItem> onPlay;
  final void Function(ConversationHistoryItem item, bool approved) onReview;
  final ValueChanged<ConversationHistoryItem> onDelete;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return _HistoryMessage(
        icon: Icons.cloud_off_rounded,
        text: error!,
        actionLabel: 'Thử lại',
        onAction: onRetry,
      );
    }
    if (items.isEmpty) {
      return _HistoryMessage(
        icon: hasAnyItems ? Icons.search_off_rounded : Icons.history_rounded,
        text: hasAnyItems
            ? 'Không tìm thấy lượt nói phù hợp.'
            : 'Chưa có lượt nói nào.',
      );
    }

    final children = <Widget>[];
    String? currentDay;
    for (final item in items) {
      final dayKey = _dateKey(item.createdAt);
      if (dayKey != currentDay) {
        currentDay = dayKey;
        children.add(
          Padding(
            padding: EdgeInsets.only(top: children.isEmpty ? 4 : 12, bottom: 8),
            child: Text(
              _dayLabel(item.createdAt),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.muted,
                fontSize: 14,
              ),
            ),
          ),
        );
      }
      children.add(
        _HistoryRow(
          item: item,
          busy: busyItems.contains(item.conversationId),
          onPlay: () => onPlay(item),
          onApprove: () => onReview(item, true),
          onReject: () => onReview(item, false),
          onDelete: () => onDelete(item),
        ),
      );
    }
    return ListView(children: children);
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.item,
    required this.busy,
    required this.onPlay,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  final ConversationHistoryItem item;
  final bool busy;
  final VoidCallback onPlay;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final status = _statusPresentation(item.reviewStatus);

    return Semantics(
      container: true,
      label:
          '${status.label}. ${item.vietnameseText}. ${item.englishText}. '
          '${_formatTime(item.createdAt)}.',
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.lavenderBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: status.background,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(status.icon, color: status.color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.vietnameseText,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatTime(item.createdAt),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: Text(
                item.englishText,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.indigo),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  _MetadataChip(label: item.context.label),
                  _MetadataChip(label: _sourceLabel(item)),
                  _LearningChip(item: item),
                  _MetadataChip(label: _asrLabel(item.asrMode)),
                  if (item.latency.timeToFirstAudioMs > 0)
                    _MetadataChip(
                      label: '${item.latency.timeToFirstAudioMs} ms',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: status.background,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(status.icon, color: status.color, size: 17),
                        const SizedBox(width: 5),
                        Text(
                          status.label,
                          style: TextStyle(
                            color: status.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (item.audioUri != null)
                      IconButton(
                        onPressed: busy ? null : onPlay,
                        icon: const Icon(Icons.play_arrow_rounded),
                        tooltip: 'Phát lại câu tiếng Anh',
                      ),
                    IconButton(
                      onPressed: busy ? null : onApprove,
                      icon: const Icon(Icons.sentiment_satisfied_alt_rounded),
                      tooltip: 'Đánh dấu Đúng ý',
                      style: IconButton.styleFrom(
                        backgroundColor:
                            item.reviewStatus == HistoryReviewStatus.approved
                            ? AppColors.successSoft
                            : AppColors.lavender,
                        foregroundColor:
                            item.reviewStatus == HistoryReviewStatus.approved
                            ? AppColors.success
                            : AppColors.indigoDark,
                      ),
                    ),
                    IconButton(
                      onPressed: busy ? null : onReject,
                      icon: const Icon(Icons.sentiment_dissatisfied_rounded),
                      tooltip: 'Đánh dấu Sai ý',
                      style: IconButton.styleFrom(
                        backgroundColor:
                            item.reviewStatus == HistoryReviewStatus.rejected
                            ? AppColors.coralSoft
                            : AppColors.lavender,
                        foregroundColor:
                            item.reviewStatus == HistoryReviewStatus.rejected
                            ? Theme.of(context).colorScheme.error
                            : AppColors.indigoDark,
                      ),
                    ),
                    IconButton(
                      onPressed: busy ? null : onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: 'Xóa lượt nói',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.lavenderSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _LearningChip extends StatelessWidget {
  const _LearningChip({required this.item});

  final ConversationHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final presentation = _learningPresentation(item);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: presentation.background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(presentation.icon, size: 13, color: presentation.color),
          const SizedBox(width: 4),
          Text(
            presentation.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: presentation.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: AppColors.muted, size: 38),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPresentation {
  const _StatusPresentation({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;
}

_StatusPresentation _learningPresentation(ConversationHistoryItem item) {
  return switch (item.learningStatus) {
    'promoted' || 'already_rule' => const _StatusPresentation(
      icon: Icons.bolt_rounded,
      label: 'Đã tối ưu',
      color: AppColors.success,
      background: AppColors.successSoft,
    ),
    'cached' || 'observing' => _StatusPresentation(
      icon: Icons.psychology_alt_rounded,
      label: item.learningUseCount == null
          ? 'Đang học'
          : 'Đang học ${item.learningUseCount}/3',
      color: AppColors.indigo,
      background: AppColors.lavender,
    ),
    'rejected' => const _StatusPresentation(
      icon: Icons.do_not_disturb_alt_rounded,
      label: 'Không học',
      color: Color(0xFFD92D20),
      background: AppColors.coralSoft,
    ),
    'conflict' => const _StatusPresentation(
      icon: Icons.warning_amber_rounded,
      label: 'Cần kiểm tra',
      color: Color(0xFFB54708),
      background: Color(0xFFFFF4E5),
    ),
    _ => const _StatusPresentation(
      icon: Icons.info_outline_rounded,
      label: 'Chưa tối ưu',
      color: AppColors.muted,
      background: AppColors.lavenderSoft,
    ),
  };
}

_StatusPresentation _statusPresentation(HistoryReviewStatus status) {
  return switch (status) {
    HistoryReviewStatus.approved => const _StatusPresentation(
      icon: Icons.check_rounded,
      label: 'Đúng ý',
      color: AppColors.success,
      background: AppColors.successSoft,
    ),
    HistoryReviewStatus.rejected => const _StatusPresentation(
      icon: Icons.close_rounded,
      label: 'Sai ý',
      color: Color(0xFFD92D20),
      background: AppColors.coralSoft,
    ),
    HistoryReviewStatus.pending => const _StatusPresentation(
      icon: Icons.schedule_rounded,
      label: 'Chưa đánh giá',
      color: AppColors.indigo,
      background: AppColors.lavender,
    ),
  };
}

String _filterLabel(_HistoryFilter filter) {
  return switch (filter) {
    _HistoryFilter.all => 'Tất cả',
    _HistoryFilter.approved => 'Đúng ý',
    _HistoryFilter.rejected => 'Sai ý',
    _HistoryFilter.pending => 'Chưa đánh giá',
  };
}

String _sourceLabel(ConversationHistoryItem item) {
  if (item.processingMode == 'rule' || item.textSource.contains('rule')) {
    return 'Rule';
  }
  if (item.processingMode == 'ai' || item.textSource == 'openai') {
    return 'AI';
  }
  if (item.processingMode == 'cache' || item.textSource.contains('cache')) {
    return 'Cache';
  }
  return item.processingMode == 'unknown'
      ? 'Không rõ nguồn'
      : item.processingMode;
}

String _asrLabel(String asrMode) {
  return switch (asrMode) {
    'android_streaming' => 'ASR trực tiếp',
    'openai_realtime' => 'OpenAI Realtime',
    'ble_offline_intent' => 'BLE offline',
    'batch_chunks' => 'Batch ASR',
    'device_streaming' => 'BLE ASR',
    _ => asrMode == 'unknown' ? 'ASR cũ' : asrMode,
  };
}

String _dateKey(DateTime value) {
  return '${value.year}-${value.month}-${value.day}';
}

String _dayLabel(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(value.year, value.month, value.day);
  final difference = today.difference(date).inDays;
  if (difference == 0) {
    return 'Hôm nay';
  }
  if (difference == 1) {
    return 'Hôm qua';
  }
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';
}

String _formatTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
