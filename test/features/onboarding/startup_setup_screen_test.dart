import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/features/onboarding/presentation/startup_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('requires permissions before age and confirms the chosen group', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var permissionsRequested = 0;
    int? selectedAge;
    var confirmed = false;

    Widget subject({required bool permissionsGranted}) {
      return MaterialApp(
        theme: buildAppTheme(),
        home: StartupSetupScreen(
          profileLoading: false,
          permissionRequestInProgress: false,
          microphoneGranted: permissionsGranted,
          bluetoothRequired: true,
          bluetoothGranted: permissionsGranted,
          selectedAge: selectedAge,
          onRetryPermissions: () => permissionsRequested += 1,
          onAgeSelected: (age) => selectedAge = age,
          onConfirmAge: () => confirmed = true,
        ),
      );
    }

    await tester.pumpWidget(subject(permissionsGranted: false));
    await tester.tap(find.byKey(const Key('startup-request-permissions')));
    expect(permissionsRequested, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('startup-confirm-age')))
          .onPressed,
      isNull,
    );

    await tester.pumpWidget(subject(permissionsGranted: true));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('startup-age-8-10')),
      300,
    );
    await tester.tap(find.byKey(const ValueKey('startup-age-8-10')));
    await tester.pumpWidget(subject(permissionsGranted: true));
    await tester.ensureVisible(find.byKey(const Key('startup-confirm-age')));
    await tester.tap(find.byKey(const Key('startup-confirm-age')));

    expect(selectedAge, 8);
    expect(confirmed, isTrue);
  });
}
