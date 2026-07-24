import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class ListeningContentCatalog {
  const ListeningContentCatalog({required this.groups});

  factory ListeningContentCatalog.fromJson(Map<String, Object?> json) {
    final groups = (json['groups'] as List<Object?>? ?? const <Object?>[])
        .whereType<Map<String, Object?>>()
        .map(ListeningContentAgeGroup.fromJson)
        .toList(growable: false);
    return ListeningContentCatalog(groups: groups);
  }

  final List<ListeningContentAgeGroup> groups;

  ListeningTopicContent topic({
    required int startAge,
    required int endAge,
    required int topicNumber,
  }) {
    final group = groups.firstWhere(
      (candidate) =>
          candidate.startAge == startAge && candidate.endAge == endAge,
    );
    return group.topics.firstWhere(
      (candidate) => candidate.number == topicNumber,
    );
  }
}

@immutable
class ListeningContentAgeGroup {
  const ListeningContentAgeGroup({
    required this.startAge,
    required this.endAge,
    required this.topics,
  });

  factory ListeningContentAgeGroup.fromJson(Map<String, Object?> json) {
    return ListeningContentAgeGroup(
      startAge: json['startAge'] as int? ?? 0,
      endAge: json['endAge'] as int? ?? 0,
      topics: (json['topics'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map<String, Object?>>()
          .map(ListeningTopicContent.fromJson)
          .toList(growable: false),
    );
  }

  final int startAge;
  final int endAge;
  final List<ListeningTopicContent> topics;
}

@immutable
class ListeningTopicContent {
  const ListeningTopicContent({
    required this.id,
    required this.number,
    required this.titleVi,
    required this.titleEn,
    required this.lessons,
  });

  factory ListeningTopicContent.fromJson(Map<String, Object?> json) {
    return ListeningTopicContent(
      id: json['id'] as String? ?? '',
      number: json['number'] as int? ?? 0,
      titleVi: json['titleVi'] as String? ?? '',
      titleEn: json['titleEn'] as String? ?? '',
      lessons: (json['lessons'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map<String, Object?>>()
          .map(ListeningLessonContent.fromJson)
          .toList(growable: false),
    );
  }

  final String id;
  final int number;
  final String titleVi;
  final String titleEn;
  final List<ListeningLessonContent> lessons;

  int get sentenceCount =>
      lessons.fold<int>(0, (count, lesson) => count + lesson.sentences.length);
}

@immutable
class ListeningLessonContent {
  const ListeningLessonContent({
    required this.id,
    required this.number,
    required this.titleVi,
    required this.titleEn,
    required this.intro,
    required this.outro,
    required this.estimatedMinutes,
    required this.sentences,
    this.introAudioUri,
    this.outroAudioUri,
  });

  factory ListeningLessonContent.fromJson(Map<String, Object?> json) {
    return ListeningLessonContent(
      id: json['id'] as String? ?? '',
      number: json['number'] as int? ?? 0,
      titleVi: json['titleVi'] as String? ?? '',
      titleEn: json['titleEn'] as String? ?? '',
      intro: json['intro'] as String? ?? '',
      outro: json['outro'] as String? ?? '',
      estimatedMinutes: json['estimatedMinutes'] as int? ?? 3,
      sentences: (json['sentences'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map<String, Object?>>()
          .map(ListeningSentenceContent.fromJson)
          .toList(growable: false),
      introAudioUri: _readUri(json['introAudioUrl']),
      outroAudioUri: _readUri(json['outroAudioUrl']),
    );
  }

  final String id;
  final int number;
  final String titleVi;
  final String titleEn;
  final String intro;
  final String outro;
  final int estimatedMinutes;
  final List<ListeningSentenceContent> sentences;
  final Uri? introAudioUri;
  final Uri? outroAudioUri;
}

@immutable
class ListeningSentenceContent {
  const ListeningSentenceContent({
    required this.number,
    required this.english,
    required this.vietnamese,
    this.audioUri,
    this.vietnameseAudioUri,
  });

  factory ListeningSentenceContent.fromJson(Map<String, Object?> json) {
    return ListeningSentenceContent(
      number: json['number'] as int? ?? 0,
      english: json['english'] as String? ?? '',
      vietnamese: json['vietnamese'] as String? ?? '',
      audioUri: _readUri(json['audioUrl']),
      vietnameseAudioUri: _readUri(json['vietnameseAudioUrl']),
    );
  }

  final int number;
  final String english;
  final String vietnamese;
  final Uri? audioUri;
  final Uri? vietnameseAudioUri;
}

Uri? _readUri(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return Uri.tryParse(value.trim());
}

class AssetListeningContentRepository {
  AssetListeningContentRepository({
    AssetBundle? bundle,
    this.assetPath = 'assets/data/listening_lessons.json',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String assetPath;
  Future<ListeningContentCatalog>? _catalogFuture;

  Future<ListeningContentCatalog> load() {
    return _catalogFuture ??= _load();
  }

  Future<ListeningContentCatalog> _load() async {
    final data = await _bundle.load(assetPath);
    final raw = utf8.decode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Dữ liệu bài học không đúng định dạng.');
    }
    return ListeningContentCatalog.fromJson(decoded);
  }
}
