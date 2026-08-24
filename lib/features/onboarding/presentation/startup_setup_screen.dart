import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_theme.dart';
import '../../../app/learning_scenery.dart';
import '../../../app/mascot_assets.dart';
import '../../listening/domain/listening_catalog.dart';

enum _ParentSetupStep { privacy, profile, permissions }

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
  final ValueChanged<int> onAgeSelected;
  final Future<void> Function() onCompleteSetup;
  final String? permissionError;

  @override
  State<StartupSetupScreen> createState() => _StartupSetupScreenState();
}

class _StartupSetupScreenState extends State<StartupSetupScreen> {
  _ParentSetupStep _step = _ParentSetupStep.privacy;
  late bool _adultRoleConfirmed;
  late bool _legalReviewCompleted;
  late bool _voiceDataAccepted;
  bool _h20SetupRequested = false;
  bool _choiceInProgress = false;

  bool get _privacyChoiceMade =>
      widget.privacyConsentGranted || widget.limitedModeSelected;

  bool get _h20Ready => widget.h20BleConnected && widget.h20HfpConfigured;

  bool get _canComplete =>
      widget.limitedModeSelected || widget.microphoneGranted;

  @override
  void initState() {
    super.initState();
    _adultRoleConfirmed = widget.privacyConsentGranted;
    _legalReviewCompleted = widget.privacyConsentGranted;
    _voiceDataAccepted = widget.privacyConsentGranted;
  }

  @override
  void didUpdateWidget(StartupSetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.privacyConsentGranted && widget.privacyConsentGranted) {
      _adultRoleConfirmed = true;
      _legalReviewCompleted = true;
      _voiceDataAccepted = true;
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
      subtitle: 'Phụ huynh hoặc giáo viên thiết lập phiên học tại đây.',
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
          ),
          const Divider(height: 24),
          TextButton.icon(
            key: const Key('startup-review-legal'),
            onPressed: _showLegalReview,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
            icon: Icon(
              _legalReviewCompleted
                  ? Icons.check_circle_rounded
                  : Icons.description_outlined,
              color: _legalReviewCompleted ? AppColors.success : null,
            ),
            label: Text(
              _legalReviewCompleted
                  ? 'Đã đọc Điều khoản và Chính sách quyền riêng tư'
                  : 'Đọc Điều khoản và Chính sách quyền riêng tư',
              style: const TextStyle(decoration: TextDecoration.underline),
            ),
          ),
          CheckboxListTile(
            key: const Key('startup-accept-legal'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _voiceDataAccepted,
            onChanged:
                !_legalReviewCompleted ||
                    widget.profileLoading ||
                    widget.privacyConsentGranted
                ? null
                : (value) =>
                      setState(() => _voiceDataAccepted = value ?? false),
            title: const Text(
              'Tôi đồng ý cho HOMI xử lý dữ liệu giọng nói cần thiết cho phiên học',
            ),
            subtitle: !_legalReviewCompleted
                ? const Text('Đọc hết nội dung trên để mở lựa chọn này.')
                : null,
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
                      !_legalReviewCompleted ||
                      !_voiceDataAccepted ||
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
              onPressed:
                  !_adultRoleConfirmed ||
                      !_legalReviewCompleted ||
                      widget.profileLoading
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
      icon: Icons.bluetooth_audio_rounded,
      title: 'Cấp quyền và kết nối thiết bị',
      subtitle: widget.limitedModeSelected
          ? 'Chế độ không giọng nói không cần quyền micro hoặc Bluetooth.'
          : 'HOMI ưu tiên thiết bị đã kết nối và dùng micro điện thoại khi chưa có thiết bị.',
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
                label: 'Bluetooth',
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
            const SizedBox(height: 16),
            _DeviceChoiceCard(
              key: const Key('startup-h20-choice'),
              icon: Icons.bluetooth_audio_rounded,
              title: 'Kết nối thiết bị (tùy chọn)',
              description:
                  'Bật thiết bị và Bluetooth trên điện thoại, sau đó nhấn nút bên dưới. HOMI sẽ tự kiểm tra kết nối.',
              selected: _h20Ready,
              status: _h20Ready
                  ? 'Đã kết nối và sẵn sàng'
                  : widget.h20HfpConfigured || widget.h20BleConnected
                  ? 'Đang hoàn tất kết nối…'
                  : _h20SetupRequested
                  ? 'Chưa kết nối • kiểm tra thiết bị đã bật và ở gần'
                  : 'Chưa kết nối • có thể thực hiện ngay hoặc để sau',
              actionKey: const Key('startup-setup-h20'),
              actionLabel: _h20Ready ? 'Đã kết nối' : 'Kết nối thiết bị',
              busy: _choiceInProgress,
              onPressed: _choiceInProgress || _h20Ready ? null : _setupH20,
            ),
            if (widget.microphoneGranted && !_h20Ready) ...<Widget>[
              const SizedBox(height: 12),
              const _InfoBox(
                icon: Icons.phone_iphone_rounded,
                text:
                    'HOMI sẽ dùng micro điện thoại cho đến khi thiết bị kết nối xong.',
              ),
            ],
          ],
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
          if (!_canComplete) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              'Cần cấp quyền micro để tiếp tục, hoặc quay lại chọn chế độ không dùng giọng nói.',
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
    });
    try {
      await widget.onSetupH20();
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

  Future<void> _showLegalReview() async {
    final reviewed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      builder: (context) => _LegalReviewSheet(
        aiSubprocessors: widget.aiSubprocessors,
        dataRetentionSummary: widget.dataRetentionSummary,
        privacyPolicyUri: widget.privacyPolicyUri,
        termsUri: widget.termsUri,
        supportUri: widget.supportUri,
        onOpenPrivacyPolicy: () => _openLegalPage(
          widget.privacyPolicyUri,
          'Chính sách quyền riêng tư',
        ),
        onOpenTerms: () =>
            _openLegalPage(widget.termsUri, 'Điều khoản sử dụng'),
        onOpenSupport: () => _openLegalPage(widget.supportUri, 'Hỗ trợ'),
      ),
    );
    if (reviewed == true && mounted) {
      setState(() => _legalReviewCompleted = true);
    }
  }

  Future<void> _openLegalPage(Uri? uri, String label) async {
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label chưa được cấu hình cho bản build này.')),
      );
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể mở $label.')));
    }
  }
}

class _LegalReviewSheet extends StatefulWidget {
  const _LegalReviewSheet({
    required this.aiSubprocessors,
    required this.dataRetentionSummary,
    required this.privacyPolicyUri,
    required this.termsUri,
    required this.supportUri,
    required this.onOpenPrivacyPolicy,
    required this.onOpenTerms,
    required this.onOpenSupport,
  });

  final String aiSubprocessors;
  final String dataRetentionSummary;
  final Uri? privacyPolicyUri;
  final Uri? termsUri;
  final Uri? supportUri;
  final VoidCallback onOpenPrivacyPolicy;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenSupport;

  @override
  State<_LegalReviewSheet> createState() => _LegalReviewSheetState();
}

class _LegalReviewSheetState extends State<_LegalReviewSheet> {
  final ScrollController _scrollController = ScrollController();
  bool _reachedEnd = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateReachedEnd);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateReachedEnd());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateReachedEnd)
      ..dispose();
    super.dispose();
  }

  void _updateReachedEnd() {
    if (!_scrollController.hasClients || _reachedEnd) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0 || position.extentAfter <= 20) {
      setState(() => _reachedEnd = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.9;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Điều khoản và quyền riêng tư',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.indigoDark,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('startup-close-legal'),
                  onPressed: () => Navigator.of(context).pop(false),
                  tooltip: 'Đóng',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: const Key('startup-legal-scroll'),
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Thông tin phụ huynh cần biết',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'HOMI chỉ bắt đầu xử lý dữ liệu giọng nói sau khi phụ huynh chủ động đồng ý và cấp quyền micro.',
                    ),
                    const SizedBox(height: 20),
                    const _LegalSection(
                      icon: Icons.graphic_eq_rounded,
                      title: 'Dữ liệu được xử lý',
                      text:
                          'Giọng nói/audio khi dùng tính năng nói; nội dung đã nhận dạng; nhóm tuổi đã chọn; lịch sử tương tác; mã cài đặt và chẩn đoán kỹ thuật cần thiết để vận hành bài học.',
                    ),
                    const SizedBox(height: 18),
                    const _LegalSection(
                      icon: Icons.school_outlined,
                      title: 'Mục đích sử dụng',
                      text:
                          'Nhận dạng lời nói, dịch nội dung, tạo phản hồi và giọng đọc, lưu tiến trình học, khắc phục lỗi và bảo vệ dịch vụ.',
                    ),
                    const SizedBox(height: 18),
                    _LegalSection(
                      icon: Icons.cloud_outlined,
                      title: 'Nơi dữ liệu được gửi tới',
                      text:
                          'Dữ liệu cần thiết có thể được gửi tới ${widget.aiSubprocessors} để cung cấp và vận hành các tính năng đã mô tả ở trên.',
                    ),
                    const SizedBox(height: 18),
                    _LegalSection(
                      icon: Icons.schedule_rounded,
                      title: 'Lưu trữ, xóa và rút lại chấp thuận',
                      text:
                          '${widget.dataRetentionSummary} Phụ huynh có thể rút lại chấp thuận hoặc yêu cầu xóa dữ liệu trong phần Cài đặt/Hỗ trợ.',
                    ),
                    const SizedBox(height: 18),
                    const _LegalSection(
                      icon: Icons.mic_off_outlined,
                      title: 'Quyền lựa chọn',
                      text:
                          'Có thể tiếp tục ở chế độ không dùng giọng nói. Khi đó HOMI không yêu cầu quyền micro và các tính năng cần nói sẽ không hoạt động.',
                    ),
                    const SizedBox(height: 22),
                    Text('Tài liệu đầy đủ', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    _LegalDocumentLink(
                      key: const Key('startup-open-privacy-policy'),
                      label: 'Chính sách quyền riêng tư',
                      available: widget.privacyPolicyUri != null,
                      onPressed: widget.onOpenPrivacyPolicy,
                    ),
                    _LegalDocumentLink(
                      key: const Key('startup-open-terms'),
                      label: 'Điều khoản sử dụng',
                      available: widget.termsUri != null,
                      onPressed: widget.onOpenTerms,
                    ),
                    _LegalDocumentLink(
                      key: const Key('startup-open-support'),
                      label: 'Hỗ trợ và yêu cầu xóa dữ liệu',
                      available: widget.supportUri != null,
                      onPressed: widget.onOpenSupport,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Bằng việc tiếp tục, phụ huynh xác nhận đã hiểu nội dung trên. Việc đồng ý xử lý dữ liệu giọng nói vẫn được thực hiện bằng một lựa chọn riêng ở màn hình trước.',
                    ),
                    const SizedBox(
                      key: Key('startup-legal-end-marker'),
                      height: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (!_reachedEnd)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Cuộn đến cuối nội dung để xác nhận đã đọc.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    FilledButton.icon(
                      key: const Key('startup-legal-reviewed'),
                      onPressed: _reachedEnd
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: Text(
                        _reachedEnd ? 'Tôi đã đọc hết' : 'Đọc hết để tiếp tục',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 23, color: AppColors.indigo),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(text),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegalDocumentLink extends StatelessWidget {
  const _LegalDocumentLink({
    required this.label,
    required this.available,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool available;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      child: Text(
        available ? label : '$label (chưa cấu hình)',
        style: const TextStyle(decoration: TextDecoration.underline),
      ),
    );
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
