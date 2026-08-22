import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('requires parental consent before requesting microphone access', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var permissionsRequested = 0;
    var consentGranted = 0;
    var limitedModeStarted = false;
    int? selectedAge;
    var confirmed = false;

    Widget subject({
      required bool privacyConsentGranted,
      required bool permissionsGranted,
    }) {
      return MaterialApp(
        theme: buildAppTheme(),
        home: StartupSetupScreen(
          profileLoading: false,
          permissionRequestInProgress: false,
          privacyConfigurationComplete: true,
          privacyConsentGranted: privacyConsentGranted,
          microphoneGranted: permissionsGranted,
          bluetoothRequired: true,
          bluetoothGranted: permissionsGranted,
          selectedAge: selectedAge,
          aiSubprocessors: 'HOMI backend trên Railway và Cloudflare',
          dataRetentionSummary: 'Audio được xóa sau 24 giờ.',
          privacyPolicyUri: Uri.parse('https://example.com/privacy'),
          termsUri: Uri.parse('https://example.com/terms'),
          supportUri: Uri.parse('https://example.com/support'),
          onGrantPrivacyConsent: () async => consentGranted += 1,
          onContinueWithoutVoice: () async => limitedModeStarted = true,
          onRetryPermissions: () => permissionsRequested += 1,
          onAgeSelected: (age) => selectedAge = age,
          onConfirmAge: () => confirmed = true,
        ),
      );
    }

    await tester.pumpWidget(
      subject(privacyConsentGranted: false, permissionsGranted: false),
    );
    await tester.ensureVisible(
      find.byKey(const Key('startup-grant-privacy-consent')),
    );
    await tester.tap(find.byKey(const Key('startup-grant-privacy-consent')));
    await tester.pump();
    expect(consentGranted, 1);

    await tester.pumpWidget(
      subject(privacyConsentGranted: true, permissionsGranted: false),
    );
    await tester.ensureVisible(
      find.byKey(const Key('startup-request-permissions')),
    );
    await tester.tap(find.byKey(const Key('startup-request-permissions')));
    expect(permissionsRequested, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('startup-confirm-age')))
          .onPressed,
      isNull,
    );

    await tester.pumpWidget(
      subject(privacyConsentGranted: true, permissionsGranted: true),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('startup-age-8-10')),
      300,
    );
    await tester.tap(find.byKey(const ValueKey('startup-age-8-10')));
    await tester.pumpWidget(
      subject(privacyConsentGranted: true, permissionsGranted: true),
    );
    await tester.ensureVisible(find.byKey(const Key('startup-confirm-age')));
    await tester.tap(find.byKey(const Key('startup-confirm-age')));

    expect(selectedAge, 8);
    expect(confirmed, isTrue);
    expect(limitedModeStarted, isFalse);
  });
}
