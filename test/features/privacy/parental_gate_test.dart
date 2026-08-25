import 'package:ai_speaking_flutter_app/features/privacy/presentation/parental_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthenticator implements ParentalGateAuthenticator {
  _FakeAuthenticator({this.supported = true, this.approved = true});

  final bool supported;
  final bool approved;

  int supportChecks = 0;
  int authenticationCalls = 0;

  @override
  Future<bool> isSupported() async {
    supportChecks += 1;
    return supported;
  }

  @override
  Future<bool> authenticate({required String localizedReason}) async {
    authenticationCalls += 1;
    return approved;
  }
}

void main() {
  testWidgets(
    'successful device authentication is cached and backgrounding locks it',
    (tester) async {
      final authenticator = _FakeAuthenticator();
      final session = ParentalGateSession();
      late BuildContext context;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (buildContext) {
              context = buildContext;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        await showParentalGate(
          context,
          authenticator: authenticator,
          session: session,
        ),
        isTrue,
      );
      expect(authenticator.authenticationCalls, 1);

      expect(
        await showParentalGate(
          context,
          authenticator: authenticator,
          session: session,
        ),
        isTrue,
      );
      expect(authenticator.authenticationCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      expect(
        await showParentalGate(
          context,
          authenticator: authenticator,
          session: session,
        ),
        isTrue,
      );
      expect(authenticator.authenticationCalls, 2);

      session.dispose();
    },
  );

  testWidgets('parental unlock expires after ten minutes', (tester) async {
    var now = DateTime(2026, 8, 25, 10);
    final authenticator = _FakeAuthenticator();
    final session = ParentalGateSession(now: () => now);
    late BuildContext context;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      await showParentalGate(
        context,
        authenticator: authenticator,
        session: session,
      ),
      isTrue,
    );
    now = now.add(const Duration(minutes: 10, seconds: 1));
    expect(
      await showParentalGate(
        context,
        authenticator: authenticator,
        session: session,
      ),
      isTrue,
    );
    expect(authenticator.authenticationCalls, 2);

    session.dispose();
  });

  testWidgets('rejected device authentication keeps parental area locked', (
    tester,
  ) async {
    final authenticator = _FakeAuthenticator(approved: false);
    final session = ParentalGateSession();
    late BuildContext context;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      await showParentalGate(
        context,
        authenticator: authenticator,
        session: session,
      ),
      isFalse,
    );
    expect(session.isUnlocked, isFalse);

    session.dispose();
  });

  testWidgets('device without a screen lock cannot enter parental area', (
    tester,
  ) async {
    final authenticator = _FakeAuthenticator(supported: false);
    final session = ParentalGateSession();
    late BuildContext context;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox();
          },
        ),
      ),
    );

    final result = showParentalGate(
      context,
      authenticator: authenticator,
      session: session,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('parental-auth-unavailable-dialog')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
    expect(authenticator.authenticationCalls, 0);

    session.dispose();
  });
}
