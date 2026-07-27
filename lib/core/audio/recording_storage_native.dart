import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> createTemporaryRecordingPath(String extension) async {
  final directory = await getTemporaryDirectory();
  return '${directory.path}${Platform.pathSeparator}'
      'utterance_${DateTime.now().microsecondsSinceEpoch}.$extension';
}

Future<void> persistRecordingBytes(String path, Uint8List bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}
