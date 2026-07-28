import 'package:flutter/services.dart';

class AndroidDeviceHardware {
  const AndroidDeviceHardware({
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.androidVersion,
    required this.sdkInt,
    required this.supportedAbis,
    required this.totalRamBytes,
    required this.availableRamBytes,
    required this.totalStorageBytes,
    required this.availableStorageBytes,
    this.socManufacturer,
    this.socModel,
  });

  factory AndroidDeviceHardware.fromPlatformMap(Map<Object?, Object?> value) {
    String requiredText(String key) {
      final raw = value[key];
      if (raw is! String || raw.trim().isEmpty) {
        throw FormatException('Missing Android device field: $key');
      }
      return raw.trim();
    }

    String? optionalText(String key) {
      final raw = value[key];
      if (raw == null) {
        return null;
      }
      if (raw is! String) {
        throw FormatException('Invalid Android device field: $key');
      }
      final normalized = raw.trim();
      return normalized.isEmpty ? null : normalized;
    }

    int requiredInteger(String key) {
      final raw = value[key];
      if (raw is! int || raw < 0) {
        throw FormatException('Invalid Android device field: $key');
      }
      return raw;
    }

    final rawAbis = value['supportedAbis'];
    if (rawAbis is! List || rawAbis.isEmpty) {
      throw const FormatException(
        'Missing Android device field: supportedAbis',
      );
    }
    final abis = rawAbis
        .map((value) {
          if (value is! String || value.trim().isEmpty) {
            throw const FormatException(
              'Invalid Android device field: supportedAbis',
            );
          }
          return value.trim();
        })
        .toList(growable: false);

    return AndroidDeviceHardware(
      manufacturer: requiredText('manufacturer'),
      brand: requiredText('brand'),
      model: requiredText('model'),
      androidVersion: requiredText('androidVersion'),
      sdkInt: requiredInteger('sdkInt'),
      supportedAbis: abis,
      socManufacturer: optionalText('socManufacturer'),
      socModel: optionalText('socModel'),
      totalRamBytes: requiredInteger('totalRamBytes'),
      availableRamBytes: requiredInteger('availableRamBytes'),
      totalStorageBytes: requiredInteger('totalStorageBytes'),
      availableStorageBytes: requiredInteger('availableStorageBytes'),
    );
  }

  final String manufacturer;
  final String brand;
  final String model;
  final String androidVersion;
  final int sdkInt;
  final List<String> supportedAbis;
  final String? socManufacturer;
  final String? socModel;
  final int totalRamBytes;
  final int availableRamBytes;
  final int totalStorageBytes;
  final int availableStorageBytes;

  Map<String, Object> toJson() => <String, Object>{
    'manufacturer': manufacturer,
    'brand': brand,
    'model': model,
    'androidVersion': androidVersion,
    'sdkInt': sdkInt,
    'supportedAbis': supportedAbis,
    'socManufacturer': ?socManufacturer,
    'socModel': ?socModel,
    'totalRamBytes': totalRamBytes,
    'availableRamBytes': availableRamBytes,
    'totalStorageBytes': totalStorageBytes,
    'availableStorageBytes': availableStorageBytes,
  };
}

class AndroidDeviceHardwareReader {
  const AndroidDeviceHardwareReader();

  static const MethodChannel _channel = MethodChannel('ailingo_platform');

  Future<AndroidDeviceHardware> read() async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'device.hardwareInfo',
    );
    if (raw == null) {
      throw StateError('Android did not return device hardware information.');
    }
    return AndroidDeviceHardware.fromPlatformMap(raw);
  }
}
