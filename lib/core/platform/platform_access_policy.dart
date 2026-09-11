import 'package:flutter/foundation.dart';

abstract final class PlatformAccessPolicy {
  /// The Android APK opens Settings without a device credential because many
  /// target devices do not have biometrics or a lock-screen credential set.
  static bool bypassesSettingsAuthentication({
    required bool isWeb,
    required TargetPlatform platform,
  }) => !isWeb && platform == TargetPlatform.android;

  /// Changing the listening age group follows the Android Settings behavior:
  /// target devices are not required to have a biometric or screen lock.
  /// iOS continues through LocalAuthentication, where the device passcode is
  /// available when Face ID or Touch ID cannot be used.
  static bool bypassesTopicAgeAuthentication({
    required bool isWeb,
    required TargetPlatform platform,
  }) => !isWeb && platform == TargetPlatform.android;
}
