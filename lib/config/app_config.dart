import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({
    required this.backendBaseUri,
    required this.useDemoBackend,
    required this.childAge,
    this.preferBleStreaming = true,
    this.realtimeBatchFallback = true,
    this.realtimeFallbackBufferBytes = 15 * 1024 * 1024,
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
    );
  }

  final Uri backendBaseUri;
  final bool useDemoBackend;
  final int childAge;
  final bool preferBleStreaming;
  final bool realtimeBatchFallback;
  final int realtimeFallbackBufferBytes;

  Uri resolve(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return backendBaseUri.resolve(normalizedPath);
  }
}
