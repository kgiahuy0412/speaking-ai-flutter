class VocabularyEntry {
  const VocabularyEntry({
    required this.id,
    required this.word,
    required this.meaning,
    required this.addedAt,
  });

  final String id;
  final String word;
  final String meaning;
  final DateTime addedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'word': word,
    'meaning': meaning,
    'addedAt': addedAt.toIso8601String(),
  };

  factory VocabularyEntry.fromJson(Map<String, Object?> json) {
    return VocabularyEntry(
      id: json['id'] as String,
      word: json['word'] as String,
      meaning: json['meaning'] as String,
      addedAt: DateTime.parse(json['addedAt'] as String),
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
