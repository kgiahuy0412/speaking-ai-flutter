enum V4CompletionStage {
  lessonEnd,
  topicEnd,
  topicEndOneRemaining,
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
    V4CompletionStage.topicEnd => 'Bạn muốn học chủ đề khác hay học lại?',
    V4CompletionStage.topicEndOneRemaining =>
      'Bạn còn một Chủ đề chưa học. Bạn muốn học tiếp hay học lại?',
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
    V4CompletionAction.nextTopic => 'Chủ đề khác',
    V4CompletionAction.relearnTopic => 'Học lại toàn bộ chủ đề',
    V4CompletionAction.startNextLevel => 'Bắt đầu Level tiếp theo',
    V4CompletionAction.requestNewCourse => 'Học khóa mới',
    V4CompletionAction.relearn => 'Học lại',
    V4CompletionAction.relearnLevel1 => 'Học lại Level 1',
    V4CompletionAction.relearnLevel2 => 'Học lại Level 2',
    V4CompletionAction.relearnLevel3 => 'Học lại Level 3',
  };
}

class V4CompletionChoiceResolver {
  const V4CompletionChoiceResolver();

  V4CompletionAction? resolve(
    String transcript, {
    required V4CompletionStage stage,
    Iterable<V4CompletionAction> allowedActions = V4CompletionAction.values,
  }) {
    final value = _normalize(transcript);
    if (value.isEmpty) return null;
    final allowed = allowedActions.toSet();

    V4CompletionAction? result;
    if (_hasAny(value, const <String>['dung lai', 'ket thuc', 'thoi'])) {
      result = V4CompletionAction.stop;
    } else {
      result = switch (stage) {
        V4CompletionStage.lessonEnd =>
          _hasAny(value, const <String>[
                'bai tiep theo',
                'hoc tiep',
                'tiep theo',
              ])
              ? V4CompletionAction.nextLesson
              : _hasAny(value, const <String>[
                  'hoc lai bai',
                  'luyen lai bai',
                  'bai nay',
                  'hoc lai',
                ])
              ? V4CompletionAction.relearnCurrentLesson
              : null,
        V4CompletionStage.topicEnd || V4CompletionStage.topicEndOneRemaining =>
          _hasAny(value, const <String>[
                'chu de tiep theo',
                'hoc tiep chu de',
                'chu de moi',
              ])
              ? V4CompletionAction.nextTopic
              : _hasAny(value, const <String>['hoc lai', 'luyen lai'])
              ? V4CompletionAction.relearn
              : null,
        V4CompletionStage.topicRelearnScope =>
          _hasAny(value, const <String>[
                'toan bo chu de',
                'hoc lai chu de',
                'ca chu de',
              ])
              ? V4CompletionAction.relearnTopic
              : _hasAny(value, const <String>[
                  'bai nay',
                  'bai hien tai',
                  'chi hoc lai bai',
                ])
              ? V4CompletionAction.relearnCurrentLesson
              : null,
        V4CompletionStage.nextLevel =>
          _hasAny(value, const <String>[
                'level tiep theo',
                'bat dau level',
                'hoc level',
                'hoc tiep',
              ])
              ? V4CompletionAction.startNextLevel
              : null,
        V4CompletionStage.courseEnd =>
          _hasAny(value, const <String>[
                'khoa moi',
                'hoc khoa moi',
                'khoa tiep theo',
              ])
              ? V4CompletionAction.requestNewCourse
              : _hasAny(value, const <String>['hoc lai', 'luyen lai'])
              ? V4CompletionAction.relearn
              : null,
        V4CompletionStage.courseRelearnLevel => _levelAction(value),
      };
    }
    return result != null && allowed.contains(result) ? result : null;
  }

  static V4CompletionAction? _levelAction(String value) {
    if (_hasAny(value, const <String>['level 1', 'level mot', 'cap 1'])) {
      return V4CompletionAction.relearnLevel1;
    }
    if (_hasAny(value, const <String>['level 2', 'level hai', 'cap 2'])) {
      return V4CompletionAction.relearnLevel2;
    }
    if (_hasAny(value, const <String>['level 3', 'level ba', 'cap 3'])) {
      return V4CompletionAction.relearnLevel3;
    }
    return null;
  }

  static bool _hasAny(String value, Iterable<String> phrases) =>
      phrases.any((phrase) => value.contains(phrase));

  static String _normalize(String input) {
    const accented =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const plain =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final character = String.fromCharCode(rune);
      final index = accented.indexOf(character);
      buffer.write(index < 0 ? character : plain[index]);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
