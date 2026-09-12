import 'dart:convert';

import 'package:flutter/services.dart';

/// The manifest is bundled; the recordings themselves are delivered remotely.
/// Original asset paths remain stable identifiers for age/cue lookups.
class CloudinaryAudioLibrary {
  CloudinaryAudioLibrary({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const assetPath = 'assets/data/cloudinary_audio_manifest.json';
  static final shared = CloudinaryAudioLibrary();
  final AssetBundle _bundle;
  Future<Map<String, Uri>>? _index;

  Future<Map<String, Uri>> _load() =>
      _index ??= _read().catchError((Object error) {
        _index = null;
        throw error;
      });

  Future<Map<String, Uri>> _read() async {
    final json =
        jsonDecode(await _bundle.loadString(assetPath, cache: false))
            as Map<String, dynamic>;
    final index = <String, Uri>{};
    for (final raw in json['clips'] as List<dynamic>) {
      final clip = raw as Map<String, dynamic>;
      final uri = Uri.parse(clip['url'] as String);
      if (!uri.isScheme('https') || uri.host != 'res.cloudinary.com') {
        throw const FormatException('Invalid Cloudinary audio URL');
      }
      index[clip['asset'] as String] = uri;
    }
    return Map<String, Uri>.unmodifiable(index);
  }

  Future<Uri?> uriForAsset(String asset) async => (await _load())[asset];

  Future<List<String>> assetIdentifiers() async =>
      (await _load()).keys.toList(growable: false)..sort();
}
