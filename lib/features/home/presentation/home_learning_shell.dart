import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../config/app_config.dart';
import '../../../l10n/display_language.dart';
import '../../conversation/presentation/conversation_controller.dart';
import '../../conversation/presentation/conversation_screen.dart';
import '../../listening/presentation/listening_route_names.dart';
import '../../listening/presentation/topic_listening_screen.dart';
import '../../settings/presentation/history_sheet.dart';
import '../../settings/presentation/settings_sheet.dart';
import '../../vocabulary/presentation/vocabulary_home_screen.dart';
import 'home_mode_rail.dart';

class HomeLearningShell extends StatefulWidget {
  const HomeLearningShell({
    required this.controller,
    required this.config,
    super.key,
  });

  final ConversationController controller;
  final AppConfig config;

  @override
  State<HomeLearningShell> createState() => _HomeLearningShellState();
}

class _HomeLearningShellState extends State<HomeLearningShell> {
  late final PageController _pageController;
  int _page = 0;
  bool _topicPreviewExpanded = false;
  bool _openingTopics = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return DisplayLanguageScope(
          language: widget.controller.displayLanguage,
          child: PopScope<void>(
            canPop: _page == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && _page == 1) {
                _showConversation();
              }
            },
            child: Stack(
              children: <Widget>[
                PageView(
                  key: const Key('home-learning-page-view'),
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) => setState(() => _page = page),
                  children: <Widget>[
                    ConversationScreen(
                      controller: widget.controller,
                      config: widget.config,
                    ),
                    VocabularyHomeScreen(
                      isReady: widget.controller.isInputAvailable,
                      onReturnToConversation: _showConversation,
                      onHistory: _showHistory,
                      onSettings: _showSettings,
                    ),
                  ],
                ),
                Align(
                  alignment: const Alignment(-1, -0.20),
                  child: HomeModeRail(
                    key: const Key('vocabulary-edge-tab'),
                    edge: HomeRailEdge.left,
                    label: _page == 0
                        ? context.tr('Từ vựng', '词汇')
                        : context.tr('Giao tiếp', '沟通'),
                    icon: _page == 0
                        ? Icons.chat_bubble_rounded
                        : Icons.mic_rounded,
                    color: AppColors.indigo,
                    onPressed: _page == 0 ? _showVocabulary : _showConversation,
                  ),
                ),
                Align(
                  alignment: const Alignment(1, -0.05),
                  child: HomeModeRail(
                    key: const Key('topic-listening-edge-tab'),
                    edge: HomeRailEdge.right,
                    label: context.tr('Chủ đề', '主题'),
                    icon: Icons.headphones_rounded,
                    color: const Color(0xFF7443D8),
                    expanded: _topicPreviewExpanded,
                    onPressed: _openTopicListening,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Duration get _motionDuration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 420);

  void _showVocabulary() {
    _pageController.animateToPage(
      1,
      duration: _motionDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _showConversation() {
    _pageController.animateToPage(
      0,
      duration: _motionDuration,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openTopicListening() async {
    if (_openingTopics) {
      return;
    }
    _openingTopics = true;
    setState(() => _topicPreviewExpanded = true);
    if (!MediaQuery.disableAnimationsOf(context)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: ListeningRouteNames.topicCatalog),
        transitionDuration: _motionDuration,
        reverseTransitionDuration: _motionDuration,
        pageBuilder: (_, _, _) => TopicListeningScreen(
          language: widget.controller.displayLanguage,
          childAge: widget.config.childAge,
          controller: widget.controller,
        ),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _topicPreviewExpanded = false;
      _openingTopics = false;
    });
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SettingsSheet(controller: widget.controller),
    );
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => HistorySheet(controller: widget.controller),
    );
  }
}
