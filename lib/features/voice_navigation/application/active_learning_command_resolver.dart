import '../../../core/device/active_learning_module.dart';
import '../domain/controlled_speech_lexicon.dart';

/// Small deterministic grammar for commands spoken after MAIN is pressed
/// while a lesson is active. It deliberately does not interpret lesson
/// content; it only maps navigation/control phrases to the shared adapter.
class ActiveLearningCommandResolver {
  const ActiveLearningCommandResolver();

  static const ControlledSpeechLexicon _controlledLexicon =
      ControlledSpeechLexicon();

  ActiveLearningCommand? resolve(String transcript) {
    final controlled = _controlledLexicon.resolve(
      transcript,
      state: ControlledSpeechState.course,
    );
    final controlledCommand = switch (controlled?.intent) {
      ControlledSpeechIntent.globalStop => ActiveLearningCommand.stop,
      ControlledSpeechIntent.courseContinue => ActiveLearningCommand.resume,
      ControlledSpeechIntent.courseNextSentence =>
        ActiveLearningCommand.nextItem,
      ControlledSpeechIntent.coursePreviousSentence =>
        ActiveLearningCommand.previousItem,
      ControlledSpeechIntent.courseReplayCurrent =>
        ActiveLearningCommand.replayCurrent,
      ControlledSpeechIntent.courseRestartCurrent =>
        ActiveLearningCommand.restart,
      ControlledSpeechIntent.courseNextLesson =>
        ActiveLearningCommand.nextLesson,
      ControlledSpeechIntent.coursePreviousLesson =>
        ActiveLearningCommand.previousLesson,
      _ => null,
    };
    if (controlledCommand != null) {
      return controlledCommand;
    }

    // Preserve a small set of already-shipped aliases while the controlled
    // V0.1 table becomes the primary grammar.
    final value = _normalize(transcript);
    if (value.isEmpty) {
      return null;
    }
    if (_has(value, 'dung lai') || _has(value, 'tam dung') || value == 'dung') {
      return ActiveLearningCommand.stop;
    }
    if (_has(value, 'tiep tuc') ||
        _has(value, 'hoc tiep') ||
        _has(value, 'lam tiep')) {
      return ActiveLearningCommand.resume;
    }
    if (_has(value, 'luyen lai tu dau') ||
        _has(value, 'hoc lai tu dau') ||
        _has(value, 'lam lai tu dau')) {
      return ActiveLearningCommand.restart;
    }
    if (_has(value, 'bai tiep theo') || _has(value, 'bai ke tiep')) {
      return ActiveLearningCommand.nextLesson;
    }
    if (_has(value, 'bai truoc') || _has(value, 'bai vua roi')) {
      return ActiveLearningCommand.previousLesson;
    }
    if (_has(value, 'cau tiep theo') ||
        _has(value, 'dong tiep theo') ||
        _has(value, 'hoc cau tiep') ||
        _has(value, 'qua cau tiep') ||
        _has(value, 'tiep theo')) {
      return ActiveLearningCommand.nextItem;
    }
    if (_has(value, 'cau truoc') ||
        _has(value, 'dong truoc') ||
        _has(value, 'nghe cau truoc') ||
        _has(value, 'quay lai cau truoc') ||
        _has(value, 'cau vua roi') ||
        value == 'quay lai') {
      return ActiveLearningCommand.previousItem;
    }
    if (_has(value, 'nghe lai') ||
        _has(value, 'doc lai') ||
        _has(value, 'lap lai')) {
      return ActiveLearningCommand.replayCurrent;
    }
    return null;
  }

  static bool _has(String value, String phrase) =>
      ' $value '.contains(' $phrase ');

  static String _normalize(String value) {
    var normalized = value.trim().toLowerCase();
    const replacements = <String, String>{
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    for (final entry in replacements.entries) {
      normalized = normalized.replaceAll(RegExp('[${entry.value}]'), entry.key);
    }
    return normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
