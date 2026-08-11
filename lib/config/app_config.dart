import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({
    required this.backendBaseUri,
    required this.useDemoBackend,
    required this.childAge,
    this.enableInnotrikBle = true,
    this.enableHfpAudio = true,
    this.preferBleStreaming = true,
    this.realtimeBatchFallback = true,
    this.realtimeFallbackBufferBytes = 15 * 1024 * 1024,
    this.enableWorkerAsrPilot = false,
    this.enableWorkerAsrPrepare = false,
    this.enableWorkerAsrPcmTrim = true,
    this.workerAsrPilotBaseUri,
  });

  factory AppConfig.fromEnvironment() {
    const configuredBackendUrl = String.fromEnvironment(
      'BACKEND_BASE_URL',
      defaultValue: '',
    );
    final rawBackendUrl = configuredBackendUrl.trim().isNotEmpty
        ? configuredBackendUrl.trim()
        : kIsWeb
        ? 'http://localhost:3000'
        : 'http://10.0.2.2:3000';
    const configuredWorkerAsrPilotUrl = String.fromEnvironment(
      'WORKER_ASR_PILOT_URL',
      defaultValue: '',
    );
    final normalizedWorkerAsrPilotUrl = configuredWorkerAsrPilotUrl.trim();

    return AppConfig(
      backendBaseUri: Uri.parse(
        rawBackendUrl.endsWith('/')
            ? rawBackendUrl.substring(0, rawBackendUrl.length - 1)
            : rawBackendUrl,
      ),
      useDemoBackend: const bool.fromEnvironment(
        'USE_DEMO_BACKEND',
        defaultValue: false,
      ),
      childAge: const int.fromEnvironment('CHILD_AGE', defaultValue: 6),
      enableInnotrikBle: const bool.fromEnvironment(
        'ENABLE_INNOTRIK_BLE',
        defaultValue: true,
      ),
      enableHfpAudio: const bool.fromEnvironment(
        'ENABLE_HFP_AUDIO',
        defaultValue: true,
      ),
      preferBleStreaming: const bool.fromEnvironment(
        'PREFER_BLE_STREAMING',
        defaultValue: true,
      ),
      realtimeBatchFallback: const bool.fromEnvironment(
        'REALTIME_BATCH_FALLBACK',
        defaultValue: true,
      ),
      realtimeFallbackBufferBytes: const int.fromEnvironment(
        'REALTIME_FALLBACK_BUFFER_BYTES',
        defaultValue: 15 * 1024 * 1024,
      ),
      enableWorkerAsrPilot:
          kIsWeb &&
          const bool.fromEnvironment(
            'ENABLE_WORKER_ASR_PILOT',
            defaultValue: false,
          ),
      enableWorkerAsrPrepare:
          kIsWeb &&
          const bool.fromEnvironment(
            'ENABLE_WORKER_ASR_PREPARE',
            defaultValue: false,
          ),
      enableWorkerAsrPcmTrim: const bool.fromEnvironment(
        'ENABLE_WORKER_ASR_PCM_TRIM',
        defaultValue: true,
      ),
      workerAsrPilotBaseUri: normalizedWorkerAsrPilotUrl.isEmpty
          ? null
          : Uri.tryParse(normalizedWorkerAsrPilotUrl),
    );
  }

  final Uri backendBaseUri;
  final bool useDemoBackend;
  final int childAge;
  final bool enableInnotrikBle;
  final bool enableHfpAudio;
  final bool preferBleStreaming;
  final bool realtimeBatchFallback;
  final int realtimeFallbackBufferBytes;
  final bool enableWorkerAsrPilot;
  final bool enableWorkerAsrPrepare;
  final bool enableWorkerAsrPcmTrim;
  final Uri? workerAsrPilotBaseUri;

  bool get workerAsrPilotReady =>
      enableWorkerAsrPilot &&
      workerAsrPilotBaseUri != null &&
      (workerAsrPilotBaseUri!.scheme == 'https' ||
          workerAsrPilotBaseUri!.scheme == 'http');

  bool get workerAsrPrepareReady =>
      workerAsrPilotReady && enableWorkerAsrPrepare;

  bool get workerAsrPcmTrimReady =>
      workerAsrPilotReady && enableWorkerAsrPcmTrim;

  Uri resolve(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return backendBaseUri.resolve(normalizedPath);
  }
}
