import 'dart:typed_data';

Future<String> createTemporaryRecordingPath(String extension) async =>
    'utterance_${DateTime.now().microsecondsSinceEpoch}.$extension';

Future<void> persistRecordingBytes(String path, Uint8List bytes) async {
  // Browser recordings are uploaded from [AudioCapture.dataBytes]. Browsers
  // do not expose a writable native file path.
}
