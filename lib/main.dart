import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/ai_speaking_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const <String>[
      'HOMI: native libraries and optional models',
    ], await rootBundle.loadString('THIRD_PARTY_NOTICES.md'));
    yield LicenseEntryWithLineBreaks(const <String>[
      'Vosk API',
      'Vosk models',
      'JNA',
    ], await rootBundle.loadString('assets/legal/APACHE-2.0.txt'));
  });
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
