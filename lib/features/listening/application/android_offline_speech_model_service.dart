import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AndroidOfflineSpeechModelState {
  installed,
  downloadable,
  pending,
  missing,
  unavailable,
  unknown,
}

class AndroidOfflineSpeechModelStatus {
  const AndroidOfflineSpeechModelStatus({
    required this.state,
    this.apiLevel,
    this.strictOnDeviceAvailable = false,
    this.appManaged = false,
    this.progress = 0,
    this.modelId,
    this.downloadBytes,
  });

  final AndroidOfflineSpeechModelState state;
  final int? apiLevel;
  final bool strictOnDeviceAvailable;
  final bool appManaged;
  final int progress;
  final String? modelId;
  final int? downloadBytes;

  bool get canRequestDownload =>
      state == AndroidOfflineSpeechModelState.downloadable ||
      state == AndroidOfflineSpeechModelState.missing ||
      state == AndroidOfflineSpeechModelState.unknown;
}

enum AndroidOfflineSpeechModelDownloadResult {
  requested,
  waitingForWifi,
  unavailable,
  failed,
}

abstract interface class AndroidOfflineSpeechModelService {
  Future<AndroidOfflineSpeechModelStatus> status({String locale = 'en-US'});

  Future<AndroidOfflineSpeechModelDownloadResult> requestDownload({
    String locale = 'en-US',
  });

  Future<void> cancelDownload();
}

class MethodChannelAndroidOfflineSpeechModelService
    implements AndroidOfflineSpeechModelService {
  const MethodChannelAndroidOfflineSpeechModelService({
    MethodChannel channel = const MethodChannel('homi_offline_speech'),
    Duration timeout = const Duration(seconds: 4),
  }) : _channel = channel,
       _timeout = timeout;

  final MethodChannel _channel;
  final Duration _timeout;

  @override
  Future<AndroidOfflineSpeechModelStatus> status({
    String locale = 'en-US',
  }) async {
    try {
      final payload = await _channel
          .invokeMethod<Object?>('model.status', <String, Object?>{
            'locale': locale,
          })
          .timeout(_timeout);
      if (payload is! Map<Object?, Object?>) {
        return const AndroidOfflineSpeechModelStatus(
          state: AndroidOfflineSpeechModelState.unknown,
        );
      }
      return AndroidOfflineSpeechModelStatus(
        state: _parseState(payload['state']),
        apiLevel: (payload['apiLevel'] as num?)?.toInt(),
        strictOnDeviceAvailable: payload['strictOnDeviceAvailable'] == true,
        appManaged: payload['appManaged'] == true,
        progress: ((payload['progress'] as num?)?.toInt() ?? 0).clamp(0, 100),
        modelId: payload['modelId'] as String?,
        downloadBytes: (payload['downloadBytes'] as num?)?.toInt(),
      );
    } on MissingPluginException {
      return const AndroidOfflineSpeechModelStatus(
        state: AndroidOfflineSpeechModelState.unavailable,
      );
    } on PlatformException catch (error) {
      return AndroidOfflineSpeechModelStatus(
        state: error.code == 'ON_DEVICE_MODEL_UNSUPPORTED'
            ? AndroidOfflineSpeechModelState.unavailable
            : AndroidOfflineSpeechModelState.unknown,
      );
    } on TimeoutException {
      return const AndroidOfflineSpeechModelStatus(
        state: AndroidOfflineSpeechModelState.unknown,
      );
    }
  }

  @override
  Future<AndroidOfflineSpeechModelDownloadResult> requestDownload({
    String locale = 'en-US',
  }) async {
    try {
      final payload = await _channel
          .invokeMethod<Object?>('model.requestDownload', <String, Object?>{
            'locale': locale,
          })
          .timeout(_timeout);
      if (payload is Map<Object?, Object?> && payload['state'] == 'requested') {
        return AndroidOfflineSpeechModelDownloadResult.requested;
      }
      return AndroidOfflineSpeechModelDownloadResult.failed;
    } on MissingPluginException {
      return AndroidOfflineSpeechModelDownloadResult.unavailable;
    } on PlatformException catch (error) {
      if (error.code == 'ON_DEVICE_MODEL_WIFI_REQUIRED') {
        return AndroidOfflineSpeechModelDownloadResult.waitingForWifi;
      }
      if (error.code == 'ON_DEVICE_MODEL_UNSUPPORTED') {
        return AndroidOfflineSpeechModelDownloadResult.unavailable;
      }
      return AndroidOfflineSpeechModelDownloadResult.failed;
    } on TimeoutException {
      return AndroidOfflineSpeechModelDownloadResult.failed;
    }
  }

  @override
  Future<void> cancelDownload() async {
    try {
      await _channel
          .invokeMethod<void>('model.cancelDownload')
          .timeout(_timeout);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    } on TimeoutException {
      return;
    }
  }

  AndroidOfflineSpeechModelState _parseState(Object? rawState) {
    switch (rawState) {
      case 'installed':
        return AndroidOfflineSpeechModelState.installed;
      case 'downloadable':
        return AndroidOfflineSpeechModelState.downloadable;
      case 'pending':
        return AndroidOfflineSpeechModelState.pending;
      case 'missing':
        return AndroidOfflineSpeechModelState.missing;
      case 'unavailable':
      case 'unsupported':
        return AndroidOfflineSpeechModelState.unavailable;
      default:
        return AndroidOfflineSpeechModelState.unknown;
    }
  }
}

enum AndroidOfflineSpeechModelConsent { undecided, allowed, declined }

abstract interface class AndroidOfflineSpeechModelConsentStore {
  Future<AndroidOfflineSpeechModelConsent> read();
  Future<void> write(AndroidOfflineSpeechModelConsent consent);
}

class SharedPreferencesAndroidOfflineSpeechModelConsentStore
    implements AndroidOfflineSpeechModelConsentStore {
  const SharedPreferencesAndroidOfflineSpeechModelConsentStore();

  static const _key = 'homi.offline-language-packs-consent.v2';
  static const _legacyKey = 'homi.android-offline-english-model-consent.v1';

  @override
  Future<AndroidOfflineSpeechModelConsent> read() async {
    final preferences = await SharedPreferences.getInstance();
    final value =
        preferences.getString(_key) ?? preferences.getString(_legacyKey);
    return switch (value) {
      'allowed' => AndroidOfflineSpeechModelConsent.allowed,
      'declined' => AndroidOfflineSpeechModelConsent.declined,
      _ => AndroidOfflineSpeechModelConsent.undecided,
    };
  }

  @override
  Future<void> write(AndroidOfflineSpeechModelConsent consent) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, consent.name);
  }
}

enum AndroidOfflineSpeechModelPreparationResult {
  ready,
  downloadRequested,
  waitingForWifi,
  pending,
  declined,
  unavailable,
  idle,
  failed,
}

class AndroidOfflineSpeechModelCoordinator {
  AndroidOfflineSpeechModelCoordinator({
    AndroidOfflineSpeechModelService service =
        const MethodChannelAndroidOfflineSpeechModelService(),
    AndroidOfflineSpeechModelConsentStore consentStore =
        const SharedPreferencesAndroidOfflineSpeechModelConsentStore(),
  }) : _service = service,
       _consentStore = consentStore;

  final AndroidOfflineSpeechModelService _service;
  final AndroidOfflineSpeechModelConsentStore _consentStore;

  Future<void> cancelDownload() => _service.cancelDownload();

  Future<AndroidOfflineSpeechModelPreparationResult> prepare({
    Future<bool> Function()? requestConsent,
    String locale = 'en-US',
  }) async {
    var consent = await _consentStore.read();
    if (consent == AndroidOfflineSpeechModelConsent.declined) {
      return AndroidOfflineSpeechModelPreparationResult.declined;
    }
    if (consent == AndroidOfflineSpeechModelConsent.undecided &&
        requestConsent == null) {
      return AndroidOfflineSpeechModelPreparationResult.idle;
    }

    final status = await _service.status(locale: locale);
    switch (status.state) {
      case AndroidOfflineSpeechModelState.installed:
        return AndroidOfflineSpeechModelPreparationResult.ready;
      case AndroidOfflineSpeechModelState.pending:
        return AndroidOfflineSpeechModelPreparationResult.pending;
      case AndroidOfflineSpeechModelState.unavailable:
        return AndroidOfflineSpeechModelPreparationResult.unavailable;
      case AndroidOfflineSpeechModelState.downloadable:
      case AndroidOfflineSpeechModelState.missing:
      case AndroidOfflineSpeechModelState.unknown:
        break;
    }

    if (consent == AndroidOfflineSpeechModelConsent.undecided) {
      final allowed = await requestConsent!();
      consent = allowed
          ? AndroidOfflineSpeechModelConsent.allowed
          : AndroidOfflineSpeechModelConsent.declined;
      await _consentStore.write(consent);
    }
    if (consent == AndroidOfflineSpeechModelConsent.declined) {
      return AndroidOfflineSpeechModelPreparationResult.declined;
    }

    return switch (await _service.requestDownload(locale: locale)) {
      AndroidOfflineSpeechModelDownloadResult.requested =>
        AndroidOfflineSpeechModelPreparationResult.downloadRequested,
      AndroidOfflineSpeechModelDownloadResult.waitingForWifi =>
        AndroidOfflineSpeechModelPreparationResult.waitingForWifi,
      AndroidOfflineSpeechModelDownloadResult.unavailable =>
        AndroidOfflineSpeechModelPreparationResult.unavailable,
      AndroidOfflineSpeechModelDownloadResult.failed =>
        AndroidOfflineSpeechModelPreparationResult.failed,
    };
  }
}
