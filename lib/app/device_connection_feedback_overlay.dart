import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'mascot_assets.dart';

enum DeviceConnectionFeedbackStage { connecting, connected }

/// Short, app-owned feedback shown while HOMI's BLE control transport is
/// becoming ready. Audio-route readiness is intentionally not inferred here:
/// HFP/SCO is selected and verified separately when a microphone turn starts.
class DeviceConnectionFeedbackOverlay extends StatelessWidget {
  const DeviceConnectionFeedbackOverlay({required this.stage, super.key});

  final DeviceConnectionFeedbackStage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = stage == DeviceConnectionFeedbackStage.connected;
    final title = connected ? 'Đã kết nối thiết bị' : 'Đang kết nối thiết bị';
    final detail = connected
        ? 'HOMI đã sẵn sàng nhận nút MAIN.'
        : 'Hãy bật thiết bị và đặt gần điện thoại nhé.';

    return Stack(
      key: const Key('device-connection-feedback-overlay'),
      fit: StackFit.expand,
      children: <Widget>[
        const ModalBarrier(dismissible: false, color: Color(0x520B2355)),
        Center(
          child: Semantics(
            liveRegion: true,
            label: title,
            child: Container(
              key: Key(
                connected
                    ? 'device-connection-feedback-connected'
                    : 'device-connection-feedback-connecting',
              ),
              width: 310,
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(30),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.primaryNavy.withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: 116,
                    child: Image.asset(
                      connected ? MascotAssets.speak : MascotAssets.wave,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: connected
                        ? const Icon(
                            Icons.check_circle_rounded,
                            key: Key('device-connection-success-icon'),
                            color: AppColors.success,
                            size: 34,
                          )
                        : const SizedBox.square(
                            key: Key('device-connection-progress'),
                            dimension: 30,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.2,
                              color: AppColors.indigo,
                            ),
                          ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
