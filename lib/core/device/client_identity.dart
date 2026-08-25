import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_client_identity.dart';

class ClientIdentity {
  Future<String>? _clientId;

  Future<String> getClientId() => _clientId ??= _loadClientId();

  Future<void> resetClientId() async {
    try {
      await resetPlatformClientId();
    } on MissingPluginException {
      // Unsupported desktop test runners do not expose a platform identity.
    } on PlatformException catch (error) {
      if (error.code != 'unimplemented') {
        rethrow;
      }
    } finally {
      _clientId = null;
    }
  }

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
