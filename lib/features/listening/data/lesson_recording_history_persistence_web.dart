import 'package:web/web.dart' as web;

class LessonRecordingHistoryPersistence {
  const LessonRecordingHistoryPersistence({this.customPath});

  final String? customPath;

  String get _key => customPath == null
      ? 'innotrik.lesson-recording-history.v1'
      : 'innotrik.lesson-recording-history.test.$customPath';

  Future<String?> read() async => web.window.localStorage.getItem(_key);

  Future<void> write(String value) async {
    web.window.localStorage.setItem(_key, value);
  }
}
