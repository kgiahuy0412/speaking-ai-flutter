abstract interface class VoicePromptService {
  Future<void> speak(String text, {String locale = 'vi-VN'});

  /// Plays a prompt and completes only after speech output has stopped.
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'});

  Future<void> stop();

  Future<void> dispose();
}
