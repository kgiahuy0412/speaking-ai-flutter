import 'audio_turn_coordinator.dart';
import 'hfp_audio_control.dart';
import 'streaming_speech_input.dart';

/// Audio capabilities exposed to learning features without depending on a
/// conversation presentation controller.
abstract interface class LearningAudioDependencies {
  AudioTurnCoordinator? get audioTurnCoordinator;
  StreamingSpeechInput? get learningSpeechInput;
  HfpAudioControl? createLearningAudioRouteControl();
}
