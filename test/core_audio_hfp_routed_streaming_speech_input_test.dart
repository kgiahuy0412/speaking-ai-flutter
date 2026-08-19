import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_routed_streaming_speech_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/streaming_speech_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'MAIN command opens HFP before listening and closes it on stop',
    () async {
      final actions = <String>[];
      final hfp = _FakeHfpAudioControl(actions: actions, connected: true);
      final input = _FakeCommandSpeechInput(actions);
      final routed = HfpRoutedStreamingSpeechInput(
        speechInput: input,
        hfpAudioControl: hfp,
      );

      await routed.startCommandRecognition();
      final capture = await routed.stop();

      expect(capture.sourceText, 'học tiếng Anh');
      expect(actions, <String>[
        'hfp.start',
        'speech.start.normal',
        'speech.stop',
        'hfp.stop',
      ]);
      await routed.dispose();
    },
  );

  test('MAIN cancellation always releases an active HFP route', () async {
    final actions = <String>[];
    final routed = HfpRoutedStreamingSpeechInput(
      speechInput: _FakeCommandSpeechInput(actions),
      hfpAudioControl: _FakeHfpAudioControl(actions: actions, connected: true),
    );

    await routed.start();
    await routed.cancel();

    expect(actions, <String>[
      'hfp.start',
      'speech.start.normal',
      'speech.cancel',
      'hfp.stop',
    ]);
    await routed.dispose();
  });

  test(
    'MAIN keeps the normal microphone path when HFP is not selected',
    () async {
      final actions = <String>[];
      final routed = HfpRoutedStreamingSpeechInput(
        speechInput: _FakeCommandSpeechInput(actions),
        hfpAudioControl: _FakeHfpAudioControl(
          actions: actions,
          connected: false,
        ),
      );

      await routed.startCommandRecognition();
      await routed.cancel();

      expect(actions, <String>['speech.start.command', 'speech.cancel']);
      await routed.dispose();
    },
  );
}

class _FakeCommandSpeechInput
    implements StreamingSpeechInput, CommandStreamingSpeechInput {
  _FakeCommandSpeechInput(this.actions);

  final List<String> actions;

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<void> get completed => const Stream<void>.empty();

  @override
  String get label => 'fake';

  @override
  Stream<String> get partialText => const Stream<String>.empty();

  @override
  Future<bool> checkAvailability() async => true;

  @override
  Future<void> start() async => actions.add('speech.start.normal');

  @override
  Future<void> startCommandRecognition() async =>
      actions.add('speech.start.command');

  @override
  Future<StreamingSpeechCapture> stop() async {
    actions.add('speech.stop');
    return const StreamingSpeechCapture(
      sourceText: 'học tiếng Anh',
      duration: Duration(seconds: 1),
      inputLabel: 'fake',
      confidence: null,
      firstResultMs: null,
      finalAfterStopMs: 10,
    );
  }

  @override
  Future<void> cancel() async => actions.add('speech.cancel');

  @override
  Future<void> dispose() async => actions.add('speech.dispose');
}

class _FakeHfpAudioControl implements HfpAudioControl {
  _FakeHfpAudioControl({required this.actions, required bool connected})
    : _status = BluetoothAudioStatus(
        phase: connected
            ? BluetoothAudioConnectionPhase.ready
            : BluetoothAudioConnectionPhase.idle,
      );

  final List<String> actions;
  BluetoothAudioStatus _status;

  @override
  BluetoothAudioStatus get status => _status;

  @override
  Stream<BluetoothAudioStatus> get statusChanges =>
      const Stream<BluetoothAudioStatus>.empty();

  @override
  bool get usesBrowserAudioInput => false;

  @override
  Future<void> startAudioRoute() async {
    actions.add('hfp.start');
    _status = const BluetoothAudioStatus(
      phase: BluetoothAudioConnectionPhase.recording,
      routeActive: true,
    );
  }

  @override
  Future<void> stopAudioRoute() async {
    actions.add('hfp.stop');
    _status = const BluetoothAudioStatus(
      phase: BluetoothAudioConnectionPhase.ready,
    );
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<List<HfpAudioDevice>> findDevices() async => const <HfpAudioDevice>[];

  @override
  Future<void> connect(HfpAudioDevice device) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}
