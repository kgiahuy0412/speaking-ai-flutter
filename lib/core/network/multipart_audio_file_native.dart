import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<http.MultipartFile> createAudioMultipartFile({
  required String field,
  required String path,
  required String filename,
  Uint8List? bytes,
}) {
  if (bytes != null) {
    return Future<http.MultipartFile>.value(
      http.MultipartFile.fromBytes(field, bytes, filename: filename),
    );
  }
  return http.MultipartFile.fromPath(field, path, filename: filename);
}
