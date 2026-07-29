import 'package:ai_speaking_flutter_app/core/update/app_update_policy.dart';
import 'package:ai_speaking_flutter_app/core/update/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdateService', () {
    test('allows a build at the minimum supported version', () async {
      final store = _MemoryPolicyStore();
      final service = AppUpdateService(
        fetchPolicy: () async => _policy(minimum: 2, latest: 3),
        loadCurrentBuild: () async => 2,
        store: store,
      );

      final decision = await service.check();

      expect(decision.requiresUpdate, isFalse);
      expect(decision.updateAvailable, isTrue);
      expect(decision.source, AppUpdatePolicySource.network);
      expect(store.value?.latestBuild, 3);
    });

    test('requires an update below the minimum supported build', () async {
      final service = AppUpdateService(
        fetchPolicy: () async => _policy(minimum: 3, latest: 3),
        loadCurrentBuild: () async => 2,
        store: _MemoryPolicyStore(),
      );

      final decision = await service.check();

      expect(decision.requiresUpdate, isTrue);
    });

    test('fails open when network and cache are unavailable', () async {
      final service = AppUpdateService(
        fetchPolicy: () async => throw StateError('offline'),
        loadCurrentBuild: () async => 2,
        store: _MemoryPolicyStore(),
      );

      final decision = await service.check();

      expect(decision.requiresUpdate, isFalse);
      expect(decision.source, AppUpdatePolicySource.unavailable);
    });

    test('keeps a cached mandatory policy while offline', () async {
      final service = AppUpdateService(
        fetchPolicy: () async => throw StateError('offline'),
        loadCurrentBuild: () async => 2,
        store: _MemoryPolicyStore(value: _policy(minimum: 3, latest: 4)),
      );

      final decision = await service.check();

      expect(decision.requiresUpdate, isTrue);
      expect(decision.source, AppUpdatePolicySource.cache);
    });
  });

  test('rejects malformed or insecure policies', () {
    expect(
      () => AppUpdatePolicy.fromJson(<String, dynamic>{
        'latestVersion': '1.0.1',
        'latestBuild': 3,
        'minimumSupportedBuild': 4,
        'downloadUrl': 'http://example.com',
        'messages': <String, String>{'vi': 'Cập nhật', 'zh': '更新'},
      }),
      throwsFormatException,
    );
  });
}

AppUpdatePolicy _policy({required int minimum, required int latest}) =>
    AppUpdatePolicy(
      latestVersion: '1.0.1',
      latestBuild: latest,
      minimumSupportedBuild: minimum,
      downloadUrl: Uri.parse('https://download.example.com/android'),
      vietnameseMessage: 'Vui lòng cập nhật.',
      chineseMessage: '请更新。',
    );

class _MemoryPolicyStore implements AppUpdatePolicyStore {
  _MemoryPolicyStore({this.value});

  AppUpdatePolicy? value;

  @override
  Future<AppUpdatePolicy?> read() async => value;

  @override
  Future<void> write(AppUpdatePolicy policy) async {
    value = policy;
  }
}
