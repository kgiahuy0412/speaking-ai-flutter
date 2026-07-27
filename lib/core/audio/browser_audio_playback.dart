abstract interface class BrowserAudioPlayback {
  Stream<bool> get playingStream;

  Future<void> unlockForUserGesture();
  Future<void> preload(Uri uri);
  Future<void> play(Uri uri);
  Future<void> pause();
  Future<void> dispose();
}
