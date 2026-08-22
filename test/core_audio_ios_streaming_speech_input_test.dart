import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS native speech keeps Apple latency and privacy telemetry', () async {
    const methodChannel = MethodChannel('test_ios_native_speech');
    final events = StreamController<dynamic>.broadcast();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'speech.isAvailable':
        case 'speech.prepare':
          return true;
        case 'speech.start':
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

    await input.start();
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

  test('iOS native runtime error exposes its private WAV for Batch', () async {
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
    expect(fallback?.filePath, '/tmp/homi-ios-speech.wav');
    expect(fallback?.isBluetoothInput, isTrue);
    expect(fallback?.recordingSampleRate, 16000);
    expect(input.takeFallbackAudioCapture(), isNull);
  });

  test('iOS MAIN opens and releases the selected H20 HFP route', () async {
    const methodChannel = MethodChannel('test_ios_native_hfp_route');
    final events = StreamController<dynamic>.broadcast();
    final route = _FakeHfpAudioControl();
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
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async {
    startCount += 1;
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
  Future<void> disconnect() async {}

  @override
  Future<void> startAudioRoute() async {
    startRouteCount += 1;
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
