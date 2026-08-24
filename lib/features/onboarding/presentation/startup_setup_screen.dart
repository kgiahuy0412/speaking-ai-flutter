import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../listening/domain/listening_catalog.dart';
import '../../privacy/presentation/parental_gate.dart';

enum _ParentSetupStep { privacy, profile, permissions, device }

/// Mandatory parent/teacher setup shown before a child learning session starts.
class StartupSetupScreen extends StatefulWidget {
  const StartupSetupScreen({
    required this.profileLoading,
    required this.permissionRequestInProgress,
    required this.privacyConfigurationComplete,
    required this.privacyConsentGranted,
    required this.limitedModeSelected,
    required this.microphoneGranted,
    required this.bluetoothRequired,
    required this.bluetoothGranted,
    required this.h20BleConnected,
    required this.h20HfpConfigured,
    required this.selectedAge,
    required this.aiSubprocessors,
    required this.dataRetentionSummary,
    required this.onGrantPrivacyConsent,
    required this.onContinueWithoutVoice,
    required this.onRetryPermissions,
    required this.onSetupH20,
    required this.onUsePhoneMicrophone,
    required this.onAgeSelected,
    required this.onCompleteSetup,
    this.h20DeviceName,
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
  final bool limitedModeSelected;
  final bool microphoneGranted;
  final bool bluetoothRequired;
  final bool bluetoothGranted;
  final bool h20BleConnected;
  final bool h20HfpConfigured;
  final int? selectedAge;
  final String aiSubprocessors;
  final String dataRetentionSummary;
  final String? h20DeviceName;
  final Uri? privacyPolicyUri;
  final Uri? termsUri;
  final Uri? supportUri;
  final Future<void> Function() onGrantPrivacyConsent;
  final Future<void> Function() onContinueWithoutVoice;
  final VoidCallback onRetryPermissions;
  final Future<void> Function() onSetupH20;
  final Future<void> Function() onUsePhoneMicrophone;
  final ValueChanged<int> onAgeSelected;
  final Future<void> Function() onCompleteSetup;
  final String? permissionError;

  @override
  State<StartupSetupScreen> createState() => _StartupSetupScreenState();
}

class _StartupSetupScreenState extends State<StartupSetupScreen> {
  _ParentSetupStep _step = _ParentSetupStep.privacy;
  late bool _adultRoleConfirmed;
  bool _phoneMicrophoneSelected = false;
  bool _h20SetupRequested = false;
  bool _choiceInProgress = false;

  bool get _privacyChoiceMade =>
      widget.privacyConsentGranted || widget.limitedModeSelected;

  bool get _h20Ready => widget.h20BleConnected && widget.h20HfpConfigured;

  bool get _canComplete =>
      widget.limitedModeSelected ||
      (_phoneMicrophoneSelected && widget.microphoneGranted) ||
      (_h20Ready && widget.microphoneGranted);

  @override
  void initState() {
    super.initState();
    _adultRoleConfirmed = widget.privacyConsentGranted;
  }

  @override
  void didUpdateWidget(StartupSetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.privacyConsentGranted && widget.privacyConsentGranted) {
      _adultRoleConfirmed = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stepNumber = _step.index + 1;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LearningScenery(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                children: <Widget>[
                  _SetupHeader(
                    stepNumber: stepNumber,
                    totalSteps: _ParentSetupStep.values.length,
                    canGoBack: _step.index > 0,
                    onBack: _goBack,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KeyedSubtree(
                          key: ValueKey<_ParentSetupStep>(_step),
                          child: switch (_step) {
                            _ParentSetupStep.privacy => _buildPrivacyStep(
                              theme,
                            ),
                            _ParentSetupStep.profile => _buildProfileStep(
                              theme,
                            ),
                            _ParentSetupStep.permissions =>
                              _buildPermissionsStep(theme),
                            _ParentSetupStep.device => _buildDeviceStep(theme),
                          },
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
    );
  }

  Widget _buildPrivacyStep(ThemeData theme) {
    return _SetupCard(
      icon: Icons.family_restroom_rounded,
      title: 'Khu vực thiết lập của phụ huynh',
      subtitle:
          'Điện thoại dùng để phụ huynh hoặc giáo viên cấu hình phiên học. Trẻ có thể tương tác bằng thiết bị H20 sau khi thiết lập xong.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          CheckboxListTile(
            key: const Key('startup-confirm-adult-role'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _adultRoleConfirmed,
            onChanged: widget.profileLoading
                ? null
                : (value) =>
                      setState(() => _adultRoleConfirmed = value ?? false),
            title: const Text('Tôi là phụ huynh, người giám hộ hoặc giáo viên'),
            subtitle: const Text(
              'Tôi sẽ chọn nhóm tuổi, cấp quyền và quản lý thiết bị cho trẻ.',
            ),
          ),
          const Divider(height: 28),
          const _DisclosureItem(
            icon: Icons.graphic_eq_rounded,
            text:
                'HOMI có thể xử lý giọng nói/audio, transcript, nhóm tuổi, lịch sử tương tác, mã cài đặt và chẩn đoán kỹ thuật để cung cấp bài học.',
          ),
          const SizedBox(height: 10),
          _DisclosureItem(
            icon: Icons.cloud_outlined,
            text:
                'Dữ liệu cần thiết có thể được gửi tới ${widget.aiSubprocessors} để nhận dạng, dịch, tạo phản hồi/giọng đọc và vận hành dịch vụ.',
          ),
          const SizedBox(height: 10),
          _DisclosureItem(
            icon: Icons.schedule_rounded,
            text: widget.dataRetentionSummary,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _LegalButton(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                onPressed: () => _openLegalPage(
                  widget.privacyPolicyUri,
                  'Chính sách quyền riêng tư',
                ),
              ),
              _LegalButton(
                icon: Icons.description_outlined,
                label: 'Terms',
                onPressed: () =>
                    _openLegalPage(widget.termsUri, 'Điều khoản sử dụng'),
              ),
              _LegalButton(
                icon: Icons.support_agent_rounded,
                label: 'Support',
                onPressed: () => _openLegalPage(widget.supportUri, 'Hỗ trợ'),
              ),
            ],
          ),
          if (!widget.privacyConfigurationComplete) ...<Widget>[
            const SizedBox(height: 12),
            const _WarningBox(
              text:
                  'Bản build chưa cấu hình đầy đủ URL pháp lý, nhà cung cấp hoặc thời hạn lưu. Chế độ giọng nói đang bị khóa.',
            ),
          ],
          const SizedBox(height: 18),
          if (widget.privacyConsentGranted)
            const _GrantedBanner(
              text: 'Phụ huynh đã đồng ý cho xử lý dữ liệu giọng nói.',
            )
          else if (widget.limitedModeSelected)
            const _GrantedBanner(text: 'Đã chọn chế độ không dùng giọng nói.')
          else
            FilledButton.icon(
              key: const Key('startup-grant-privacy-consent'),
              onPressed:
                  !_adultRoleConfirmed ||
                      widget.profileLoading ||
                      !widget.privacyConfigurationComplete
                  ? null
                  : _grantConsentAndContinue,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Đồng ý và tiếp tục'),
            ),
          if (!_privacyChoiceMade) ...<Widget>[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('startup-continue-without-voice'),
              onPressed: !_adultRoleConfirmed || widget.profileLoading
                  ? null
                  : _chooseLimitedMode,
              icon: const Icon(Icons.mic_off_outlined),
              label: const Text('Tiếp tục không dùng giọng nói'),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 12),
            _PrimaryNextButton(onPressed: _adultRoleConfirmed ? _goNext : null),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileStep(ThemeData theme) {
    return _SetupCard(
      icon: Icons.child_care_rounded,
      title: 'Chọn hồ sơ học của trẻ',
      subtitle:
          'Phụ huynh chọn nhóm tuổi để HOMI chuẩn bị từ vựng, chủ đề và cách hướng dẫn phù hợp.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final catalog in listeningCatalogs)
                ChoiceChip(
                  key: ValueKey('startup-age-${catalog.id}'),
                  label: Text('${catalog.startAge}–${catalog.endAge} tuổi'),
                  selected:
                      widget.selectedAge != null &&
                      widget.selectedAge! >= catalog.startAge &&
                      widget.selectedAge! <= catalog.endAge,
                  onSelected: (_) => widget.onAgeSelected(catalog.startAge),
                  avatar: const Icon(Icons.face_rounded, size: 19),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const _InfoBox(
            icon: Icons.admin_panel_settings_outlined,
            text:
                'Nhóm tuổi chỉ được thay đổi trong Cài đặt dành cho phụ huynh.',
          ),
          const SizedBox(height: 18),
          _PrimaryNextButton(
            onPressed: widget.selectedAge == null ? null : _goNext,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsStep(ThemeData theme) {
    final permissionsGranted =
        widget.microphoneGranted &&
        (!widget.bluetoothRequired || widget.bluetoothGranted);
    return _SetupCard(
      icon: Icons.security_rounded,
      title: 'Cấp quyền trên thiết bị',
      subtitle: widget.limitedModeSelected
          ? 'Chế độ không giọng nói không cần quyền micro hoặc Bluetooth.'
          : 'HOMI chỉ mở hộp thoại hệ thống sau khi phụ huynh đã đồng ý ở bước đầu.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.limitedModeSelected)
            const _InfoBox(
              icon: Icons.mic_off_outlined,
              text:
                  'Trẻ vẫn xem/nghe được nội dung không cần micro. Phụ huynh có thể bật giọng nói sau trong Cài đặt.',
            )
          else ...<Widget>[
            _PermissionRow(
              icon: Icons.mic_rounded,
              label: 'Micro và nhận dạng giọng nói',
              granted: widget.microphoneGranted,
              waiting:
                  widget.profileLoading || widget.permissionRequestInProgress,
            ),
            if (widget.bluetoothRequired) ...<Widget>[
              const SizedBox(height: 10),
              _PermissionRow(
                icon: Icons.bluetooth_rounded,
                label: 'Bluetooth / thiết bị ở gần',
                granted: widget.bluetoothGranted,
                waiting:
                    widget.profileLoading || widget.permissionRequestInProgress,
              ),
            ],
            if (widget.permissionError != null) ...<Widget>[
              const SizedBox(height: 12),
              _WarningBox(text: widget.permissionError!),
            ],
            if (!permissionsGranted) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('startup-request-permissions'),
                onPressed: widget.permissionRequestInProgress
                    ? null
                    : widget.onRetryPermissions,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                icon: widget.permissionRequestInProgress
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_open_rounded),
                label: Text(
                  widget.permissionRequestInProgress
                      ? 'Đang yêu cầu quyền…'
                      : 'Cấp quyền cần thiết',
                ),
              ),
            ],
          ],
          const SizedBox(height: 18),
          _PrimaryNextButton(
            onPressed: widget.limitedModeSelected || widget.microphoneGranted
                ? _goNext
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStep(ThemeData theme) {
    final deviceName = widget.h20DeviceName?.trim();
    return _SetupCard(
      icon: Icons.headset_mic_rounded,
      title: 'Chọn cách trẻ tương tác',
      subtitle: widget.limitedModeSelected
          ? 'Hoàn tất thiết lập để dùng các nội dung không cần micro.'
          : 'Ưu tiên H20 cho trẻ. Mic điện thoại luôn có sẵn để phụ huynh và Apple Review kiểm tra khi không có thiết bị.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!widget.limitedModeSelected) ...<Widget>[
            _DeviceChoiceCard(
              key: const Key('startup-h20-choice'),
              icon: Icons.bluetooth_audio_rounded,
              title: deviceName == null || deviceName.isEmpty
                  ? 'Thiết bị H20'
                  : deviceName,
              description:
                  'Phụ huynh ghép đôi H20 trong Cài đặt Bluetooth; HOMI kiểm tra HFP (mic/loa) và BLE (nút MAIN).',
              selected: _h20Ready,
              status: _h20Ready
                  ? 'HFP và BLE đã sẵn sàng'
                  : widget.h20HfpConfigured
                  ? 'HFP đã chọn • đang chờ BLE'
                  : widget.h20BleConnected
                  ? 'BLE đã kết nối • đang chờ HFP'
                  : _h20SetupRequested
                  ? 'Chưa thấy đủ hai kết nối; kiểm tra ghép đôi H20'
                  : 'Chưa thiết lập',
              actionKey: const Key('startup-setup-h20'),
              actionLabel: _h20Ready ? 'Đã kết nối' : 'Thiết lập H20',
              busy: _choiceInProgress,
              onPressed: _choiceInProgress ? null : _setupH20,
            ),
            const SizedBox(height: 12),
            _DeviceChoiceCard(
              key: const Key('startup-phone-choice'),
              icon: Icons.phone_iphone_rounded,
              title: 'Mic điện thoại',
              description:
                  'Dùng điện thoại để kiểm tra bài học mà không cần có H20.',
              selected: _phoneMicrophoneSelected && widget.microphoneGranted,
              status: widget.microphoneGranted
                  ? 'Micro đã được cấp quyền'
                  : 'Cần cấp quyền micro',
              actionKey: const Key('startup-use-phone-mic'),
              actionLabel: _phoneMicrophoneSelected
                  ? 'Đang chọn'
                  : 'Dùng mic điện thoại',
              busy: _choiceInProgress,
              onPressed: _choiceInProgress ? null : _selectPhoneMicrophone,
            ),
          ] else
            const _InfoBox(
              icon: Icons.visibility_outlined,
              text:
                  'HOMI sẽ vào chế độ giới hạn. Các nút cần ghi âm sẽ hướng phụ huynh quay lại phần quyền riêng tư.',
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('startup-confirm-age'),
            onPressed: _canComplete && !_choiceInProgress
                ? widget.onCompleteSetup
                : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              backgroundColor: AppColors.indigo,
            ),
            icon: const Icon(Icons.play_circle_outline_rounded),
            label: const Text('Hoàn tất và bắt đầu phiên học'),
          ),
          if (!_canComplete && !widget.limitedModeSelected) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              'Hãy hoàn tất H20 hoặc chọn mic điện thoại để tiếp tục.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _grantConsentAndContinue() async {
    await widget.onGrantPrivacyConsent();
    if (mounted && widget.privacyConfigurationComplete) {
      setState(() => _step = _ParentSetupStep.profile);
    }
  }

  Future<void> _chooseLimitedMode() async {
    await widget.onContinueWithoutVoice();
    if (mounted) {
      setState(() => _step = _ParentSetupStep.profile);
    }
  }

  Future<void> _setupH20() async {
    setState(() {
      _choiceInProgress = true;
      _h20SetupRequested = true;
      _phoneMicrophoneSelected = false;
    });
    try {
      await widget.onSetupH20();
    } finally {
      if (mounted) setState(() => _choiceInProgress = false);
    }
  }

  Future<void> _selectPhoneMicrophone() async {
    setState(() {
      _choiceInProgress = true;
      _h20SetupRequested = false;
    });
    try {
      await widget.onUsePhoneMicrophone();
      if (mounted && widget.microphoneGranted) {
        setState(() => _phoneMicrophoneSelected = true);
      }
    } finally {
      if (mounted) setState(() => _choiceInProgress = false);
    }
  }

  void _goNext() {
    if (_step.index < _ParentSetupStep.values.length - 1) {
      setState(() => _step = _ParentSetupStep.values[_step.index + 1]);
    }
  }

  void _goBack() {
    if (_step.index > 0) {
      setState(() => _step = _ParentSetupStep.values[_step.index - 1]);
    }
  }

  Future<void> _openLegalPage(Uri? uri, String label) async {
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label chưa được cấu hình cho bản build này.')),
      );
      return;
    }
    if (!await showParentalGate(context) || !mounted) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể mở $label.')));
    }
  }
}

class _SetupHeader extends StatelessWidget {
  const _SetupHeader({
    required this.stepNumber,
    required this.totalSteps,
    required this.canGoBack,
    required this.onBack,
  });

  final int stepNumber;
  final int totalSteps;
  final bool canGoBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 22, 8),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox.square(
                dimension: 48,
                child: canGoBack
                    ? IconButton(
                        key: const Key('startup-back'),
                        onPressed: onBack,
                        tooltip: 'Quay lại',
                        icon: const Icon(Icons.arrow_back_rounded),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(4),
                        child: Image.asset(MascotAssets.avatar),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Thiết lập HOMI',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.indigoDark,
                      ),
                    ),
                    Text(
                      'Bước $stepNumber/$totalSteps • Dành cho phụ huynh',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: stepNumber / totalSteps,
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
          ),
        ],
      ),
    );
  }
}

class _PrimaryNextButton extends StatelessWidget {
  const _PrimaryNextButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      key: const Key('startup-next'),
      onPressed: onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
      icon: const Icon(Icons.arrow_forward_rounded),
      label: const Text('Tiếp tục'),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 34, color: AppColors.indigo),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceChoiceCard extends StatelessWidget {
  const _DeviceChoiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.status,
    required this.actionKey,
    required this.actionLabel,
    required this.busy,
    required this.onPressed,
    super.key,
  });
  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final String status;
  final Key actionKey;
  final String actionLabel;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.successSoft
            : theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? AppColors.success
              : theme.colorScheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                icon,
                color: selected ? AppColors.success : AppColors.indigo,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(description),
          const SizedBox(height: 8),
          Text(
            status,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: selected
                  ? AppColors.success
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: actionKey,
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Icon(selected ? Icons.check_rounded : icon),
              label: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
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

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(color: theme.colorScheme.onErrorContainer),
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
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(16),
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

class _LegalButton extends StatelessWidget {
  const _LegalButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
