import 'dart:async';

import 'package:ai_speaking_flutter_app/core/audio/audio_input.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_control.dart';
import 'package:ai_speaking_flutter_app/core/audio/hfp_audio_route_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first owner opens HFP and final owner closes it', () async {
    final native = _FakeHfpAudioControl();
    final coordinator = HfpAudioRouteCoordinator(native);
    addTearDown(coordinator.dispose);
    final lesson = coordinator.createScope('lesson');
    final speech = coordinator.createScope('apple-speech');

    await lesson.startAudioRoute();
    await speech.startAudioRoute();
    expect(native.startCalls, 1);

    await lesson.stopAudioRoute();
    expect(native.stopCalls, 0);
    await speech.stopAudioRoute();
    expect(native.stopCalls, 1);
  });

  test('revalidating one scope keeps the same lease and route', () async {
    final native = _FakeHfpAudioControl();
    final coordinator = HfpAudioRouteCoordinator(native);
    addTearDown(coordinator.dispose);
    final lesson = coordinator.createScope('lesson');

    await lesson.startAudioRoute();
    final firstToken =
        (lesson as HfpAudioRouteLeaseControl).activeAudioRouteToken;
    await lesson.startAudioRoute();

    expect(native.startCalls, 2);
    expect(
      (lesson as HfpAudioRouteLeaseControl).activeAudioRouteToken,
      firstToken,
    );
    await lesson.stopAudioRoute();
    expect(native.stopCalls, 1);
  });

  test('handoff does not close a route retained by native speech', () async {
    final native = _FakeHfpAudioControl();
    final coordinator = HfpAudioRouteCoordinator(native);
    addTearDown(coordinator.dispose);
    final lesson = coordinator.createScope('lesson');
    final speech = coordinator.createScope('apple-speech');

    await lesson.startAudioRoute();
    await speech.startAudioRoute();
    await (lesson as HfpAudioRouteLeaseControl).handoffAudioRoute();
    expect(native.stopCalls, 0);

    await lesson.stopAudioRoute();
    expect(native.stopCalls, 0);
    await speech.stopAudioRoute();
    expect(native.stopCalls, 1);
  });

  test('disposing an old scope cannot close the next owner', () async {
    final native = _FakeHfpAudioControl();
    final coordinator = HfpAudioRouteCoordinator(native);
    addTearDown(coordinator.dispose);
    final oldLesson = coordinator.createScope('old-lesson');
    final nextLesson = coordinator.createScope('next-lesson');

    await oldLesson.startAudioRoute();
    await nextLesson.startAudioRoute();
    await oldLesson.dispose();
    expect(native.stopCalls, 0);

    await nextLesson.stopAudioRoute();
    expect(native.stopCalls, 1);
  });
}

class _FakeHfpAudioControl implements HfpAudioControl {
  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  bool get usesBrowserAudioInput => false;

  @override
  BluetoothAudioStatus get status => const BluetoothAudioStatus(
    phase: BluetoothAudioConnectionPhase.ready,
    routeActive: true,
  );

  @override
  Stream<BluetoothAudioStatus> get statusChanges =>
      const Stream<BluetoothAudioStatus>.empty();

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
    startCalls += 1;
  }

  @override
  Future<void> stopAudioRoute() async {
    stopCalls += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}
