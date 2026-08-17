import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the required pauses for the bilingual sentence guide', () {
    expect(
      LessonGuideFlowV2.guideToSamplePause,
      const Duration(milliseconds: 300),
    );
    expect(
      LessonGuideFlowV2.englishToVietnamesePause,
      const Duration(seconds: 2),
    );
    expect(LessonGuideFlowV2.beforeSentence.text, 'Nói theo cô nhé.');
  });

  test('defines the authoritative common guide prompts', () {
    expect(
      LessonGuideFlowV2.beforeSentence.audioCode,
      'AI_GUIDE_BEFORE_SENTENCE',
    );
    expect(LessonGuideFlowV2.afterSample.audioCode, 'AI_GUIDE_AFTER_SAMPLE');
    expect(
      LessonGuideFlowV2.completionChoiceUnclear.audioCode,
      'AI_GUIDE_COMPLETION_CHOICE_UNCLEAR',
    );
    expect(
      LessonGuideFlowV2.completionChoiceUnclear.text,
      'Nói lại lựa chọn của con nhé',
    );
    expect(LessonGuideFlowV2.good.audioCode, 'AI_GUIDE_GOOD');
    expect(LessonGuideFlowV2.retryFirst.audioCode, 'AI_GUIDE_RETRY_1');
    expect(LessonGuideFlowV2.retrySecond.audioCode, 'AI_GUIDE_RETRY_2');
    expect(LessonGuideFlowV2.moveToNext.audioCode, 'AI_GUIDE_MOVE_TO_NEXT');
    expect(LessonGuideFlowV2.moveToNext.text, 'Mình cùng học câu khác nhé!');
    expect(
      LessonGuideFlowV2.needsPractice.audioCode,
      'AI_GUIDE_NEEDS_PRACTICE',
    );
  });

  test('builds exact per-lesson entry and ending audio codes', () {
    final first = LessonGuideFlowV2.entry(
      lessonCode: 'A035_T01_L01',
      lessonTitleEn: 'Saying Hello',
      kind: LessonEntryGuideKind.first,
    );
    final next = LessonGuideFlowV2.entry(
      lessonCode: 'A035_T01_L01',
      lessonTitleEn: 'Saying Hello',
      kind: LessonEntryGuideKind.newLesson,
    );
    final resume = LessonGuideFlowV2.entry(
      lessonCode: 'A035_T01_L01',
      lessonTitleEn: 'Saying Hello',
      kind: LessonEntryGuideKind.resume,
    );
    final ending = LessonGuideFlowV2.ending(
      lessonCode: 'A035_T01_L01',
      lessonTitleEn: 'Saying Hello',
    );

    expect(first.audioCode, 'A035_T01_L01_FIRST');
    expect(first.text, contains('bấm nút Main'));
    expect(next.audioCode, 'A035_T01_L01_NEW');
    expect(resume.audioCode, 'A035_T01_L01_RESUME');
    expect(resume.text, contains('chỗ lúc trước'));
    expect(ending.audioCode, 'A035_T01_L01_END');
    expect(ending.text, contains('luyện lại từ đầu hay học bài tiếp theo'));
  });
}
