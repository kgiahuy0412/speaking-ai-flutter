import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> readDisplayLanguageCode() async {
  final directory = await getApplicationSupportDirectory();
  final file = File(
    '${directory.path}${Platform.pathSeparator}display-language.txt',
  );
  return file.readAsString();
}

Future<void> writeDisplayLanguageCode(String code) async {
  final directory = await getApplicationSupportDirectory();
  final file = File(
    '${directory.path}${Platform.pathSeparator}display-language.txt',
  );
  await file.parent.create(recursive: true);
  await file.writeAsString(code, flush: true);
}
