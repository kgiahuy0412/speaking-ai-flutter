import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ClientIdentity {
  static const MethodChannel _channel = MethodChannel('ailingo_platform');

  Future<String>? _clientId;

  Future<String> getClientId() => _clientId ??= _loadClientId();

  Future<String> _loadClientId() async {
    final clientId = await _channel.invokeMethod<String>('device.clientId');
    final normalized = clientId?.trim();

    if (normalized == null || normalized.isEmpty) {
      throw StateError('Không thể xác định thiết bị hiện tại.');
    }

    if (kDebugMode) {
      debugPrint('Adaptive learning client: $normalized');
    }

    return normalized;
  }
}
