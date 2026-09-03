import 'dart:convert';

import 'package:flutter/services.dart';

import 'installation_credentials.dart';

class InstallationCredentialStore {
  const InstallationCredentialStore();

  static const MethodChannel _channel = MethodChannel('ailingo_platform');

  Future<InstallationCredentials?> read() async {
    final encoded = await _channel.invokeMethod<String>(
      'auth.credentials.read',
    );
    if (encoded == null || encoded.trim().isEmpty) {
      return null;
    }
    try {
      return InstallationCredentials.fromJson(jsonDecode(encoded));
    } on FormatException {
      await clear();
      return null;
    }
  }

  Future<void> write(InstallationCredentials credentials) async {
    final stored = await _channel.invokeMethod<bool>(
      'auth.credentials.write',
      jsonEncode(credentials.toJson()),
    );
    if (stored != true) {
      throw StateError('Không lưu được installation credential an toàn.');
    }
  }

  Future<void> clear() async {
    final cleared = await _channel.invokeMethod<bool>('auth.credentials.clear');
    if (cleared != true) {
      throw StateError('Không xóa được installation credential an toàn.');
    }
  }
}
