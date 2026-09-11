import 'audio_turn_coordinator.dart';
import 'coordinated_voice_prompt_service.dart';
import 'voice_prompt_service_base.dart';
import 'voice_prompt_service_native.dart'
    if (dart.library.js_interop) 'voice_prompt_service_web.dart'
    as platform;

export 'voice_prompt_service_base.dart';
export 'audio_turn_coordinator.dart' show AudioTurnCoordinator, AudioTurnOwner;

VoicePromptService createVoicePromptService({
  AudioTurnCoordinator? coordinator,
  AudioTurnOwner owner = AudioTurnOwner.legacy,
}) {
  final service = platform.createPlatformVoicePromptService();
  return coordinator == null
      ? service
      : CoordinatedVoicePromptService(
          delegate: service,
          coordinator: coordinator,
          owner: owner,
        );
}
