import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/ai_speaking_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF8F7FF),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const AiSpeakingApp());
}
