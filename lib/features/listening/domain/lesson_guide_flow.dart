enum LessonEntryGuideKind { first, newLesson, resume }

enum LessonAttemptOutcome { good, unclear, retry, needsPractice }

/// V4 content supplies these cues as audio sources. Keep their text centralized
/// so the runtime and future recorded assets always use the same wording.
const String v4SongPrealertAudioId = 'SONG_PREALERT';
const String v4SongPrealertTemplate =
    'Tiếp theo là hai câu thử thách. Xong rồi mình nghe bài hát [SONG_TITLE] nhé.';
const String v4SongStartCueAudioId = 'SONG_START_CUE';
const String v4SongStartCueTemplate = 'Bây giờ cùng nghe [SONG_TITLE] nhé.';

String v4SongPrealert(String songTitle) =>
    v4SongPrealertTemplate.replaceAll('[SONG_TITLE]', songTitle.trim());

String v4SongStartCue(String songTitle) =>
    v4SongStartCueTemplate.replaceAll('[SONG_TITLE]', songTitle.trim());

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
    Iterable<String> acceptedVariants = const <String>[],
    bool requireAllExpectedTokens = false,
  });
}

/// Test/compatibility evaluator. Production lessons use the backend English
/// content recognizer instead of accepting every successfully saved recording.
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
    Iterable<String> acceptedVariants = const <String>[],
    bool requireAllExpectedTokens = false,
  }) async => LessonAttemptOutcome.good;
}

class LessonGuideFlowV2 {
  const LessonGuideFlowV2._();

  /// A short breathing gap keeps the beginning of the English sample from
  /// touching or clipping the final syllable of the spoken guide.
  static const Duration guideToSamplePause = Duration(milliseconds: 300);

  /// The bilingual lesson script requires a clear two-second pause after the
  /// English sample before its Vietnamese meaning is played.
  static const Duration englishToVietnamesePause = Duration(seconds: 2);

  static const LessonGuidePrompt beforeSentence = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_BEFORE_SENTENCE',
    text: 'Nói theo cô nhé.',
  );

  static const LessonGuidePrompt afterSample = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_AFTER_SAMPLE',
    text: 'Bây giờ đến lượt con. Con nói lại nhé.',
  );

  static const LessonGuidePrompt completionChoice = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_COMPLETION_CHOICE',
    text: 'Con hãy nói “Luyện lại từ đầu” hoặc “Bài tiếp theo” nhé.',
  );

  static const LessonGuidePrompt completionChoiceUnclear = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_COMPLETION_CHOICE_UNCLEAR',
    text: 'Nói lại lựa chọn của con nhé',
  );

  static const LessonGuidePrompt topicCompleted = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_TOPIC_COMPLETED',
    text: 'Con đã học xong chủ đề này rồi. Con chọn tiếp chủ đề mới nhé.',
  );

  static const LessonGuidePrompt good = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_GOOD',
    text: 'Con làm tốt lắm',
  );

  static const LessonGuidePrompt unclear = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_UNCLEAR',
    text: 'Cô chưa nghe rõ. Con nói lại nhé.',
  );

  static const LessonGuidePrompt focusAndRetry = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_FOCUS_RETRY',
    text: 'Con tập trung học đi',
  );

  static const LessonGuidePrompt moveToNext = LessonGuidePrompt(
    audioCode: 'AI_GUIDE_MOVE_TO_NEXT',
    text: 'Mình cùng học câu khác nhé!',
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
