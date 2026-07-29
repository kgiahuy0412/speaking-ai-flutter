import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

typedef PwaBuildLoader = Future<PwaBuildVersion> Function();

abstract interface class PwaUpdateChecker {
  Future<PwaUpdateDecision> check();
  void dispose();
}

class PwaBuildVersion {
  const PwaBuildVersion({required this.version, required this.buildNumber});

  factory PwaBuildVersion.fromJson(Map<String, dynamic> json) {
    final version = json['version']?.toString().trim() ?? '';
    final buildNumber = int.tryParse(
      json['build_number']?.toString().trim() ?? '',
    );
    if (version.isEmpty || buildNumber == null || buildNumber < 1) {
      throw const FormatException('Invalid Flutter web version.json.');
    }
    return PwaBuildVersion(version: version, buildNumber: buildNumber);
  }

  final String version;
  final int buildNumber;
}

class PwaUpdateDecision {
  const PwaUpdateDecision({required this.current, required this.latest});

  final PwaBuildVersion current;
  final PwaBuildVersion latest;

  bool get updateAvailable => latest.buildNumber > current.buildNumber;
}

class PwaUpdateService implements PwaUpdateChecker {
  PwaUpdateService({
    required PwaBuildLoader loadCurrent,
    required PwaBuildLoader fetchLatest,
    void Function()? onDispose,
  }) : _loadCurrent = loadCurrent,
       _fetchLatest = fetchLatest,
       _onDispose = onDispose;

  factory PwaUpdateService.network({
    Duration timeout = const Duration(seconds: 2),
  }) {
    final client = http.Client();
    return PwaUpdateService(
      loadCurrent: () async {
        final info = await PackageInfo.fromPlatform();
        final buildNumber = int.tryParse(info.buildNumber.trim());
        if (info.version.trim().isEmpty ||
            buildNumber == null ||
            buildNumber < 1) {
          throw const FormatException('Current web build is unavailable.');
        }
        return PwaBuildVersion(
          version: info.version.trim(),
          buildNumber: buildNumber,
        );
      },
      fetchLatest: () async {
        final baseEndpoint = Uri.base.resolve('version.json');
        final query = <String, String>{
          ...baseEndpoint.queryParameters,
          '_update': DateTime.now().millisecondsSinceEpoch.toString(),
        };
        final response = await client
            .get(
              baseEndpoint.replace(queryParameters: query),
              headers: const <String, String>{
                'Cache-Control': 'no-cache, no-store',
                'Pragma': 'no-cache',
              },
            )
            .timeout(timeout);
        if (response.statusCode != 200) {
          throw StateError(
            'Web version endpoint returned ${response.statusCode}.',
          );
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw const FormatException('Web version response is not an object.');
        }
        return PwaBuildVersion.fromJson(Map<String, dynamic>.from(decoded));
      },
      onDispose: client.close,
    );
  }

  final PwaBuildLoader _loadCurrent;
  final PwaBuildLoader _fetchLatest;
  final void Function()? _onDispose;
  PwaBuildVersion? _current;
  bool _disposed = false;

  @override
  Future<PwaUpdateDecision> check() async {
    if (_disposed) {
      throw StateError('PwaUpdateService has been disposed.');
    }
    final current = _current ??= await _loadCurrent();
    final latest = await _fetchLatest();
    return PwaUpdateDecision(current: current, latest: latest);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _onDispose?.call();
  }
}
