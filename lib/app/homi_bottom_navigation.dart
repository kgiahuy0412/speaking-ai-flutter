import 'package:flutter/material.dart';

import '../l10n/display_language.dart';
import 'app_theme.dart';

/// The shared primary navigation used by the HOMI home and vocabulary screens.
///
/// MAIN stays an action instead of becoming a tab so its physical-button
/// behavior and the on-screen behavior continue to share the same coordinator.
class HomiBottomNavigation extends StatelessWidget {
  const HomiBottomNavigation({
    required this.selectedIndex,
    required this.onConversation,
    required this.onTopics,
    required this.onMain,
    required this.onVocabulary,
    required this.onHistory,
    this.conversationKey,
    this.topicsKey,
    this.mainKey,
    this.vocabularyKey,
    this.historyKey,
    this.topicsTutorialKey,
    this.vocabularyTutorialKey,
    super.key,
  });

  static const double contentHeight = 78;

  final int selectedIndex;
  final VoidCallback onConversation;
  final VoidCallback onTopics;
  final VoidCallback? onMain;
  final VoidCallback onVocabulary;
  final VoidCallback onHistory;
  final Key? conversationKey;
  final Key? topicsKey;
  final Key? mainKey;
  final Key? vocabularyKey;
  final Key? historyKey;
  final Key? topicsTutorialKey;
  final Key? vocabularyTutorialKey;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.98)
        : Colors.white.withValues(alpha: 0.98);

    return Material(
      color: surface,
      elevation: 8,
      shadowColor: AppColors.primaryNavy.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: contentHeight,
          child: Row(
            children: <Widget>[
              _NavigationItem(
                key: conversationKey,
                selected: selectedIndex == 0,
                icon: Icons.chat_bubble_rounded,
                label: context.tr('Giao tiếp', '沟通'),
                onPressed: onConversation,
              ),
              KeyedSubtree(
                key: topicsTutorialKey,
                child: _NavigationItem(
                  key: topicsKey,
                  selected: selectedIndex == 1,
                  icon: Icons.grid_view_rounded,
                  label: context.tr('Chủ đề', '主题'),
                  onPressed: onTopics,
                ),
              ),
              Expanded(
                child: _MainNavigationAction(key: mainKey, onPressed: onMain),
              ),
              KeyedSubtree(
                key: vocabularyTutorialKey,
                child: _NavigationItem(
                  key: vocabularyKey,
                  selected: selectedIndex == 3,
                  icon: Icons.menu_book_rounded,
                  label: context.tr('Từ vựng', '词汇'),
                  onPressed: onVocabulary,
                ),
              ),
              _NavigationItem(
                key: historyKey,
                selected: selectedIndex == 4,
                icon: Icons.history_rounded,
                label: context.tr('Lịch sử', '历史'),
                onPressed: onHistory,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark
        ? Theme.of(context).colorScheme.primary
        : AppColors.indigo;
    final inactiveColor = isDark
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : AppColors.muted;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkResponse(
          onTap: onPressed,
          radius: 34,
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: selected ? 39 : 34,
                  height: selected ? 32 : 30,
                  decoration: BoxDecoration(
                    color: selected
                        ? activeColor.withValues(alpha: isDark ? 0.18 : 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: selected ? activeColor : inactiveColor,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? activeColor : inactiveColor,
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
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

class _MainNavigationAction extends StatelessWidget {
  const _MainNavigationAction({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ringColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : AppColors.mintSoft;
    final buttonColor = enabled
        ? (isDark ? theme.colorScheme.primary : AppColors.indigo)
        : (isDark
              ? theme.colorScheme.surfaceContainerHighest
              : AppColors.periwinkle);
    final buttonForeground = isDark
        ? theme.colorScheme.onPrimary
        : Colors.white;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'MAIN, gọi trợ lý HOMI',
      child: InkResponse(
        onTap: onPressed,
        radius: 42,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: <Widget>[
            Positioned(
              top: -22,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: 7),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AppColors.primaryNavy.withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: buttonColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.mic_rounded,
                    color: buttonForeground,
                    size: 30,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 4,
              child: Text(
                'MAIN',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isDark ? theme.colorScheme.primary : AppColors.indigo,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
