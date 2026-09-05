import 'package:ai_speaking_flutter_app/features/listening/application/android_offline_speech_model_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelAndroidOfflineSpeechModelService', () {
    const channel = MethodChannel('test.offline-model');

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('reads installed en-US model status from Android', () async {
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            receivedCall = call;
            return <String, Object?>{
              'state': 'installed',
              'apiLevel': 33,
              'strictOnDeviceAvailable': false,
              'appManaged': true,
              'progress': 100,
              'modelId': 'vosk-model-small-en-us-0.15',
              'downloadBytes': 41205931,
            };
          });
      const service = MethodChannelAndroidOfflineSpeechModelService(
        channel: channel,
      );

      final status = await service.status();

      expect(receivedCall?.method, 'model.status');
      expect(receivedCall?.arguments, <String, Object?>{'locale': 'en-US'});
      expect(status.state, AndroidOfflineSpeechModelState.installed);
      expect(status.apiLevel, 33);
      expect(status.strictOnDeviceAvailable, isFalse);
      expect(status.appManaged, isTrue);
      expect(status.progress, 100);
      expect(status.modelId, 'vosk-model-small-en-us-0.15');
    });

    test(
      'maps native Wi-Fi requirement without treating it as consent',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              throw PlatformException(
                code: 'ON_DEVICE_MODEL_WIFI_REQUIRED',
                message: 'Wi-Fi required',
              );
            });
        const service = MethodChannelAndroidOfflineSpeechModelService(
          channel: channel,
        );

        expect(
          await service.requestDownload(),
          AndroidOfflineSpeechModelDownloadResult.waitingForWifi,
        );
      },
    );
  });

  group('AndroidOfflineSpeechModelCoordinator', () {
    test('asks once, saves approval, and requests download', () async {
      final service = _FakeModelService(
        statusValue: const AndroidOfflineSpeechModelStatus(
          state: AndroidOfflineSpeechModelState.missing,
        ),
        downloadValue: AndroidOfflineSpeechModelDownloadResult.waitingForWifi,
      );
      final store = _MemoryConsentStore();
      final coordinator = AndroidOfflineSpeechModelCoordinator(
        service: service,
        consentStore: store,
      );
      var promptCount = 0;

      final first = await coordinator.prepare(
        requestConsent: () async {
          promptCount += 1;
          return true;
        },
      );
      final second = await coordinator.prepare(
        requestConsent: () async {
          promptCount += 1;
          return true;
        },
      );

      expect(first, AndroidOfflineSpeechModelPreparationResult.waitingForWifi);
      expect(second, AndroidOfflineSpeechModelPreparationResult.waitingForWifi);
      expect(promptCount, 1);
      expect(store.value, AndroidOfflineSpeechModelConsent.allowed);
      expect(service.downloadRequests, 2);
    });

    test('remembered decline never requests a model download', () async {
      final service = _FakeModelService(
        statusValue: const AndroidOfflineSpeechModelStatus(
          state: AndroidOfflineSpeechModelState.downloadable,
        ),
      );
      final store = _MemoryConsentStore();
      final coordinator = AndroidOfflineSpeechModelCoordinator(
        service: service,
        consentStore: store,
      );

      final first = await coordinator.prepare(
        requestConsent: () async => false,
      );
      final second = await coordinator.prepare(
        requestConsent: () async => true,
      );

      expect(first, AndroidOfflineSpeechModelPreparationResult.declined);
      expect(second, AndroidOfflineSpeechModelPreparationResult.declined);
      expect(store.value, AndroidOfflineSpeechModelConsent.declined);
      expect(service.downloadRequests, 0);
    });

    test('installed model bypasses consent and download', () async {
      final service = _FakeModelService(
        statusValue: const AndroidOfflineSpeechModelStatus(
          state: AndroidOfflineSpeechModelState.installed,
        ),
      );
      final store = _MemoryConsentStore();
      final coordinator = AndroidOfflineSpeechModelCoordinator(
        service: service,
        consentStore: store,
      );

      final result = await coordinator.prepare(
        requestConsent: () async => fail('Consent must not be requested'),
      );

      expect(result, AndroidOfflineSpeechModelPreparationResult.ready);
      expect(store.value, AndroidOfflineSpeechModelConsent.undecided);
      expect(service.downloadRequests, 0);
    });

    test('undecided consent stays idle during background retries', () async {
      final service = _FakeModelService(
        statusValue: const AndroidOfflineSpeechModelStatus(
          state: AndroidOfflineSpeechModelState.missing,
        ),
      );
      final coordinator = AndroidOfflineSpeechModelCoordinator(
        service: service,
        consentStore: _MemoryConsentStore(),
      );

      expect(
        await coordinator.prepare(),
        AndroidOfflineSpeechModelPreparationResult.idle,
      );
      expect(service.statusRequests, 0);
    });

    test('cancel forwards to the app-owned model downloader', () async {
      final service = _FakeModelService(
        statusValue: const AndroidOfflineSpeechModelStatus(
          state: AndroidOfflineSpeechModelState.pending,
        ),
      );
      final coordinator = AndroidOfflineSpeechModelCoordinator(
        service: service,
        consentStore: _MemoryConsentStore(),
      );

      await coordinator.cancelDownload();

      expect(service.cancelRequests, 1);
    });
  });

  test(
    'SharedPreferences consent store persists the one-time choice',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const store = SharedPreferencesAndroidOfflineSpeechModelConsentStore();

      expect(await store.read(), AndroidOfflineSpeechModelConsent.undecided);
      await store.write(AndroidOfflineSpeechModelConsent.allowed);
      expect(await store.read(), AndroidOfflineSpeechModelConsent.allowed);
    },
  );
}

class _FakeModelService implements AndroidOfflineSpeechModelService {
  _FakeModelService({
    required this.statusValue,
    this.downloadValue = AndroidOfflineSpeechModelDownloadResult.requested,
  });

  final AndroidOfflineSpeechModelStatus statusValue;
  final AndroidOfflineSpeechModelDownloadResult downloadValue;
  int downloadRequests = 0;
  int statusRequests = 0;
  int cancelRequests = 0;

  @override
  Future<void> cancelDownload() async {
    cancelRequests += 1;
  }

  @override
  Future<AndroidOfflineSpeechModelStatus> status({
    String locale = 'en-US',
  }) async {
    statusRequests += 1;
    return statusValue;
  }

  @override
  Future<AndroidOfflineSpeechModelDownloadResult> requestDownload({
    String locale = 'en-US',
  }) async {
    downloadRequests += 1;
    return downloadValue;
  }
}

class _MemoryConsentStore implements AndroidOfflineSpeechModelConsentStore {
  AndroidOfflineSpeechModelConsent value =
      AndroidOfflineSpeechModelConsent.undecided;

  @override
  Future<AndroidOfflineSpeechModelConsent> read() async => value;

  @override
  Future<void> write(AndroidOfflineSpeechModelConsent consent) async {
    value = consent;
  }
}
