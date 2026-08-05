import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../l10n/display_language.dart';
import '../../home/presentation/scenic_app_header.dart';
import '../data/vocabulary_store.dart';
import '../domain/vocabulary_entry.dart';

class VocabularyHomeScreen extends StatefulWidget {
  const VocabularyHomeScreen({
    required this.isReady,
    required this.onReturnToConversation,
    required this.onHistory,
    required this.onSettings,
    this.store = const VocabularyStore(),
    this.voicePromptService,
    this.translator,
    super.key,
  });

  final bool isReady;
  final VoidCallback onReturnToConversation;
  final VoidCallback onHistory;
  final VoidCallback onSettings;
  final VocabularyStore store;
  final VoicePromptService? voicePromptService;
  final VocabularyTranslator? translator;

  @override
  State<VocabularyHomeScreen> createState() => _VocabularyHomeScreenState();
}

class _VocabularyHomeScreenState extends State<VocabularyHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final VoicePromptService _voicePromptService;
  late final bool _ownsVoicePromptService;
  List<VocabularyEntry> _entries = const <VocabularyEntry>[];
  bool _loading = true;
  bool _deleteMode = false;
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    _ownsVoicePromptService = widget.voicePromptService == null;
    _voicePromptService =
        widget.voicePromptService ?? createVoicePromptService();
    _searchController.addListener(_refreshSearch);
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    if (_ownsVoicePromptService) {
      unawaited(_voicePromptService.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 370 ? 52.0 : 60.0;
    final visibleEntries = _filteredEntries;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LearningScenery(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              ScenicAppHeader(
                isReady: widget.isReady,
                onHistory: widget.onHistory,
                onSettings: widget.onSettings,
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: SingleChildScrollView(
                      key: const Key('vocabulary-home-scroll'),
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        68,
                        horizontalPadding,
                        20,
                      ),
                      child: Column(
                        children: <Widget>[
                          _buildTitleRow(context),
                          const SizedBox(height: 18),
                          _buildSearchField(context),
                          const SizedBox(height: 24),
                          Text(
                            context.tr(
                              '${visibleEntries.length} từ đã lưu',
                              '已保存 ${visibleEntries.length} 个词',
                            ),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Theme.of(context).colorScheme.primary
                                      : AppColors.indigoDark,
                                  fontWeight: FontWeight.w800,
                                  shadows: const <Shadow>[
                                    Shadow(color: Colors.white, blurRadius: 8),
                                  ],
                                ),
                          ),
                          const SizedBox(height: 16),
                          _buildVocabularyCard(context, visibleEntries),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: _buildPracticeButton(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleRow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: <Widget>[
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              context.tr('Từ vựng của con', '孩子的词汇'),
              maxLines: 1,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: isDark
                    ? Theme.of(context).colorScheme.primary
                    : AppColors.indigoDark,
                fontSize: 25,
                shadows: const <Shadow>[
                  Shadow(color: Colors.white, blurRadius: 10),
                ],
              ),
            ),
          ),
        ),
        IconButton.filled(
          key: const Key('add-vocabulary-button'),
          onPressed: _translating ? null : _showAddDialog,
          icon: _translating
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : const Icon(Icons.add_rounded),
          tooltip: context.tr('Thêm từ vựng', '添加词汇'),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(46),
            maximumSize: const Size.square(46),
            backgroundColor: AppColors.indigo,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          key: const Key('toggle-delete-vocabulary'),
          onPressed: () => setState(() => _deleteMode = !_deleteMode),
          icon: Icon(
            _deleteMode ? Icons.close_rounded : Icons.delete_outline_rounded,
          ),
          tooltip: _deleteMode
              ? context.tr('Đóng chế độ xóa', '退出删除模式')
              : context.tr('Xóa từ vựng', '删除词汇'),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(46),
            maximumSize: const Size.square(46),
            backgroundColor: isDark
                ? Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.86),
            foregroundColor: _deleteMode ? AppColors.coral : AppColors.indigo,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: context.tr('Tìm từ vựng…', '搜索词汇…'),
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: isDark
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.88),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(
            color: isDark
                ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.9),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 17),
      ),
    );
  }

  Widget _buildVocabularyCard(
    BuildContext context,
    List<VocabularyEntry> entries,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_loading) {
      return const SizedBox(
        height: 330,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 330),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: scenicPanelDecoration(
        radius: 28,
        color: isDark
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.94)
            : const Color(0xEFFFFDF9),
        borderColor: isDark
            ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.55)
            : const Color(0x66FFFFFF),
      ),
      child: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 70),
                child: Text(
                  context.tr(
                    'Chưa có từ phù hợp. Con thử tìm từ khác nhé.',
                    '没有匹配的词，试试其他关键词。',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ),
            )
          : Column(
              children: <Widget>[
                for (
                  var index = 0;
                  index < entries.length;
                  index++
                ) ...<Widget>[
                  _VocabularyRow(
                    entry: entries[index],
                    deleteMode: _deleteMode,
                    onPlay: () => unawaited(
                      _voicePromptService.speak(
                        entries[index].word,
                        locale: 'en-US',
                      ),
                    ),
                    onDelete: () => unawaited(_delete(entries[index])),
                  ),
                  if (index != entries.length - 1)
                    const Divider(color: AppColors.lavenderBorder, height: 1),
                ],
              ],
            ),
    );
  }

  Widget _buildPracticeButton(BuildContext context) {
    return FilledButton(
      key: const Key('vocabulary-practice-button'),
      onPressed: widget.onReturnToConversation,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 68),
        backgroundColor: AppColors.indigo,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.auto_stories_rounded, size: 27),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              context.tr('Tạo tình huống luyện tập', '生成练习场景'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<VocabularyEntry> get _filteredEntries {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _entries;
    }
    return _entries
        .where((entry) {
          return entry.word.toLowerCase().contains(query) ||
              entry.meaning.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _load() async {
    final entries = await widget.store.read();
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _delete(VocabularyEntry entry) async {
    final entries = _entries.where((item) => item.id != entry.id).toList();
    await widget.store.write(entries);
    if (!mounted) {
      return;
    }
    setState(() => _entries = entries);
  }

  void _refreshSearch() => setState(() {});

  Future<void> _showAddDialog() async {
    final input = await showDialog<String>(
      context: context,
      builder: (_) => const _AddVocabularyDialog(),
    );
    final normalized = input?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }

    setState(() => _translating = true);
    try {
      final translated = await _translateVocabulary(normalized);
      final entry = VocabularyEntry(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        word: translated.englishText,
        meaning: translated.vietnameseText,
        addedAt: DateTime.now(),
      );
      final entries = <VocabularyEntry>[entry, ..._entries];
      await widget.store.write(entries);
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
        _deleteMode = false;
        _searchController.clear();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'Chưa dịch được từ này. Con kiểm tra mạng rồi thử lại nhé.',
              '暂时无法翻译这个词，请检查网络后重试。',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _translating = false);
      }
    }
  }

  Future<VocabularyTranslation> _translateVocabulary(String input) async {
    const pairs = <String, VocabularyTranslation>{
      'apple': VocabularyTranslation(
        englishText: 'Apple',
        vietnameseText: 'Quả táo',
      ),
      'quả táo': VocabularyTranslation(
        englishText: 'Apple',
        vietnameseText: 'Quả táo',
      ),
      'family': VocabularyTranslation(
        englishText: 'Family',
        vietnameseText: 'Gia đình',
      ),
      'gia đình': VocabularyTranslation(
        englishText: 'Family',
        vietnameseText: 'Gia đình',
      ),
      'school': VocabularyTranslation(
        englishText: 'School',
        vietnameseText: 'Trường học',
      ),
      'trường học': VocabularyTranslation(
        englishText: 'School',
        vietnameseText: 'Trường học',
      ),
      'happy': VocabularyTranslation(
        englishText: 'Happy',
        vietnameseText: 'Vui vẻ',
      ),
      'vui vẻ': VocabularyTranslation(
        englishText: 'Happy',
        vietnameseText: 'Vui vẻ',
      ),
      'hello': VocabularyTranslation(
        englishText: 'Hello',
        vietnameseText: 'Xin chào',
      ),
      'xin chào': VocabularyTranslation(
        englishText: 'Hello',
        vietnameseText: 'Xin chào',
      ),
      'thank you': VocabularyTranslation(
        englishText: 'Thank you',
        vietnameseText: 'Cảm ơn',
      ),
      'cảm ơn': VocabularyTranslation(
        englishText: 'Thank you',
        vietnameseText: 'Cảm ơn',
      ),
    };
    final normalized = input.toLowerCase();
    final known = pairs[normalized];
    if (known != null) {
      return known;
    }

    final translator = widget.translator;
    if (translator == null) {
      throw StateError('Không có dịch vụ dịch từ vựng.');
    }
    final translated = await translator(input);
    final englishText = _capitalize(translated.englishText.trim());
    final vietnameseText = _capitalize(
      translated.vietnameseText.trim().isEmpty
          ? input
          : translated.vietnameseText.trim(),
    );
    if (englishText.isEmpty || _containsVietnameseCharacters(englishText)) {
      throw StateError('Bản dịch tiếng Anh không hợp lệ.');
    }
    return VocabularyTranslation(
      englishText: englishText,
      vietnameseText: vietnameseText,
    );
  }

  String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  bool _containsVietnameseCharacters(String value) => RegExp(
    r'[ăâđêôơưáàảãạấầẩẫậắằẳẵặéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ]',
    caseSensitive: false,
  ).hasMatch(value);
}

class _VocabularyRow extends StatelessWidget {
  const _VocabularyRow({
    required this.entry,
    required this.deleteMode,
    required this.onPlay,
    required this.onDelete,
  });

  final VocabularyEntry entry;
  final bool deleteMode;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: AppColors.lavender,
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, color: AppColors.indigo, size: 25),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.word,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.indigoDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.meaning,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Text(
                  _dateLabel(context),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey<String>('vocabulary-action-${entry.id}'),
            onPressed: deleteMode ? onDelete : onPlay,
            icon: Icon(
              deleteMode ? Icons.delete_rounded : Icons.volume_up_rounded,
            ),
            tooltip: deleteMode
                ? context.tr('Xóa từ này', '删除此词')
                : context.tr('Nghe phát âm', '播放发音'),
            color: deleteMode ? AppColors.coral : AppColors.indigo,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(44),
              backgroundColor: AppColors.lavenderSoft,
            ),
          ),
        ],
      ),
    );
  }

  IconData get _icon {
    return switch (entry.word.toLowerCase()) {
      'family' => Icons.family_restroom_rounded,
      'school' => Icons.school_rounded,
      'happy' => Icons.sentiment_very_satisfied_rounded,
      _ => Icons.auto_stories_rounded,
    };
  }

  String _dateLabel(BuildContext context) {
    final days = DateTime.now().difference(entry.addedAt).inDays;
    if (days <= 0) {
      return context.tr('Đã lưu hôm nay', '今天保存');
    }
    if (days == 1) {
      return context.tr('Đã lưu hôm qua', '昨天保存');
    }
    return context.tr('Đã lưu $days ngày trước', '$days 天前保存');
  }
}

class _AddVocabularyDialog extends StatefulWidget {
  const _AddVocabularyDialog();

  @override
  State<_AddVocabularyDialog> createState() => _AddVocabularyDialogState();
}

class _AddVocabularyDialogState extends State<_AddVocabularyDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refresh);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _controller.text.trim().isNotEmpty;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 48),
      backgroundColor: const Color(0xFFFFFDFB),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Text(
                  context.tr('Thêm từ vựng', '添加词汇'),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.indigoDark,
                    fontSize: 23,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('add-vocabulary-field'),
                controller: _controller,
                autofocus: true,
                minLines: 1,
                maxLines: 1,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: context.tr(
                    'Nhập từ tiếng Anh hoặc tiếng Việt',
                    '输入英文或越南文',
                  ),
                  filled: true,
                  fillColor: AppColors.lavenderSoft,
                  hintStyle: const TextStyle(fontSize: 13),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: AppColors.indigo,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: AppColors.indigo,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'Có thể nhập một từ hoặc cụm từ ngắn.',
                  '可以输入一个单词或短语。',
                ),
                maxLines: 1,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    color: AppColors.indigo,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: '${context.tr('Ví dụ:', '示例：')}\n',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          TextSpan(
                            text: context.tr(
                              '• Nhập “apple” để thêm trực tiếp.\n'
                                  '• Nhập “quả táo” để gợi ý từ tiếng Anh tương ứng.',
                              '• 输入 “apple” 可直接添加。\n'
                                  '• 输入越南文可匹配对应英文。',
                            ),
                          ),
                        ],
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.indigoDark,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.tr('Hủy', '取消')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('confirm-add-vocabulary'),
                    onPressed: enabled
                        ? () => Navigator.of(context).pop(_controller.text)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(context.tr('Thêm', '添加')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(104, 46),
                      backgroundColor: AppColors.indigo,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _refresh() => setState(() {});
}
