import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';
import '../../../../l10n/display_language.dart';
import '../../domain/conversation_models.dart';

class ResultPanel extends StatelessWidget {
  const ResultPanel({required this.result, required this.onPlay, super.key});

  final ConversationResult? result;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final currentResult = result;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 198),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surface.withValues(alpha: 0.96)
            : const Color(0xF8FFFDF9),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isDark
              ? colorScheme.outline.withValues(alpha: 0.65)
              : const Color(0xCCFFFFFF),
          width: 1.4,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: isDark ? Colors.black38 : const Color(0x120D1B4C),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _TranslationSection(
            icon: Icons.chat_bubble_rounded,
            label: context.tr('Câu tiếng Việt', '越南语句子'),
            text: currentResult?.vietnameseText,
            placeholder: context.tr('Câu con nói sẽ hiện ở đây', '你说的句子会显示在这里'),
          ),
          const _TranslationConnector(),
          _TranslationSection(
            icon: Icons.translate_rounded,
            label: context.tr('Câu tiếng Anh', '英语句子'),
            text: currentResult?.englishText,
            placeholder: context.tr(
              'Câu tiếng Anh sẽ hiện ở đây',
              '英语句子会显示在这里',
            ),
            trailing: currentResult?.audioUri == null
                ? null
                : Semantics(
                    button: true,
                    label: context.tr('Phát lại câu tiếng Anh', '重新播放英语句子'),
                    child: IconButton(
                      onPressed: onPlay,
                      tooltip: context.tr('Phát tiếng Anh', '播放英语'),
                      icon: const Icon(Icons.play_arrow_rounded),
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(42),
                        maximumSize: const Size.square(42),
                        backgroundColor: AppColors.indigo,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
          ),
          if (currentResult?.textSource ==
              'mlkit_on_device_translation') ...<Widget>[
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Bản dịch tự động • Powered by Google Translate',
                key: const Key('google-translate-attribution'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TranslationSection extends StatelessWidget {
  const _TranslationSection({
    required this.icon,
    required this.label,
    required this.text,
    required this.placeholder,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? text;
  final String placeholder;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasText = text?.trim().isNotEmpty ?? false;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDark
                    ? colorScheme.surfaceContainerHighest
                    : AppColors.lavender,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isDark ? colorScheme.primary : AppColors.indigo,
                size: 19,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isDark ? colorScheme.primary : AppColors.indigoDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainer
                : AppColors.lavenderSoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: Text(
                hasText ? text! : placeholder,
                key: ValueKey<String>(text ?? placeholder),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: hasText
                      ? isDark
                            ? colorScheme.onSurface
                            : AppColors.ink
                      : isDark
                      ? colorScheme.onSurfaceVariant
                      : AppColors.muted,
                  fontWeight: hasText ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TranslationConnector extends StatelessWidget {
  const _TranslationConnector();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Divider(
            color: isDark
                ? colorScheme.outlineVariant
                : AppColors.lavenderBorder,
            height: 1,
          ),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isDark ? colorScheme.surface : Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: AppColors.peach,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}
