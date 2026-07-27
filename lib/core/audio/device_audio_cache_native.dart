import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DeviceAudioCache {
  DeviceAudioCache({
    http.Client? client,
    Future<Directory> Function()? directoryProvider,
    this.maxFiles = 128,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  final http.Client _client;
  final bool _ownsClient;
  final Future<Directory> Function() _directoryProvider;
  final int maxFiles;
  final Map<String, Future<Uri?>> _downloads = <String, Future<Uri?>>{};
  Future<Directory>? _cacheDirectory;

  Future<Uri> resolve(Uri remoteUri) async {
    if (!remoteUri.isScheme('http') && !remoteUri.isScheme('https')) {
      return remoteUri;
    }
    final file = await _fileFor(remoteUri);
    if (await file.exists() && await file.length() > 0) {
      unawaited(file.setLastModified(DateTime.now()));
      return file.uri;
    }
    return remoteUri;
  }

  Future<Uri> resolveAfterPreload(
    Uri remoteUri, {
    Duration maxWait = const Duration(milliseconds: 500),
  }) async {
    final inFlight = _downloads[remoteUri.toString()];
    if (inFlight != null) {
      final cached = await inFlight.timeout(maxWait, onTimeout: () => null);
      if (cached != null) {
        return cached;
      }
    }
    return resolve(remoteUri);
  }

  Future<Uri?> cache(Uri remoteUri) {
    if (!remoteUri.isScheme('http') && !remoteUri.isScheme('https')) {
      return Future<Uri?>.value(remoteUri);
    }
    final key = remoteUri.toString();
    return _downloads.putIfAbsent(key, () async {
      try {
        final existing = await resolve(remoteUri);
        if (existing.isScheme('file')) {
          return existing;
        }
        final response = await _client
            .get(remoteUri)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            response.bodyBytes.isEmpty) {
          return null;
        }

        final target = await _fileFor(remoteUri);
        final temporary = File('${target.path}.part');
        await temporary.writeAsBytes(response.bodyBytes, flush: true);
        if (await target.exists()) {
          await target.delete();
        }
        await temporary.rename(target.path);
        unawaited(_prune());
        return target.uri;
      } catch (_) {
        return null;
      } finally {
        _downloads.remove(key);
      }
    });
  }

  Future<void> warm(Iterable<Uri> remoteUris, {int limit = 40}) async {
    var pending = remoteUris
        .where((uri) => uri.isScheme('http') || uri.isScheme('https'))
        .map((uri) => uri.toString())
        .toSet()
        .take(limit)
        .map(Uri.parse)
        .toList(growable: false);
    const concurrency = 3;
    for (var attempt = 0; attempt < 2 && pending.isNotEmpty; attempt += 1) {
      final failed = <Uri>[];
      for (var index = 0; index < pending.length; index += concurrency) {
        final batch = pending.skip(index).take(concurrency).toList();
        final results = await Future.wait(
          batch.map(cache).map((future) => future.catchError((_) => null)),
        );
        for (var item = 0; item < batch.length; item += 1) {
          if (results[item] == null) {
            failed.add(batch[item]);
          }
        }
      }
      pending = failed;
    }
  }

  Future<File> _fileFor(Uri uri) async {
    final directory = await (_cacheDirectory ??= _createCacheDirectory());
    return File(
      '${directory.path}${Platform.pathSeparator}${_fnv1a(uri.toString())}.mp3',
    );
  }

  Future<Directory> _createCacheDirectory() async {
    final support = await _directoryProvider();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}rule_audio_cache',
    );
    return directory.create(recursive: true);
  }

  Future<void> _prune() async {
    final directory = await (_cacheDirectory ??= _createCacheDirectory());
    final files = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.mp3'))
        .cast<File>()
        .toList();
    if (files.length <= maxFiles) {
      return;
    }
    final dated = await Future.wait(
      files.map(
        (file) async => (file: file, modified: await file.lastModified()),
      ),
    );
    dated.sort((a, b) => a.modified.compareTo(b.modified));
    for (final item in dated.take(dated.length - maxFiles)) {
      await item.file.delete().catchError((_) => item.file);
    }
  }

  String _fnv1a(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
