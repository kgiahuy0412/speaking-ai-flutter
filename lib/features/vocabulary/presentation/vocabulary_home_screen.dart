import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/device/active_learning_module.dart';
import '../../../l10n/display_language.dart';
import '../data/vocabulary_store.dart';
import '../domain/vocabulary_entry.dart';

const _familyAsset = 'assets/images/topics/my-family.jpg';
const _starAsset = 'assets/images/vocabulary/golden-star.png';
const _reviewAsset = 'assets/images/vocabulary/review-book.png';
const _avatarAsset = 'assets/images/mascot/penguin-avatar.png';
const _waveAsset = 'assets/images/mascot/penguin-wave.png';

class VocabularyHomeScreen extends StatefulWidget {
  const VocabularyHomeScreen({
    required this.isReady,
    required this.onReturnToConversation,
    required this.onHistory,
    required this.onSettings,
    this.isActive = true,
    this.store = const VocabularyStore(),
    this.voicePromptService,
    this.translator,
    super.key,
  });

  final bool isReady;
  final VoidCallback onReturnToConversation;
  final VoidCallback onHistory;
  final VoidCallback onSettings;
  final bool isActive;
  final VocabularyStore store;
  final VoicePromptService? voicePromptService;
  final VocabularyTranslator? translator;

  @override
  State<VocabularyHomeScreen> createState() => _VocabularyHomeScreenState();
}

class _VocabularyHomeScreenState extends State<VocabularyHomeScreen>
    implements ActiveLearningModuleController {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  StreamSubscription<void>? _storeSubscription;
  late final VoicePromptService _voicePromptService;
  late final bool _ownsVoicePromptService;
  List<VocabularyEntry> _entries = const <VocabularyEntry>[];
  _VocabularyJourney? _selectedJourney;
  bool _loading = true;
  bool _deleteMode = false;
  bool _translating = false;
  bool _pausedForMainAssistant = false;
  ActiveLearningModuleRegistry? _activeLearningRegistry;
  Object? _activeLearningRegistration;

  @override
  void initState() {
    super.initState();
    _ownsVoicePromptService = widget.voicePromptService == null;
    _voicePromptService =
        widget.voicePromptService ?? createVoicePromptService();
    _searchController.addListener(_refreshSearch);
    _storeSubscription = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = ActiveLearningModuleScope.maybeOf(context);
    if (!identical(registry, _activeLearningRegistry)) {
      _unregisterActiveLearningModule();
      _activeLearningRegistry = registry;
    }
    _syncActiveLearningRegistration();
  }

  @override
  void didUpdateWidget(VocabularyHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncActiveLearningRegistration();
    }
  }

  @override
  void dispose() {
    _unregisterActiveLearningModule();
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    _searchFocusNode.dispose();
    _storeSubscription?.cancel();
    if (_ownsVoicePromptService) {
      unawaited(_voicePromptService.dispose());
    }
    super.dispose();
  }

  void _syncActiveLearningRegistration() {
    final registry = _activeLearningRegistry;
    if (!widget.isActive || registry == null) {
      _unregisterActiveLearningModule();
      return;
    }
    _activeLearningRegistration ??= registry.register(this);
  }

  void _unregisterActiveLearningModule() {
    final registration = _activeLearningRegistration;
    if (registration == null) {
      return;
    }
    _activeLearningRegistry?.unregister(registration);
    _activeLearningRegistration = null;
  }

  @override
  ActiveLearningModuleKind get moduleKind =>
      ActiveLearningModuleKind.vocabulary;

  @override
  bool get isPausedForMain => _pausedForMainAssistant;

  @override
  Future<void> pauseForMainAssistant() async {
    _pausedForMainAssistant = true;
    await _voicePromptService.stop();
  }

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    if (!mounted || !widget.isActive) {
      return const ActiveLearningCommandResult.unavailable();
    }
    switch (command) {
      case ActiveLearningCommand.stop:
        await pauseForMainAssistant();
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.resume:
        _pausedForMainAssistant = false;
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.vocabularyPracticeAgain:
        _pausedForMainAssistant = false;
        _openJourney(_VocabularyJourney.review);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.vocabularyStars:
        _pausedForMainAssistant = false;
        _openJourney(_VocabularyJourney.stars);
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.exitToHome:
        _pausedForMainAssistant = false;
        widget.onReturnToConversation();
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.replayCurrent:
      case ActiveLearningCommand.nextItem:
      case ActiveLearningCommand.previousItem:
      case ActiveLearningCommand.nextLesson:
      case ActiveLearningCommand.previousLesson:
      case ActiveLearningCommand.restart:
        return const ActiveLearningCommandResult.unavailable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LearningScenery(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              _VocabularyHeader(
                isReady: widget.isReady,
                onBrandPressed: widget.onReturnToConversation,
                onSearchPressed: _openSearch,
                onAddPressed: _translating ? null : _showAddDialog,
                adding: _translating,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _selectedJourney == null
                      ? _buildJourneyLanding(context)
                      : _buildJourneyDetail(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJourneyLanding(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFF102653);
    final savedCount = _entriesForJourney(_VocabularyJourney.family).length;
    final starCount = _entriesForJourney(_VocabularyJourney.stars).length;
    final reviewCount = _entriesForJourney(_VocabularyJourney.review).length;

    return Center(
      key: const ValueKey<String>('vocabulary-journey-landing'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          key: const Key('vocabulary-home-scroll'),
          padding: const EdgeInsets.fromLTRB(40, 36, 40, 104),
          child: Column(
            children: <Widget>[
              Text(
                context.tr('Từ vựng của con', '孩子的词汇'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: titleColor,
                  fontSize: 31,
                  letterSpacing: -0.9,
                  shadows: const <Shadow>[
                    Shadow(color: Colors.white, blurRadius: 9),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                context.tr('Chọn hành trình của con', '选择你的学习旅程'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.muted,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 30),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: _JourneyCard(
                    key: const Key('vocabulary-family-card'),
                    height: 156,
                    backgroundColor: const Color(0xFFFFF0E8),
                    borderColor: const Color(0xFFF6CDBE),
                    accentColor: const Color(0xFFFF664B),
                    onPressed: () => _openJourney(_VocabularyJourney.family),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          flex: 6,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Image.asset(
                                _familyAsset,
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: _JourneyCopy(
                            title: context.tr('Gia đình', '家庭'),
                            count: context.tr(
                              '$savedCount từ',
                              '$savedCount 个词',
                            ),
                            countColor: const Color(0xFFF4573F),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                height: 158,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: -18,
                      bottom: 0,
                      width: 112,
                      height: 142,
                      child: IgnorePointer(
                        child: Image.asset(
                          _waveAsset,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 71,
                      right: -14,
                      top: 0,
                      child: _JourneyCard(
                        key: const Key('vocabulary-stars-card'),
                        height: 148,
                        backgroundColor: const Color(0xFFFFF8DD),
                        borderColor: const Color(0xFFF5DEA2),
                        accentColor: const Color(0xFFFFB719),
                        onPressed: () => _openJourney(_VocabularyJourney.stars),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              flex: 5,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  8,
                                  14,
                                  0,
                                  10,
                                ),
                                child: Image.asset(
                                  _starAsset,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 6,
                              child: _JourneyCopy(
                                title: context.tr('Ngôi sao', '小星星'),
                                count: context.tr(
                                  '$starCount từ yêu thích',
                                  '$starCount 个收藏词',
                                ),
                                countColor: const Color(0xFFFFAC13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: _JourneyCard(
                    key: const Key('vocabulary-review-card'),
                    height: 148,
                    backgroundColor: const Color(0xFFF5F0FF),
                    borderColor: const Color(0xFFD7C7F3),
                    accentColor: const Color(0xFF8354DF),
                    onPressed: () => _openJourney(_VocabularyJourney.review),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          flex: 6,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 2, 8),
                            child: Image.asset(
                              _reviewAsset,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: _JourneyCopy(
                            title: context.tr('Luyện lại', '复习'),
                            count: context.tr(
                              '$reviewCount từ cần ôn',
                              '$reviewCount 个待复习词',
                            ),
                            countColor: const Color(0xFF8354DF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJourneyDetail(BuildContext context) {
    final journey = _selectedJourney!;
    final visibleEntries = _filteredEntries;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      key: ValueKey<_VocabularyJourney>(journey),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(52, 24, 52, 110),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton.filledTonal(
                    key: const Key('vocabulary-back-to-journeys'),
                    onPressed: _closeJourney,
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: context.tr('Quay lại', '返回'),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.9),
                      foregroundColor: AppColors.indigoDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _journeyTitle(context, journey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: isDark
                                ? Theme.of(context).colorScheme.primary
                                : AppColors.indigoDark,
                            fontSize: 27,
                          ),
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const Key('toggle-delete-vocabulary'),
                    onPressed: visibleEntries.isEmpty
                        ? null
                        : () => setState(() => _deleteMode = !_deleteMode),
                    icon: Icon(
                      _deleteMode
                          ? Icons.close_rounded
                          : Icons.delete_outline_rounded,
                    ),
                    tooltip: _deleteMode
                        ? context.tr('Đóng chế độ xóa', '退出删除模式')
                        : context.tr('Xóa từ vựng', '删除词汇'),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.9),
                      foregroundColor: _deleteMode
                          ? AppColors.coral
                          : AppColors.indigo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSearchField(context),
              const SizedBox(height: 22),
              Text(
                context.tr(
                  '${visibleEntries.length} từ đã lưu',
                  '已保存 ${visibleEntries.length} 个词',
                ),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isDark
                      ? Theme.of(context).colorScheme.primary
                      : AppColors.indigoDark,
                  fontWeight: FontWeight.w800,
                  shadows: const <Shadow>[
                    Shadow(color: Colors.white, blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildVocabularyCard(context, visibleEntries),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
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

  void _openJourney(_VocabularyJourney journey, {bool focusSearch = false}) {
    setState(() {
      _selectedJourney = journey;
      _deleteMode = false;
      _searchController.clear();
    });
    if (focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    }
  }

  void _openSearch() {
    if (_selectedJourney == null) {
      _openJourney(_VocabularyJourney.family, focusSearch: true);
      return;
    }
    _searchFocusNode.requestFocus();
  }

  void _closeJourney() {
    _searchFocusNode.unfocus();
    setState(() {
      _selectedJourney = null;
      _deleteMode = false;
      _searchController.clear();
    });
  }

  String _journeyTitle(BuildContext context, _VocabularyJourney journey) {
    return switch (journey) {
      _VocabularyJourney.family => context.tr('Gia đình', '家庭'),
      _VocabularyJourney.stars => context.tr('Ngôi sao của con', '我的星星'),
      _VocabularyJourney.review => context.tr('Luyện lại', '复习'),
    };
  }

  List<VocabularyEntry> get _filteredEntries {
    final journey = _selectedJourney ?? _VocabularyJourney.family;
    final journeyEntries = _entriesForJourney(journey);
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return journeyEntries;
    }
    return journeyEntries
        .where((entry) {
          return entry.word.toLowerCase().contains(query) ||
              entry.meaning.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  List<VocabularyEntry> _entriesForJourney(_VocabularyJourney journey) {
    final collection = switch (journey) {
      _VocabularyJourney.family => VocabularyCollection.saved,
      _VocabularyJourney.stars => VocabularyCollection.star,
      _VocabularyJourney.review => VocabularyCollection.review,
    };
    return _entries
        .where((entry) => entry.collection == collection)
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
        _selectedJourney = _VocabularyJourney.family;
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

enum _VocabularyJourney { family, stars, review }

class _VocabularyHeader extends StatelessWidget {
  const _VocabularyHeader({
    required this.isReady,
    required this.onBrandPressed,
    required this.onSearchPressed,
    required this.onAddPressed,
    required this.adding,
  });

  final bool isReady;
  final VoidCallback onBrandPressed;
  final VoidCallback onSearchPressed;
  final VoidCallback? onAddPressed;
  final bool adding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFF102653);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 26, 18, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  key: const Key('vocabulary-practice-button'),
                  onTap: onBrandPressed,
                  borderRadius: BorderRadius.circular(36),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 64,
                          height: 64,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.95),
                              width: 2.5,
                            ),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x24142451),
                                blurRadius: 15,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Transform.scale(
                            scale: 1.14,
                            child: Image.asset(
                              _avatarAsset,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'INNOTRIK',
                                  maxLines: 1,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: foreground,
                                        fontSize: 23,
                                        letterSpacing: -0.35,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: isReady
                                          ? AppColors.success
                                          : AppColors.muted,
                                      shape: BoxShape.circle,
                                      boxShadow: isReady
                                          ? const <BoxShadow>[
                                              BoxShadow(
                                                color: Color(0x3323A05A),
                                                blurRadius: 5,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      isReady
                                          ? context.tr('Sẵn sàng', '已就绪')
                                          : context.tr('Chưa kết nối', '未连接'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: isReady
                                                ? AppColors.success
                                                : AppColors.muted,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
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
              ),
              const SizedBox(width: 7),
              _VocabularyHeaderButton(
                key: const Key('search-vocabulary-button'),
                icon: Icons.search_rounded,
                tooltip: context.tr('Tìm từ vựng', '搜索词汇'),
                onPressed: onSearchPressed,
              ),
              const SizedBox(width: 8),
              _VocabularyHeaderButton(
                key: const Key('add-vocabulary-button'),
                icon: Icons.add_rounded,
                tooltip: context.tr('Thêm từ vựng', '添加词汇'),
                onPressed: onAddPressed,
                loading: adding,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VocabularyHeaderButton extends StatelessWidget {
  const _VocabularyHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.loading = false,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : Icon(icon, size: 30),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(48),
        maximumSize: const Size.square(48),
        backgroundColor: isDark
            ? Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.94)
            : Colors.white.withValues(alpha: 0.9),
        foregroundColor: isDark
            ? Theme.of(context).colorScheme.primary
            : const Color(0xFF153B9A),
        side: BorderSide(
          color: isDark
              ? Theme.of(context).colorScheme.outline
              : const Color(0xFFD4E5ED),
          width: 1.4,
        ),
        elevation: 2,
        shadowColor: const Color(0x24142451),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.height,
    required this.backgroundColor,
    required this.borderColor,
    required this.accentColor,
    required this.onPressed,
    required this.child,
    super.key,
  });

  final double height;
  final Color backgroundColor;
  final Color borderColor;
  final Color accentColor;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(34),
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            color: backgroundColor.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x21142451),
                blurRadius: 18,
                offset: Offset(0, 9),
              ),
              BoxShadow(
                color: Color(0xA6FFFFFF),
                blurRadius: 1,
                spreadRadius: 1,
                offset: Offset(0, -1),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Padding(padding: const EdgeInsets.only(right: 8), child: child),
              Positioned(
                right: 11,
                bottom: 11,
                child: Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JourneyCopy extends StatelessWidget {
  const _JourneyCopy({
    required this.title,
    required this.count,
    required this.countColor,
  });

  final String title;
  final String count;
  final Color countColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 12, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 1,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF102653),
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            count,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: countColor,
              fontSize: 16,
              height: 1.16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
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
