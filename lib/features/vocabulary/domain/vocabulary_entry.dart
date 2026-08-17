enum VocabularyCollection { saved, star, review }

class VocabularyEntry {
  const VocabularyEntry({
    required this.id,
    required this.word,
    required this.meaning,
    required this.addedAt,
    this.collection = VocabularyCollection.saved,
    this.sourceLessonCode,
    this.sourceSentenceId,
  });

  final String id;
  final String word;
  final String meaning;
  final DateTime addedAt;
  final VocabularyCollection collection;
  final String? sourceLessonCode;
  final String? sourceSentenceId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'word': word,
    'meaning': meaning,
    'addedAt': addedAt.toIso8601String(),
    'collection': collection.name,
    if (sourceLessonCode != null) 'sourceLessonCode': sourceLessonCode,
    if (sourceSentenceId != null) 'sourceSentenceId': sourceSentenceId,
  };

  factory VocabularyEntry.fromJson(Map<String, Object?> json) {
    return VocabularyEntry(
      id: json['id'] as String,
      word: json['word'] as String,
      meaning: json['meaning'] as String,
      addedAt: DateTime.parse(json['addedAt'] as String),
      collection: VocabularyCollection.values.firstWhere(
        (value) => value.name == json['collection'],
        orElse: () => VocabularyCollection.saved,
      ),
      sourceLessonCode: json['sourceLessonCode'] as String?,
      sourceSentenceId: json['sourceSentenceId'] as String?,
    );
  }
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
