abstract interface class BrowserAudioPlayback {
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Duration get position;
  Duration? get duration;
  bool hasPreloadedSource(Uri uri);
  bool hasLoadedPreloadedSource(Uri uri);
  bool hasReadyPreloadedSource(Uri uri);
  Duration? preloadedSourceLoadedAfter(Uri uri);
  Duration? preloadedSourceReadyAfter(Uri uri);

  Future<void> unlockForUserGesture();
  Future<void> preload(Uri uri);
  Future<void> play(Uri uri);
  Future<void> pause();
  void setPlaybackRate(double rate);
  Future<void> dispose();
}
