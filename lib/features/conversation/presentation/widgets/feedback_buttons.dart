import 'package:flutter/material.dart';

import '../../../../app/app_theme.dart';
import '../../../../l10n/display_language.dart';

class FeedbackButtons extends StatelessWidget {
  const FeedbackButtons({
    required this.enabled,
    required this.selectedValue,
    required this.onSelected,
    super.key,
  });

  final bool enabled;
  final bool? selectedValue;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackButtons =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        final approveButton = _FeedbackButton(
          label: context.tr('Đúng ý', '符合原意'),
          icon: Icons.sentiment_satisfied_alt_rounded,
          foreground: AppColors.success,
          background: AppColors.successSoft,
          selected: selectedValue == true,
          enabled: enabled,
          onPressed: () => onSelected(true),
        );
        final rejectButton = _FeedbackButton(
          label: context.tr('Sai ý', '不符合原意'),
          icon: Icons.sentiment_dissatisfied_rounded,
          foreground: const Color(0xFFD92D20),
          background: const Color(0xFFFFF3F2),
          selected: selectedValue == false,
          enabled: enabled,
          onPressed: () => onSelected(false),
        );

        if (stackButtons) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              approveButton,
              const SizedBox(height: 10),
              rejectButton,
            ],
          );
        }

        return Row(
          children: <Widget>[
            Expanded(child: approveButton),
            const SizedBox(width: 12),
            Expanded(child: rejectButton),
          ],
        );
      },
    );
  }
}

class _FeedbackButton extends StatelessWidget {
  const _FeedbackButton({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label:
          '$label. ${selected ? context.tr('Đang được chọn', '已选择') : context.tr('Chưa được chọn', '未选择')}',
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 25),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 54),
          foregroundColor: foreground,
          backgroundColor: selected ? background : AppColors.surface,
          side: BorderSide(
            color: selected ? foreground : foreground.withValues(alpha: 0.6),
            width: selected ? 2 : 1.35,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
    );
  }
}
