import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_theme.dart';
import '../../app/learning_scenery.dart';
import '../../app/mascot_assets.dart';
import '../../config/app_config.dart';
import '../../l10n/display_language.dart';
import 'app_update_policy.dart';
import 'app_update_service.dart';

typedef UpdateUrlOpener = Future<bool> Function(Uri uri);

class AndroidUpdateGate extends StatefulWidget {
  const AndroidUpdateGate({
    required this.config,
    required this.child,
    this.checker,
    this.urlOpener,
    super.key,
  });

  final AppConfig config;
  final Widget child;
  final AppUpdateChecker? checker;
  final UpdateUrlOpener? urlOpener;

  @override
  State<AndroidUpdateGate> createState() => _AndroidUpdateGateState();
}

class _AndroidUpdateGateState extends State<AndroidUpdateGate>
    with WidgetsBindingObserver {
  AppUpdateChecker? _checker;
  AppUpdateDecision? _decision;
  DisplayLanguage _language = DisplayLanguage.vietnamese;
  DateTime? _lastCheckedAt;
  bool _checking = false;
  bool _openFailed = false;
  int _generation = 0;

  bool get _enabled =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (!_enabled) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _checker =
        widget.checker ?? AppUpdateService.network(config: widget.config);
    unawaited(_loadLanguage());
    unawaited(_check());
  }

  Future<void> _loadLanguage() async {
    final language = await const DisplayLanguageStore().read();
    if (mounted) {
      setState(() => _language = language);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_enabled) {
      return;
    }
    final blocked = _decision?.requiresUpdate ?? false;
    final stale =
        _lastCheckedAt == null ||
        DateTime.now().difference(_lastCheckedAt!) >=
            const Duration(minutes: 15);
    if (blocked || stale) {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    final checker = _checker;
    if (checker == null || _checking) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _checking = true;
      _openFailed = false;
    });
    AppUpdateDecision decision;
    try {
      decision = await checker.check();
    } catch (error) {
      debugPrint('App update gate failed open safely: $error');
      decision = const AppUpdateDecision.unavailable();
    }
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _decision = decision;
      _checking = false;
      _lastCheckedAt = DateTime.now();
    });
  }

  Future<void> _openUpdatePage() async {
    final uri = _decision?.policy?.downloadUrl;
    if (uri == null) {
      return;
    }
    final opener =
        widget.urlOpener ??
        (value) => launchUrl(value, mode: LaunchMode.externalApplication);
    var opened = false;
    try {
      opened = await opener(uri);
    } catch (error) {
      debugPrint('Cannot open Android update page: $error');
    }
    if (mounted && !opened) {
      setState(() => _openFailed = true);
    }
  }

  @override
  void dispose() {
    _generation += 1;
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
    final decision = _decision;
    if (!_checking && !(decision?.requiresUpdate ?? false)) {
      return widget.child;
    }
    if (decision?.requiresUpdate ?? false) {
      return _RequiredUpdateScreen(
        decision: decision!,
        language: _language,
        checking: _checking,
        openFailed: _openFailed,
        onUpdate: _openUpdatePage,
        onRetry: _check,
      );
    }
    return const _UpdateCheckSplash();
  }
}

class _UpdateCheckSplash extends StatelessWidget {
  const _UpdateCheckSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: LearningScenery(
        child: Center(
          child: SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    );
  }
}

class _RequiredUpdateScreen extends StatelessWidget {
  const _RequiredUpdateScreen({
    required this.decision,
    required this.language,
    required this.checking,
    required this.openFailed,
    required this.onUpdate,
    required this.onRetry,
  });

  final AppUpdateDecision decision;
  final DisplayLanguage language;
  final bool checking;
  final bool openFailed;
  final VoidCallback onUpdate;
  final VoidCallback onRetry;

  String _tr(String vi, String zh) => language.choose(vi, zh);

  @override
  Widget build(BuildContext context) {
    final policy = decision.policy!;
    final message = language == DisplayLanguage.simplifiedChinese
        ? policy.chineseMessage
        : policy.vietnameseMessage;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LearningScenery(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: AppColors.lavenderBorder),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x1F142451),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Image.asset(
                            MascotAssets.wave,
                            width: 112,
                            height: 112,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _tr('Cần cập nhật ứng dụng', '需要更新应用'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: AppColors.muted),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _tr(
                              'Bản hiện tại: ${decision.currentBuild}  •  '
                                  'Bản mới: ${policy.latestVersion} '
                                  '(${policy.latestBuild})',
                              '当前版本：${decision.currentBuild}  •  '
                                  '新版本：${policy.latestVersion} '
                                  '(${policy.latestBuild})',
                            ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (openFailed) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              _tr(
                                'Không mở được trang tải. Hãy thử lại.',
                                '无法打开下载页面，请重试。',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFFD92D20)),
                            ),
                          ],
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              key: const Key('required-update-open'),
                              onPressed: onUpdate,
                              icon: const Icon(Icons.system_update_alt_rounded),
                              label: Text(_tr('Cập nhật ngay', '立即更新')),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            key: const Key('required-update-retry'),
                            onPressed: checking ? null : onRetry,
                            icon: checking
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded),
                            label: Text(
                              _tr('Tôi đã cập nhật – kiểm tra lại', '已更新－重新检查'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
