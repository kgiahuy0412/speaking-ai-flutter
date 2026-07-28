import 'package:ai_speaking_flutter_app/core/device/android_device_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Android hardware returned by the platform channel', () {
    final hardware = AndroidDeviceHardware.fromPlatformMap(<Object?, Object?>{
      'manufacturer': 'samsung',
      'brand': 'samsung',
      'model': 'SM-S918B',
      'androidVersion': '14',
      'sdkInt': 34,
      'supportedAbis': <String>['arm64-v8a', 'armeabi-v7a'],
      'socManufacturer': 'Qualcomm',
      'socModel': 'SM8550',
      'totalRamBytes': 12884901888,
      'availableRamBytes': 5368709120,
      'totalStorageBytes': 256000000000,
      'availableStorageBytes': 74000000000,
    });

    expect(hardware.model, 'SM-S918B');
    expect(hardware.androidVersion, '14');
    expect(hardware.supportedAbis, <String>['arm64-v8a', 'armeabi-v7a']);
    expect(hardware.toJson()['totalRamBytes'], 12884901888);
  });

  test('rejects a platform response without ABIs', () {
    expect(
      () => AndroidDeviceHardware.fromPlatformMap(<Object?, Object?>{
        'manufacturer': 'samsung',
        'brand': 'samsung',
        'model': 'SM-S918B',
        'androidVersion': '14',
        'sdkInt': 34,
        'supportedAbis': <String>[],
        'totalRamBytes': 12884901888,
        'availableRamBytes': 5368709120,
        'totalStorageBytes': 256000000000,
        'availableStorageBytes': 74000000000,
      }),
      throwsFormatException,
    );
  });
}
