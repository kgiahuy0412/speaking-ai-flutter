import 'dart:convert';

import 'package:web/web.dart' as web;

import 'installation_credentials.dart';

class InstallationCredentialStore {
  const InstallationCredentialStore();

  static const _key = 'homi.installation-auth.v1';

  Future<InstallationCredentials?> read() async {
    final encoded = web.window.localStorage.getItem(_key);
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
    web.window.localStorage.setItem(_key, jsonEncode(credentials.toJson()));
  }

  Future<void> clear() async {
    web.window.localStorage.removeItem(_key);
  }
}
