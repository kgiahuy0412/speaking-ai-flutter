import 'dart:convert';

import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/device/android_device_hardware.dart';
import 'package:ai_speaking_flutter_app/core/device/device_registration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const hardware = AndroidDeviceHardware(
    manufacturer: 'Google',
    brand: 'google',
    model: 'Pixel 8',
    androidVersion: '15',
    sdkInt: 35,
    supportedAbis: <String>['arm64-v8a'],
    socManufacturer: 'Google',
    socModel: 'Tensor G3',
    totalRamBytes: 8589934592,
    availableRamBytes: 3221225472,
    totalStorageBytes: 128000000000,
    availableStorageBytes: 64000000000,
  );

  test('posts the current device identity and hardware', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response('{}', 200);
    });
    final service = DeviceRegistrationService(
      config: AppConfig(
        backendBaseUri: Uri.https('api.example.com'),
        useDemoBackend: false,
        childAge: 6,
      ),
      clientIdProvider: () async => 'android_7396019906ad3574',
      hardwareProvider: () async => hardware,
      client: client,
    );

    await service.register();

    expect(
      captured.url.toString(),
      'https://api.example.com/api/devices/register',
    );
    expect(captured.headers['content-type'], 'application/json');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['clientId'], 'android_7396019906ad3574');
    expect((body['device'] as Map<String, dynamic>)['model'], 'Pixel 8');
    service.dispose();
  });

  test('throws when the backend rejects registration', () async {
    final service = DeviceRegistrationService(
      config: AppConfig(
        backendBaseUri: Uri.https('api.example.com'),
        useDemoBackend: false,
        childAge: 6,
      ),
      clientIdProvider: () async => 'android_7396019906ad3574',
      hardwareProvider: () async => hardware,
      client: MockClient((request) async => http.Response('{}', 400)),
    );

    await expectLater(service.register(), throwsStateError);
    service.dispose();
  });
}
