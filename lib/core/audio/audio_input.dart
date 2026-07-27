import 'dart:typed_data';

class AudioCapture {
  const AudioCapture({
    required this.filePath,
    required this.mimeType,
    required this.duration,
    required this.inputLabel,
    required this.isBluetoothInput,
    required this.initialNoiseRms,
    this.streamHeaderBytes,
    this.streamedAudioBytes,
    this.dataBytes,
  });

  final String filePath;
  final String mimeType;
  final Duration duration;
  final String inputLabel;
  final bool isBluetoothInput;
  final double? initialNoiseRms;
  final Uint8List? streamHeaderBytes;
  final int? streamedAudioBytes;

  /// In-memory payload used by Flutter Web, where a native file path is not
  /// available. Native platforms may also provide it for a retry upload.
  final Uint8List? dataBytes;
}

abstract interface class AudioInput {
  String get label;
  bool get isBluetooth;
  bool get isAvailable;
  Stream<double> get amplitudeDbfs;

  Future<void> start();
  Future<AudioCapture> stop();
  Future<void> cancel();
  Future<void> dispose();
}

abstract interface class ChunkedAudioInput implements AudioInput {
  Stream<Uint8List> get audioChunks;

  Future<void> startChunked();
}
