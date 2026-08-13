import 'package:ai_speaking_flutter_app/features/listening/application/listening_voice_navigation_target.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final catalog = listeningCatalogs.singleWhere(
    (candidate) => candidate.startAge == 6 && candidate.endAge == 7,
  );

  test('matches a spoken Vietnamese topic title', () {
    const target = ListeningVoiceNavigationTarget(
      recognizedText: 'Mở bài 2 trong chủ đề Gia đình và ngôi nhà',
      openLesson: true,
      lessonNumber: 2,
    );

    expect(target.resolveTopicIndex(catalog), 1);
    expect(target.resolvedLessonNumber, 2);
  });

  test('uses explicit topic number before title matching', () {
    const target = ListeningVoiceNavigationTarget(
      recognizedText: 'Mở chủ đề số 3',
      openLesson: false,
      topicNumber: 3,
    );

    expect(target.resolveTopicIndex(catalog), 2);
  });

  test('matches a unique short topic name without guessing ambiguity', () {
    const classroom = ListeningVoiceNavigationTarget(
      recognizedText: 'Mở bài 1 trong chủ đề lớp học',
      openLesson: true,
      lessonNumber: 1,
    );
    const ambiguousDay = ListeningVoiceNavigationTarget(
      recognizedText: 'Mở chủ đề ngày',
      openLesson: false,
    );

    expect(classroom.resolveTopicIndex(catalog), 2);
    expect(ambiguousDay.resolveTopicIndex(catalog), isNull);
  });

  test('uses the current topic for a contextual lesson command', () {
    const target = ListeningVoiceNavigationTarget(
      recognizedText: 'Mở bài 2',
      openLesson: true,
      lessonNumber: 2,
      fallbackTopicIndex: 4,
    );

    expect(target.resolveTopicIndex(catalog), 4);
  });

  test('keeps a generic topic command on the catalog', () {
    const target = ListeningVoiceNavigationTarget(
      recognizedText: 'Mở chủ đề',
      openLesson: false,
    );

    expect(target.resolveTopicIndex(catalog), isNull);
  });
}
