import 'package:ai_speaking_flutter_app/core/pwa/pwa_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports a newer deployed web build', () async {
    final service = PwaUpdateService(
      loadCurrent: () async =>
          const PwaBuildVersion(version: '1.0.2', buildNumber: 4),
      fetchLatest: () async =>
          const PwaBuildVersion(version: '1.0.3', buildNumber: 5),
    );

    final decision = await service.check();

    expect(decision.updateAvailable, isTrue);
    expect(decision.latest.version, '1.0.3');
  });

  test('keeps the loaded build stable between update checks', () async {
    var currentLoads = 0;
    final service = PwaUpdateService(
      loadCurrent: () async {
        currentLoads += 1;
        return const PwaBuildVersion(version: '1.0.2', buildNumber: 4);
      },
      fetchLatest: () async =>
          const PwaBuildVersion(version: '1.0.2', buildNumber: 4),
    );

    expect((await service.check()).updateAvailable, isFalse);
    expect((await service.check()).updateAvailable, isFalse);
    expect(currentLoads, 1);
  });

  test('parses Flutter generated version metadata', () {
    final version = PwaBuildVersion.fromJson(const <String, dynamic>{
      'version': '1.0.3',
      'build_number': '5',
    });

    expect(version.version, '1.0.3');
    expect(version.buildNumber, 5);
  });
}
