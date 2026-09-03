import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum BackgroundLearningEventType { stopped, interrupted }

class BackgroundLearningEvent {
  const BackgroundLearningEvent({required this.type, this.reason});

  final BackgroundLearningEventType type;
  final String? reason;
}

abstract interface class BackgroundLearningSessionControl {
  Stream<BackgroundLearningEvent> get events;

  Future<bool> start();

  Future<void> stop();
}

/// Keeps an explicitly-started HOMI learning session eligible to run while
/// the screen is locked or the app is covered by a silent foreground app.
///
/// Native code owns platform policy: Android promotes the session to a
/// foreground service, while iOS declares the audio/BLE background modes and
/// forwards real AVAudioSession interruptions. This bridge never attempts to
/// mix HOMI with another app that has taken audio focus.
class MethodChannelBackgroundLearningSession
    implements BackgroundLearningSessionControl {
  MethodChannelBackgroundLearningSession({
    MethodChannel methodChannel = const MethodChannel(
      'ailingo_background_learning',
    ),
    EventChannel eventChannel = const EventChannel(
      'ailingo_background_learning/events',
    ),
  }) : _methodChannel = methodChannel,
       _eventChannel = eventChannel;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<BackgroundLearningEvent>? _events;

  bool get _supportsNativeBackgroundSession =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Stream<BackgroundLearningEvent> get events {
    if (!_supportsNativeBackgroundSession) {
      return const Stream<BackgroundLearningEvent>.empty();
    }
    return _events ??= _eventChannel
        .receiveBroadcastStream()
        .map((raw) {
          final values = raw is Map
              ? raw.cast<Object?, Object?>()
              : const <Object?, Object?>{};
          final type = values['type']?.toString();
          return BackgroundLearningEvent(
            type: type == 'background.interrupted'
                ? BackgroundLearningEventType.interrupted
                : BackgroundLearningEventType.stopped,
            reason: values['reason']?.toString(),
          );
        })
        .handleError((Object _, StackTrace _) {
          // A missing native event channel must not make the foreground UI fail.
        });
  }

  @override
  Future<bool> start() async {
    if (!_supportsNativeBackgroundSession) {
      return false;
    }
    try {
      return await _methodChannel.invokeMethod<bool>('start') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_supportsNativeBackgroundSession) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Older builds can safely ignore the optional background bridge.
    } on PlatformException {
      // Stopping is best-effort during widget/app disposal.
    }
  }
}
