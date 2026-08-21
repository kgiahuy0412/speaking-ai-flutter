import 'package:flutter/foundation.dart';

class AppConfig {
  static const String productionBackendBaseUrl =
      'https://speaking-ai-nextjs-backend-production.up.railway.app';

  const AppConfig({
    required this.backendBaseUri,
    required this.useDemoBackend,
    required this.childAge,
    this.enableAiv0BleControl = true,
    this.aiv0DraftProtocolConfirmed = false,
    this.enableLegacyBleAudio = false,
    this.enableHfpAudio = true,
    this.preferBleStreaming = false,
    this.realtimeBatchFallback = true,
    this.realtimeFallbackBufferBytes = 15 * 1024 * 1024,
    this.enableWorkerAsrPilot = false,
    this.enableWorkerAsrPrepare = false,
    this.enableWorkerAsrPcmTrim = true,
    this.workerAsrPilotBaseUri,
    this.enableVoiceNavigation = true,
    this.autoStartVoiceNavigation = false,
    this.privacyPolicyUri,
    this.termsUri,
    this.supportUri,
    this.aiSubprocessors = '',
    this.dataRetentionSummary = '',
  });

  factory AppConfig.fromEnvironment() {
    const configuredBackendUrl = String.fromEnvironment(
      'BACKEND_BASE_URL',
      defaultValue: '',
    );
    // A build without dart-defines must remain usable on a real device/PWA.
    // Local development can still opt in explicitly with BACKEND_BASE_URL.
    final rawBackendUrl = configuredBackendUrl.trim().isNotEmpty
        ? configuredBackendUrl.trim()
        : productionBackendBaseUrl;
    const configuredWorkerAsrPilotUrl = String.fromEnvironment(
      'WORKER_ASR_PILOT_URL',
      defaultValue: '',
    );
    final normalizedWorkerAsrPilotUrl = configuredWorkerAsrPilotUrl.trim();
    const configuredPrivacyPolicyUrl = String.fromEnvironment(
      'PRIVACY_POLICY_URL',
      defaultValue: '',
    );
    const configuredTermsUrl = String.fromEnvironment(
      'TERMS_URL',
      defaultValue: '',
    );
    const configuredSupportUrl = String.fromEnvironment(
      'SUPPORT_URL',
      defaultValue: '',
    );

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
      enableAiv0BleControl: const bool.fromEnvironment(
        'ENABLE_AIV0_BLE_CONTROL',
        defaultValue: true,
      ),
      aiv0DraftProtocolConfirmed: const bool.fromEnvironment(
        'AIV0_DRAFT_PROTOCOL_CONFIRMED',
        defaultValue: false,
      ),
      enableLegacyBleAudio: const bool.fromEnvironment(
        'ENABLE_LEGACY_BLE_AUDIO',
        defaultValue: false,
      ),
      enableHfpAudio: const bool.fromEnvironment(
        'ENABLE_HFP_AUDIO',
        defaultValue: true,
      ),
      preferBleStreaming: const bool.fromEnvironment(
        'PREFER_BLE_STREAMING',
        defaultValue: false,
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
      enableVoiceNavigation: const bool.fromEnvironment(
        'ENABLE_VOICE_NAVIGATION',
        defaultValue: true,
      ),
      autoStartVoiceNavigation: const bool.fromEnvironment(
        'AUTO_START_VOICE_NAVIGATION',
        defaultValue: false,
      ),
      privacyPolicyUri: _httpsUriOrNull(configuredPrivacyPolicyUrl),
      termsUri: _httpsUriOrNull(configuredTermsUrl),
      supportUri: _httpsUriOrNull(configuredSupportUrl),
      aiSubprocessors: const String.fromEnvironment(
        'AI_SUBPROCESSORS',
        defaultValue: '',
      ),
      dataRetentionSummary: const String.fromEnvironment(
        'DATA_RETENTION_SUMMARY',
        defaultValue: '',
      ),
    );
  }

  final Uri backendBaseUri;
  final bool useDemoBackend;
  final int childAge;
  final bool enableAiv0BleControl;

  /// Enables the draft 12-byte button/8-byte APP-state codec only after ODM
  /// confirms the raw packets. Raw BLE diagnostics remain available when off.
  final bool aiv0DraftProtocolConfirmed;

  /// Legacy FF12/FF13/FF14 BLE audio. Disabled for the AIV0 V1 architecture.
  final bool enableLegacyBleAudio;
  final bool enableHfpAudio;
  final bool preferBleStreaming;
  final bool realtimeBatchFallback;
  final int realtimeFallbackBufferBytes;
  final bool enableWorkerAsrPilot;
  final bool enableWorkerAsrPrepare;
  final bool enableWorkerAsrPcmTrim;
  final Uri? workerAsrPilotBaseUri;
  final bool enableVoiceNavigation;

  /// Keeps voice navigation listening while the Android app is in the
  /// foreground. Each recognition window is restarted after a short pause.
  /// Web remains gesture-driven because browsers can block microphone capture
  /// that was not initiated by the user.
  final bool autoStartVoiceNavigation;
  final Uri? privacyPolicyUri;
  final Uri? termsUri;
  final Uri? supportUri;

  /// Human-readable providers that may receive child voice/text data.
  /// Release CI requires this value instead of silently guessing providers.
  final String aiSubprocessors;

  /// Human-readable retention and deletion terms shown before consent.
  /// This must match the production backend behavior and Privacy Policy.
  final String dataRetentionSummary;

  bool get privacyReleaseConfigurationComplete =>
      privacyPolicyUri != null &&
      termsUri != null &&
      supportUri != null &&
      aiSubprocessors.trim().isNotEmpty &&
      dataRetentionSummary.trim().isNotEmpty;

  String get disclosedAiSubprocessors => aiSubprocessors.trim().isEmpty
      ? 'HOMI backend, Cloudflare và OpenAI'
      : aiSubprocessors.trim();

  String get disclosedDataRetention => dataRetentionSummary.trim().isEmpty
      ? 'Chưa cấu hình thời hạn lưu và xóa dữ liệu cho bản phát hành.'
      : dataRetentionSummary.trim();

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

  static Uri? _httpsUriOrNull(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }
}
