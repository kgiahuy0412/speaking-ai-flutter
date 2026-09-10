import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// A deliberately narrow, parent-started diagnostic recorder for ODM hardware.
///
/// It records transport state only. Speech transcripts, backend payloads,
/// authentication data, and recorded audio are intentionally excluded.
class OdmDiagnosticRecorder {
  static const int maxEvents = 1000;

  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];
  DateTime? _startedAt;
  String? _sessionId;
  String? _lastReportPath;

  bool get isActive => _startedAt != null;
  int get eventCount => _events.length;
  String? get sessionId => _sessionId;
  String? get lastReportPath => _lastReportPath;

  void start() {
    final now = DateTime.now().toUtc();
    _events.clear();
    _startedAt = now;
    _sessionId = now.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
    record(
      category: 'session',
      stage: 'ODM_DIAGNOSTIC_STARTED',
      data: const <String, Object?>{
        'audioIncluded': false,
        'transcriptsIncluded': false,
        'networkPayloadsIncluded': false,
      },
    );
  }

  void cancel() {
    _events.clear();
    _startedAt = null;
    _sessionId = null;
  }

  void record({
    required String category,
    required String stage,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    if (!isActive) return;
    _events.add(<String, Object?>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'category': category,
      'stage': stage,
      'data': _jsonSafe(data),
    });
    if (_events.length > maxEvents) {
      _events.removeRange(0, _events.length - maxEvents);
    }
  }

  Future<File> exportAndShare({
    required Map<String, Object?> ble,
    required Map<String, Object?> hfp,
    required Map<String, Object?> hardwareTest,
    required List<Map<String, Object?>> buttonPackets,
  }) async {
    if (!isActive) {
      throw StateError('Chưa bắt đầu phiên chẩn đoán ODM.');
    }
    record(
      category: 'session',
      stage: 'ODM_DIAGNOSTIC_EXPORT_REQUESTED',
      data: <String, Object?>{
        'blePhase': ble['phase'],
        'hfpPhase': hfp['phase'],
        'buttonPacketCount': buttonPackets.length,
      },
    );

    final packageInfo = await PackageInfo.fromPlatform();
    final endedAt = DateTime.now().toUtc();
    final payload = buildReportPayload(
      sessionId: _sessionId!,
      startedAt: _startedAt!,
      endedAt: endedAt,
      app: <String, Object?>{
        'name': packageInfo.appName,
        'packageName': packageInfo.packageName,
        'version': packageInfo.version,
        'buildNumber': packageInfo.buildNumber,
      },
      platform: <String, Object?>{
        'operatingSystem': Platform.operatingSystem,
        'operatingSystemVersion': Platform.operatingSystemVersion,
        'locale': Platform.localeName,
        'numberOfProcessors': Platform.numberOfProcessors,
      },
      ble: ble,
      hfp: hfp,
      hardwareTest: hardwareTest,
      buttonPackets: buttonPackets,
      events: List<Map<String, Object?>>.from(_events),
    );

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      'homi_odm_diagnostic_${_sessionId!}.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    _lastReportPath = file.path;
    _startedAt = null;
    _sessionId = null;

    await SharePlus.instance.share(
      ShareParams(
        subject: 'HOMI ODM device diagnostic',
        text:
            'Báo cáo BLE/HFP/SCO và nút vật lý. File không chứa transcript, token hoặc audio ghi âm.',
        files: <XFile>[XFile(file.path, mimeType: 'application/json')],
      ),
    );
    return file;
  }

  static Map<String, Object?> buildReportPayload({
    required String sessionId,
    required DateTime startedAt,
    required DateTime endedAt,
    required Map<String, Object?> app,
    required Map<String, Object?> platform,
    required Map<String, Object?> ble,
    required Map<String, Object?> hfp,
    required Map<String, Object?> hardwareTest,
    required List<Map<String, Object?>> buttonPackets,
    required List<Map<String, Object?>> events,
  }) {
    final hfpDetails = hfp['diagnosticDetails'];
    final profileConnected = hfpDetails is Map
        ? hfpDetails['profileConnected'] == true
        : false;
    final hfpSelected = '${hfp['deviceId'] ?? ''}'.trim().isNotEmpty;
    final routeActive = hfp['routeActive'] == true;
    final bleConnected = ble['phase'] == 'connected';
    final testResult = hardwareTest['result'];
    final inputConfirmed =
        '${hfp['inputDeviceName'] ?? ''}'.trim().isNotEmpty ||
        (testResult is Map && testResult['inputRouteVerified'] == true);
    final outputConfirmed =
        '${hfp['outputDeviceName'] ?? ''}'.trim().isNotEmpty ||
        (testResult is Map && testResult['outputRouteVerified'] == true);
    final issues = <String>[];
    if (!bleConnected) issues.add('BLE_NOT_CONNECTED');
    if (!profileConnected) issues.add('HFP_PROFILE_NOT_CONNECTED');
    if (profileConnected && !hfpSelected) {
      issues.add('HFP_CONNECTED_NOT_SELECTED');
    }
    if (!inputConfirmed) issues.add('SCO_INPUT_NOT_VERIFIED');
    if (!outputConfirmed) issues.add('SCO_OUTPUT_NOT_VERIFIED');
    if (buttonPackets.isEmpty) issues.add('NO_PHYSICAL_BUTTON_PACKET');

    return <String, Object?>{
      'schema': 'homi.odm-diagnostic.v1',
      'privacy': const <String, Object?>{
        'containsAudio': false,
        'containsTranscripts': false,
        'containsAuthenticationTokens': false,
        'containsBackendPayloads': false,
      },
      'session': <String, Object?>{
        'id': sessionId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': endedAt.toUtc().toIso8601String(),
      },
      'app': _jsonSafe(app),
      'platform': _jsonSafe(platform),
      'summary': <String, Object?>{
        'bleConnected': bleConnected,
        'hfpProfileConnected': profileConnected,
        'hfpSelectedByApp': hfpSelected,
        'scoRouteActiveAtExport': routeActive,
        'scoInputConfirmedAtExport': inputConfirmed,
        'scoOutputConfirmedAtExport': outputConfirmed,
        'physicalButtonPacketCount': buttonPackets.length,
        'issues': issues,
      },
      'currentState': <String, Object?>{
        'ble': _jsonSafe(ble),
        'hfp': _jsonSafe(hfp),
        'hardwareTest': _jsonSafe(hardwareTest),
      },
      'buttonPackets': _jsonSafe(buttonPackets),
      'events': _jsonSafe(events),
    };
  }

  static Object? _jsonSafe(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Duration) return value.inMilliseconds;
    if (value is Enum) return value.name;
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _jsonSafe(entry.value),
      };
    }
    if (value is Iterable) return value.map(_jsonSafe).toList(growable: false);
    return '$value';
  }
}
