import 'dart:convert';

import 'package:flutter/services.dart';

/// Exact Vietnamese text -> authored recording. The small indexes are bundled;
/// recordings use their Cloudinary URL after migration.
class BundledVoicePromptLibrary {
  BundledVoicePromptLibrary({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const assetPath = 'assets/data/elevenlabs_prompt_index.json';
  static const existingAssetPath = 'assets/data/homi_audio_index.json';
  static final shared = BundledVoicePromptLibrary();
  final AssetBundle _bundle;
  Future<Map<String, String>>? _index;
  final Map<String, Uri> _remoteUris = <String, Uri>{};

  static String normalize(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<String?> assetFor(String text, {String locale = 'vi-VN'}) async {
    if (locale != 'vi-VN' && locale != 'vi') return null;
    final index = await (_index ??= _load().catchError((Object error) {
      _index = null;
      throw error;
    }));
    return index[normalize(text)];
  }

  Future<Uri?> uriFor(String text, {String locale = 'vi-VN'}) async {
    final asset = await assetFor(text, locale: locale);
    if (asset == null) return null;
    return _remoteUris[asset] ?? Uri(scheme: 'asset', path: '/$asset');
  }

  void _readRemoteUri(Map<String, dynamic> clip) {
    final url = clip['audioUrl'] as String?;
    if (url == null) return;
    final uri = Uri.parse(url);
    if (!uri.isScheme('https') || uri.host != 'res.cloudinary.com') {
      throw const FormatException('Invalid recorded prompt URL');
    }
    _remoteUris[clip['asset'] as String] = uri;
  }

  Future<Map<String, String>> _load() async {
    final index = <String, String>{};
    _remoteUris.clear();
    // Exclude hooks/SFX/context-dependent feedback: their original callers
    // select by ID or age, so a text match must never replay unrelated effects.
    final existing =
        jsonDecode(await _bundle.loadString(existingAssetPath, cache: false))
            as Map<String, dynamic>;
    for (final raw in existing['clips'] as List<dynamic>) {
      final clip = raw as Map<String, dynamic>;
      _readRemoteUri(clip);
      if (clip['locale'] == 'vi-VN' &&
          (clip['kind'] == 'system' || clip['kind'] == 'core')) {
        index.putIfAbsent(
          normalize(clip['text'] as String),
          () => clip['asset'] as String,
        );
      }
    }
    final generated =
        jsonDecode(await _bundle.loadString(assetPath, cache: false))
            as Map<String, dynamic>;
    for (final raw in generated['clips'] as List<dynamic>) {
      final clip = raw as Map<String, dynamic>;
      _readRemoteUri(clip);
      final asset = clip['asset'] as String;
      if (clip['locale'] == 'vi-VN' &&
          asset.startsWith('assets/audio/elevenlabs_vi/') &&
          !asset.contains('..')) {
        index.putIfAbsent(normalize(clip['text'] as String), () => asset);
      }
    }
    return index;
  }
}
