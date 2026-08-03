import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<http.MultipartFile> createAudioMultipartFile({
  required String field,
  required String path,
  required String filename,
  Uint8List? bytes,
}) async {
  if (bytes == null || bytes.isEmpty) {
    throw StateError('Trình duyệt không có dữ liệu audio để tải lên.');
  }
  return http.MultipartFile.fromBytes(field, bytes, filename: filename);
}

Future<Uint8List> readAudioBytes({
  required String path,
  Uint8List? bytes,
}) async {
  if (bytes == null || bytes.isEmpty) {
    throw StateError('Trình duyệt không có dữ liệu audio để tải lên.');
  }
  return Uint8List.fromList(bytes);
}
