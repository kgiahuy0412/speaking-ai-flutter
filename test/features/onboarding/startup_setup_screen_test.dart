import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'requires adult role, consent, profile, permissions and an audio source',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var privacyConsentGranted = false;
      var permissionsGranted = false;
      var limitedModeSelected = false;
      var phoneSelected = false;
      int? selectedAge;
      var completed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: StatefulBuilder(
            builder: (context, setState) => StartupSetupScreen(
              profileLoading: false,
              permissionRequestInProgress: false,
              privacyConfigurationComplete: true,
              privacyConsentGranted: privacyConsentGranted,
              limitedModeSelected: limitedModeSelected,
              microphoneGranted: permissionsGranted,
              bluetoothRequired: true,
              bluetoothGranted: permissionsGranted,
              h20BleConnected: false,
              h20HfpConfigured: false,
              selectedAge: selectedAge,
              aiSubprocessors: 'HOMI backend trên Railway và Cloudflare',
              dataRetentionSummary: 'Audio được xóa sau 24 giờ.',
              privacyPolicyUri: Uri.parse('https://example.com/privacy'),
              termsUri: Uri.parse('https://example.com/terms'),
              supportUri: Uri.parse('https://example.com/support'),
              onGrantPrivacyConsent: () async {
                setState(() => privacyConsentGranted = true);
              },
              onContinueWithoutVoice: () async {
                setState(() => limitedModeSelected = true);
              },
              onRetryPermissions: () {
                setState(() => permissionsGranted = true);
              },
              onSetupH20: () async {},
              onUsePhoneMicrophone: () async {
                setState(() => phoneSelected = true);
              },
              onAgeSelected: (age) => setState(() => selectedAge = age),
              onCompleteSetup: () async {
                setState(() => completed = true);
              },
            ),
          ),
        ),
      );

      final consentButton = find.byKey(
        const Key('startup-grant-privacy-consent'),
      );
      expect(tester.widget<FilledButton>(consentButton).onPressed, isNull);

      await tester.tap(find.byKey(const Key('startup-confirm-adult-role')));
      await tester.pump();
      await tester.ensureVisible(consentButton);
      expect(tester.widget<FilledButton>(consentButton).onPressed, isNotNull);
      await tester.tap(consentButton);
      await tester.pumpAndSettle();

      expect(find.text('Chọn hồ sơ học của trẻ'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('startup-age-8-10')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('startup-next')));
      await tester.tap(find.byKey(const Key('startup-next')));
      await tester.pumpAndSettle();

      expect(find.text('Cấp quyền trên thiết bị'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('startup-request-permissions')),
      );
      await tester.tap(find.byKey(const Key('startup-request-permissions')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('startup-next')));
      await tester.tap(find.byKey(const Key('startup-next')));
      await tester.pumpAndSettle();

      expect(find.text('Chọn cách trẻ tương tác'), findsOneWidget);
      final completeButton = find.byKey(const Key('startup-confirm-age'));
      await tester.ensureVisible(completeButton);
      expect(tester.widget<FilledButton>(completeButton).onPressed, isNull);
      await tester.ensureVisible(
        find.byKey(const Key('startup-use-phone-mic')),
      );
      await tester.tap(find.byKey(const Key('startup-use-phone-mic')));
      await tester.pump();
      await tester.ensureVisible(completeButton);
      expect(tester.widget<FilledButton>(completeButton).onPressed, isNotNull);
      await tester.tap(completeButton);

      expect(selectedAge, 8);
      expect(phoneSelected, isTrue);
      expect(completed, isTrue);
      expect(limitedModeSelected, isFalse);
    },
  );

  testWidgets('limited mode can finish without microphone or H20', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var limited = false;
    int? age;
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StatefulBuilder(
          builder: (context, setState) => StartupSetupScreen(
            profileLoading: false,
            permissionRequestInProgress: false,
            privacyConfigurationComplete: true,
            privacyConsentGranted: false,
            limitedModeSelected: limited,
            microphoneGranted: false,
            bluetoothRequired: true,
            bluetoothGranted: false,
            h20BleConnected: false,
            h20HfpConfigured: false,
            selectedAge: age,
            aiSubprocessors: 'Railway và Cloudflare',
            dataRetentionSummary: 'Theo chính sách công khai.',
            onGrantPrivacyConsent: () async {},
            onContinueWithoutVoice: () async {
              setState(() => limited = true);
            },
            onRetryPermissions: () {},
            onSetupH20: () async {},
            onUsePhoneMicrophone: () async {},
            onAgeSelected: (value) => setState(() => age = value),
            onCompleteSetup: () async {
              setState(() => completed = true);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('startup-confirm-adult-role')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('startup-continue-without-voice')),
    );
    await tester.tap(find.byKey(const Key('startup-continue-without-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('startup-age-6-7')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('startup-next')));
    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('startup-next')));
    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('startup-confirm-age')));
    await tester.tap(find.byKey(const Key('startup-confirm-age')));

    expect(limited, isTrue);
    expect(age, 6);
    expect(completed, isTrue);
  });
}
