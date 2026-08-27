import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS forwards native speech activity and preserves dBFS', () async {
    final events = StreamController<dynamic>.broadcast();
    final input = AndroidStreamingSpeechInput(
      eventStream: events.stream,
      platformName: 'iOS',
    );
    addTearDown(() async {
      await input.dispose();
      await events.close();
    });

    final beganSpeech = input.speechStarted.first;
    events.add(<String, dynamic>{'type': 'speech.begin'});
    await beganSpeech;

    final amplitude = input.amplitudeDbfs.first;
    events.add(<String, dynamic>{'type': 'speech.rms', 'rmsDb': -18.5});
    expect(await amplitude, -18.5);
  });

  test('iOS native speech keeps Apple latency and privacy telemetry', () async {
    const methodChannel = MethodChannel('test_ios_native_speech');
    final events = StreamController<dynamic>.broadcast();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? receivedAudioSource;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'speech.isAvailable':
        case 'speech.prepare':
          return true;
        case 'speech.start':
          receivedAudioSource =
              (call.arguments as Map<Object?, Object?>?)?['audioSource']
                  as String?;
          scheduleMicrotask(() {
            events.add(<String, dynamic>{
              'type': 'speech.ready',
              'engine': 'speech_analyzer',
              'locale': 'vi-VN',
              'onDevice': true,
              'audioRoute': 'in=[BuiltInMic:iPhone]',
              'listeningReadyMs': 42,
            });
          });
          return true;
        case 'speech.stop':
          return true;
        case 'speech.cancel':
          return true;
      }
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(methodChannel, null);
      await events.close();
    });

    final input = IOSStreamingSpeechInput(
      methodChannel: methodChannel,
      eventStream: events.stream,
    );
    addTearDown(input.dispose);
    expect(input, isNot(isA<BatchFallbackCapableNativeSpeechInput>()));

    await input.start();
    expect(receivedAudioSource, 'builtInMic');
    events.add(<String, dynamic>{
      'type': 'speech.partial',
      'text': 'xin chào',
      'alternatives': <String>['xin chào'],
      'engine': 'speech_analyzer',
      'locale': 'vi-VN',
      'onDevice': true,
      'firstPartialMs': 118,
    });
    events.add(<String, dynamic>{
      'type': 'speech.final',
      'text': 'xin chào',
      'alternatives': <String>['xin chào'],
      'confidence': 0.91,
      'engine': 'speech_analyzer',
      'locale': 'vi-VN',
      'onDevice': true,
      'finalTranscriptMs': 354,
    });
    await Future<void>.delayed(Duration.zero);

    final capture = await input.stop();
    expect(capture.sourceText, 'xin chào');
    expect(capture.inputLabel, 'Apple Native Speech');
    expect(capture.recordedAudio, isNull);
    expect(capture.extraBenchmark, containsPair('nativeSpeechOnDevice', true));
    expect(
      capture.extraBenchmark,
      containsPair('nativeSpeechEngine', 'speech_analyzer'),
    );
    expect(
      capture.extraBenchmark,
      containsPair('nativeSpeechListeningReadyMs', 42),
    );
    expect(
      capture.extraBenchmark,
      containsPair('nativeSpeechFirstPartialMs', 118),
    );
    expect(
      capture.extraBenchmark,
      containsPair('nativeSpeechFinalTranscriptMs', 354),
    );
  });

  test('iOS native runtime error never exposes a Batch WAV', () async {
    const methodChannel = MethodChannel('test_ios_native_runtime_error');
    final events = StreamController<dynamic>.broadcast();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'speech.isAvailable':
          return true;
        case 'speech.start':
          scheduleMicrotask(() {
            events.add(<String, dynamic>{
              'type': 'speech.ready',
              'engine': 'speech_analyzer',
              'onDevice': true,
            });
          });
          return true;
        case 'speech.stop':
        case 'speech.cancel':
          return true;
      }
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(methodChannel, null);
      await events.close();
    });
    final input = IOSStreamingSpeechInput(
      methodChannel: methodChannel,
      eventStream: events.stream,
    );
    addTearDown(input.dispose);

    await input.start();
    events.add(<String, dynamic>{
      'type': 'speech.partial',
      'text': 'xin chào',
      'engine': 'speech_analyzer',
    });
    events.add(<String, dynamic>{
      'type': 'speech.error',
      'code': 'SPEECH_ANALYZER_FAILED',
      'message': 'SpeechAnalyzer interrupted',
      'audioPath': '/tmp/homi-ios-speech.wav',
      'audioMimeType': 'audio/wav',
      'audioByteLength': 4096,
      'audioSampleRate': 16000,
      'isBluetoothInput': true,
    });
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      input.stop(),
      throwsA(isA<StreamingSpeechInputException>()),
    );
    final fallback = input.takeFallbackAudioCapture();
    expect(fallback, isNull);
    expect(input.takeFallbackAudioCapture(), isNull);
  });

  test('iOS MAIN opens and releases the selected H20 HFP route', () async {
    const methodChannel = MethodChannel('test_ios_native_hfp_route');
    final events = StreamController<dynamic>.broadcast();
    final route = _FakeHfpAudioControl();
    bool? receivedCommandMode;
    String? receivedAudioSource;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'speech.isAvailable':
          return true;
        case 'speech.start':
          receivedCommandMode =
              (call.arguments as Map<Object?, Object?>?)?['commandMode']
                  as bool?;
          receivedAudioSource =
              (call.arguments as Map<Object?, Object?>?)?['audioSource']
                  as String?;
          scheduleMicrotask(() {
            events.add(<String, dynamic>{
              'type': 'speech.ready',
              'engine': 'speech_analyzer',
              'audioRoute': 'in=[BluetoothHFP:H20]',
            });
          });
          return true;
        case 'speech.stop':
        case 'speech.cancel':
          return true;
      }
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(methodChannel, null);
      await events.close();
      await route.dispose();
    });

    final input = IOSStreamingSpeechInput(
      methodChannel: methodChannel,
      eventStream: events.stream,
      audioRouteControl: route,
    );
    addTearDown(input.dispose);

    await input.startCommandRecognition();
    expect(route.startRouteCount, 1);
    expect(route.status.routeActive, isTrue);
    expect(receivedCommandMode, isTrue);
    expect(receivedAudioSource, 'hfp');

    events.add(<String, dynamic>{
      'type': 'speech.final',
      'text': 'học từ vựng',
      'alternatives': <String>['học từ vựng'],
      'engine': 'speech_analyzer',
    });
    await Future<void>.delayed(Duration.zero);
    final capture = await input.stop();

    expect(capture.sourceText, 'học từ vựng');
    expect(route.stopRouteCount, 1);
    expect(route.status.routeActive, isFalse);
  });

  test('iOS lesson requests English Apple Speech on the H20 route', () async {
    const methodChannel = MethodChannel('test_ios_lesson_english_hfp');
    final events = StreamController<dynamic>.broadcast();
    final route = _FakeHfpAudioControl();
    bool? receivedCommandMode;
    String? receivedAudioSource;
    String? receivedLocale;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'speech.isAvailable':
          return true;
        case 'speech.start':
          final arguments = call.arguments as Map<Object?, Object?>?;
          receivedCommandMode = arguments?['commandMode'] as bool?;
          receivedAudioSource = arguments?['audioSource'] as String?;
          receivedLocale = arguments?['locale'] as String?;
          scheduleMicrotask(() {
            events.add(<String, dynamic>{
              'type': 'speech.ready',
              'engine': 'sf_speech_recognizer',
              'locale': 'en-US',
              'audioRoute': 'in=[BluetoothHFP:H20]',
            });
          });
          return true;
        case 'speech.stop':
        case 'speech.cancel':
          return true;
      }
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(methodChannel, null);
      await events.close();
      await route.dispose();
    });

    final input = IOSStreamingSpeechInput(
      methodChannel: methodChannel,
      eventStream: events.stream,
      audioRouteControl: route,
    );
    addTearDown(input.dispose);

    await input.startLessonEnglishRecognition();
    expect(receivedCommandMode, isFalse);
    expect(receivedAudioSource, 'hfp');
    expect(receivedLocale, 'en-US');
    expect(route.startRouteCount, 1);

    events.add(<String, dynamic>{
      'type': 'speech.final',
      'text': 'I am hungry',
      'alternatives': <String>['I am hungry'],
      'engine': 'sf_speech_recognizer',
      'locale': 'en-US',
    });
    await Future<void>.delayed(Duration.zero);
    final capture = await input.stop();

    expect(capture.sourceText, 'I am hungry');
    expect(route.stopRouteCount, 1);
  });

  test('iOS MAIN reports HFP route failure without changing mic', () async {
    const methodChannel = MethodChannel('test_ios_native_hfp_fallback');
    final events = StreamController<dynamic>.broadcast();
    final route = _FakeHfpAudioControl(
      startError: const HfpAudioException('HFP route unavailable'),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var nativeStartCount = 0;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'speech.isAvailable':
          return true;
        case 'speech.start':
          nativeStartCount += 1;
          return true;
        case 'speech.cancel':
          return true;
      }
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(methodChannel, null);
      await events.close();
      await route.dispose();
    });

    final input = IOSStreamingSpeechInput(
      methodChannel: methodChannel,
      eventStream: events.stream,
      audioRouteControl: route,
    );
    addTearDown(input.dispose);

    await expectLater(
      input.startCommandRecognition(),
      throwsA(isA<HfpAudioException>()),
    );

    expect(route.startRouteCount, 1);
    expect(route.disconnectCount, 0);
    expect(nativeStartCount, 0);
  });

  test('physical MAIN one-shot source bypasses a selected HFP route', () async {
    const methodChannel = MethodChannel('test_ios_forced_phone_mic');
    final events = StreamController<dynamic>.broadcast();
    final route = _FakeHfpAudioControl();
    String? receivedAudioSource;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'speech.isAvailable':
          return true;
        case 'speech.start':
          receivedAudioSource =
              (call.arguments as Map<Object?, Object?>?)?['audioSource']
                  as String?;
          scheduleMicrotask(() {
            events.add(<String, dynamic>{
              'type': 'speech.ready',
              'audioSource': 'builtInMic',
              'audioRoute': 'in=[BuiltInMic:iPhone]',
            });
          });
          return true;
        case 'speech.cancel':
          return true;
      }
      return null;
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(methodChannel, null);
      await events.close();
      await route.dispose();
    });

    final input = IOSStreamingSpeechInput(
      methodChannel: methodChannel,
      eventStream: events.stream,
      audioRouteControl: route,
    );
    addTearDown(input.dispose);

    input.useNativeSpeechAudioSourceOnce(NativeSpeechAudioSource.builtInMic);
    await input.startCommandRecognition();

    expect(receivedAudioSource, 'builtInMic');
    expect(route.startRouteCount, 0);
  });

  test(
    'iOS reports native HFP start failure without retrying phone mic',
    () async {
      const methodChannel = MethodChannel('test_ios_native_start_failure');
      final events = StreamController<dynamic>.broadcast();
      final route = _FakeHfpAudioControl();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final receivedSources = <String>[];
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        switch (call.method) {
          case 'speech.isAvailable':
            return true;
          case 'speech.start':
            final source =
                (call.arguments as Map<Object?, Object?>?)?['audioSource']
                    as String? ??
                '';
            receivedSources.add(source);
            throw PlatformException(
              code: 'IOS_NATIVE_SPEECH_START_FAILED',
              message: 'AVAudioEngine could not open HFP input',
            );
          case 'speech.cancel':
            return true;
        }
        return null;
      });
      addTearDown(() async {
        messenger.setMockMethodCallHandler(methodChannel, null);
        await events.close();
        await route.dispose();
      });

      final input = IOSStreamingSpeechInput(
        methodChannel: methodChannel,
        eventStream: events.stream,
        audioRouteControl: route,
      );
      addTearDown(input.dispose);

      await expectLater(
        input.startCommandRecognition(),
        throwsA(isA<StreamingSpeechInputException>()),
      );
      expect(route.startRouteCount, 1);
      expect(route.stopRouteCount, 1);
      expect(route.disconnectCount, 0);
      expect(receivedSources, <String>['hfp']);
    },
  );

  test('MAIN uses Batch only when Apple native cannot start', () async {
    final primary = _FakeSpeechInput(
      failOnStart: const StreamingSpeechInputException(
        'Vietnamese model unavailable',
        code: 'IOS_NATIVE_SPEECH_UNAVAILABLE',
      ),
    );
    final fallback = _FakeSpeechInput(
      capture: const StreamingSpeechCapture(
        sourceText: 'mở từ vựng',
        duration: Duration(seconds: 1),
        inputLabel: 'Cloudflare Batch',
        confidence: null,
        firstResultMs: null,
        finalAfterStopMs: 300,
        asrMode: 'batch_chunks',
      ),
    );
    final input = NativeFirstStreamingSpeechInput(
      primary: primary,
      fallback: fallback,
      disposePrimary: true,
      disposeFallback: true,
    );

    await input.startCommandRecognition();
    final capture = await input.stop();

    expect(primary.startCount, 1);
    expect(fallback.commandStartCount, 1);
    expect(capture.sourceText, 'mở từ vựng');
    expect(capture.asrMode, 'batch_chunks');
    expect(
      capture.extraBenchmark,
      containsPair('nativeSpeechFallbackUsed', true),
    );
    expect(
      capture.extraBenchmark?['nativeSpeechFallbackReason'],
      'IOS_NATIVE_SPEECH_UNAVAILABLE',
    );
    await input.dispose();
  });

  test('MAIN falls back when Apple native start does not complete', () async {
    final startGate = Completer<void>();
    final primary = _FakeSpeechInput(startGate: startGate);
    final fallback = _FakeSpeechInput();
    final input = NativeFirstStreamingSpeechInput(
      primary: primary,
      fallback: fallback,
      primaryStartTimeout: const Duration(milliseconds: 5),
      disposePrimary: true,
      disposeFallback: true,
    );

    await input.startCommandRecognition();

    expect(primary.commandStartCount, 1);
    expect(fallback.commandStartCount, 1);
    expect(input.label, fallback.label);
    startGate.complete();
    await input.dispose();
  });

  test(
    'MAIN bounds a stalled native availability check before using fallback',
    () async {
      final availabilityGate = Completer<bool>();
      final primary = _FakeSpeechInput(availabilityGate: availabilityGate);
      final fallback = _FakeSpeechInput();
      final input = NativeFirstStreamingSpeechInput(
        primary: primary,
        fallback: fallback,
        primaryStartTimeout: const Duration(milliseconds: 5),
        disposePrimary: true,
        disposeFallback: true,
      );

      await input.startCommandRecognition();

      expect(primary.commandStartCount, 1);
      expect(fallback.commandStartCount, 1);
      expect(input.label, fallback.label);
      availabilityGate.complete(true);
      await input.dispose();
    },
  );

  test('MAIN recovers the same WAV when Apple native fails at stop', () async {
    const safetyRecording = AudioCapture(
      filePath: '/tmp/homi-ios-speech.wav',
      mimeType: 'audio/wav',
      duration: Duration(milliseconds: 900),
      inputLabel: 'Apple Native Speech',
      isBluetoothInput: true,
      initialNoiseRms: null,
    );
    final primary = _FakeSpeechInput(
      stopError: const StreamingSpeechInputException(
        'SpeechAnalyzer stopped unexpectedly',
        code: 'SPEECH_ANALYZER_FAILED',
      ),
      fallbackAudio: safetyRecording,
    );
    final fallback = _FakeRecordedFallbackSpeechInput(
      capture: const StreamingSpeechCapture(
        sourceText: 'mở chủ đề',
        duration: Duration(milliseconds: 900),
        inputLabel: 'Cloudflare Batch',
        confidence: null,
        firstResultMs: null,
        finalAfterStopMs: 250,
        asrMode: 'batch_chunks',
        isBluetoothInput: true,
        recordedAudio: safetyRecording,
      ),
    );
    final input = NativeFirstStreamingSpeechInput(
      primary: primary,
      fallback: fallback,
      disposePrimary: true,
      disposeFallback: true,
    );

    await input.startCommandRecognition();
    final capture = await input.stop();

    expect(fallback.receivedRecording, same(safetyRecording));
    expect(capture.sourceText, 'mở chủ đề');
    expect(capture.isBluetoothInput, isTrue);
    expect(
      capture.extraBenchmark,
      containsPair('nativeSpeechFallbackUsed', true),
    );
    expect(
      capture.extraBenchmark?['nativeSpeechFallbackReason'],
      'SPEECH_ANALYZER_FAILED',
    );
    await input.dispose();
  });
}

class _FakeSpeechInput
    implements
        StreamingSpeechInput,
        CommandStreamingSpeechInput,
        NativeSpeechFallbackAudioProvider {
  _FakeSpeechInput({
    this.failOnStart,
    this.stopError,
    this.fallbackAudio,
    this.startGate,
    this.availabilityGate,
    this.capture = const StreamingSpeechCapture(
      sourceText: 'xin chào',
      duration: Duration(seconds: 1),
      inputLabel: 'Fake',
      confidence: null,
      firstResultMs: 100,
      finalAfterStopMs: 100,
    ),
  });

  final StreamingSpeechInputException? failOnStart;
  final StreamingSpeechInputException? stopError;
  final AudioCapture? fallbackAudio;
  final Completer<void>? startGate;
  final Completer<bool>? availabilityGate;
  final StreamingSpeechCapture capture;
  final StreamController<double> _amplitude =
      StreamController<double>.broadcast();
  final StreamController<void> _completed = StreamController<void>.broadcast();
  final StreamController<String> _partial =
      StreamController<String>.broadcast();
  int startCount = 0;
  int commandStartCount = 0;

  @override
  String get label => capture.inputLabel;

  @override
  Stream<double> get amplitudeDbfs => _amplitude.stream;

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Stream<String> get partialText => _partial.stream;

  @override
  Future<bool> checkAvailability() async =>
      availabilityGate == null ? true : await availabilityGate!.future;

  @override
  Future<void> start() async {
    startCount += 1;
    if (availabilityGate != null) {
      await availabilityGate!.future;
    }
    await startGate?.future;
    final error = failOnStart;
    if (error != null) throw error;
  }

  @override
  Future<void> startCommandRecognition() async {
    commandStartCount += 1;
    await start();
  }

  @override
  Future<StreamingSpeechCapture> stop() async {
    final error = stopError;
    if (error != null) throw error;
    return capture;
  }

  @override
  AudioCapture? takeFallbackAudioCapture() => fallbackAudio;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    await _amplitude.close();
    await _completed.close();
    await _partial.close();
  }
}

class _FakeRecordedFallbackSpeechInput extends _FakeSpeechInput
    implements RecordedAudioFallbackSpeechInput {
  _FakeRecordedFallbackSpeechInput({required super.capture});

  AudioCapture? receivedRecording;

  @override
  Future<StreamingSpeechCapture> recognizeRecordedAudio(
    AudioCapture capture, {
    String? fallbackReason,
  }) async {
    receivedRecording = capture;
    return this.capture;
  }
}

class _FakeHfpAudioControl implements HfpAudioControl {
  _FakeHfpAudioControl({this.startError});

  final Object? startError;
  final StreamController<BluetoothAudioStatus> _statuses =
      StreamController<BluetoothAudioStatus>.broadcast(sync: true);
  BluetoothAudioStatus _status = const BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.ready,
    deviceId: 'h20-hfp',
    deviceName: 'H20',
    sampleRate: 16000,
  );
  int startRouteCount = 0;
  int stopRouteCount = 0;
  int disconnectCount = 0;

  @override
  bool get usesBrowserAudioInput => false;

  @override
  BluetoothAudioStatus get status => _status;

  @override
  Stream<BluetoothAudioStatus> get statusChanges => _statuses.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<List<HfpAudioDevice>> findDevices() async => const <HfpAudioDevice>[];

  @override
  Future<void> connect(HfpAudioDevice device) async {}

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
  }

  @override
  Future<void> startAudioRoute() async {
    startRouteCount += 1;
    final error = startError;
    if (error != null) throw error;
    _status = const BluetoothAudioStatus(
      phase: BluetoothAudioConnectionPhase.recording,
      deviceId: 'h20-hfp',
      deviceName: 'H20',
      sampleRate: 16000,
      routeActive: true,
    );
    _statuses.add(_status);
  }

  @override
  Future<void> stopAudioRoute() async {
    stopRouteCount += 1;
    _status = const BluetoothAudioStatus(
      phase: BluetoothAudioConnectionPhase.ready,
      deviceId: 'h20-hfp',
      deviceName: 'H20',
      sampleRate: 16000,
    );
    _statuses.add(_status);
  }

  @override
  Future<void> dispose() => _statuses.close();
}
