/// Flutter Web relies on the browser HTTP cache. Generated audio URLs are
/// immutable and include the content hash, so a second playback is served by
/// the browser without maintaining a duplicate Dart-side file cache.
class DeviceAudioCache {
  DeviceAudioCache({this.maxFiles = 256});

  final int maxFiles;

  Future<Uri> resolve(Uri remoteUri) async => remoteUri;

  Future<Uri> resolveAfterPreload(
    Uri remoteUri, {
    Duration maxWait = const Duration(milliseconds: 500),
  }) async => remoteUri;

  Future<Uri?> cache(Uri remoteUri) async => remoteUri;

  Future<void> warm(Iterable<Uri> remoteUris, {int limit = 40}) async {}

  void dispose() {}
}
