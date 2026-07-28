import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import 'android_device_hardware.dart';

typedef ClientIdProvider = Future<String> Function();
typedef AndroidHardwareProvider = Future<AndroidDeviceHardware> Function();

class DeviceRegistrationService {
  DeviceRegistrationService({
    required AppConfig config,
    required ClientIdProvider clientIdProvider,
    required AndroidHardwareProvider hardwareProvider,
    http.Client? client,
  }) : _config = config,
       _clientIdProvider = clientIdProvider,
       _hardwareProvider = hardwareProvider,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final AppConfig _config;
  final ClientIdProvider _clientIdProvider;
  final AndroidHardwareProvider _hardwareProvider;
  final http.Client _client;
  final bool _ownsClient;

  Future<void> register() async {
    final clientId = await _clientIdProvider();
    final hardware = await _hardwareProvider();
    final response = await _client
        .post(
          _config.resolve('/api/devices/register'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(<String, Object>{
            'clientId': clientId,
            'device': hardware.toJson(),
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Device registration failed with HTTP ${response.statusCode}.',
      );
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
