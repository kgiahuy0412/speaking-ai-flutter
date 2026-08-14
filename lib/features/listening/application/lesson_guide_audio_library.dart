import 'dart:math';

import 'package:flutter/services.dart';

enum LessonGuideCue {
  record('GUIDE_RECORD'),
  praise('GUIDE_PRAISE'),
  next('GUIDE_NEXT'),
  idleFirst('GUIDE_IDLE1'),
  idleSecond('GUIDE_IDLE2'),
  skip('GUIDE_SKIP'),
  ending('GUIDE_ENDING');

  const LessonGuideCue(this.directoryName);

  final String directoryName;
}

class LessonGuideAudioLibrary {
  LessonGuideAudioLibrary({
    AssetBundle? bundle,
    Random? random,
    List<String>? assetPaths,
  }) : _bundle = bundle ?? rootBundle,
       _random = random ?? Random(),
       _providedAssetPaths = assetPaths == null
           ? null
           : List<String>.unmodifiable(assetPaths);

  static const Set<String> _supportedExtensions = <String>{
    '.aac',
    '.m4a',
    '.mp3',
    '.ogg',
    '.wav',
  };

  final AssetBundle _bundle;
  final Random _random;
  final List<String>? _providedAssetPaths;
  Future<List<String>>? _assetPathsFuture;

  Future<Uri?> randomUri(
    LessonGuideCue cue, {
    required int startAge,
    required int endAge,
  }) async {
    final assets = await (_assetPathsFuture ??= _loadAssetPaths());
    final assetPrefix =
        'assets/audio/A-$startAge-$endAge/${cue.directoryName}/';
    final candidates = assets
        .where((asset) => asset.startsWith(assetPrefix))
        .where(_isSupportedAudio)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }
    final selected = candidates[_random.nextInt(candidates.length)];
    return Uri(scheme: 'asset', path: '/$selected');
  }

  /// Resolves a V2 guide by its stable audio code, regardless of the folder in
  /// which the generated audio pack is mounted. This lets IT add the 410-file
  /// pack without changing the lesson state machine or renaming legacy guides.
  Future<Uri?> uriForAudioCode(String audioCode) async {
    final normalizedCode = audioCode.trim().toLowerCase();
    if (normalizedCode.isEmpty) {
      return null;
    }
    final assets = await (_assetPathsFuture ??= _loadAssetPaths());
    for (final asset in assets) {
      if (!_isSupportedAudio(asset)) {
        continue;
      }
      final filename = asset.split('/').last;
      final extensionIndex = filename.lastIndexOf('.');
      final basename =
          (extensionIndex < 0
                  ? filename
                  : filename.substring(0, extensionIndex))
              .toLowerCase();
      if (basename == normalizedCode) {
        return Uri(scheme: 'asset', path: '/$asset');
      }
    }
    return null;
  }

  Future<List<String>> _loadAssetPaths() async {
    final provided = _providedAssetPaths;
    if (provided != null) {
      return provided.map(_normalizePath).toList(growable: false)..sort();
    }
    final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
    return manifest.listAssets().map(_normalizePath).toList(growable: false)
      ..sort();
  }

  static bool _isSupportedAudio(String assetPath) {
    final normalized = assetPath.toLowerCase();
    return _supportedExtensions.any(normalized.endsWith);
  }

  static String _normalizePath(String value) => value.replaceAll(r'\', '/');
}
