import 'dart:io';

abstract interface class RealtimeSocket {
  Stream<dynamic> get messages;
  void add(String data);
  Future<void> close([int? code, String? reason]);
}

class _IoRealtimeSocket implements RealtimeSocket {
  const _IoRealtimeSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<dynamic> get messages => _socket;

  @override
  void add(String data) => _socket.add(data);

  @override
  Future<void> close([int? code, String? reason]) =>
      _socket.close(code, reason);
}

Future<RealtimeSocket> connectRealtimeSocket(
  String url, {
  required Map<String, String> headers,
}) async {
  final socket = await WebSocket.connect(url, headers: headers);
  return _IoRealtimeSocket(socket);
}
