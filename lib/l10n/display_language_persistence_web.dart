import 'package:web/web.dart' as web;

const _storageKey = 'innotrik.display-language.v1';

Future<String?> readDisplayLanguageCode() async =>
    web.window.localStorage.getItem(_storageKey);

Future<void> writeDisplayLanguageCode(String code) async {
  web.window.localStorage.setItem(_storageKey, code);
}
