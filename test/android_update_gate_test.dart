import 'package:ai_speaking_flutter_app/config/app_config.dart';
import 'package:ai_speaking_flutter_app/core/update/android_update_gate.dart';
import 'package:ai_speaking_flutter_app/core/update/app_update_policy.dart';
import 'package:ai_speaking_flutter_app/core/update/app_update_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final config = AppConfig(
    backendBaseUri: Uri.parse('https://api.example.com'),
    useDemoBackend: false,
    childAge: 6,
  );

  testWidgets('shows a blocking screen below the minimum build', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final checker = _FakeChecker(
        AppUpdateDecision(
          currentBuild: 2,
          policy: _policy(minimum: 3),
          source: AppUpdatePolicySource.network,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AndroidUpdateGate(
            config: config,
            checker: checker,
            urlOpener: (_) async => true,
            child: const Text('MAIN_APP'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cần cập nhật ứng dụng'), findsOneWidget);
      expect(find.text('MAIN_APP'), findsNothing);
      expect(find.byKey(const Key('required-update-open')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('opens the main app at the minimum supported build', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final checker = _FakeChecker(
        AppUpdateDecision(
          currentBuild: 3,
          policy: _policy(minimum: 3),
          source: AppUpdatePolicySource.network,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AndroidUpdateGate(
            config: config,
            checker: checker,
            child: const Text('MAIN_APP'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MAIN_APP'), findsOneWidget);
      expect(find.byKey(const Key('required-update-open')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

AppUpdatePolicy _policy({required int minimum}) => AppUpdatePolicy(
  latestVersion: '1.0.1',
  latestBuild: 3,
  minimumSupportedBuild: minimum,
  downloadUrl: Uri.parse('https://download.example.com/android'),
  vietnameseMessage: 'Vui lòng cập nhật.',
  chineseMessage: '请更新。',
);

class _FakeChecker implements AppUpdateChecker {
  _FakeChecker(this.decision);

  final AppUpdateDecision decision;

  @override
  Future<AppUpdateDecision> check() async => decision;

  @override
  void dispose() {}
}
