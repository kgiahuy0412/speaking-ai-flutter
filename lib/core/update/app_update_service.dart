import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import 'app_update_policy.dart';

typedef AppUpdatePolicyFetcher = Future<AppUpdatePolicy> Function();
typedef CurrentBuildLoader = Future<int?> Function();

abstract interface class AppUpdatePolicyStore {
  Future<AppUpdatePolicy?> read();
  Future<void> write(AppUpdatePolicy policy);
}

abstract interface class AppUpdateChecker {
  Future<AppUpdateDecision> check();
  void dispose();
}

class SharedPreferencesAppUpdatePolicyStore implements AppUpdatePolicyStore {
  const SharedPreferencesAppUpdatePolicyStore();

  static const _key = 'innotrik.android-update-policy.v1';

  @override
  Future<AppUpdatePolicy?> read() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_key)?.trim();
      if (encoded == null || encoded.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(encoded);
      return decoded is Map
          ? AppUpdatePolicy.fromJson(Map<String, dynamic>.from(decoded))
          : null;
    } catch (error) {
      debugPrint('Cached app update policy was ignored: $error');
      return null;
    }
  }

  @override
  Future<void> write(AppUpdatePolicy policy) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(policy.toJson()));
  }
}

class AppUpdateService implements AppUpdateChecker {
  AppUpdateService({
    required AppUpdatePolicyFetcher fetchPolicy,
    required CurrentBuildLoader loadCurrentBuild,
    required AppUpdatePolicyStore store,
    void Function()? onDispose,
  }) : _fetchPolicy = fetchPolicy,
       _loadCurrentBuild = loadCurrentBuild,
       _store = store,
       _onDispose = onDispose;

  factory AppUpdateService.network({
    required AppConfig config,
    Duration timeout = const Duration(milliseconds: 1500),
  }) {
    final client = http.Client();
    final endpoint = config.resolve(
      '/api/app-version?platform=android&channel=direct',
    );

    return AppUpdateService(
      fetchPolicy: () async {
        final requestId = _newRequestId();
        final response = await client
            .get(endpoint, headers: <String, String>{'X-Request-Id': requestId})
            .timeout(timeout);
        if (response.statusCode != 200) {
          throw StateError(
            'App version endpoint returned ${response.statusCode}.',
          );
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw const FormatException('App version response is not an object.');
        }
        return AppUpdatePolicy.fromJson(Map<String, dynamic>.from(decoded));
      },
      loadCurrentBuild: () async {
        final info = await PackageInfo.fromPlatform();
        final build = int.tryParse(info.buildNumber.trim());
        return build != null && build > 0 ? build : null;
      },
      store: const SharedPreferencesAppUpdatePolicyStore(),
      onDispose: client.close,
    );
  }

  final AppUpdatePolicyFetcher _fetchPolicy;
  final CurrentBuildLoader _loadCurrentBuild;
  final AppUpdatePolicyStore _store;
  final void Function()? _onDispose;
  bool _disposed = false;

  @override
  Future<AppUpdateDecision> check() async {
    if (_disposed) {
      return const AppUpdateDecision.unavailable();
    }

    final currentBuild = await _readCurrentBuild();
    if (currentBuild == null) {
      return const AppUpdateDecision.unavailable();
    }

    try {
      final policy = await _fetchPolicy();
      try {
        await _store.write(policy);
      } catch (error) {
        debugPrint('App update policy could not be cached: $error');
      }
      return AppUpdateDecision(
        currentBuild: currentBuild,
        policy: policy,
        source: AppUpdatePolicySource.network,
      );
    } catch (error) {
      debugPrint('Live app update check failed safely: $error');
      final cachedPolicy = await _store.read();
      if (cachedPolicy == null) {
        return AppUpdateDecision(
          currentBuild: currentBuild,
          policy: null,
          source: AppUpdatePolicySource.unavailable,
        );
      }
      return AppUpdateDecision(
        currentBuild: currentBuild,
        policy: cachedPolicy,
        source: AppUpdatePolicySource.cache,
      );
    }
  }

  Future<int?> _readCurrentBuild() async {
    try {
      return await _loadCurrentBuild();
    } catch (error) {
      debugPrint('Current Android build number is unavailable: $error');
      return null;
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _onDispose?.call();
  }

  static String _newRequestId() {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return 'app-update-${DateTime.now().microsecondsSinceEpoch}-$random';
  }
}
