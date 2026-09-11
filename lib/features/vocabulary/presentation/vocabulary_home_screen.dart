import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../core/audio/learning_audio_dependencies.dart';
import '../../../core/audio/voice_prompt_service.dart';
import '../../../core/device/active_learning_module.dart';
import '../../../core/navigation/active_learning_navigation.dart';
import '../../../l10n/display_language.dart';
import '../../listening/application/lesson_media_service.dart';
import '../data/vocabulary_session_store.dart';
import '../data/vocabulary_store.dart';
import '../domain/vocabulary_entry.dart';
import '../domain/vocabulary_flow_v3.dart';
import 'vocabulary_practice_screen.dart';

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
    this.sessionStore = const VocabularySessionStore(),
    this.voicePromptService,
    this.mediaService,
    this.audioDependencies,
    this.translator,
    this.suggestionProvider,
    this.childAge = 5,
    this.autoStartToday = false,
    this.onRequestVoiceChoice,
    super.key,
  });

  final bool isReady;
  final VoidCallback onReturnToConversation;
  final VoidCallback onHistory;
  final VoidCallback onSettings;
  final bool isActive;
  final VocabularyStore store;
  final VocabularySessionStore sessionStore;
  final VoicePromptService? voicePromptService;
  final LessonMediaService? mediaService;
  final LearningAudioDependencies? audioDependencies;
  final VocabularyTranslator? translator;
  final VocabularySuggestionProvider? suggestionProvider;
  final int childAge;
  final bool autoStartToday;
  final Future<void> Function({
    String? noSpeechRetryPrompt,
    String? noSpeechExitPrompt,
  })?
  onRequestVoiceChoice;

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
  late final LessonMediaService _mediaService;
  late final bool _ownsMediaService;
  List<VocabularyEntry> _entries = const <VocabularyEntry>[];
  _VocabularyJourney? _selectedJourney;
  bool _loading = true;
  bool _deleteMode = false;
  bool _translating = false;
  bool _pausedForMainAssistant = false;
  bool _openingPractice = false;
  bool _startingToday = false;
  bool _todayOffered = false;
  bool _playingCollection = false;
  bool _playbackInterrupted = false;
  List<VocabularyEntry> _playbackQueue = const <VocabularyEntry>[];
  int _playbackIndex = 0;
  String? _playbackBranch;
  int _nextPlaybackIndex = 0;
  VocabularyEntry? _lastPlayedEntry;
  _VocabularyJourney? _pendingPlaybackScopeJourney;
  bool _scopeSheetOpen = false;
  bool _waitingForPlaybackContinuation = false;
  bool _starVoiceIntroSpoken = false;
  int _starPlayedCount = 0;
  ActiveLearningModuleRegistry? _activeLearningRegistry;
  Object? _activeLearningRegistration;

  @override
  void initState() {
    super.initState();
    _ownsVoicePromptService = widget.voicePromptService == null;
    _voicePromptService =
        widget.voicePromptService ??
        createVoicePromptService(
          coordinator: widget.audioDependencies?.audioTurnCoordinator,
          owner: AudioTurnOwner.vocabulary,
        );
    _ownsMediaService = widget.mediaService == null;
    _mediaService =
        widget.mediaService ??
        LessonMediaService(
          hfpAudioControl: widget.audioDependencies
              ?.createLearningAudioRouteControl(),
          audioTurnCoordinator: widget.audioDependencies?.audioTurnCoordinator,
          audioTurnOwner: AudioTurnOwner.vocabulary,
        );
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
      if (widget.isActive && widget.autoStartToday) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_maybeStartToday());
        });
      }
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
    if (_ownsMediaService) {
      unawaited(_mediaService.dispose());
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
    _playbackInterrupted = _playingCollection;
    await Future.wait<void>(<Future<void>>[
      _voicePromptService.stop().catchError((Object _) {}),
      _mediaService.stopPlayback().catchError((Object _) {}),
    ]);
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
        if (_playbackInterrupted) {
          unawaited(_resumePlayback());
        } else if (_waitingForPlaybackContinuation) {
          unawaited(_continuePlayback());
        }
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.vocabularyParentAdded:
        _pausedForMainAssistant = false;
        _openJourney(_VocabularyJourney.family);
        unawaited(_playJourney(_VocabularyJourney.family));
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.vocabularyPracticeAgain:
        _pausedForMainAssistant = false;
        final replayEntry = _lastPlayedEntry;
        if (_selectedJourney == _VocabularyJourney.family &&
            replayEntry != null &&
            replayEntry.isParentAdded) {
          _playbackInterrupted = false;
          unawaited(_practiceEntryAgain(replayEntry));
        } else {
          unawaited(_startReview());
        }
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.vocabularyStars:
        _pausedForMainAssistant = false;
        _openJourney(_VocabularyJourney.stars);
        unawaited(_playJourney(_VocabularyJourney.stars));
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.vocabularyLatest:
      case ActiveLearningCommand.vocabularyAll:
        _pausedForMainAssistant = false;
        final scope = command == ActiveLearningCommand.vocabularyLatest
            ? _VocabularyPlaybackScope.latest
            : _VocabularyPlaybackScope.all;
        if (_scopeSheetOpen) {
          Navigator.of(context).pop(scope);
          return const ActiveLearningCommandResult.handled();
        }
        final pendingJourney = _pendingPlaybackScopeJourney;
        if (pendingJourney != null) {
          unawaited(_playJourney(pendingJourney, requestedScope: scope));
          return const ActiveLearningCommandResult.handled();
        }
        if (_selectedJourney == _VocabularyJourney.stars) {
          unawaited(_switchStarBranch(scope));
          return const ActiveLearningCommandResult.handled();
        }
        return const ActiveLearningCommandResult.unavailable();
      case ActiveLearningCommand.replayCurrent:
        if (_playbackQueue.isEmpty) {
          return const ActiveLearningCommandResult.unavailable();
        }
        _pausedForMainAssistant = false;
        _playbackInterrupted = true;
        unawaited(_resumePlayback());
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.exitToHome:
        _pausedForMainAssistant = false;
        unawaited(_leavePlaybackForOtherContent());
        return const ActiveLearningCommandResult.handled();
      case ActiveLearningCommand.nextItem:
        _pausedForMainAssistant = false;
        if (_waitingForPlaybackContinuation) {
          unawaited(_continuePlayback());
          return const ActiveLearningCommandResult.handled();
        }
        return const ActiveLearningCommandResult.unavailable();
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
        overlayOpacity: 0.025,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark
        ? Theme.of(context).colorScheme.primary
        : AppColors.deepNavy;
    final savedCount = _entriesForJourney(_VocabularyJourney.family).length;
    final starCount = _entriesForJourney(_VocabularyJourney.stars).length;
    final reviewCount = _entriesForJourney(_VocabularyJourney.review).length;

    return Center(
      key: const ValueKey<String>('vocabulary-journey-landing'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          key: const Key('vocabulary-home-scroll'),
          padding: const EdgeInsets.fromLTRB(36, 14, 36, 24),
          child: Column(
            children: <Widget>[
              Text(
                context.tr('Từ vựng của con', '孩子的词汇'),
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: titleColor,
                  fontSize: 31,
                  letterSpacing: -0.9,
                  shadows: isDark
                      ? const <Shadow>[
                          Shadow(color: Colors.black54, blurRadius: 12),
                        ]
                      : const <Shadow>[
                          Shadow(color: Colors.white, blurRadius: 9),
                        ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                context.tr('Chọn hành trình của con', '选择你的学习旅程'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isDark
                      ? theme.colorScheme.onSurfaceVariant
                      : AppColors.muted,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              _JourneyCard(
                key: const Key('vocabulary-family-card'),
                height: 138,
                onPressed: () => _openJourney(_VocabularyJourney.family),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(26),
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
                      flex: 6,
                      child: _JourneyCopy(
                        title: context.tr('Ba mẹ đã thêm', '家长添加'),
                        count: context.tr('$savedCount từ', '$savedCount 个词'),
                        countColor: AppColors.accentPink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 144,
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
                      left: 0,
                      right: 0,
                      top: 0,
                      child: _JourneyCard(
                        key: const Key('vocabulary-stars-card'),
                        height: 138,
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
                                countColor: AppColors.accentPink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _JourneyCard(
                key: const Key('vocabulary-review-card'),
                height: 138,
                onPressed: () => _openJourney(_VocabularyJourney.review),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                        child: Image.asset(
                          _reviewAsset,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 6,
                      child: _JourneyCopy(
                        title: context.tr('Luyện lại', '复习'),
                        count: context.tr(
                          '$reviewCount từ cần ôn',
                          '$reviewCount 个待复习词',
                        ),
                        countColor: AppColors.accentPink,
                      ),
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

  Widget _buildJourneyDetail(BuildContext context) {
    final journey = _selectedJourney!;
    final visibleEntries = _filteredEntries;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                      backgroundColor: isDark
                          ? theme.colorScheme.surfaceContainerHighest
                          : Colors.white.withValues(alpha: 0.9),
                      foregroundColor: isDark
                          ? theme.colorScheme.primary
                          : AppColors.indigoDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _journeyTitle(context, journey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: isDark
                            ? theme.colorScheme.primary
                            : AppColors.indigoDark,
                        fontSize: 27,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const Key('toggle-delete-vocabulary'),
                    onPressed:
                        journey != _VocabularyJourney.family ||
                            !visibleEntries.any((entry) => entry.canParentEdit)
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
                      backgroundColor: isDark
                          ? theme.colorScheme.surfaceContainerHighest
                          : Colors.white.withValues(alpha: 0.9),
                      foregroundColor: _deleteMode
                          ? (isDark
                                ? theme.colorScheme.secondary
                                : AppColors.coral)
                          : (isDark
                                ? theme.colorScheme.primary
                                : AppColors.indigo),
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
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isDark
                      ? theme.colorScheme.primary
                      : AppColors.indigoDark,
                  fontWeight: FontWeight.w800,
                  shadows: isDark
                      ? const <Shadow>[
                          Shadow(color: Colors.black54, blurRadius: 10),
                        ]
                      : const <Shadow>[
                          Shadow(color: Colors.white, blurRadius: 8),
                        ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: ValueKey<String>('vocabulary-${journey.name}-action'),
                onPressed: visibleEntries.isEmpty || _playingCollection
                    ? null
                    : () => unawaited(
                        journey == _VocabularyJourney.review
                            ? _startReview()
                            : _playJourney(journey),
                      ),
                icon: _playingCollection
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Icon(
                        journey == _VocabularyJourney.review
                            ? Icons.mic_rounded
                            : Icons.play_arrow_rounded,
                      ),
                label: Text(
                  journey == _VocabularyJourney.review
                      ? context.tr('Bắt đầu luyện', '开始练习')
                      : context.tr('Bắt đầu nghe', '开始播放'),
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
                    canDelete: entries[index].canParentEdit,
                    canEdit:
                        _selectedJourney == _VocabularyJourney.family &&
                        entries[index].canParentEdit,
                    canPlay:
                        !entries[index].isParentAdded ||
                        entries[index].isLearnedWell,
                    onPlay: () => unawaited(_playEntry(entries[index])),
                    onEdit: () => unawaited(_editParentEntry(entries[index])),
                    onDelete: () => unawaited(_delete(entries[index])),
                  ),
                  if (index != entries.length - 1)
                    Divider(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      height: 1,
                    ),
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
      _VocabularyJourney.family => context.tr('Ba mẹ đã thêm', '家长添加'),
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
    final entries = _entries
        .where(
          (entry) => switch (journey) {
            _VocabularyJourney.family => entry.isParentAdded,
            _VocabularyJourney.stars => entry.isStar,
            _VocabularyJourney.review => entry.needsPractice,
          },
        )
        .toList();
    if (journey == _VocabularyJourney.review) {
      final byTarget = <String, VocabularyEntry>{};
      for (final entry in entries) {
        final target = _normalizedVocabularyText(entry.word);
        final previous = byTarget[target];
        if (previous == null ||
            (entry.isParentAdded && !previous.isParentAdded)) {
          byTarget[target] = entry;
        }
      }
      entries
        ..clear()
        ..addAll(byTarget.values);
    }
    entries.sort((a, b) {
      if (journey == _VocabularyJourney.review) {
        return a.addedAt.compareTo(b.addedAt);
      }
      if (journey == _VocabularyJourney.stars) {
        return (b.earnedAt ?? b.addedAt).compareTo(a.earnedAt ?? a.addedAt);
      }
      return b.addedAt.compareTo(a.addedAt);
    });
    return entries;
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
    if (widget.isActive && widget.autoStartToday && !_todayOffered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_maybeStartToday());
      });
    }
  }

  Future<void> _delete(VocabularyEntry entry) async {
    try {
      await widget.store.deleteParentEntry(entry.id);
      await _load();
    } on VocabularyValidationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _editParentEntry(VocabularyEntry entry) async {
    final input = await showDialog<String>(
      context: context,
      builder: (_) =>
          _AddVocabularyDialog(initialValue: entry.word, editing: true),
    );
    final normalized = input?.trim();
    if (normalized == null || normalized.isEmpty) return;
    setState(() => _translating = true);
    try {
      final translated = await _translateVocabulary(normalized);
      await widget.store.updateParentEntry(
        entryId: entry.id,
        value: translated,
      );
      await _load();
    } on VocabularyValidationException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Chưa sửa được nội dung này. Ba mẹ thử lại nhé.');
    } finally {
      if (mounted) setState(() => _translating = false);
    }
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
      final usedToday = await widget.store.parentAddCountForDay(DateTime.now());
      final remaining = VocabularyStore.parentDailyLimit - usedToday;
      if (remaining <= 0) {
        throw const VocabularyDailyLimitException(remaining: 0);
      }
      final translated = await _translateVocabulary(normalized);
      final selections = await _prepareParentChoices(
        input: normalized,
        translated: translated,
        maxSelections: remaining.clamp(1, 3),
      );
      if (selections == null || selections.isEmpty) return;
      final entries = await widget.store.addParentEntries(selections);
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
        _selectedJourney = _VocabularyJourney.family;
        _deleteMode = false;
        _searchController.clear();
      });
    } on VocabularyValidationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
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

  Future<void> _maybeStartToday() async {
    if (!mounted ||
        !widget.isActive ||
        _openingPractice ||
        _startingToday ||
        _pausedForMainAssistant) {
      return;
    }
    _startingToday = true;
    try {
      final firstEntryToday = await widget.sessionStore
          .markAndCheckFirstEntryToday(DateTime.now());
      final activeBeforeEntry = await widget.sessionStore.readActive();
      final session = await widget.sessionStore.prepareToday(widget.store);
      _todayOffered = true;
      if (session == null) {
        if (mounted && widget.isActive) {
          await _speakAndRequestChoice(
            firstEntryToday
                ? VocabularyFlowV3.todayEmptyMenu
                : VocabularyFlowV3.menu,
          );
        }
        return;
      }
      if (!mounted || !widget.isActive) return;
      await _runPracticeSession(
        session,
        announceInitialIntro: activeBeforeEntry?.id != session.id,
      );
    } finally {
      _startingToday = false;
    }
  }

  Future<void> _startReview() async {
    if (_openingPractice || !mounted) return;
    _openJourney(_VocabularyJourney.review);
    final active = await widget.sessionStore.readActive();
    if (active?.mode == VocabularyPracticeMode.today) {
      await _speakOnSelectedOutput(VocabularyFlowV3.finishActiveGroupFirst);
      await _runPracticeSession(active!, announceInitialIntro: false);
      return;
    }
    final session = active?.mode == VocabularyPracticeMode.review
        ? active
        : await widget.sessionStore.prepareReview(widget.store);
    if (session == null || !mounted) {
      await _speakAndRequestChoice(VocabularyFlowV3.reviewEmpty);
      return;
    }
    await _runPracticeSession(
      session,
      announceInitialIntro: active?.id != session.id,
    );
  }

  Future<void> _runPracticeSession(
    VocabularyPracticeSession first, {
    bool announceInitialIntro = true,
  }) async {
    if (_openingPractice || !mounted) return;
    _openingPractice = true;
    var session = first;
    var announceIntro = announceInitialIntro;
    final reviewedThisCycle = <String>{};
    try {
      while (true) {
        if (!mounted) return;
        final language = DisplayLanguageScope.of(context);
        final result = await pushForActiveLearning<VocabularyPracticeResult>(
          context,
          (_) => VocabularyPracticeScreen(
            language: language,
            childAge: widget.childAge,
            session: session,
            store: widget.store,
            sessionStore: widget.sessionStore,
            mediaService: _mediaService,
            audioDependencies: widget.audioDependencies,
            voicePromptService: _voicePromptService,
            onRequestVoiceChoice: widget.onRequestVoiceChoice,
            announceIntro: announceIntro,
          ),
        );
        if (!mounted) return;
        await _load();
        if (result != VocabularyPracticeResult.continueLearning) {
          final active = await widget.sessionStore.readActive();
          if (session.mode == VocabularyPracticeMode.today && active == null) {
            await widget.sessionStore.suppressToday(DateTime.now());
            await _speakAndRequestChoice(VocabularyFlowV3.menu);
          } else if (session.mode == VocabularyPracticeMode.review &&
              active == null) {
            await _speakAndRequestChoice(VocabularyFlowV3.reviewOtherMenu);
          }
          return;
        }
        if (session.mode == VocabularyPracticeMode.review) {
          reviewedThisCycle.addAll(session.entryIds);
        }
        final next = switch (session.mode) {
          VocabularyPracticeMode.today =>
            await widget.sessionStore.prepareToday(
              widget.store,
              forceNextGroup: true,
            ),
          VocabularyPracticeMode.review =>
            await widget.sessionStore.prepareReview(
              widget.store,
              forceNextGroup: true,
              excludeEntryIds: reviewedThisCycle,
            ),
          VocabularyPracticeMode.speakAgain => null,
        };
        if (next == null) {
          final prompt = session.mode == VocabularyPracticeMode.today
              ? VocabularyFlowV3.todayQueueEmpty
              : VocabularyFlowV3.reviewCycleFinished;
          await _speakAndRequestChoice(prompt);
          return;
        }
        session = next;
        announceIntro = false;
      }
    } finally {
      _openingPractice = false;
    }
  }

  Future<void> _playJourney(
    _VocabularyJourney journey, {
    _VocabularyPlaybackScope? requestedScope,
    bool directBranchSwitch = false,
  }) async {
    if (_playingCollection || !mounted) return;
    if (await _resumeBlockingPracticeIfNeeded()) return;

    _openJourney(journey);
    var entries = _entriesForJourney(journey);
    if (journey == _VocabularyJourney.family) {
      entries = entries.where((entry) => entry.isLearnedWell).toList();
    }
    if (entries.isEmpty) {
      await _speakAndRequestChoice(
        journey == _VocabularyJourney.family
            ? VocabularyFlowV3.parentEmpty
            : VocabularyFlowV3.starEmpty,
      );
      return;
    }

    var scope = requestedScope;
    if (entries.length > VocabularyFlowV3.groupSize && scope == null) {
      _pendingPlaybackScopeJourney = journey;
      final prompt = journey == _VocabularyJourney.family
          ? VocabularyFlowV3.parentScopeChoice
          : VocabularyFlowV3.starScopeChoice(entries.length);
      await _speakOnSelectedOutput(prompt);
      if (!mounted) return;
      _scopeSheetOpen = true;
      unawaited(
        _requestVoiceChoice(
          noSpeechRetryPrompt: journey == _VocabularyJourney.stars
              ? VocabularyFlowV3.starScopeRetry
              : null,
          noSpeechExitPrompt: journey == _VocabularyJourney.stars
              ? VocabularyFlowV3.stopHere
              : null,
        ),
      );
      scope = await showModalBottomSheet<_VocabularyPlaybackScope>(
        context: context,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(prompt, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 18),
                ListTile(
                  leading: const Icon(Icons.fiber_new_rounded),
                  title: Text(
                    journey == _VocabularyJourney.family
                        ? 'Nội dung mới nhất'
                        : 'Ngôi sao mới nhất',
                  ),
                  onTap: () =>
                      Navigator.pop(context, _VocabularyPlaybackScope.latest),
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_play_rounded),
                  title: const Text('Nghe lại tất cả'),
                  onTap: () =>
                      Navigator.pop(context, _VocabularyPlaybackScope.all),
                ),
              ],
            ),
          ),
        ),
      );
      _scopeSheetOpen = false;
      _pendingPlaybackScopeJourney = null;
      if (scope == null || !mounted) return;
    }

    scope ??= _VocabularyPlaybackScope.all;
    final flowScope = scope == _VocabularyPlaybackScope.latest
        ? VocabularyPlaybackScope.latest
        : VocabularyPlaybackScope.all;
    final flowJourney = journey == _VocabularyJourney.family
        ? VocabularyJourneyKind.parentAdded
        : VocabularyJourneyKind.stars;
    final queue = VocabularyFlowV3.orderedForPlayback(
      entries,
      journey: flowJourney,
      scope: flowScope,
    );
    final playAll = scope == _VocabularyPlaybackScope.all;
    final branch = '${journey.name}:${playAll ? 'all' : 'latest'}';
    var start = 0;
    if (playAll) {
      start = await widget.sessionStore.readPlaybackCheckpoint(branch);
      if (start >= queue.length) start = 0;
    }

    if (directBranchSwitch) {
      await _speakOnSelectedOutput(
        scope == _VocabularyPlaybackScope.latest
            ? VocabularyFlowV3.switchToLatestStars
            : VocabularyFlowV3.switchToAllStars,
      );
    } else if (entries.length <= VocabularyFlowV3.groupSize) {
      await _speakOnSelectedOutput(
        journey == _VocabularyJourney.family
            ? VocabularyFlowV3.parentSmallIntro
            : VocabularyFlowV3.starSmallIntro(entries.length),
      );
    } else if (journey == _VocabularyJourney.stars && start > 0) {
      await _speakOnSelectedOutput(VocabularyFlowV3.resumeStars);
    } else {
      await _speakOnSelectedOutput(VocabularyFlowV3.startPlayback);
    }
    if (journey == _VocabularyJourney.family &&
        await widget.sessionStore.recordParentPlaybackEntry()) {
      await _speakOnSelectedOutput(VocabularyFlowV3.parentSpeakAgainGuide);
    }

    _waitingForPlaybackContinuation = false;
    _starVoiceIntroSpoken = false;
    _starPlayedCount = 0;
    _lastPlayedEntry = null;
    await _playQueue(
      queue,
      startIndex: start,
      branch: branch,
      checkpoint: playAll,
      journey: journey,
    );
  }

  Future<void> _playEntry(VocabularyEntry entry) async {
    if (entry.isLearnedWell || entry.isStar) {
      await _playQueue(
        <VocabularyEntry>[entry],
        branch: 'single:${entry.id}',
        checkpoint: false,
        journey: entry.isStar
            ? _VocabularyJourney.stars
            : _VocabularyJourney.family,
      );
      return;
    }
    _showMessage('Nội dung này cần được học xong trước khi nghe lại.');
  }

  Future<void> _playQueue(
    List<VocabularyEntry> entries, {
    required String branch,
    required bool checkpoint,
    required _VocabularyJourney journey,
    int startIndex = 0,
  }) async {
    if (_playingCollection || entries.isEmpty) return;
    _playbackQueue = entries;
    _playbackIndex = startIndex;
    _playbackBranch = branch;
    _nextPlaybackIndex = startIndex;
    _playbackInterrupted = false;
    _waitingForPlaybackContinuation = false;
    if (mounted) setState(() => _playingCollection = true);
    try {
      var playedInGroup = 0;
      for (var index = startIndex; index < entries.length; index++) {
        _playbackIndex = index;
        if (_pausedForMainAssistant) {
          _playbackInterrupted = true;
          return;
        }
        final played = await _speakVocabularyEntry(
          entries[index],
          journey: journey,
        );
        if (_pausedForMainAssistant) {
          _playbackInterrupted = true;
          return;
        }
        if (checkpoint) {
          await widget.sessionStore.savePlaybackCheckpoint(branch, index + 1);
        }
        _nextPlaybackIndex = index + 1;
        if (!played) continue;
        _lastPlayedEntry = entries[index];
        playedInGroup += 1;
        if (playedInGroup >= VocabularyFlowV3.groupSize &&
            branch.endsWith(':latest')) {
          _waitingForPlaybackContinuation = false;
          await _speakAndRequestChoice(
            journey == _VocabularyJourney.stars
                ? VocabularyFlowV3.starFinished
                : VocabularyFlowV3.parentFinished,
          );
          return;
        }
        if (playedInGroup >= VocabularyFlowV3.groupSize &&
            index + 1 < entries.length) {
          _waitingForPlaybackContinuation = true;
          await _speakAndRequestChoice(
            journey == _VocabularyJourney.stars
                ? VocabularyFlowV3.starGroupCompletion
                : VocabularyFlowV3.parentGroupCompletion,
          );
          return;
        }
      }
      if (checkpoint) {
        await widget.sessionStore.clearPlaybackCheckpoint(branch);
      }
      _playbackInterrupted = false;
      _waitingForPlaybackContinuation = false;
      if (!branch.startsWith('single:')) {
        await _speakAndRequestChoice(
          journey == _VocabularyJourney.stars
              ? VocabularyFlowV3.starFinished
              : VocabularyFlowV3.parentFinished,
        );
      }
    } catch (error) {
      if (_pausedForMainAssistant) {
        _playbackInterrupted = true;
      } else {
        _showMessage(_friendlyPlaybackError(error));
      }
    } finally {
      if (mounted) setState(() => _playingCollection = false);
    }
  }

  Future<bool> _speakVocabularyEntry(
    VocabularyEntry entry, {
    required _VocabularyJourney journey,
    bool replay = false,
  }) async {
    final path = entry.correctAudioPath?.trim();
    if (journey == _VocabularyJourney.stars && (path == null || path.isEmpty)) {
      debugPrint('VOCABULARY_STAR_AUDIO_MISSING slot=${entry.starSlotId}');
      return false;
    }
    await _mediaService.prepareSelectedLessonOutput();
    if (journey == _VocabularyJourney.stars &&
        !replay &&
        _starPlayedCount > 0) {
      final cue =
          VocabularyFlowV3.starNextCues[(_starPlayedCount - 1) %
              VocabularyFlowV3.starNextCues.length];
      await _speakOnSelectedOutput(cue);
    }
    await _speakOnSelectedOutput(entry.word, locale: 'en-US');
    if (_pausedForMainAssistant) return false;
    await _speakOnSelectedOutput(entry.meaning, locale: 'vi-VN');
    if (_pausedForMainAssistant) return false;
    if (journey == _VocabularyJourney.stars &&
        !replay &&
        !_starVoiceIntroSpoken) {
      _starVoiceIntroSpoken = true;
      await _speakOnSelectedOutput(VocabularyFlowV3.starVoiceIntro);
    }
    if (path == null || path.isEmpty) return true;
    final uri = path.startsWith('http://') || path.startsWith('https://')
        ? Uri.parse(path)
        : Uri.file(path);
    try {
      await _mediaService.playToCompletion(uri);
    } catch (error) {
      if (journey == _VocabularyJourney.stars) {
        debugPrint(
          'VOCABULARY_STAR_AUDIO_FAILED slot=${entry.starSlotId} error=$error',
        );
        return false;
      }
      rethrow;
    }
    if (journey == _VocabularyJourney.stars && !replay) {
      _starPlayedCount += 1;
    }
    return true;
  }

  Future<void> _resumePlayback() async {
    for (var attempt = 0; attempt < 20 && _playingCollection; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (!_playbackInterrupted || _playbackQueue.isEmpty || _playingCollection) {
      return;
    }
    final queue = _playbackQueue;
    final branch = _playbackBranch ?? 'resume';
    _playbackInterrupted = false;
    await _playQueue(
      queue,
      startIndex: _playbackIndex,
      branch: branch,
      checkpoint: branch.endsWith(':all'),
      journey: branch.startsWith('stars:')
          ? _VocabularyJourney.stars
          : _VocabularyJourney.family,
    );
  }

  Future<void> _continuePlayback() async {
    if (_playingCollection || _playbackQueue.isEmpty) return;
    final branch = _playbackBranch ?? '';
    final start = _nextPlaybackIndex.clamp(0, _playbackQueue.length);
    if (start >= _playbackQueue.length) return;
    _waitingForPlaybackContinuation = false;
    await _playQueue(
      _playbackQueue,
      startIndex: start,
      branch: branch,
      checkpoint: branch.endsWith(':all'),
      journey: branch.startsWith('stars:')
          ? _VocabularyJourney.stars
          : _VocabularyJourney.family,
    );
  }

  Future<bool> _resumeBlockingPracticeIfNeeded() async {
    final active = await widget.sessionStore.readActive();
    if (active == null) return false;
    if (active.mode == VocabularyPracticeMode.today) {
      await _speakOnSelectedOutput(VocabularyFlowV3.finishActiveGroupFirst);
    }
    await _runPracticeSession(active, announceInitialIntro: false);
    return true;
  }

  Future<void> _practiceEntryAgain(VocabularyEntry entry) async {
    if (_openingPractice || !mounted) return;
    await Future.wait<void>(<Future<void>>[
      _voicePromptService.stop().catchError((Object _) {}),
      _mediaService.stopPlayback().catchError((Object _) {}),
    ]);
    final session = await widget.sessionStore.prepareSpeakAgain(entry);
    if (!mounted) return;
    final language = DisplayLanguageScope.of(context);
    await pushForActiveLearning<VocabularyPracticeResult>(
      context,
      (_) => VocabularyPracticeScreen(
        language: language,
        childAge: widget.childAge,
        session: session,
        store: widget.store,
        sessionStore: widget.sessionStore,
        mediaService: _mediaService,
        audioDependencies: widget.audioDependencies,
        voicePromptService: _voicePromptService,
        onRequestVoiceChoice: widget.onRequestVoiceChoice,
      ),
    );
    if (!mounted) return;
    await _load();
    final queueIndex = _playbackQueue.indexWhere(
      (candidate) => candidate.id == entry.id,
    );
    if (queueIndex >= 0) {
      _nextPlaybackIndex = queueIndex + 1;
      await _continuePlayback();
    }
  }

  Future<void> _leavePlaybackForOtherContent() async {
    final journey = _selectedJourney;
    _playbackInterrupted = false;
    _waitingForPlaybackContinuation = false;
    _pendingPlaybackScopeJourney = null;
    await Future.wait<void>(<Future<void>>[
      _voicePromptService.stop().catchError((Object _) {}),
      _mediaService.stopPlayback().catchError((Object _) {}),
    ]);
    if (!mounted) return;
    _closeJourney();
    await _speakAndRequestChoice(
      journey == _VocabularyJourney.family
          ? VocabularyFlowV3.parentOtherMenu
          : journey == _VocabularyJourney.stars
          ? VocabularyFlowV3.starOtherMenu
          : VocabularyFlowV3.menu,
    );
  }

  Future<void> _speakAndRequestChoice(String prompt) async {
    await _speakOnSelectedOutput(prompt);
    if (!mounted) return;
    if (_playingCollection) setState(() => _playingCollection = false);
    await _requestVoiceChoice();
  }

  Future<void> _requestVoiceChoice({
    String? noSpeechRetryPrompt,
    String? noSpeechExitPrompt,
  }) async {
    if (!mounted || !widget.isActive || widget.onRequestVoiceChoice == null) {
      return;
    }
    await widget.onRequestVoiceChoice!.call(
      noSpeechRetryPrompt: noSpeechRetryPrompt,
      noSpeechExitPrompt: noSpeechExitPrompt,
    );
  }

  Future<List<VocabularyTranslation>?> _prepareParentChoices({
    required String input,
    required VocabularyTranslation translated,
    required int maxSelections,
  }) async {
    VocabularyValidationException? originalError;
    var originalAccepted = true;
    try {
      await widget.store.validateParentCandidate(translated);
    } on VocabularyDuplicateException {
      rethrow;
    } on VocabularyTopicDuplicateException {
      rethrow;
    } on VocabularyValidationException catch (error) {
      originalAccepted = false;
      originalError = error;
    }

    final candidates = <VocabularyTranslation>[
      if (originalAccepted) translated,
      ..._approvedSuggestionsFor(translated),
    ];
    final targetOptionCount = originalAccepted ? 4 : 3;
    var options = await widget.store.filterParentSuggestions(
      candidates,
      limit: targetOptionCount,
    );
    final provider = widget.suggestionProvider;
    if (provider != null && options.length < targetOptionCount) {
      try {
        final aiSuggestions = await provider(input, widget.childAge);
        options = await widget.store.filterParentSuggestions(
          <VocabularyTranslation>[...options, ...aiSuggestions],
          limit: targetOptionCount,
        );
      } catch (error) {
        debugPrint('VOCABULARY_SUGGESTION_FALLBACK_FAILED error=$error');
      }
    }
    if (options.isEmpty) {
      if (originalError != null) throw originalError;
      throw const VocabularyValidationException(
        'Chưa có phương án phù hợp. Ba mẹ thử nội dung khác nhé.',
      );
    }
    if (!mounted) return null;
    return showDialog<List<VocabularyTranslation>>(
      context: context,
      builder: (_) => _VocabularySuggestionDialog(
        options: options,
        maxSelections: maxSelections,
      ),
    );
  }

  List<VocabularyTranslation> _approvedSuggestionsFor(
    VocabularyTranslation translated,
  ) {
    const catalog = <String, List<VocabularyTranslation>>{
      'apple': <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'Red apple',
          vietnameseText: 'Quả táo đỏ',
        ),
        VocabularyTranslation(
          englishText: 'Green apple',
          vietnameseText: 'Quả táo xanh',
        ),
        VocabularyTranslation(
          englishText: 'I like apples',
          vietnameseText: 'Con thích táo',
        ),
      ],
      'family': <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'My family',
          vietnameseText: 'Gia đình của con',
        ),
        VocabularyTranslation(
          englishText: 'This is my mother',
          vietnameseText: 'Đây là mẹ của con',
        ),
        VocabularyTranslation(
          englishText: 'This is my father',
          vietnameseText: 'Đây là bố của con',
        ),
      ],
      'school': <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'My school',
          vietnameseText: 'Trường của con',
        ),
        VocabularyTranslation(
          englishText: 'I go to school',
          vietnameseText: 'Con đi học',
        ),
        VocabularyTranslation(
          englishText: 'This is my classroom',
          vietnameseText: 'Đây là lớp học của con',
        ),
      ],
      'happy': <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'I am happy',
          vietnameseText: 'Con vui',
        ),
        VocabularyTranslation(
          englishText: 'A happy day',
          vietnameseText: 'Một ngày vui',
        ),
        VocabularyTranslation(
          englishText: 'You make me happy',
          vietnameseText: 'Bạn làm con vui',
        ),
      ],
      'hello': <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'Hello, Mom',
          vietnameseText: 'Con chào mẹ',
        ),
        VocabularyTranslation(
          englishText: 'Hello, Dad',
          vietnameseText: 'Con chào bố',
        ),
        VocabularyTranslation(
          englishText: 'Hello, my friend',
          vietnameseText: 'Chào bạn của mình',
        ),
      ],
      'thank you': <VocabularyTranslation>[
        VocabularyTranslation(
          englishText: 'Thank you, Mom',
          vietnameseText: 'Con cảm ơn mẹ',
        ),
        VocabularyTranslation(
          englishText: 'Thank you, Dad',
          vietnameseText: 'Con cảm ơn bố',
        ),
        VocabularyTranslation(
          englishText: 'Thank you for helping me',
          vietnameseText: 'Cảm ơn bạn đã giúp con',
        ),
      ],
    };
    return catalog[_normalizedVocabularyText(translated.englishText)] ??
        const <VocabularyTranslation>[];
  }

  Future<void> _switchStarBranch(_VocabularyPlaybackScope scope) async {
    _playbackInterrupted = false;
    _waitingForPlaybackContinuation = false;
    await Future.wait<void>(<Future<void>>[
      _voicePromptService.stop().catchError((Object _) {}),
      _mediaService.stopPlayback().catchError((Object _) {}),
    ]);
    for (var attempt = 0; attempt < 30 && _playingCollection; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (!mounted || _playingCollection) return;
    await _playJourney(
      _VocabularyJourney.stars,
      requestedScope: scope,
      directBranchSwitch: true,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyPlaybackError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '');

  Future<void> _speakOnSelectedOutput(
    String text, {
    String locale = 'vi-VN',
  }) async {
    final promptService = _voicePromptService;
    if (promptService is SelectedMediaOutputVoicePromptService) {
      await (promptService as SelectedMediaOutputVoicePromptService)
          .speakAndWaitOnSelectedMediaOutput(text, locale: locale);
      return;
    }
    await promptService.speakAndWait(text, locale: locale);
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

  String _normalizedVocabularyText(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"[\s.,!?;:…_-]+"), ' ')
      .trim();
}

enum _VocabularyJourney { family, stars, review }

enum _VocabularyPlaybackScope { latest, all }

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
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = isDark ? colorScheme.primary : AppColors.deepNavy;
    final readyColor = isDark ? colorScheme.tertiary : AppColors.success;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 16, 4),
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
                          width: 56,
                          height: 56,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest
                                : Colors.white.withValues(alpha: 0.92),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? Theme.of(context).colorScheme.outline
                                  : Colors.white.withValues(alpha: 0.95),
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
                                  'HOMI',
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
                                          ? readyColor
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
                                                ? readyColor
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
            : AppColors.primaryNavy,
        side: BorderSide(
          color: isDark
              ? Theme.of(context).colorScheme.outline
              : AppColors.mintBorder,
          width: 1.4,
        ),
        elevation: 0,
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.height,
    required this.onPressed,
    required this.child,
    super.key,
  });

  final double height;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? theme.colorScheme.outlineVariant
                    : AppColors.mintBorder,
                width: 1.2,
              ),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Padding(padding: const EdgeInsets.only(right: 52), child: child),
              Positioned(
                right: 4,
                top: (height - 45) / 2,
                child: Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.colorScheme.primary
                        : AppColors.primaryNavy,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: isDark ? theme.colorScheme.onPrimary : Colors.white,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
              style: theme.textTheme.headlineMedium?.copyWith(
                color: isDark
                    ? theme.colorScheme.onSurface
                    : AppColors.deepNavy,
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
            style: theme.textTheme.titleMedium?.copyWith(
              color: isDark ? theme.colorScheme.secondary : countColor,
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
    required this.canDelete,
    required this.canEdit,
    required this.canPlay,
    required this.onPlay,
    required this.onEdit,
    required this.onDelete,
  });

  final VocabularyEntry entry;
  final bool deleteMode;
  final bool canDelete;
  final bool canEdit;
  final bool canPlay;
  final VoidCallback onPlay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surfaceContainerHighest
                  : AppColors.lavender,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _icon,
              color: isDark ? theme.colorScheme.primary : AppColors.indigo,
              size: 25,
            ),
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.meaning,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_statusLabel(context)} • ${_dateLabel(context)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (!deleteMode && canEdit)
            IconButton(
              key: ValueKey<String>('edit-vocabulary-${entry.id}'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded),
              tooltip: context.tr('Sửa nội dung', '编辑内容'),
              color: isDark ? theme.colorScheme.primary : AppColors.indigo,
            ),
          IconButton(
            key: ValueKey<String>('vocabulary-action-${entry.id}'),
            onPressed: deleteMode
                ? (canDelete ? onDelete : null)
                : (canPlay ? onPlay : null),
            icon: Icon(
              deleteMode
                  ? (canDelete ? Icons.delete_rounded : Icons.lock_rounded)
                  : Icons.volume_up_rounded,
            ),
            tooltip: deleteMode
                ? canDelete
                      ? context.tr('Xóa từ này', '删除此词')
                      : context.tr('Nội dung đã bắt đầu học', '内容已开始学习')
                : context.tr('Nghe phát âm', '播放发音'),
            color: deleteMode
                ? (isDark ? theme.colorScheme.secondary : AppColors.coral)
                : (isDark ? theme.colorScheme.primary : AppColors.indigo),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(44),
              backgroundColor: isDark
                  ? theme.colorScheme.surfaceContainerHighest
                  : AppColors.lavenderSoft,
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

  String _statusLabel(BuildContext context) {
    if (entry.isStar) return context.tr('Ngôi sao', '星星');
    return switch (entry.status) {
      VocabularyLearningStatus.unlearned => context.tr('Chưa học', '未学习'),
      VocabularyLearningStatus.needsPractice => context.tr(
        'Cần luyện lại',
        '需复习',
      ),
      VocabularyLearningStatus.learnedWell => context.tr('Đã học tốt', '掌握良好'),
    };
  }
}

class _VocabularySuggestionDialog extends StatefulWidget {
  const _VocabularySuggestionDialog({
    required this.options,
    required this.maxSelections,
  });

  final List<VocabularyTranslation> options;
  final int maxSelections;

  @override
  State<_VocabularySuggestionDialog> createState() =>
      _VocabularySuggestionDialogState();
}

class _VocabularySuggestionDialogState
    extends State<_VocabularySuggestionDialog> {
  final Set<int> _selectedIndexes = <int>{0};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chọn nội dung phù hợp'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Ba mẹ chọn tối đa ${widget.maxSelections} nội dung.'),
              const SizedBox(height: 10),
              for (var index = 0; index < widget.options.length; index++)
                CheckboxListTile(
                  key: ValueKey<String>('vocabulary-suggestion-$index'),
                  value: _selectedIndexes.contains(index),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.options[index].englishText),
                  subtitle: Text(widget.options[index].vietnameseText),
                  onChanged: (selected) {
                    if (selected == true &&
                        _selectedIndexes.length >= widget.maxSelections) {
                      return;
                    }
                    setState(() {
                      if (selected == true) {
                        _selectedIndexes.add(index);
                      } else {
                        _selectedIndexes.remove(index);
                      }
                    });
                  },
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('confirm-vocabulary-suggestions'),
          onPressed: _selectedIndexes.isEmpty
              ? null
              : () => Navigator.of(context).pop(<VocabularyTranslation>[
                  for (final index in _selectedIndexes) widget.options[index],
                ]),
          child: const Text('Thêm vào hàng chờ'),
        ),
      ],
    );
  }
}

class _AddVocabularyDialog extends StatefulWidget {
  const _AddVocabularyDialog({this.initialValue = '', this.editing = false});

  final String initialValue;
  final bool editing;

  @override
  State<_AddVocabularyDialog> createState() => _AddVocabularyDialogState();
}

class _AddVocabularyDialogState extends State<_AddVocabularyDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 48),
      backgroundColor: theme.colorScheme.surface,
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
                  widget.editing
                      ? context.tr('Sửa nội dung', '编辑内容')
                      : context.tr('Thêm từ vựng', '添加词汇'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
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
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: context.tr(
                    'Nhập từ tiếng Anh hoặc tiếng Việt',
                    '输入英文或越南文',
                  ),
                  filled: true,
                  fillColor: isDark
                      ? theme.colorScheme.surfaceContainer
                      : AppColors.lavenderSoft,
                  hintStyle: const TextStyle(fontSize: 13),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: isDark
                          ? theme.colorScheme.outline
                          : AppColors.indigo,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: isDark
                          ? theme.colorScheme.secondary
                          : AppColors.indigo,
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
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: isDark
                        ? theme.colorScheme.tertiary
                        : AppColors.indigo,
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
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
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
                    icon: Icon(
                      widget.initialValue.isEmpty
                          ? Icons.add_rounded
                          : Icons.save_rounded,
                    ),
                    label: Text(
                      widget.editing
                          ? context.tr('Lưu', '保存')
                          : context.tr('Thêm', '添加'),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(104, 46),
                      backgroundColor: isDark
                          ? theme.colorScheme.primary
                          : AppColors.indigo,
                      foregroundColor: isDark
                          ? theme.colorScheme.onPrimary
                          : Colors.white,
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
