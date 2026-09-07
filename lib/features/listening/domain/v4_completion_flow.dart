enum V4CompletionStage {
  lessonEnd,
  topicEnd,
  topicRelearnScope,
  nextLevel,
  courseEnd,
  courseRelearnLevel,
}

enum V4CompletionAction {
  nextLesson,
  relearnCurrentLesson,
  stop,
  nextTopic,
  relearnTopic,
  startNextLevel,
  requestNewCourse,
  relearn,
  relearnLevel1,
  relearnLevel2,
  relearnLevel3,
}

String v4CompletionPrompt(V4CompletionStage stage, {int? nextLevel}) {
  return switch (stage) {
    V4CompletionStage.lessonEnd =>
      'Bạn muốn học bài tiếp theo hay học lại bài này?',
    V4CompletionStage.topicEnd => 'Bạn muốn học chủ đề tiếp theo hay học lại?',
    V4CompletionStage.topicRelearnScope =>
      'Bạn muốn học lại toàn bộ chủ đề hay chỉ học lại bài này?',
    V4CompletionStage.nextLevel =>
      'Bạn muốn bắt đầu Level ${nextLevel ?? ''} hay dừng lại?'.replaceAll(
        'Level  ',
        'Level ',
      ),
    V4CompletionStage.courseEnd => 'Bạn muốn học khóa mới hay học lại?',
    V4CompletionStage.courseRelearnLevel =>
      'Bạn muốn học lại Level 1, Level 2 hay Level 3?',
  };
}

String v4CompletionActionLabel(V4CompletionAction action) {
  return switch (action) {
    V4CompletionAction.nextLesson => 'Bài tiếp theo',
    V4CompletionAction.relearnCurrentLesson => 'Học lại bài này',
    V4CompletionAction.stop => 'Dừng lại',
    V4CompletionAction.nextTopic => 'Chủ đề tiếp theo',
    V4CompletionAction.relearnTopic => 'Học lại toàn bộ chủ đề',
    V4CompletionAction.startNextLevel => 'Bắt đầu Level tiếp theo',
    V4CompletionAction.requestNewCourse => 'Học khóa mới',
    V4CompletionAction.relearn => 'Học lại',
    V4CompletionAction.relearnLevel1 => 'Học lại Level 1',
    V4CompletionAction.relearnLevel2 => 'Học lại Level 2',
    V4CompletionAction.relearnLevel3 => 'Học lại Level 3',
  };
}
