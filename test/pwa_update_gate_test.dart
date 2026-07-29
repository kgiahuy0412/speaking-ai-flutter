import 'package:ai_speaking_flutter_app/core/pwa/pwa_update_gate.dart';
import 'package:ai_speaking_flutter_app/core/pwa/pwa_update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offers a reload when a newer web build is available', (
    tester,
  ) async {
    var reloads = 0;
    final checker = _FakeChecker(
      const PwaUpdateDecision(
        current: PwaBuildVersion(version: '1.0.2', buildNumber: 4),
        latest: PwaBuildVersion(version: '1.0.3', buildNumber: 5),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PwaUpdateGate(
          enabled: true,
          checker: checker,
          reload: () => reloads += 1,
          child: const Scaffold(body: Text('MAIN_APP')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pwa-update-banner')), findsOneWidget);
    expect(find.text('MAIN_APP'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pwa-update-reload')));
    expect(reloads, 1);
  });

  testWidgets('keeps the banner hidden for the current web build', (
    tester,
  ) async {
    final checker = _FakeChecker(
      const PwaUpdateDecision(
        current: PwaBuildVersion(version: '1.0.2', buildNumber: 4),
        latest: PwaBuildVersion(version: '1.0.2', buildNumber: 4),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PwaUpdateGate(
          enabled: true,
          checker: checker,
          child: const Scaffold(body: Text('MAIN_APP')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pwa-update-banner')), findsNothing);
    expect(find.text('MAIN_APP'), findsOneWidget);
  });
}

class _FakeChecker implements PwaUpdateChecker {
  _FakeChecker(this.decision);

  final PwaUpdateDecision decision;

  @override
  Future<PwaUpdateDecision> check() async => decision;

  @override
  void dispose() {}
}
