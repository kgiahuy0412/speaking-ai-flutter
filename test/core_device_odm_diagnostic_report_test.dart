import 'package:ai_speaking_flutter_app/core/device/odm_diagnostic_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> build({
    required Map<String, Object?> ble,
    required Map<String, Object?> hfp,
    Map<String, Object?> hardwareTest = const <String, Object?>{},
    List<Map<String, Object?>> buttons = const <Map<String, Object?>>[],
  }) => OdmDiagnosticRecorder.buildReportPayload(
    sessionId: 'test-session',
    startedAt: DateTime.utc(2026, 9, 10, 1),
    endedAt: DateTime.utc(2026, 9, 10, 1, 1),
    app: const <String, Object?>{'version': '1.0.5'},
    platform: const <String, Object?>{'operatingSystem': 'android'},
    ble: ble,
    hfp: hfp,
    hardwareTest: hardwareTest,
    buttonPackets: buttons,
    events: const <Map<String, Object?>>[],
  );

  test('separates connected BLE from missing HFP profile', () {
    final report = build(
      ble: const <String, Object?>{'phase': 'connected'},
      hfp: const <String, Object?>{
        'phase': 'idle',
        'routeActive': false,
        'diagnosticDetails': <String, Object?>{'profileConnected': false},
      },
    );

    final summary = report['summary']! as Map<String, Object?>;
    expect(summary['bleConnected'], isTrue);
    expect(summary['hfpProfileConnected'], isFalse);
    expect(
      summary['issues'],
      containsAll(<String>[
        'HFP_PROFILE_NOT_CONNECTED',
        'SCO_INPUT_NOT_VERIFIED',
        'SCO_OUTPUT_NOT_VERIFIED',
        'NO_PHYSICAL_BUTTON_PACKET',
      ]),
    );
  });

  test('uses completed offline hardware test as route evidence', () {
    final report = build(
      ble: const <String, Object?>{'phase': 'connected'},
      hfp: const <String, Object?>{
        'phase': 'ready',
        'deviceId': 'AA:BB:CC:DD:EE:FF',
        'routeActive': false,
        'diagnosticDetails': <String, Object?>{'profileConnected': true},
      },
      hardwareTest: const <String, Object?>{
        'result': <String, Object?>{
          'inputRouteVerified': true,
          'outputRouteVerified': true,
        },
      },
      buttons: const <Map<String, Object?>>[
        <String, Object?>{'rawHex': '01 01 01 01'},
      ],
    );

    final summary = report['summary']! as Map<String, Object?>;
    expect(summary['hfpProfileConnected'], isTrue);
    expect(summary['hfpSelectedByApp'], isTrue);
    expect(summary['scoInputConfirmedAtExport'], isTrue);
    expect(summary['scoOutputConfirmedAtExport'], isTrue);
    expect(summary['physicalButtonPacketCount'], 1);
    expect(summary['issues'], isEmpty);
  });

  test('declares that sensitive speech and backend data are excluded', () {
    final report = build(
      ble: const <String, Object?>{'phase': 'idle'},
      hfp: const <String, Object?>{'phase': 'idle'},
    );

    expect(report['privacy'], <String, Object?>{
      'containsAudio': false,
      'containsTranscripts': false,
      'containsAuthenticationTokens': false,
      'containsBackendPayloads': false,
    });
  });
}
