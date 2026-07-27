import 'dart:math';

import 'package:web/web.dart' as web;

const _storageKey = 'innotrik.client-id.v1';

Future<String?> loadPlatformClientId() async {
  final stored = web.window.localStorage.getItem(_storageKey)?.trim();
  if (stored != null && stored.isNotEmpty) {
    return stored;
  }

  final random = Random.secure();
  final token = List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  final clientId = 'web_$token';
  web.window.localStorage.setItem(_storageKey, clientId);
  return clientId;
}
