import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Lightweight first Flutter frame shown while essential local state is
/// prepared. Network warm-ups and non-critical data continue after this screen.
class StartupSplashScreen extends StatefulWidget {
  const StartupSplashScreen({
    required this.status,
    required this.progress,
    required this.version,
    super.key,
  });

  final String status;
  final double progress;
  final String version;

  @override
  State<StartupSplashScreen> createState() => _StartupSplashScreenState();
}

class _StartupSplashScreenState extends State<StartupSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _iconScale;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _iconScale = Tween<double>(begin: 0.98, end: 1.025).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final reduceMotion = mediaQuery.disableAnimations;
    final progress = widget.progress.clamp(0.0, 1.0);

    return ColoredBox(
      color: const Color(0xFFEAF4FF),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                28,
                compact ? 24 : 44,
                28,
                compact ? 18 : 28,
              ),
              child: Column(
                children: <Widget>[
                  const Spacer(flex: 2),
                  ScaleTransition(
                    scale: reduceMotion
                        ? const AlwaysStoppedAnimation<double>(1)
                        : _iconScale,
                    child: Container(
                      width: compact ? 118 : 136,
                      height: compact ? 118 : 136,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF9),
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.92),
                          width: 2,
                        ),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                            color: Color(0x243D4DD6),
                            blurRadius: 30,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(27),
                        child: Image.asset(
                          'assets/icon/app_icon.png',
                          key: const ValueKey('startup-app-icon'),
                          fit: BoxFit.cover,
                          cacheWidth: 384,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 24 : 32),
                  const Text(
                    'INNOTRIK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 31,
                      height: 1.12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cùng con nói tiếng Anh mỗi ngày',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 16,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(flex: 2),
                  Semantics(
                    liveRegion: true,
                    label: '${widget.status}, ${(progress * 100).round()}%',
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 17),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFD8E7FA)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: progress >= 1
                                    ? const Icon(
                                        Icons.check_circle_rounded,
                                        key: ValueKey('startup-ready'),
                                        color: AppColors.success,
                                        size: 22,
                                      )
                                    : const SizedBox.square(
                                        key: ValueKey('startup-loading'),
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: AppColors.indigo,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: Text(
                                    widget.status,
                                    key: ValueKey(widget.status),
                                    style: const TextStyle(
                                      color: AppColors.ink,
                                      fontSize: 16,
                                      height: 1.3,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              key: const ValueKey('startup-progress'),
                              value: progress,
                              minHeight: 7,
                              color: AppColors.indigo,
                              backgroundColor: const Color(0xFFDDE6FF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Chỉ chuẩn bị dữ liệu cần thiết.\nNội dung còn lại sẽ tiếp tục tải nền.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.version.isEmpty ? 'INNOTRIK' : 'v${widget.version}',
                    style: const TextStyle(
                      color: Color(0xFF8390AA),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
