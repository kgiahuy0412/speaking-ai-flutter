import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all three setup steps share the approved HOMI form', (
    tester,
  ) async {
    await _loadGoldenFonts();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var selectedAge = 6;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: StartupSetupScreen(
            profileLoading: false,
            permissionRequestInProgress: false,
            privacyConfigurationComplete: true,
            privacyConsentGranted: true,
            limitedModeSelected: false,
            microphoneGranted: true,
            bluetoothRequired: false,
            bluetoothGranted: true,
            h20BleConnected: false,
            h20HfpConfigured: false,
            selectedAge: selectedAge,
            aiSubprocessors: 'HOMI AI',
            dataRetentionSummary: 'Lưu theo chính sách HOMI.',
            onGrantPrivacyConsent: () async {},
            onContinueWithoutVoice: () async {},
            onRetryPermissions: () {},
            onSetupH20: () async {},
            onAgeSelected: (age) => setState(() => selectedAge = age),
            onCompleteSetup: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final context = tester.element(find.byType(StartupSetupScreen));
      await Future.wait<void>(
        const <AssetImage>[
          AssetImage('assets/images/mascot/penguin-avatar.png'),
          AssetImage('assets/images/mascot/penguin-wave.png'),
        ].map((provider) => precacheImage(provider, context)),
      );
    });

    await expectLater(
      find.byType(StartupSetupScreen),
      matchesGoldenFile('goldens/startup-privacy-390x844.png'),
    );

    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(StartupSetupScreen),
      matchesGoldenFile('goldens/startup-profile-390x844.png'),
    );

    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(StartupSetupScreen),
      matchesGoldenFile('goldens/startup-permissions-390x844.png'),
    );
  });

  testWidgets('all three setup steps share one dark HOMI form', (tester) async {
    await _loadGoldenFonts();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var selectedAge = 6;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          darkTheme: buildDarkAppTheme(),
          themeMode: ThemeMode.dark,
          home: StartupSetupScreen(
            profileLoading: false,
            permissionRequestInProgress: false,
            privacyConfigurationComplete: true,
            privacyConsentGranted: true,
            limitedModeSelected: false,
            microphoneGranted: true,
            bluetoothRequired: false,
            bluetoothGranted: true,
            h20BleConnected: false,
            h20HfpConfigured: false,
            selectedAge: selectedAge,
            aiSubprocessors: 'HOMI AI',
            dataRetentionSummary: 'Lưu theo chính sách HOMI.',
            onGrantPrivacyConsent: () async {},
            onContinueWithoutVoice: () async {},
            onRetryPermissions: () {},
            onSetupH20: () async {},
            onAgeSelected: (age) => setState(() => selectedAge = age),
            onCompleteSetup: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final context = tester.element(find.byType(StartupSetupScreen));
      await Future.wait<void>(
        const <AssetImage>[
          AssetImage('assets/images/mascot/penguin-avatar.png'),
          AssetImage('assets/images/mascot/penguin-wave.png'),
        ].map((provider) => precacheImage(provider, context)),
      );
    });

    await expectLater(
      find.byType(StartupSetupScreen),
      matchesGoldenFile('goldens/dark-startup-privacy-390x844.png'),
    );
    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(StartupSetupScreen),
      matchesGoldenFile('goldens/dark-startup-profile-390x844.png'),
    );
    await tester.tap(find.byKey(const Key('startup-next')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(StartupSetupScreen),
      matchesGoldenFile('goldens/dark-startup-permissions-390x844.png'),
    );
  });
}

Future<void> _loadGoldenFonts() async {
  final roboto = FontLoader('Roboto')
    ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
  await Future.wait<void>(<Future<void>>[roboto.load(), materialIcons.load()]);
}
