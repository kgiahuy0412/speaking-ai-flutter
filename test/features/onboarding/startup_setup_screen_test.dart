import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'requires a complete H20 connection before voice setup can finish',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var privacyConsentGranted = false;
      var permissionsGranted = false;
      var limitedModeSelected = false;
      var offlineEnglishModelAllowed = false;
      var h20BleConnected = false;
      var h20HfpConfigured = false;
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
              h20BleConnected: h20BleConnected,
              h20HfpConfigured: h20HfpConfigured,
              selectedAge: selectedAge,
              aiSubprocessors: 'HOMI backend trên Railway và Cloudflare',
              dataRetentionSummary: 'Audio được xóa sau 24 giờ.',
              privacyPolicyUri: Uri.parse('https://example.com/privacy'),
              termsUri: Uri.parse('https://example.com/terms'),
              supportUri: Uri.parse('https://example.com/support'),
              androidOfflineEnglishModelOptionAvailable: true,
              androidOfflineEnglishModelDownloadAllowed:
                  offlineEnglishModelAllowed,
              onAndroidOfflineEnglishModelDownloadChanged: (enabled) async {
                setState(() => offlineEnglishModelAllowed = enabled);
              },
              onGrantPrivacyConsent: () async {
                setState(() => privacyConsentGranted = true);
              },
              onContinueWithoutVoice: () async {
                setState(() => limitedModeSelected = true);
              },
              onRetryPermissions: () {
                setState(() => permissionsGranted = true);
              },
              onSetupH20: () async {
                setState(() {
                  h20BleConnected = true;
                  h20HfpConfigured = true;
                });
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
      expect(tester.widget<FilledButton>(consentButton).onPressed, isNull);
      expect(
        find.textContaining(
          'Tôi đồng ý để HOMI xử lý dữ liệu giọng nói theo Điều khoản',
        ),
        findsOneWidget,
      );

      await _completeLegalReview(tester);
      final legalCheckbox = find.byKey(const Key('startup-accept-legal'));
      expect(
        tester.widget<CheckboxListTile>(legalCheckbox).onChanged,
        isNotNull,
      );
      await tester.tap(legalCheckbox);
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

      expect(find.text('Cấp quyền và kết nối thiết bị'), findsOneWidget);
      expect(find.text('Bước 3/3 • Dành cho phụ huynh'), findsOneWidget);
      expect(find.text('Kết nối H20 (bắt buộc)'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('startup-request-permissions')),
      );
      expect(find.text('Tiếp tục'), findsOneWidget);
      expect(find.text('Cấp quyền cần thiết'), findsNothing);
      await tester.tap(find.byKey(const Key('startup-request-permissions')));
      await tester.pumpAndSettle();

      final offlineModelSwitch = find.byKey(
        const Key('startup-android-offline-english-model'),
      );
      await tester.ensureVisible(offlineModelSwitch);
      expect(offlineModelSwitch, findsOneWidget);
      await tester.tap(offlineModelSwitch);
      await tester.pumpAndSettle();
      expect(offlineEnglishModelAllowed, isTrue);

      final completeButton = find.byKey(const Key('startup-confirm-age'));
      await tester.ensureVisible(completeButton);
      expect(tester.widget<FilledButton>(completeButton).onPressed, isNull);
      expect(find.byKey(const Key('startup-use-phone-mic')), findsNothing);
      expect(
        find.text('Cần kết nối H20 thành công trước khi bắt đầu phiên học.'),
        findsWidgets,
      );

      final connectButton = find.byKey(const Key('startup-setup-h20'));
      await tester.ensureVisible(connectButton);
      await tester.tap(connectButton);
      await tester.pumpAndSettle();

      await tester.ensureVisible(completeButton);
      expect(tester.widget<FilledButton>(completeButton).onPressed, isNotNull);
      await tester.tap(completeButton);

      expect(selectedAge, 8);
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
    await _completeLegalReview(tester);
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
    expect(find.text('Bước 3/3 • Dành cho phụ huynh'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('startup-confirm-age')));
    await tester.tap(find.byKey(const Key('startup-confirm-age')));

    expect(limited, isTrue);
    expect(age, 6);
    expect(completed, isTrue);
  });

  testWidgets('closing legal review early does not unlock voice consent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StartupSetupScreen(
          profileLoading: false,
          permissionRequestInProgress: false,
          privacyConfigurationComplete: true,
          privacyConsentGranted: false,
          limitedModeSelected: false,
          microphoneGranted: false,
          bluetoothRequired: true,
          bluetoothGranted: false,
          h20BleConnected: false,
          h20HfpConfigured: false,
          selectedAge: null,
          aiSubprocessors: 'Railway và Cloudflare',
          dataRetentionSummary: 'Theo chính sách công khai.',
          privacyPolicyUri: Uri.parse('https://example.com/privacy'),
          termsUri: Uri.parse('https://example.com/terms'),
          supportUri: Uri.parse('https://example.com/support'),
          onGrantPrivacyConsent: () async {},
          onContinueWithoutVoice: () async {},
          onRetryPermissions: () {},
          onSetupH20: () async {},
          onAgeSelected: (_) {},
          onCompleteSetup: () async {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('startup-review-legal')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('startup-legal-reviewed')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('startup-close-legal')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('startup-accept-legal')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('startup-grant-privacy-consent')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('parent setup explains how to keep other app audio on phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var settingsOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: StartupSetupScreen(
          profileLoading: false,
          permissionRequestInProgress: false,
          privacyConfigurationComplete: true,
          privacyConsentGranted: true,
          limitedModeSelected: false,
          microphoneGranted: true,
          bluetoothRequired: true,
          bluetoothGranted: true,
          h20BleConnected: true,
          h20HfpConfigured: true,
          h20MediaAudioConnected: true,
          selectedAge: 6,
          aiSubprocessors: 'Railway và Cloudflare',
          dataRetentionSummary: 'Theo chính sách công khai.',
          onGrantPrivacyConsent: () async {},
          onContinueWithoutVoice: () async {},
          onRetryPermissions: () {},
          onSetupH20: () async {},
          onOpenH20MediaAudioSettings: () async {
            settingsOpened = true;
          },
          onAgeSelected: (_) {},
          onCompleteSetup: () async {},
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('startup-next')));
    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();

    expect(find.text('Chọn hồ sơ học của trẻ'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('startup-next')));
    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Âm thanh đa phương tiện'), findsOneWidget);
    final openSettings = find.byKey(
      const Key('startup-open-h20-media-audio-settings'),
    );
    await tester.ensureVisible(openSettings);
    await tester.tap(openSettings);
    await tester.pump();

    expect(settingsOpened, isTrue);
  });
}

Future<void> _completeLegalReview(WidgetTester tester) async {
  final legalReviewButton = find.byKey(const Key('startup-review-legal'));
  await tester.ensureVisible(legalReviewButton);
  await tester.tap(legalReviewButton);
  await tester.pumpAndSettle();

  expect(find.text('Bên thứ ba nhận dữ liệu và mục đích'), findsOneWidget);
  expect(
    find.textContaining('biện pháp bảo vệ dữ liệu tương đương'),
    findsOneWidget,
  );

  final reviewedButton = find.byKey(const Key('startup-legal-reviewed'));
  expect(tester.widget<FilledButton>(reviewedButton).onPressed, isNull);

  for (var attempt = 0; attempt < 6; attempt += 1) {
    if (tester.widget<FilledButton>(reviewedButton).onPressed != null) break;
    await tester.drag(
      find.byKey(const Key('startup-legal-scroll')),
      const Offset(0, -480),
    );
    await tester.pumpAndSettle();
  }

  expect(tester.widget<FilledButton>(reviewedButton).onPressed, isNotNull);
  await tester.tap(reviewedButton);
  await tester.pumpAndSettle();
}
