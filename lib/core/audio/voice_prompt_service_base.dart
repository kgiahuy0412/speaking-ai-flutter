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
