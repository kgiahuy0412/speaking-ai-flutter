import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ListeningProgressPersistence {
  const ListeningProgressPersistence({this.customPath});

  final String? customPath;

  Future<File> _file() async {
    if (customPath != null) {
      return File(customPath!);
    }
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}listening-progress.json',
    );
  }

  Future<String?> read() async => (await _file()).readAsString();

  Future<void> write(String value) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }
}
