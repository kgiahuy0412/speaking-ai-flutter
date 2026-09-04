import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import 'installation_auth_session.dart';

class InstallationAuthenticatedClient extends http.BaseClient {
  InstallationAuthenticatedClient({
    required AppConfig config,
    required Future<String> Function() clientIdProvider,
    Future<void> Function()? clientIdResetter,
    http.Client? inner,
    InstallationAuthSession? session,
  }) : _config = config,
       _inner = inner ?? http.Client(),
       _session =
           session ??
           InstallationAuthRegistry.session(
             config: config,
             clientIdProvider: clientIdProvider,
             clientIdResetter: clientIdResetter,
           );

  final AppConfig _config;
  final http.Client _inner;
  final InstallationAuthSession _session;

  /// Ensures an installation credential is valid before a caller serializes
  /// a request body containing its client id. A registration conflict can
  /// rotate the native id, so this must happen before that id is read.
  Future<void> ensureAuthenticated() => _session.accessToken();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var attachedInstallationToken = false;
    if (_isBackendRequest(request.url) &&
        !request.headers.containsKey('authorization')) {
      request.headers['authorization'] =
          'Bearer ${await _session.accessToken()}';
      attachedInstallationToken = true;
    }
    final response = await _inner.send(request);
    if (attachedInstallationToken && response.statusCode == 401) {
      await _session.invalidateAccessToken();
    }
    return response;
  }

  bool _isBackendRequest(Uri uri) =>
      uri.scheme == _config.backendBaseUri.scheme &&
      uri.host == _config.backendBaseUri.host &&
      uri.port == _config.backendBaseUri.port;

  @override
  void close() {
    _inner.close();
  }
}
