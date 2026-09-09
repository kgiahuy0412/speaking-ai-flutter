import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VietnameseTranscriptCorrection {
  const VietnameseTranscriptCorrection({
    required this.originalText,
    required this.matchedText,
    required this.correctedText,
  });

  final String originalText;
  final String matchedText;
  final String correctedText;

  bool get wasCorrected =>
      normalizeVietnameseTranscript(originalText) !=
      normalizeVietnameseTranscript(correctedText);
}

abstract interface class VietnameseTranscriptCorrector {
  /// Loads and indexes correction data before the first recorded turn.
  ///
  /// Implementations must keep this idempotent so callers can safely start it
  /// in the background without adding another step to the translation path.
  Future<void> warmUp();

  Future<VietnameseTranscriptCorrection> correct({
    required String primaryText,
    Iterable<String> alternatives = const <String>[],
  });
}

/// Corrects only complete, exact transcript variants after punctuation,
/// casing and whitespace normalization.
///
/// Deliberately avoiding substring and fuzzy matching keeps ordinary speech
/// from being rewritten merely because it sounds similar to one authored
/// speech-impediment sample.
class AssetVietnameseTranscriptCorrector
    implements VietnameseTranscriptCorrector {
  AssetVietnameseTranscriptCorrector({
    AssetBundle? bundle,
    this.assetPath = defaultAssetPath,
  }) : _bundle = bundle ?? rootBundle;

  static const String defaultAssetPath =
      'assets/data/vietnamese_speech_corrections_v1.json';

  final AssetBundle _bundle;
  final String assetPath;
  Future<Map<String, String>>? _loadedCorrections;

  @override
  Future<void> warmUp() async {
    await (_loadedCorrections ??= _loadCorrections());
  }

  @override
  Future<VietnameseTranscriptCorrection> correct({
    required String primaryText,
    Iterable<String> alternatives = const <String>[],
  }) async {
    final source = primaryText.trim();
    if (source.isEmpty) {
      return const VietnameseTranscriptCorrection(
        originalText: '',
        matchedText: '',
        correctedText: '',
      );
    }

    final corrections = await (_loadedCorrections ??= _loadCorrections());
    for (final candidate in <String>[source, ...alternatives]) {
      final normalized = normalizeVietnameseTranscript(candidate);
      if (normalized.isEmpty) continue;
      final corrected = corrections[normalized];
      if (corrected != null && corrected.trim().isNotEmpty) {
        return VietnameseTranscriptCorrection(
          originalText: source,
          matchedText: candidate.trim(),
          correctedText: corrected.trim(),
        );
      }
    }
    return VietnameseTranscriptCorrection(
      originalText: source,
      matchedText: source,
      correctedText: source,
    );
  }

  Future<Map<String, String>> _loadCorrections() async {
    final raw = await _bundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Transcript correction asset is not a map.');
    }
    final entries = decoded['corrections'];
    if (entries is! List<dynamic>) {
      throw const FormatException(
        'Transcript correction asset has no corrections list.',
      );
    }

    final corrections = <String, String>{};
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) continue;
      final heard = entry['heard'];
      final standard = entry['standard'];
      if (heard is! String || standard is! String) continue;
      final normalized = normalizeVietnameseTranscript(heard);
      final replacement = standard.trim();
      if (normalized.isEmpty ||
          replacement.isEmpty ||
          normalized == normalizeVietnameseTranscript(replacement)) {
        continue;
      }
      corrections.putIfAbsent(normalized, () => replacement);
    }
    return Map<String, String>.unmodifiable(corrections);
  }
}

/// Small injectable implementation used by tests and future downloaded packs.
class MapVietnameseTranscriptCorrector
    implements VietnameseTranscriptCorrector {
  MapVietnameseTranscriptCorrector(Map<String, String> corrections)
    : _corrections = Map<String, String>.unmodifiable(<String, String>{
        for (final entry in corrections.entries)
          if (normalizeVietnameseTranscript(entry.key).isNotEmpty &&
              entry.value.trim().isNotEmpty)
            normalizeVietnameseTranscript(entry.key): entry.value.trim(),
      });

  final Map<String, String> _corrections;

  @override
  Future<void> warmUp() async {}

  @override
  Future<VietnameseTranscriptCorrection> correct({
    required String primaryText,
    Iterable<String> alternatives = const <String>[],
  }) async {
    final source = primaryText.trim();
    for (final candidate in <String>[source, ...alternatives]) {
      final replacement =
          _corrections[normalizeVietnameseTranscript(candidate)];
      if (replacement != null) {
        return VietnameseTranscriptCorrection(
          originalText: source,
          matchedText: candidate.trim(),
          correctedText: replacement,
        );
      }
    }
    return VietnameseTranscriptCorrection(
      originalText: source,
      matchedText: source,
      correctedText: source,
    );
  }
}

@visibleForTesting
String normalizeVietnameseTranscript(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^0-9a-zà-ỹđ]+', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
