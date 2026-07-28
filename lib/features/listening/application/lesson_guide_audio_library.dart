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
