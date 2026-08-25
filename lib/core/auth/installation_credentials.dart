class InstallationCredentials {
  const InstallationCredentials({
    required this.clientId,
    required this.installationSecret,
    this.accessToken,
    this.accessTokenExpiresAt,
    this.refreshToken,
    this.refreshTokenExpiresAt,
  });

  final String clientId;
  final String installationSecret;
  final String? accessToken;
  final DateTime? accessTokenExpiresAt;
  final String? refreshToken;
  final DateTime? refreshTokenExpiresAt;

  bool get hasUsableAccessToken {
    final token = accessToken?.trim();
    final expiresAt = accessTokenExpiresAt;
    return token != null &&
        token.isNotEmpty &&
        expiresAt != null &&
        expiresAt.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 1)),
        );
  }

  bool get hasUsableRefreshToken {
    final token = refreshToken?.trim();
    final expiresAt = refreshTokenExpiresAt;
    return token != null &&
        token.isNotEmpty &&
        expiresAt != null &&
        expiresAt.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 5)),
        );
  }

  InstallationCredentials withoutAccessToken() => InstallationCredentials(
    clientId: clientId,
    installationSecret: installationSecret,
    refreshToken: refreshToken,
    refreshTokenExpiresAt: refreshTokenExpiresAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'clientId': clientId,
    'installationSecret': installationSecret,
    if (accessToken != null) 'accessToken': accessToken,
    if (accessTokenExpiresAt != null)
      'accessTokenExpiresAt': accessTokenExpiresAt!.toUtc().toIso8601String(),
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (refreshTokenExpiresAt != null)
      'refreshTokenExpiresAt': refreshTokenExpiresAt!.toUtc().toIso8601String(),
  };

  static InstallationCredentials? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final clientId = value['clientId'];
    final installationSecret = value['installationSecret'];
    if (clientId is! String ||
        clientId.trim().isEmpty ||
        installationSecret is! String ||
        installationSecret.trim().isEmpty) {
      return null;
    }
    return InstallationCredentials(
      clientId: clientId.trim(),
      installationSecret: installationSecret.trim(),
      accessToken: _stringOrNull(value['accessToken']),
      accessTokenExpiresAt: _dateOrNull(value['accessTokenExpiresAt']),
      refreshToken: _stringOrNull(value['refreshToken']),
      refreshTokenExpiresAt: _dateOrNull(value['refreshTokenExpiresAt']),
    );
  }

  static String? _stringOrNull(Object? value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _dateOrNull(Object? value) {
    return value is String ? DateTime.tryParse(value)?.toUtc() : null;
  }
}
