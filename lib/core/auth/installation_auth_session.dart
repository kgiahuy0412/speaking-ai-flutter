import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import 'installation_credential_store.dart';
import 'installation_credentials.dart';

class InstallationAuthException implements Exception {
  const InstallationAuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class InstallationAuthSession {
  InstallationAuthSession({
    required AppConfig config,
    required Future<String> Function() clientIdProvider,
    Future<void> Function()? clientIdResetter,
    InstallationCredentialStore store = const InstallationCredentialStore(),
    http.Client? transport,
  }) : _config = config,
       _clientIdProvider = clientIdProvider,
       _clientIdResetter = clientIdResetter,
       _store = store,
       _transport = transport ?? http.Client();

  final AppConfig _config;
  final Future<String> Function() _clientIdProvider;
  Future<void> Function()? _clientIdResetter;
  final InstallationCredentialStore _store;
  final http.Client _transport;

  InstallationCredentials? _credentials;
  Future<InstallationCredentials>? _authenticationInFlight;

  void attachClientIdResetter(Future<void> Function()? resetter) {
    if (resetter != null) {
      _clientIdResetter ??= resetter;
    }
  }

  Future<String> accessToken() async {
    final credentials = await _ensureAuthenticated();
    return credentials.accessToken!;
  }

  Future<void> invalidateAccessToken() async {
    final current = _credentials ?? await _store.read();
    if (current == null) return;
    final invalidated = current.withoutAccessToken();
    _credentials = invalidated;
    await _store.write(invalidated);
  }

  Future<void> revoke() async {
    try {
      final current = _credentials ?? await _store.read();
      if (current != null) {
        try {
          final token = await accessToken();
          await _transport
              .delete(
                _config.resolve('/api/installations/revoke'),
                headers: <String, String>{'authorization': 'Bearer $token'},
              )
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          // Consent withdrawal must still clear the local credential even when
          // the network is unavailable. The access token expires quickly.
        }
      }
    } finally {
      _credentials = null;
      await _store.clear();
    }
  }

  Future<InstallationCredentials> _ensureAuthenticated() {
    final current = _authenticationInFlight;
    if (current != null) return current;
    final future = _authenticate();
    _authenticationInFlight = future;
    return future.whenComplete(() {
      if (identical(_authenticationInFlight, future)) {
        _authenticationInFlight = null;
      }
    });
  }

  Future<InstallationCredentials> _authenticate() async {
    final clientId = await _clientIdProvider();
    var current = _credentials ?? await _store.read();
    if (current != null && current.clientId != clientId) {
      await _store.clear();
      current = null;
    }
    if (current?.hasUsableAccessToken == true) {
      _credentials = current;
      return current!;
    }
    if (current?.hasUsableRefreshToken == true) {
      try {
        return await _refresh(current!);
      } on InstallationAuthException catch (error) {
        if (error.statusCode != 401 && error.statusCode != 404) rethrow;
      }
    }
    final installationSecret = current?.installationSecret ?? _createSecret();
    try {
      return await _register(clientId, installationSecret);
    } on InstallationAuthException catch (error) {
      final resetter = _clientIdResetter;
      if (error.statusCode != 409 || resetter == null) rethrow;
      // A previous app install can leave a server record after the local app
      // data/Keystore entry was removed. Retry once for a concurrent register,
      // then rotate the public client reference instead of taking ownership by
      // clientId alone.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      try {
        return await _register(clientId, installationSecret);
      } on InstallationAuthException catch (retryError) {
        if (retryError.statusCode != 409) rethrow;
      }
      await resetter();
      await _store.clear();
      final rotatedClientId = await _clientIdProvider();
      return _register(rotatedClientId, _createSecret());
    }
  }

  Future<InstallationCredentials> _register(
    String clientId,
    String installationSecret,
  ) async {
    final response = await _transport
        .post(
          _config.resolve('/api/installations/register'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, Object>{
            'clientId': clientId,
            'platform': _platform,
            'installationSecret': installationSecret,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _saveSessionResponse(
      response,
      clientId: clientId,
      installationSecret: installationSecret,
    );
  }

  Future<InstallationCredentials> _refresh(
    InstallationCredentials current,
  ) async {
    final response = await _transport
        .post(
          _config.resolve('/api/installations/refresh'),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, String>{
            'refreshToken': current.refreshToken!,
          }),
        )
        .timeout(const Duration(seconds: 15));
    return _saveSessionResponse(
      response,
      clientId: current.clientId,
      installationSecret: current.installationSecret,
    );
  }

  Future<InstallationCredentials> _saveSessionResponse(
    http.Response response, {
    required String clientId,
    required String installationSecret,
  }) async {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw InstallationAuthException(
        'Máy chủ trả về phiên xác thực không hợp lệ.',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
      final message = error is Map<String, dynamic> ? error['message'] : null;
      throw InstallationAuthException(
        message is String && message.trim().isNotEmpty
            ? message
            : 'Không xác thực được installation HOMI.',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const InstallationAuthException(
        'Máy chủ trả về phiên xác thực không hợp lệ.',
      );
    }
    final accessToken = decoded['accessToken'];
    final refreshToken = decoded['refreshToken'];
    final accessExpiresAt = decoded['accessTokenExpiresAt'];
    final refreshExpiresAt = decoded['refreshTokenExpiresAt'];
    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty ||
        accessExpiresAt is! String ||
        refreshExpiresAt is! String) {
      throw const InstallationAuthException(
        'Máy chủ trả về phiên xác thực không đầy đủ.',
      );
    }
    final credentials = InstallationCredentials(
      clientId: clientId,
      installationSecret: installationSecret,
      accessToken: accessToken,
      accessTokenExpiresAt: DateTime.parse(accessExpiresAt).toUtc(),
      refreshToken: refreshToken,
      refreshTokenExpiresAt: DateTime.parse(refreshExpiresAt).toUtc(),
    );
    _credentials = credentials;
    await _store.write(credentials);
    return credentials;
  }

  static String _createSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'web',
    };
  }
}

class InstallationAuthRegistry {
  InstallationAuthRegistry._();

  static final Map<String, InstallationAuthSession> _sessions =
      <String, InstallationAuthSession>{};

  static InstallationAuthSession session({
    required AppConfig config,
    required Future<String> Function() clientIdProvider,
    Future<void> Function()? clientIdResetter,
  }) {
    final session = _sessions.putIfAbsent(
      config.backendBaseUri.toString(),
      () => InstallationAuthSession(
        config: config,
        clientIdProvider: clientIdProvider,
        clientIdResetter: clientIdResetter,
      ),
    );
    session.attachClientIdResetter(clientIdResetter);
    return session;
  }

  static Future<void> revoke({
    required AppConfig config,
    required Future<String> Function() clientIdProvider,
  }) async {
    final key = config.backendBaseUri.toString();
    final session =
        _sessions.remove(key) ??
        InstallationAuthSession(
          config: config,
          clientIdProvider: clientIdProvider,
        );
    await session.revoke();
  }
}
