import 'package:web/web.dart' as web;

class ListeningProgressPersistence {
  const ListeningProgressPersistence({this.customPath});

  final String? customPath;

  String get _key => customPath == null
      ? 'innotrik.listening-progress.v1'
      : 'innotrik.listening-progress.test.$customPath';

  Future<String?> read() async => web.window.localStorage.getItem(_key);

  Future<void> write(String value) async {
    web.window.localStorage.setItem(_key, value);
  }
}
