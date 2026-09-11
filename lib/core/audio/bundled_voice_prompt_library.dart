import 'dart:convert';

import 'package:flutter/services.dart';

/// Exact Vietnamese text -> local audio. Never sends text or credentials over
/// the network. Existing curriculum recordings retain their original voice.
class BundledVoicePromptLibrary {
  BundledVoicePromptLibrary({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const assetPath = 'assets/data/elevenlabs_prompt_index.json';
  static const existingAssetPath = 'assets/data/homi_audio_index.json';
  static final shared = BundledVoicePromptLibrary();
  final AssetBundle _bundle;
  Future<Map<String, String>>? _index;

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

  Future<Map<String, String>> _load() async {
    final index = <String, String>{};
    // Exclude hooks/SFX/context-dependent feedback: their original callers
    // select by ID or age, so a text match must never replay unrelated effects.
    final existing =
        jsonDecode(await _bundle.loadString(existingAssetPath, cache: false))
            as Map<String, dynamic>;
    for (final raw in existing['clips'] as List<dynamic>) {
      final clip = raw as Map<String, dynamic>;
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
