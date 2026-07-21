import 'dart:io';

import 'package:ai_speaking_flutter_app/core/audio/device_audio_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('downloads an audio rule once and reuses the local file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ailingo-audio-cache-test-',
    );
    var requests = 0;
    final cache = DeviceAudioCache(
      client: MockClient((request) async {
        requests += 1;
        return http.Response.bytes(<int>[1, 2, 3, 4], 200);
      }),
      directoryProvider: () async => directory,
    );
    final remote = Uri.parse(
      'https://api.example.com/api/audio/stream?text=hello',
    );

    final first = await cache.cache(remote);
    final second = await cache.cache(remote);
    final resolved = await cache.resolve(remote);

    expect(requests, 1);
    expect(first, isNotNull);
    expect(second, first);
    expect(resolved, first);
    expect(await File.fromUri(resolved).readAsBytes(), <int>[1, 2, 3, 4]);

    cache.dispose();
    await directory.delete(recursive: true);
  });
}
