import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/mascot_assets.dart';
import '../../../l10n/display_language.dart';

class ScenicAppHeader extends StatelessWidget {
  const ScenicAppHeader({
    required this.isReady,
    required this.onHistory,
    required this.onSettings,
    super.key,
  });

  final bool isReady;
  final VoidCallback onHistory;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          child: Row(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x1A142451),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Transform.scale(
                  scale: 1.12,
                  child: Image.asset(
                    MascotAssets.avatar,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'INNOTRIK',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: AppColors.indigoDark,
                            fontSize: 27,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: isReady
                                ? AppColors.success
                                : AppColors.muted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            isReady
                                ? context.tr('Sẵn sàng', '已就绪')
                                : context.tr('Chưa kết nối', '未连接'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: isReady
                                      ? AppColors.success
                                      : AppColors.muted,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _HeaderAction(
                icon: Icons.history_rounded,
                tooltip: context.tr('Lịch sử gần đây', '最近记录'),
                onPressed: onHistory,
              ),
              const SizedBox(width: 6),
              _HeaderAction(
                icon: Icons.settings_outlined,
                tooltip: context.tr('Cài đặt', '设置'),
                onPressed: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(48),
        maximumSize: const Size.square(48),
        foregroundColor: AppColors.indigoDark,
        backgroundColor: Colors.white.withValues(alpha: 0.84),
        shadowColor: const Color(0x24142451),
        elevation: 2,
      ),
    );
  }
}
