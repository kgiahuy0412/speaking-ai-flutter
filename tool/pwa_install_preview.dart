import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/pwa/pwa_install_gate.dart';
import 'package:ai_speaking_flutter_app/core/pwa/pwa_runtime.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'INNOTRIK iOS install preview',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const PwaInstallGate(
        runtimeState: PwaRuntimeState(
          installRequired: true,
          inAppBrowser: true,
        ),
        child: SizedBox.shrink(),
      ),
    ),
  );
}
