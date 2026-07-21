import 'dart:typed_data';

/// Keeps an immutable, size-bounded copy of PCM chunks while Realtime is
/// active so the same recording can be sent through Batch Chunks on failure.
class RealtimeFallbackBuffer {
  RealtimeFallbackBuffer({required this.maxBytes})
    : assert(maxBytes > 0, 'maxBytes must be positive');

  final int maxBytes;
  final List<Uint8List> _chunks = <Uint8List>[];
  int _byteLength = 0;
  bool _overflowed = false;

  int get byteLength => _byteLength;
  bool get isEmpty => _chunks.isEmpty;
  bool get canReplay => !_overflowed && _chunks.isNotEmpty;
  bool get overflowed => _overflowed;

  void add(Uint8List bytes) {
    if (bytes.isEmpty || _overflowed) {
      return;
    }
    if (_byteLength + bytes.length > maxBytes) {
      _chunks.clear();
      _byteLength = 0;
      _overflowed = true;
      return;
    }
    final immutableBytes = Uint8List.fromList(bytes);
    _chunks.add(immutableBytes);
    _byteLength += immutableBytes.length;
  }

  void replay(void Function(Uint8List bytes) consumer) {
    if (!canReplay) {
      return;
    }
    for (final chunk in _chunks) {
      consumer(chunk);
    }
  }

  void clear() {
    _chunks.clear();
    _byteLength = 0;
    _overflowed = false;
  }
}
