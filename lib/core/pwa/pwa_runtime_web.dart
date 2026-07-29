import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('window.navigator.standalone')
external JSBoolean? get _iosStandalone;

class PwaRuntimeState {
  const PwaRuntimeState({
    required this.installRequired,
    required this.inAppBrowser,
  });

  final bool installRequired;
  final bool inAppBrowser;
}

PwaRuntimeState readPwaRuntimeState() {
  final navigator = web.window.navigator;
  final userAgent = navigator.userAgent;
  final isIPhoneFamily = RegExp(
    r'iPhone|iPad|iPod',
    caseSensitive: false,
  ).hasMatch(userAgent);
  final isTouchMac =
      userAgent.contains('Macintosh') && navigator.maxTouchPoints > 1;
  final isIos = isIPhoneFamily || isTouchMac;
  final displayModeStandalone = web.window
      .matchMedia('(display-mode: standalone)')
      .matches;
  final legacyStandalone = _iosStandalone?.toDart ?? false;
  final installed = displayModeStandalone || legacyStandalone;
  final inAppBrowser = RegExp(
    r'FBAN|FBAV|Instagram|Messenger|Zalo',
    caseSensitive: false,
  ).hasMatch(userAgent);

  return PwaRuntimeState(
    installRequired: isIos && !installed,
    inAppBrowser: inAppBrowser,
  );
}

void reloadPwaForUpdate() {
  final current = Uri.parse(web.window.location.href);
  final query = <String, String>{
    ...current.queryParameters,
    '_appUpdate': DateTime.now().millisecondsSinceEpoch.toString(),
  };
  web.window.location.replace(
    current.replace(queryParameters: query).toString(),
  );
}
