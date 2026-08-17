import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../listening/domain/listening_catalog.dart';

class StartupSetupScreen extends StatelessWidget {
  const StartupSetupScreen({
    required this.profileLoading,
    required this.permissionRequestInProgress,
    required this.microphoneGranted,
    required this.bluetoothRequired,
    required this.bluetoothGranted,
    required this.selectedAge,
    required this.onRetryPermissions,
    required this.onAgeSelected,
    required this.onConfirmAge,
    this.permissionError,
    super.key,
  });

  final bool profileLoading;
  final bool permissionRequestInProgress;
  final bool microphoneGranted;
  final bool bluetoothRequired;
  final bool bluetoothGranted;
  final int? selectedAge;
  final VoidCallback onRetryPermissions;
  final ValueChanged<int> onAgeSelected;
  final VoidCallback onConfirmAge;
  final String? permissionError;

  bool get _permissionsGranted =>
      microphoneGranted && (!bluetoothRequired || bluetoothGranted);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LearningScenery(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 68,
                          height: 68,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: AppColors.ink.withValues(alpha: 0.12),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            MascotAssets.avatar,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Thiết lập cho bé',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: isDark
                                      ? theme.colorScheme.primary
                                      : AppColors.indigoDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Chỉ cần làm một lần trước khi bắt đầu học.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    _SetupCard(
                      step: '1',
                      title: 'Cho phép ứng dụng nghe',
                      subtitle:
                          'Cấp quyền ngay khi mở app để nút MAIN và thiết bị BLE luôn sẵn sàng.',
                      child: Column(
                        children: <Widget>[
                          _PermissionRow(
                            icon: Icons.mic_rounded,
                            label: 'Micro',
                            granted: microphoneGranted,
                            waiting:
                                profileLoading || permissionRequestInProgress,
                          ),
                          if (bluetoothRequired) ...<Widget>[
                            const SizedBox(height: 10),
                            _PermissionRow(
                              icon: Icons.bluetooth_rounded,
                              label: 'Thiết bị ở gần / Bluetooth',
                              granted: bluetoothGranted,
                              waiting:
                                  profileLoading || permissionRequestInProgress,
                            ),
                          ],
                          if (permissionError != null) ...<Widget>[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                permissionError!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                          if (!_permissionsGranted &&
                              !profileLoading) ...<Widget>[
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              key: const Key('startup-request-permissions'),
                              onPressed: permissionRequestInProgress
                                  ? null
                                  : onRetryPermissions,
                              icon: permissionRequestInProgress
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.lock_open_rounded),
                              label: Text(
                                permissionRequestInProgress
                                    ? 'Đang yêu cầu quyền…'
                                    : 'Cấp quyền cần thiết',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: _permissionsGranted ? 1 : 0.48,
                      child: IgnorePointer(
                        ignoring: !_permissionsGranted,
                        child: _SetupCard(
                          step: '2',
                          title: 'Chọn nhóm tuổi của trẻ',
                          subtitle:
                              'Trợ lý sẽ tự chọn đúng bộ chủ đề và không hỏi lại tuổi khi trẻ dùng MAIN.',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  for (final catalog in listeningCatalogs)
                                    ChoiceChip(
                                      key: ValueKey(
                                        'startup-age-${catalog.id}',
                                      ),
                                      label: Text(
                                        '${catalog.startAge}–${catalog.endAge} tuổi',
                                      ),
                                      selected:
                                          selectedAge != null &&
                                          selectedAge! >= catalog.startAge &&
                                          selectedAge! <= catalog.endAge,
                                      onSelected: (_) =>
                                          onAgeSelected(catalog.startAge),
                                      avatar: const Icon(
                                        Icons.child_care_rounded,
                                        size: 19,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                key: const Key('startup-confirm-age'),
                                onPressed: selectedAge == null
                                    ? null
                                    : onConfirmAge,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(58),
                                  backgroundColor: AppColors.indigo,
                                ),
                                icon: const Icon(Icons.arrow_forward_rounded),
                                label: const Text('Bắt đầu sử dụng'),
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
          ),
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String step;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.indigo,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  step,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.granted,
    required this.waiting,
  });

  final IconData icon;
  final String label;
  final bool granted;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = granted ? AppColors.success : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: granted
            ? AppColors.successSoft
            : theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
            ),
          ),
          if (waiting)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else
            Icon(
              granted ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: color,
            ),
        ],
      ),
    );
  }
}
