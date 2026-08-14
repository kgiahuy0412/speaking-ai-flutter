enum LessonEntryGuideKind { first, newLesson, resume }

enum LessonAttemptOutcome { good, retry, needsPractice }

class LessonGuidePrompt {
  const LessonGuidePrompt({required this.audioCode, required this.text});

  final String audioCode;
  final String text;
}

abstract interface class LessonAttemptEvaluator {
  Future<LessonAttemptOutcome> evaluate({
    required String lessonCode,
    required String sentenceId,
    required String expectedEnglish,
    required String recordingPath,
    required Duration recordingDuration,
    required int attemptNumber,
    required int childAge,
  });
}

/// Compatibility evaluator used until the English pronunciation-scoring
/// endpoint is connected. It never invents a pronunciation score: a recording
/// that the media layer successfully saved follows the previous app's success
/// path, while tests and the future backend adapter can inject retry outcomes.
class RecordedAttemptEvaluator implements LessonAttemptEvaluator {
  const RecordedAttemptEvaluator();

  @override
  Future<LessonAttemptOutcome> evaluate({
    required String lessonCode,
    required String sentenceId,
    required String expectedEnglish,
    required String recordingPath,
    required Duration recordingDuration,
    required int attemptNumber,
    required int childAge,
  }) async => LessonAttemptOutcome.good;
}

class LessonGuideFlowV2 {
  const LessonGuideFlowV2._();

  static const LessonGuidePrompt beforeSentence = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_BEFORE_SENTENCE',
    text: 'Nghe cô nhé.',
  );

  static const LessonGuidePrompt afterSample = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_AFTER_SAMPLE',
    text: 'Bây giờ đến lượt con. Con nói lại nhé.',
  );

  static const LessonGuidePrompt completionChoice = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_COMPLETION_CHOICE',
    text: 'Con hãy nói “Luyện lại từ đầu” hoặc “Bài tiếp theo” nhé.',
  );

  static const LessonGuidePrompt topicCompleted = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_TOPIC_COMPLETED',
    text: 'Con đã học xong chủ đề này rồi. Con chọn tiếp chủ đề mới nhé.',
  );

  static const LessonGuidePrompt good = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_GOOD',
    text: 'Tốt lắm! Cùng học câu tiếp theo nhé.',
  );

  static const LessonGuidePrompt retryFirst = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_RETRY_1',
    text: 'Gần được rồi! Con nghe lại câu này nhé.',
  );

  static const LessonGuidePrompt retrySecond = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_RETRY_2',
    text: 'Bây giờ con thử nói lại lần nữa nhé.',
  );

  static const LessonGuidePrompt needsPractice = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_NEEDS_PRACTICE',
    text: 'Con đã cố gắng rồi! Mình sẽ luyện thêm sau. Cùng học câu tiếp nào.',
  );

  static LessonGuidePrompt entry({
    required String lessonCode,
    required String lessonTitleEn,
    required LessonEntryGuideKind kind,
  }) {
    return switch (kind) {
      LessonEntryGuideKind.first => LessonGuidePrompt(
        audioCode: '${lessonCode}_FIRST',
        text:
            'Chào con! Hôm nay mình bắt đầu với bài “$lessonTitleEn”. '
            'Con nghe cô trước, rồi nói lại theo cô. Nếu muốn nghe lại hoặc '
            'dừng, con bấm nút Main nhé.',
      ),
      LessonEntryGuideKind.newLesson => LessonGuidePrompt(
        audioCode: '${lessonCode}_NEW',
        text: 'Hôm nay mình học bài “$lessonTitleEn” nhé. Bắt đầu nào!',
      ),
      LessonEntryGuideKind.resume => LessonGuidePrompt(
        audioCode: '${lessonCode}_RESUME',
        text:
            'Mình học tiếp bài “$lessonTitleEn” nhé. Bắt đầu từ chỗ lúc '
            'trước nào!',
      ),
    };
  }

  static LessonGuidePrompt ending({
    required String lessonCode,
    required String lessonTitleEn,
  }) => LessonGuidePrompt(
    audioCode: '${lessonCode}_END',
    text:
        'Giỏi lắm! Con đã học xong bài “$lessonTitleEn” rồi. '
        'Con muốn luyện lại từ đầu hay học bài tiếp theo?',
  );
}
