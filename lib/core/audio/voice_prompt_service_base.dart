abstract interface class VoicePromptService {
  Future<void> speak(String text, {String locale = 'vi-VN'});

  /// Plays a prompt and completes only after speech output has stopped.
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'});

  Future<void> stop();

  Future<void> dispose();
}

/// Optional capability for voice prompt implementations that can signal when
/// the child may begin speaking.
abstract interface class SpeechReadyCuePlayer {
  /// Plays a short audible cue and completes after the cue has finished.
  Future<void> playSpeechReadyCue();
}

/// Optional capability for prompts that must be distinguishable from lesson
/// audio routed through a selected two-way H20 device.
abstract interface class PhoneSpeakerVoicePromptService {
  Future<void> speakAndWaitOnPhoneSpeaker(
    String text, {
    String locale = 'vi-VN',
  });
}

/// Optional native capability that brackets one physical/virtual MAIN turn.
/// The iOS implementation uses this boundary to keep one AVAudioSession owner
/// from the first prompt through the final speech result.
abstract interface class MainTurnVoicePromptService {
  Future<String?> beginMainTurn();

  Future<void> endMainTurn(String reason);
}
