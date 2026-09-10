import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum BackgroundLearningEventType { stopped, interrupted, resumable }

class BackgroundLearningEvent {
  const BackgroundLearningEvent({required this.type, this.reason});

  factory BackgroundLearningEvent.fromRaw(Object? raw) {
    final values = raw is Map
        ? raw.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    final rawType = values['type']?.toString();
    return BackgroundLearningEvent(
      type: switch (rawType) {
        'background.interrupted' => BackgroundLearningEventType.interrupted,
        'background.resumable' => BackgroundLearningEventType.resumable,
        _ => BackgroundLearningEventType.stopped,
      },
      reason: values['reason']?.toString(),
    );
  }

  final BackgroundLearningEventType type;
  final String? reason;
}

abstract interface class BackgroundLearningSessionControl {
  Stream<BackgroundLearningEvent> get events;

  Future<bool> start();

  Future<void> stop();
}

/// Optional extension used while a lesson route is actively progressing.
///
/// Android keeps a bounded CPU wake lease for this interval so audio gaps and
/// route transitions do not suspend the Dart lesson state machine while the
/// screen is locked or another silent app covers HOMI. It never opens the mic.
abstract interface class ActiveLearningBackgroundSessionControl {
  Future<void> setActiveLearning(bool active);
}

/// Keeps an explicitly-started HOMI learning session eligible to run while
/// the screen is locked or the app is covered by a silent foreground app.
///
/// Native code owns platform policy: Android promotes the session to a
/// foreground service, while iOS declares the audio/BLE background modes and
/// forwards real AVAudioSession interruptions. This bridge never attempts to
/// mix HOMI with another app that has taken audio focus.
class MethodChannelBackgroundLearningSession
    implements
        BackgroundLearningSessionControl,
        ActiveLearningBackgroundSessionControl {
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
        .map(BackgroundLearningEvent.fromRaw)
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

  /// Android 13+ hides foreground-service notifications unless the parent
  /// grants notification access. iOS does not need an extra permission for
  /// the audio/BLE background modes used by this bridge.
  Future<bool> requestNotificationPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      return await _methodChannel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Registers the already-selected H20 as an Android companion device.
  /// Android always owns the confirmation UI; this method never pairs or
  /// associates a device silently.
  Future<bool> associateH20Companion(String deviceId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final status = await _methodChannel.invokeMapMethod<Object?, Object?>(
        'companion.associate',
        <String, Object?>{'deviceId': deviceId},
      );
      return status?['supported'] != true || status?['associated'] == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> setActiveLearning(bool active) async {
    if (!_supportsNativeBackgroundSession) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>(
        'setActiveLearning',
        <String, bool>{'active': active},
      );
    } on MissingPluginException {
      // Older native builds safely keep the existing foreground-only behavior.
    } on PlatformException {
      // The lesson UI remains usable even when the OS rejects a wake lease.
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
