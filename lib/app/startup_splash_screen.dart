import 'package:flutter/material.dart';

/// A deliberately minimal first Flutter frame. Startup work is non-blocking
/// and continues in the background after this one-second logo screen.
class StartupSplashScreen extends StatelessWidget {
  const StartupSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFEAF4FF),
      child: Center(
        child: Semantics(
          label: 'INNOTRIK',
          image: true,
          child: const _StartupLogo(),
        ),
      ),
    );
  }
}

class _StartupLogo extends StatelessWidget {
  const _StartupLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 128,
      height: 128,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x203D4DD6),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Image.asset(
          'assets/icon/app_icon_splash.png',
          key: const ValueKey('startup-app-icon'),
          fit: BoxFit.cover,
          cacheWidth: 384,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
