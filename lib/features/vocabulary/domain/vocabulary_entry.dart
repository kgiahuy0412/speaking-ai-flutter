enum VocabularyCollection { saved, star, review }

enum VocabularyLearningStatus { unlearned, needsPractice, learnedWell }

enum VocabularySource {
  parent,
  topicCore,
  topicRolePlay,
  topicChallenge,
  topicMission,
}

class VocabularyEntry {
  const VocabularyEntry({
    required this.id,
    required this.word,
    required this.meaning,
    required this.addedAt,
    this.collection = VocabularyCollection.saved,
    this.status = VocabularyLearningStatus.unlearned,
    this.source = VocabularySource.parent,
    this.sourceLessonCode,
    this.sourceSentenceId,
    this.starSlotId,
    this.correctAudioPath,
    this.introducedAt,
    this.learningStartedAt,
    this.lastPracticedAt,
    this.earnedAt,
  });

  static const Object _unset = Object();

  final String id;
  final String word;
  final String meaning;
  final DateTime addedAt;

  /// Kept so existing vocabulary.v1 records and callers migrate in place.
  /// New flow decisions use [status], [source], and [starSlotId].
  final VocabularyCollection collection;
  final VocabularyLearningStatus status;
  final VocabularySource source;
  final String? sourceLessonCode;
  final String? sourceSentenceId;
  final String? starSlotId;
  final String? correctAudioPath;
  final DateTime? introducedAt;
  final DateTime? learningStartedAt;
  final DateTime? lastPracticedAt;
  final DateTime? earnedAt;

  bool get isParentAdded =>
      source == VocabularySource.parent &&
      (collection == VocabularyCollection.saved ||
          learningStartedAt != null ||
          status != VocabularyLearningStatus.unlearned);
  bool get isStar => collection == VocabularyCollection.star;
  bool get needsPractice =>
      status == VocabularyLearningStatus.needsPractice ||
      collection == VocabularyCollection.review;
  bool get isLearnedWell =>
      status == VocabularyLearningStatus.learnedWell ||
      collection == VocabularyCollection.star;
  bool get canParentEdit =>
      isParentAdded &&
      status == VocabularyLearningStatus.unlearned &&
      learningStartedAt == null;

  VocabularyEntry copyWith({
    String? word,
    String? meaning,
    VocabularyCollection? collection,
    VocabularyLearningStatus? status,
    VocabularySource? source,
    Object? sourceLessonCode = _unset,
    Object? sourceSentenceId = _unset,
    Object? starSlotId = _unset,
    Object? correctAudioPath = _unset,
    Object? introducedAt = _unset,
    Object? learningStartedAt = _unset,
    Object? lastPracticedAt = _unset,
    Object? earnedAt = _unset,
  }) => VocabularyEntry(
    id: id,
    word: word ?? this.word,
    meaning: meaning ?? this.meaning,
    addedAt: addedAt,
    collection: collection ?? this.collection,
    status: status ?? this.status,
    source: source ?? this.source,
    sourceLessonCode: identical(sourceLessonCode, _unset)
        ? this.sourceLessonCode
        : sourceLessonCode as String?,
    sourceSentenceId: identical(sourceSentenceId, _unset)
        ? this.sourceSentenceId
        : sourceSentenceId as String?,
    starSlotId: identical(starSlotId, _unset)
        ? this.starSlotId
        : starSlotId as String?,
    correctAudioPath: identical(correctAudioPath, _unset)
        ? this.correctAudioPath
        : correctAudioPath as String?,
    introducedAt: identical(introducedAt, _unset)
        ? this.introducedAt
        : introducedAt as DateTime?,
    learningStartedAt: identical(learningStartedAt, _unset)
        ? this.learningStartedAt
        : learningStartedAt as DateTime?,
    lastPracticedAt: identical(lastPracticedAt, _unset)
        ? this.lastPracticedAt
        : lastPracticedAt as DateTime?,
    earnedAt: identical(earnedAt, _unset)
        ? this.earnedAt
        : earnedAt as DateTime?,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'word': word,
    'meaning': meaning,
    'addedAt': addedAt.toIso8601String(),
    'collection': collection.name,
    'status': status.name,
    'source': source.name,
    if (sourceLessonCode != null) 'sourceLessonCode': sourceLessonCode,
    if (sourceSentenceId != null) 'sourceSentenceId': sourceSentenceId,
    if (starSlotId != null) 'starSlotId': starSlotId,
    if (correctAudioPath != null) 'correctAudioPath': correctAudioPath,
    if (introducedAt != null) 'introducedAt': introducedAt!.toIso8601String(),
    if (learningStartedAt != null)
      'learningStartedAt': learningStartedAt!.toIso8601String(),
    if (lastPracticedAt != null)
      'lastPracticedAt': lastPracticedAt!.toIso8601String(),
    if (earnedAt != null) 'earnedAt': earnedAt!.toIso8601String(),
  };

  factory VocabularyEntry.fromJson(Map<String, Object?> json) {
    final collection = VocabularyCollection.values.firstWhere(
      (value) => value.name == json['collection'],
      orElse: () => VocabularyCollection.saved,
    );
    final sourceLessonCode = json['sourceLessonCode'] as String?;
    final source = VocabularySource.values.firstWhere(
      (value) => value.name == json['source'],
      orElse: () => sourceLessonCode == null
          ? VocabularySource.parent
          : VocabularySource.topicCore,
    );
    final introducedAt = _readDate(json['introducedAt']);
    final status = VocabularyLearningStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => switch (collection) {
        VocabularyCollection.review => VocabularyLearningStatus.needsPractice,
        VocabularyCollection.star => VocabularyLearningStatus.learnedWell,
        VocabularyCollection.saved =>
          source != VocabularySource.parent || introducedAt != null
              ? VocabularyLearningStatus.learnedWell
              : VocabularyLearningStatus.unlearned,
      },
    );
    return VocabularyEntry(
      id: json['id'] as String,
      word: json['word'] as String,
      meaning: json['meaning'] as String,
      addedAt: DateTime.parse(json['addedAt'] as String),
      collection: collection,
      status: status,
      source: source,
      sourceLessonCode: sourceLessonCode,
      sourceSentenceId: json['sourceSentenceId'] as String?,
      starSlotId:
          json['starSlotId'] as String? ??
          (collection == VocabularyCollection.star
              ? json['sourceSentenceId'] as String?
              : null),
      correctAudioPath: json['correctAudioPath'] as String?,
      introducedAt: introducedAt,
      learningStartedAt: _readDate(json['learningStartedAt']),
      lastPracticedAt: _readDate(json['lastPracticedAt']),
      earnedAt: _readDate(json['earnedAt']),
    );
  }

  static DateTime? _readDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

class VocabularyTranslation {
  const VocabularyTranslation({
    required this.englishText,
    required this.vietnameseText,
  });

  final String englishText;
  final String vietnameseText;
}

typedef VocabularyTranslator =
    Future<VocabularyTranslation> Function(String input);

/// Supplies age-appropriate alternatives when the approved local catalog
/// does not contain enough parent-facing choices. API/storage details stay
/// outside the vocabulary flow; Android and iOS consume the same result.
typedef VocabularySuggestionProvider =
    Future<List<VocabularyTranslation>> Function(String input, int childAge);
