abstract interface class BrowserAudioPlayback {
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Duration get position;
  Duration? get duration;

  Future<void> unlockForUserGesture();
  Future<void> preload(Uri uri);
  Future<void> play(Uri uri);
  Future<void> pause();
  Future<void> dispose();
}
