import 'package:ai_speaking_flutter_app/core/platform/platform_access_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformAccessPolicy', () {
    test('bypasses Settings authentication only for native Android', () {
      expect(
        PlatformAccessPolicy.bypassesSettingsAuthentication(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        PlatformAccessPolicy.bypassesSettingsAuthentication(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
      expect(
        PlatformAccessPolicy.bypassesSettingsAuthentication(
          isWeb: true,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });
  });
}
