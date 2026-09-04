import 'package:flutter/foundation.dart';

abstract final class PlatformAccessPolicy {
  /// The Android APK opens Settings without a device credential because many
  /// target devices do not have biometrics or a lock-screen credential set.
  static bool bypassesSettingsAuthentication({
    required bool isWeb,
    required TargetPlatform platform,
  }) => !isWeb && platform == TargetPlatform.android;
}
