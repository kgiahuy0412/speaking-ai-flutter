import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../listening/domain/listening_catalog.dart';
import '../../privacy/presentation/parental_gate.dart';

class StartupSetupScreen extends StatelessWidget {
  const StartupSetupScreen({
    required this.profileLoading,
    required this.permissionRequestInProgress,
    required this.privacyConfigurationComplete,
    required this.privacyConsentGranted,
    required this.microphoneGranted,
    required this.bluetoothRequired,
    required this.bluetoothGranted,
    required this.selectedAge,
    required this.aiSubprocessors,
    required this.dataRetentionSummary,
    required this.onGrantPrivacyConsent,
    required this.onContinueWithoutVoice,
    required this.onRetryPermissions,
    required this.onAgeSelected,
    required this.onConfirmAge,
    this.privacyPolicyUri,
    this.termsUri,
    this.supportUri,
    this.permissionError,
    super.key,
  });

  final bool profileLoading;
  final bool permissionRequestInProgress;
  final bool privacyConfigurationComplete;
  final bool privacyConsentGranted;
  final bool microphoneGranted;
  final bool bluetoothRequired;
  final bool bluetoothGranted;
  final int? selectedAge;
  final String aiSubprocessors;
  final String dataRetentionSummary;
  final Uri? privacyPolicyUri;
  final Uri? termsUri;
  final Uri? supportUri;
  final Future<void> Function() onGrantPrivacyConsent;
  final Future<void> Function() onContinueWithoutVoice;
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
              constraints: const BoxConstraints(maxWidth: 620),
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
                                'Phụ huynh thiết lập HOMI',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: isDark
                                      ? theme.colorScheme.primary
                                      : AppColors.indigoDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'HOMI chỉ bật truyền giọng nói sau khi phụ huynh đọc và chủ động đồng ý.',
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
                      title: 'Dữ liệu trẻ em và dịch vụ AI',
                      subtitle:
                          'Thông tin này xuất hiện trước hộp thoại quyền micro của hệ thống.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const _DisclosureItem(
                            icon: Icons.graphic_eq_rounded,
                            text:
                                'Thu thập audio, transcript/nội dung trẻ nói, nhóm tuổi, lịch sử tương tác, mã cài đặt lâu dài và chẩn đoán hiệu năng.',
                          ),
                          const SizedBox(height: 10),
                          _DisclosureItem(
                            icon: Icons.cloud_outlined,
                            text:
                                'Dữ liệu cần thiết được gửi tới: $aiSubprocessors để nhận dạng, dịch, tạo phản hồi/giọng đọc và vận hành dịch vụ.',
                          ),
                          const SizedBox(height: 10),
                          _DisclosureItem(
                            icon: Icons.schedule_rounded,
                            text: dataRetentionSummary,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              TextButton.icon(
                                onPressed: () => _openLegalPage(
                                  context,
                                  privacyPolicyUri,
                                  'Chính sách quyền riêng tư',
                                ),
                                icon: const Icon(Icons.privacy_tip_outlined),
                                label: const Text('Privacy Policy'),
                              ),
                              TextButton.icon(
                                onPressed: () => _openLegalPage(
                                  context,
                                  termsUri,
                                  'Điều khoản sử dụng',
                                ),
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('Terms'),
                              ),
                              TextButton.icon(
                                onPressed: () => _openLegalPage(
                                  context,
                                  supportUri,
                                  'Hỗ trợ',
                                ),
                                icon: const Icon(Icons.support_agent_rounded),
                                label: const Text('Support'),
                              ),
                            ],
                          ),
                          if (!privacyConfigurationComplete) ...<Widget>[
                            const SizedBox(height: 10),
                            const _WarningBox(
                              text:
                                  'Chưa cấu hình đủ URL pháp lý, danh sách nhà cung cấp AI hoặc thời hạn lưu. Giọng nói bị khóa; vẫn có thể dùng nội dung không cần micro.',
                            ),
                          ],
                          const SizedBox(height: 14),
                          if (privacyConsentGranted)
                            const _GrantedBanner(
                              text: 'Phụ huynh đã đồng ý cho xử lý dữ liệu.',
                            )
                          else
                            FilledButton.icon(
                              key: const Key('startup-grant-privacy-consent'),
                              onPressed:
                                  profileLoading ||
                                      !privacyConfigurationComplete
                                  ? null
                                  : () => onGrantPrivacyConsent(),
                              icon: const Icon(Icons.verified_user_outlined),
                              label: const Text('Tôi là phụ huynh và đồng ý'),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: privacyConsentGranted ? 1 : 0.5,
                      child: IgnorePointer(
                        ignoring: !privacyConsentGranted,
                        child: _SetupCard(
                          step: '2',
                          title: 'Quyền micro và thiết bị',
                          subtitle:
                              'Hộp thoại hệ thống chỉ được gọi sau bước đồng ý ở trên.',
                          child: Column(
                            children: <Widget>[
                              _PermissionRow(
                                icon: Icons.mic_rounded,
                                label: 'Micro',
                                granted: microphoneGranted,
                                waiting:
                                    profileLoading ||
                                    permissionRequestInProgress,
                              ),
                              if (bluetoothRequired) ...<Widget>[
                                const SizedBox(height: 10),
                                _PermissionRow(
                                  icon: Icons.bluetooth_rounded,
                                  label: 'Thiết bị ở gần / Bluetooth',
                                  granted: bluetoothGranted,
                                  waiting:
                                      profileLoading ||
                                      permissionRequestInProgress,
                                ),
                              ],
                              if (permissionError != null) ...<Widget>[
                                const SizedBox(height: 12),
                                _WarningBox(text: permissionError!),
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
                                      : const Icon(Icons.mic_rounded),
                                  label: Text(
                                    permissionRequestInProgress
                                        ? 'Đang yêu cầu quyền…'
                                        : 'Cho phép micro',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SetupCard(
                      step: '3',
                      title: 'Chọn nhóm tuổi của trẻ',
                      subtitle:
                          'Nhóm tuổi được lưu trên thiết bị để chọn nội dung phù hợp.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              for (final catalog in listeningCatalogs)
                                ChoiceChip(
                                  key: ValueKey('startup-age-${catalog.id}'),
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
                            onPressed:
                                selectedAge == null || !privacyConsentGranted
                                ? null
                                : onConfirmAge,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(58),
                              backgroundColor: AppColors.indigo,
                            ),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: Text(
                              microphoneGranted
                                  ? 'Bắt đầu sử dụng'
                                  : 'Bắt đầu, bật micro sau',
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const Key('startup-continue-without-voice'),
                            onPressed: selectedAge == null
                                ? null
                                : () => onContinueWithoutVoice(),
                            icon: const Icon(Icons.mic_off_outlined),
                            label: const Text('Tiếp tục không gửi giọng nói'),
                          ),
                        ],
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

  Future<void> _openLegalPage(
    BuildContext context,
    Uri? uri,
    String label,
  ) async {
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label chưa được cấu hình cho bản build này.')),
      );
      return;
    }
    if (!await showParentalGate(context) || !context.mounted) {
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể mở $label.')));
    }
  }
}

class _DisclosureItem extends StatelessWidget {
  const _DisclosureItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 21, color: AppColors.indigo),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

class _GrantedBanner extends StatelessWidget {
  const _GrantedBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle_rounded, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
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
