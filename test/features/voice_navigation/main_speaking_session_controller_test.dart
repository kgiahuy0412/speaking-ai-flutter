import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_speaking_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exits speaking mode after ten seconds of waiting for Main', () async {
    final controller = MainSpeakingSessionController(
      idleTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);

    controller.enter();
    expect(controller.state, MainSpeakingSessionState.ready);

    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(controller.state, MainSpeakingSessionState.inactive);
    expect(controller.isActive, isFalse);
  });

  test('suspends idle timeout while a speaking turn is active', () async {
    final controller = MainSpeakingSessionController(
      idleTimeout: const Duration(milliseconds: 30),
    );
    addTearDown(controller.dispose);

    controller.enter();
    controller.synchronize(isRecording: true, isBusy: true, isPlaying: false);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(controller.state, MainSpeakingSessionState.recording);

    controller.synchronize(isRecording: false, isBusy: true, isPlaying: false);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(controller.state, MainSpeakingSessionState.processing);

    controller.synchronize(isRecording: false, isBusy: false, isPlaying: true);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(controller.state, MainSpeakingSessionState.playing);

    controller.synchronize(isRecording: false, isBusy: false, isPlaying: false);
    expect(controller.state, MainSpeakingSessionState.ready);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(controller.state, MainSpeakingSessionState.inactive);
  });

  test('repeated synchronization does not extend the ready timeout', () async {
    final controller = MainSpeakingSessionController(
      idleTimeout: const Duration(milliseconds: 30),
    );
    addTearDown(controller.dispose);

    controller.enter();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.synchronize(isRecording: false, isBusy: false, isPlaying: false);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.state, MainSpeakingSessionState.inactive);
  });
}
