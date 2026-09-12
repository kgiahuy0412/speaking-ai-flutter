import 'dart:convert';

import 'package:flutter/services.dart';

class HomiAudioClip {
  HomiAudioClip.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      uri = json['audioUrl'] is String
          ? Uri.parse(json['audioUrl'] as String)
          : Uri(scheme: 'asset', path: '/${json['asset']}'),
      text = json['text'] as String,
      locale = json['locale'] as String,
      kind = json['kind'] as String,
      age = json['age'] as String?,
      state = json['state'] as String?;

  final String id;
  final Uri uri;
  final String text;
  final String locale;
  final String kind;
  final String? age;
  final String? state;
}

class HomiAudioSegment {
  const HomiAudioSegment(this.text, {this.audioId, this.locale = 'vi-VN'});

  final String text;
  final String? audioId;
  final String locale;
}

/// Explicit IDs keep embedded Hook/SFX clips out of unrelated spoken prompts.
/// Text lookup is reserved for reusable speech and system cues with their
/// dynamic variables already expanded by the curriculum.
class HomiAudioLibrary {
  HomiAudioLibrary({AssetBundle? bundle}) : _bundle = bundle;

  static const assetPath = 'assets/data/homi_audio_index.json';
  static Future<_HomiAudioIndex>? _sharedIndex;
  final AssetBundle? _bundle;
  Future<_HomiAudioIndex>? _index;
  final Map<String, int> _feedbackCounters = <String, int>{};

  Future<_HomiAudioIndex> _load() {
    if (_bundle == null) {
      return _sharedIndex ??= _read(rootBundle).catchError((Object error) {
        _sharedIndex = null;
        throw error;
      });
    }
    return _index ??= _read(_bundle).catchError((Object error) {
      // An asset-sync/read failure must not pin every later prompt to TTS.
      _index = null;
      throw error;
    });
  }

  static Future<_HomiAudioIndex> _read(AssetBundle bundle) async {
    // We cache the parsed index ourselves. CachingAssetBundle also caches
    // failed string futures, which would otherwise defeat retry after sync.
    final json =
        jsonDecode(await bundle.loadString(assetPath, cache: false))
            as Map<String, dynamic>;
    return _HomiAudioIndex(json);
  }

  Future<Uri?> uriForAudioCode(String code) async =>
      (await _load()).byId[code.trim().toUpperCase()]?.uri;

  Future<List<HomiAudioSegment>?> sequenceForText(String text) async =>
      (await _load()).sequences[_normalize(text)];

  Future<HomiAudioClip?> resolve({
    required String text,
    String locale = 'vi-VN',
    String? audioId,
    String? feedbackState,
    int? age,
  }) async {
    final index = await _load();
    if (feedbackState != null && age != null) {
      final group = age <= 5
          ? '3-5'
          : age <= 7
          ? '6-7'
          : age <= 10
          ? '8-10'
          : age <= 12
          ? '11-12'
          : '13-15';
      final key = '$group:${feedbackState.toUpperCase()}';
      final candidates = index.feedback[key];
      if (candidates != null && candidates.isNotEmpty) {
        final position = _feedbackCounters[key] ?? 0;
        _feedbackCounters[key] = position + 1;
        return candidates[position % candidates.length];
      }
    }
    if (audioId != null) {
      final clip = index.byId[audioId.trim().toUpperCase()];
      // A stale ID must never read a different answer from the visible text.
      if (clip != null && _normalize(clip.text) == _normalize(text)) {
        return clip;
      }
      return null;
    }
    return index.byText['$locale:${_normalize(text)}'];
  }

  static String _normalize(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');
}

class _HomiAudioIndex {
  _HomiAudioIndex(Map<String, dynamic> json) {
    for (final value in json['clips'] as List<dynamic>) {
      final clip = HomiAudioClip.fromJson(value as Map<String, dynamic>);
      byId[clip.id.toUpperCase()] = clip;
      if (clip.kind == 'feedback') {
        (feedback['${clip.age}:${clip.state}'] ??= <HomiAudioClip>[]).add(clip);
      }
      if (clip.kind == 'system' ||
          clip.kind == 'core' ||
          clip.id.endsWith('_CHOICE_1') ||
          clip.id.endsWith('_CHOICE_2')) {
        byText.putIfAbsent(
          '${clip.locale}:${HomiAudioLibrary._normalize(clip.text)}',
          () => clip,
        );
      }
    }
    for (final value in json['sequences'] as List<dynamic>) {
      final sequence = value as Map<String, dynamic>;
      sequences[HomiAudioLibrary._normalize(
        sequence['text'] as String,
      )] = (sequence['parts'] as List<dynamic>)
          .map((value) {
            final part = value as Map<String, dynamic>;
            return HomiAudioSegment(
              part['text'] as String,
              audioId: part['audioId'] as String?,
              locale: part['locale'] as String? ?? 'vi-VN',
            );
          })
          .toList(growable: false);
    }
  }

  final Map<String, HomiAudioClip> byId = <String, HomiAudioClip>{};
  final Map<String, HomiAudioClip> byText = <String, HomiAudioClip>{};
  final Map<String, List<HomiAudioClip>> feedback =
      <String, List<HomiAudioClip>>{};
  final Map<String, List<HomiAudioSegment>> sequences =
      <String, List<HomiAudioSegment>>{};
}
