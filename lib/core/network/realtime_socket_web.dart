abstract interface class RealtimeSocket {
  Stream<dynamic> get messages;
  void add(String data);
  Future<void> close([int? code, String? reason]);
}

Future<RealtimeSocket> connectRealtimeSocket(
  String url, {
  required Map<String, String> headers,
}) {
  throw UnsupportedError(
    'Realtime trực tiếp cần WebSocket gateway của backend. '
    'PWA hiện dùng Batch Chunks truyền trong lúc ghi âm.',
  );
}
