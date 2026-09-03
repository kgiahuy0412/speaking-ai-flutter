import 'package:ai_speaking_flutter_app/features/listening/application/listening_voice_navigation_target.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final catalog = listeningCatalogs.singleWhere(
    (candidate) => candidate.startAge == 6 && candidate.endAge == 7,
  );

  test('matches a spoken Vietnamese topic title', () {
    const target = ListeningVoiceNavigationTarget(
      recognizedText: 'Mở bài 2 trong chủ đề Những con số quanh mình',
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

  test('matches a V4 topic title without guessing shared terms', () {
    const school = ListeningVoiceNavigationTarget(
      recognizedText: 'Mở bài 1 trong chủ đề ở trường',
      openLesson: true,
      lessonNumber: 1,
    );
    const ambiguousMine = ListeningVoiceNavigationTarget(
      recognizedText: 'Mở chủ đề mình',
      openLesson: false,
    );

    expect(school.resolveTopicIndex(catalog), 6);
    expect(ambiguousMine.resolveTopicIndex(catalog), isNull);
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
