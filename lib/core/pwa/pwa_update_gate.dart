import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../l10n/display_language.dart';
import 'pwa_runtime.dart';
import 'pwa_update_service.dart';

class PwaUpdateGate extends StatefulWidget {
  const PwaUpdateGate({
    required this.child,
    this.checker,
    this.reload,
    this.enabled,
    this.checkInterval = const Duration(minutes: 3),
    super.key,
  });

  final Widget child;
  final PwaUpdateChecker? checker;
  final VoidCallback? reload;
  final bool? enabled;
  final Duration checkInterval;

  @override
  State<PwaUpdateGate> createState() => _PwaUpdateGateState();
}

class _PwaUpdateGateState extends State<PwaUpdateGate>
    with WidgetsBindingObserver {
  PwaUpdateChecker? _checker;
  PwaUpdateDecision? _decision;
  DisplayLanguage _language = DisplayLanguage.vietnamese;
  Timer? _timer;
  DateTime? _lastCheckedAt;
  int? _dismissedBuild;
  bool _checking = false;
  int _generation = 0;

  bool get _enabled => widget.enabled ?? kIsWeb;

  bool get _showUpdate {
    final decision = _decision;
    return decision != null &&
        decision.updateAvailable &&
        decision.latest.buildNumber != _dismissedBuild;
  }

  @override
  void initState() {
    super.initState();
    if (!_enabled) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _checker = widget.checker ?? PwaUpdateService.network();
    unawaited(_loadLanguage());
    unawaited(_check());
    _timer = Timer.periodic(widget.checkInterval, (_) => unawaited(_check()));
  }

  Future<void> _loadLanguage() async {
    final language = await const DisplayLanguageStore().read();
    if (mounted) {
      setState(() => _language = language);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled || state != AppLifecycleState.resumed) {
      return;
    }
    final stale =
        _lastCheckedAt == null ||
        DateTime.now().difference(_lastCheckedAt!) >=
            const Duration(seconds: 30);
    if (stale) {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    final checker = _checker;
    if (checker == null || _checking) {
      return;
    }
    final generation = ++_generation;
    _checking = true;
    try {
      final decision = await checker.check();
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _decision = decision;
        _lastCheckedAt = DateTime.now();
      });
    } catch (error) {
      debugPrint('Web update check failed safely: $error');
      _lastCheckedAt = DateTime.now();
    } finally {
      if (generation == _generation) {
        _checking = false;
      }
    }
  }

  void _dismiss() {
    setState(() => _dismissedBuild = _decision?.latest.buildNumber);
  }

  void _reload() {
    final callback = widget.reload ?? reloadPwaForUpdate;
    callback();
  }

  @override
  void dispose() {
    _generation += 1;
    _timer?.cancel();
    if (_enabled) {
      WidgetsBinding.instance.removeObserver(this);
    }
    if (widget.checker == null) {
      _checker?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) {
      return widget.child;
    }
    return Column(
      children: <Widget>[
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _showUpdate
              ? _PwaUpdateBanner(
                  language: _language,
                  latestVersion: _decision!.latest.version,
                  onReload: _reload,
                  onDismiss: _dismiss,
                )
              : const SizedBox.shrink(),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _PwaUpdateBanner extends StatelessWidget {
  const _PwaUpdateBanner({
    required this.language,
    required this.latestVersion,
    required this.onReload,
    required this.onDismiss,
  });

  final DisplayLanguage language;
  final String latestVersion;
  final VoidCallback onReload;
  final VoidCallback onDismiss;

  String _tr(String vi, String zh) => language.choose(vi, zh);

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('pwa-update-banner'),
      color: const Color(0xFFF0F2FF),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.system_update_rounded, color: AppColors.indigo),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _tr('Đã có phiên bản web mới', '网页版已有新版本'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tr(
                        'Cập nhật lên bản $latestVersion để nhận các cải thiện mới nhất.',
                        '更新到 $latestVersion 版以获取最新改进。',
                      ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      key: const Key('pwa-update-reload'),
                      onPressed: onReload,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(_tr('Cập nhật', '更新')),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('pwa-update-dismiss'),
                onPressed: onDismiss,
                tooltip: _tr('Để sau', '稍后'),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
