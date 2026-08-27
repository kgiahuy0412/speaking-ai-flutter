import 'dart:async';

enum MainButtonSource { screen, ble }

enum MainButtonGesture { shortPress, longPress, release }

enum MainButtonActionResult { accepted, busy, ignored }

class MainButtonInputEvent {
  const MainButtonInputEvent({
    required this.source,
    required this.gesture,
    this.sequence,
  });

  final MainButtonSource source;
  final MainButtonGesture gesture;
  final int? sequence;
}

typedef MainButtonAction =
    Future<MainButtonActionResult> Function(MainButtonInputEvent event);

/// Routes the on-screen MAIN simulator and the physical BLE MAIN button
/// through one gesture policy while preserving their current short-press
/// actions.
///
/// Firmware may emit `longPress` followed by `release`. The BLE sequence guard
/// runs one action for that physical gesture; release only rearms the source.
class MainButtonCoordinator {
  MainButtonCoordinator({
    required MainButtonAction onScreenShortPress,
    required MainButtonAction onBleShortPress,
    required MainButtonAction onLongPress,
    Duration actionTimeout = const Duration(seconds: 30),
  }) : _onScreenShortPress = onScreenShortPress,
       _onBleShortPress = onBleShortPress,
       _onLongPress = onLongPress,
       _actionTimeout = actionTimeout;

  final MainButtonAction _onScreenShortPress;
  final MainButtonAction _onBleShortPress;
  final MainButtonAction _onLongPress;
  final Duration _actionTimeout;
  final Map<MainButtonSource, int?> _activeLongPressSequences =
      <MainButtonSource, int?>{};
  Future<void> _operationTail = Future<void>.value();

  Future<MainButtonActionResult> handle(MainButtonInputEvent event) {
    final completer = Completer<MainButtonActionResult>();
    _operationTail = _operationTail.then<void>((_) async {
      try {
        completer.complete(
          await _handleSerially(event).timeout(
            _actionTimeout,
            onTimeout: () => MainButtonActionResult.busy,
          ),
        );
      } catch (_) {
        completer.complete(MainButtonActionResult.busy);
      }
    });
    return completer.future;
  }

  Future<MainButtonActionResult> _handleSerially(
    MainButtonInputEvent event,
  ) async {
    switch (event.gesture) {
      case MainButtonGesture.release:
        _activeLongPressSequences.remove(event.source);
        return MainButtonActionResult.accepted;
      case MainButtonGesture.longPress:
        if (event.source == MainButtonSource.screen) {
          return _onLongPress(event);
        }
        if (_isSameActiveGesture(event)) {
          return MainButtonActionResult.accepted;
        }
        _activeLongPressSequences[event.source] = event.sequence;
        return _onLongPress(event);
      case MainButtonGesture.shortPress:
        if (_isSameActiveGesture(event)) {
          return MainButtonActionResult.ignored;
        }
        _activeLongPressSequences.remove(event.source);
        return switch (event.source) {
          MainButtonSource.screen => _onScreenShortPress(event),
          MainButtonSource.ble => _onBleShortPress(event),
        };
    }
  }

  bool _isSameActiveGesture(MainButtonInputEvent event) {
    if (event.source != MainButtonSource.ble) {
      return false;
    }
    if (!_activeLongPressSequences.containsKey(event.source)) {
      return false;
    }
    final activeSequence = _activeLongPressSequences[event.source];
    return event.sequence == null || activeSequence == event.sequence;
  }
}
