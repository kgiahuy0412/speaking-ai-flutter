abstract interface class VoicePromptService {
  Future<void> speak(String text, {String locale = 'vi-VN'});

  Future<void> stop();

  Future<void> dispose();
}
