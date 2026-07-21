import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';
import '../../domain/conversation_models.dart';

class ResultPanel extends StatelessWidget {
  const ResultPanel({required this.result, required this.onPlay, super.key});

  final ConversationResult? result;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final currentResult = result;

    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 218),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE8E7FA)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120D1B4C),
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
            label: 'Câu tiếng Việt',
            text: currentResult?.vietnameseText,
            placeholder: 'Câu con nói sẽ hiện ở đây',
          ),
          const _TranslationConnector(),
          _TranslationSection(
            icon: Icons.translate_rounded,
            label: 'English sentence',
            text: currentResult?.englishText,
            placeholder: 'Câu tiếng Anh sẽ hiện ở đây',
            trailing: currentResult == null
                ? null
                : Semantics(
                    button: true,
                    label: 'Phát lại câu tiếng Anh',
                    child: IconButton(
                      onPressed: onPlay,
                      tooltip: 'Phát tiếng Anh',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.lavender,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.indigo, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.indigoDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.lavenderSoft,
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
                  color: hasText ? AppColors.ink : AppColors.muted,
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
    return SizedBox(
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          const Divider(color: AppColors.lavenderBorder, height: 1),
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: AppColors.peach,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }
}
