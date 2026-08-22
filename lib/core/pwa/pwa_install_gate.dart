import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../app/learning_scenery.dart';
import '../../app/mascot_assets.dart';
import 'pwa_runtime.dart';
import 'pwa_update_gate.dart';

class PwaInstallGate extends StatelessWidget {
  const PwaInstallGate({required this.child, this.runtimeState, super.key});

  final Widget child;
  final PwaRuntimeState? runtimeState;

  @override
  Widget build(BuildContext context) {
    final runtime = runtimeState ?? readPwaRuntimeState();
    if (!runtime.installRequired) {
      return PwaUpdateGate(child: child);
    }

    return PwaUpdateGate(
      child: Scaffold(
        key: const ValueKey('pwa-install-guide'),
        backgroundColor: Colors.transparent,
        body: LearningScenery(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFFDDE1FF)),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x140D1B4C),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Image.asset(
                            MascotAssets.wave,
                            width: 96,
                            height: 96,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Cài HOMI lên iPhone',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Thêm ứng dụng vào Màn hình chính để micro, âm thanh '
                            'và giao diện hoạt động ổn định hơn.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: AppColors.muted,
                                  height: 1.45,
                                ),
                          ),
                          const SizedBox(height: 22),
                          if (runtime.inAppBrowser) ...<Widget>[
                            const _InstallStep(
                              number: 1,
                              icon: Icons.open_in_browser_rounded,
                              text:
                                  'Chọn “Mở bằng Safari” trong trình duyệt hiện tại.',
                            ),
                            const SizedBox(height: 12),
                          ],
                          _InstallStep(
                            number: runtime.inAppBrowser ? 2 : 1,
                            icon: Icons.ios_share_rounded,
                            text:
                                'Trong Safari, nhấn nút Chia sẻ ở thanh công cụ.',
                          ),
                          const SizedBox(height: 12),
                          _InstallStep(
                            number: runtime.inAppBrowser ? 3 : 2,
                            icon: Icons.add_box_outlined,
                            text:
                                'Chọn “Thêm vào Màn hình chính” rồi nhấn Thêm.',
                          ),
                          const SizedBox(height: 12),
                          _InstallStep(
                            number: runtime.inAppBrowser ? 4 : 3,
                            icon: Icons.touch_app_rounded,
                            text:
                                'Quay về Màn hình chính và mở biểu tượng HOMI.',
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Safari không cho website tự bấm bước này thay bạn.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InstallStep extends StatelessWidget {
  const _InstallStep({
    required this.number,
    required this.icon,
    required this.text,
  });

  final int number;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: ValueKey('pwa-install-step-$number'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xFFE9EBFF),
          foregroundColor: AppColors.indigo,
          child: Text(
            '$number',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, color: AppColors.indigo, size: 22),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(height: 1.4, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
