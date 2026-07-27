import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('ailingo_platform');

Future<String?> loadPlatformClientId() =>
    _channel.invokeMethod<String>('device.clientId');
