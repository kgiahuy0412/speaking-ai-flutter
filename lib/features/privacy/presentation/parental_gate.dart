import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../../l10n/display_language.dart';

/// Provides device-owner authentication for the parental area.
abstract interface class ParentalGateAuthenticator {
  Future<bool> isSupported();

  Future<bool> authenticate({required String localizedReason});
}

class DeviceParentalGateAuthenticator implements ParentalGateAuthenticator {
  DeviceParentalGateAuthenticator({LocalAuthentication? localAuthentication})
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  @override
  Future<bool> isSupported() => _localAuthentication.isDeviceSupported();

  @override
  Future<bool> authenticate({required String localizedReason}) {
    return _localAuthentication.authenticate(
      localizedReason: localizedReason,
      biometricOnly: false,
      sensitiveTransaction: true,
      persistAcrossBackgrounding: false,
    );
  }
}

/// Keeps a successful parental unlock briefly, and locks immediately whenever
/// the application leaves the foreground.
class ParentalGateSession with WidgetsBindingObserver {
  ParentalGateSession({
    this.unlockDuration = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration unlockDuration;
  final DateTime Function() _now;

  DateTime? _unlockedUntil;
  bool _isObserving = false;

  bool get isUnlocked {
    final unlockedUntil = _unlockedUntil;
    return unlockedUntil != null && _now().isBefore(unlockedUntil);
  }

  void unlock() {
    _unlockedUntil = _now().add(unlockDuration);
    if (!_isObserving) {
      WidgetsBinding.instance.addObserver(this);
      _isObserving = true;
    }
  }

  void lock() {
    _unlockedUntil = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      lock();
    }
  }

  @visibleForTesting
  void dispose() {
    if (_isObserving) {
      WidgetsBinding.instance.removeObserver(this);
      _isObserving = false;
    }
    lock();
  }
}

final ParentalGateSession _defaultParentalGateSession = ParentalGateSession();

/// Protects parent-only settings without replacing the separate first-run
/// consent flow. Biometrics are preferred and the device passcode/PIN remains
/// available through the operating system.
Future<bool> showParentalGate(
  BuildContext context, {
  ParentalGateAuthenticator? authenticator,
  ParentalGateSession? session,
}) async {
  final activeSession = session ?? _defaultParentalGateSession;
  if (activeSession.isUnlocked) {
    return true;
  }

  if (kIsWeb) {
    final approved = await _showWebParentConfirmation(context);
    if (approved) {
      activeSession.unlock();
    }
    return approved;
  }

  final activeAuthenticator =
      authenticator ?? DeviceParentalGateAuthenticator();

  try {
    if (!await activeAuthenticator.isSupported()) {
      if (context.mounted) {
        await _showAuthenticationUnavailable(context);
      }
      return false;
    }

    if (!context.mounted) {
      return false;
    }

    final approved = await activeAuthenticator.authenticate(
      localizedReason: context.tr(
        'Xác thực để mở khu vực dành cho phụ huynh',
        '验证身份以进入家长专区',
      ),
    );
    if (approved) {
      activeSession.unlock();
    }
    return approved;
  } catch (_) {
    if (context.mounted) {
      await _showAuthenticationError(context);
    }
    return false;
  }
}

Future<bool> _showWebParentConfirmation(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('Khu vực dành cho phụ huynh', '家长专区')),
          content: Text(
            context.tr(
              'Khu vực này dùng để quản lý nhóm tuổi, thiết bị, quyền riêng tư và dữ liệu. Vui lòng xác nhận bạn là phụ huynh, người giám hộ hoặc giáo viên.',
              '此区域用于管理年龄组、设备、隐私和数据。请确认您是家长、监护人或教师。',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.tr('Hủy', '取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(context.tr('Tôi là phụ huynh/giáo viên', '我是家长/教师')),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> _showAuthenticationUnavailable(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('parental-auth-unavailable-dialog'),
      title: Text(context.tr('Cần khóa màn hình', '需要设置屏幕锁定')),
      content: Text(
        context.tr(
          'Hãy thiết lập Face ID, Touch ID/vân tay hoặc mật mã/PIN của thiết bị, sau đó thử lại để mở khu vực phụ huynh.',
          '请先设置面容 ID、触控 ID/指纹或设备密码/PIN，然后重试以进入家长专区。',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(context.tr('Đóng', '关闭')),
        ),
      ],
    ),
  );
}

Future<void> _showAuthenticationError(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('parental-auth-error-dialog'),
      title: Text(context.tr('Không thể xác thực', '无法验证身份')),
      content: Text(
        context.tr(
          'HOMI chưa thể xác thực bằng Face ID, Touch ID/vân tay hoặc mật mã thiết bị. Vui lòng thử lại.',
          'HOMI 暂时无法通过面容 ID、触控 ID/指纹或设备密码验证身份。请重试。',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(context.tr('Đóng', '关闭')),
        ),
      ],
    ),
  );
}
