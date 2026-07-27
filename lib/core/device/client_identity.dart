import 'package:flutter/foundation.dart';

import 'platform_client_identity.dart';

class ClientIdentity {
  Future<String>? _clientId;

  Future<String> getClientId() => _clientId ??= _loadClientId();

  Future<String> _loadClientId() async {
    final clientId = await loadPlatformClientId();
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
