import 'dart:js_interop';

@JS('window.navigator.connection')
external JSObject? get _networkConnection;

extension type _NetworkInformation(JSObject _) implements JSObject {
  external JSString? get effectiveType;

  external JSNumber? get downlink;

  external JSBoolean? get saveData;
}

bool browserNetworkLooksSlow() {
  final rawConnection = _networkConnection;
  if (rawConnection == null) {
    return false;
  }

  final connection = _NetworkInformation(rawConnection);
  final effectiveType = connection.effectiveType?.toDart.toLowerCase();
  final downlinkMbps = connection.downlink?.toDartDouble;
  return (connection.saveData?.toDart ?? false) ||
      effectiveType == 'slow-2g' ||
      effectiveType == '2g' ||
      (downlinkMbps != null && downlinkMbps > 0 && downlinkMbps < 1.0);
}
