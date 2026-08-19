import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the Android process available for H20 BLE MAIN events while the
/// screen is off.
///
/// The native side owns the foreground notification and partial wake lock.
/// Microphone/Bluetooth runtime permissions must be granted before [start].
class AndroidBackgroundAssistant {
  const AndroidBackgroundAssistant();

  static const MethodChannel _channel = MethodChannel('ailingo_platform');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> start() async {
    if (!isSupported) {
      return false;
    }
    return await _channel.invokeMethod<bool>('backgroundAssistant.start') ??
        false;
  }

  Future<void> stop() async {
    if (!isSupported) {
      return;
    }
    await _channel.invokeMethod<void>('backgroundAssistant.stop');
  }
}
