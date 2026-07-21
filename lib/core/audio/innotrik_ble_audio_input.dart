import 'dart:typed_data';

import 'audio_input.dart';

/// Boundary for the native INNOTRIK implementation.
///
/// The documented packets contain 80 bytes of raw Opus payload. They are not
/// a playable Opus container, so the production implementation must use the
/// vendor SDK or a native decoder/muxer before it can return [AudioCapture].
class InnotrikBleAudioInput implements ChunkedAudioInput {
  const InnotrikBleAudioInput();

  @override
  Stream<double> get amplitudeDbfs => const Stream<double>.empty();

  @override
  Stream<Uint8List> get audioChunks => const Stream<Uint8List>.empty();

  @override
  bool get isAvailable => false;

  @override
  bool get isBluetooth => true;

  @override
  String get label => 'Mic INNOTRIK';

  @override
  Future<void> start() {
    throw const InnotrikIntegrationPending();
  }

  @override
  Future<void> startChunked() {
    throw const InnotrikIntegrationPending();
  }

  @override
  Future<AudioCapture> stop() {
    throw const InnotrikIntegrationPending();
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class InnotrikIntegrationPending implements Exception {
  const InnotrikIntegrationPending();

  @override
  String toString() =>
      'Mic BLE cần SDK/decoder Opus của INNOTRIK và thiết bị thật để hoàn tất.';
}
