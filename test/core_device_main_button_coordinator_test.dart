import 'dart:async';

import 'package:ai_speaking_flutter_app/core/device/main_button_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps screen and BLE short-press actions separate', () async {
    var screenShortPresses = 0;
    var bleShortPresses = 0;
    final coordinator = MainButtonCoordinator(
      onScreenShortPress: (_) async {
        screenShortPresses += 1;
        return MainButtonActionResult.accepted;
      },
      onBleShortPress: (_) async {
        bleShortPresses += 1;
        return MainButtonActionResult.accepted;
      },
      onLongPress: (_) async => MainButtonActionResult.accepted,
    );

    await coordinator.handle(
      const MainButtonInputEvent(
        source: MainButtonSource.screen,
        gesture: MainButtonGesture.shortPress,
      ),
    );
    await coordinator.handle(
      const MainButtonInputEvent(
        source: MainButtonSource.ble,
        gesture: MainButtonGesture.shortPress,
        sequence: 12,
      ),
    );

    expect(screenShortPresses, 1);
    expect(bleShortPresses, 1);
  });

  test('long press runs once and release only rearms its source', () async {
    var longPresses = 0;
    var shortPresses = 0;
    final coordinator = MainButtonCoordinator(
      onScreenShortPress: (_) async {
        shortPresses += 1;
        return MainButtonActionResult.accepted;
      },
      onBleShortPress: (_) async {
        shortPresses += 1;
        return MainButtonActionResult.accepted;
      },
      onLongPress: (_) async {
        longPresses += 1;
        return MainButtonActionResult.accepted;
      },
    );
    const longPress = MainButtonInputEvent(
      source: MainButtonSource.ble,
      gesture: MainButtonGesture.longPress,
      sequence: 20,
    );

    await coordinator.handle(longPress);
    await coordinator.handle(longPress);
    final suppressedShortPress = await coordinator.handle(
      const MainButtonInputEvent(
        source: MainButtonSource.ble,
        gesture: MainButtonGesture.shortPress,
        sequence: 20,
      ),
    );
    await coordinator.handle(
      const MainButtonInputEvent(
        source: MainButtonSource.ble,
        gesture: MainButtonGesture.release,
        sequence: 20,
      ),
    );
    await coordinator.handle(longPress);

    expect(longPresses, 2);
    expect(shortPresses, 0);
    expect(suppressedShortPress, MainButtonActionResult.ignored);
  });

  test('a new BLE sequence rearms long press even without release', () async {
    var longPresses = 0;
    final coordinator = MainButtonCoordinator(
      onScreenShortPress: (_) async => MainButtonActionResult.accepted,
      onBleShortPress: (_) async => MainButtonActionResult.accepted,
      onLongPress: (_) async {
        longPresses += 1;
        return MainButtonActionResult.accepted;
      },
    );

    await coordinator.handle(
      const MainButtonInputEvent(
        source: MainButtonSource.ble,
        gesture: MainButtonGesture.longPress,
        sequence: 1,
      ),
    );
    await coordinator.handle(
      const MainButtonInputEvent(
        source: MainButtonSource.ble,
        gesture: MainButtonGesture.longPress,
        sequence: 2,
      ),
    );

    expect(longPresses, 2);
  });

  test('serializes simultaneous screen and BLE actions', () async {
    final firstAction = Completer<void>();
    final calls = <String>[];
    final coordinator = MainButtonCoordinator(
      onScreenShortPress: (_) async {
        calls.add('screen-start');
        await firstAction.future;
        calls.add('screen-end');
        return MainButtonActionResult.accepted;
      },
      onBleShortPress: (_) async {
        calls.add('ble');
        return MainButtonActionResult.accepted;
      },
      onLongPress: (_) async => MainButtonActionResult.accepted,
    );

    final screen = coordinator.handle(
      const MainButtonInputEvent(
        source: MainButtonSource.screen,
        gesture: MainButtonGesture.shortPress,
      ),
    );
    final ble = coordinator.handle(
      const MainButtonInputEvent(
        source: MainButtonSource.ble,
        gesture: MainButtonGesture.shortPress,
        sequence: 31,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(calls, <String>['screen-start']);
    firstAction.complete();
    await Future.wait(<Future<MainButtonActionResult>>[screen, ble]);
    expect(calls, <String>['screen-start', 'screen-end', 'ble']);
  });
}
